#!/usr/bin/env python3
import concurrent.futures as cf
import csv
import hashlib
import io
import json
import os
import re
import time
import threading
import sys
from collections import Counter, OrderedDict, defaultdict

import mwparserfromhell
import requests
from mwparserfromhell.nodes import (Comment, ExternalLink, HTMLEntity, Tag, Template, Text, Wikilink)
from PIL import Image

import tkinter as tk
from tkinter import ttk, filedialog, scrolledtext, messagebox

# =============================================================================
# ORIGINAL SCRAPER LOGIC (Core engine unchanged)
# =============================================================================

EXCEL_CELL_LIMIT = 32000
IMAGE_EXT = r"(?:png|jpe?g|gif|webp|svg|bmp|tiff?)"
FILENAME_RE = re.compile(r"(?:(?:File|Image):)?\s*([^\[\]|{}\n<>=#]+?\." + IMAGE_EXT + r")\b", re.I)

def chunks(seq, n):
    seq = list(seq)
    for i in range(0, len(seq), n):
        yield seq[i:i + n]

def kw_regex(words):
    words = [w for w in (words or []) if w]
    if not words: return None
    alts = "|".join(re.escape(w.lower()) for w in sorted(words, key=len, reverse=True))
    return re.compile(r"(?<![a-z0-9])(" + alts + r")(?:e?s)?(?![a-z0-9])", re.I)

def slug(text, n=70):
    s = re.sub(r"[^A-Za-z0-9._-]+", "_", text).strip("._")
    return s[:n] or "file"

def norm_file(name):
    name = re.sub(r"^(File|Image):", "", name.strip(), flags=re.I).strip()
    name = name.replace("_", " ")
    return name[:1].upper() + name[1:] if name else name

class Wiki:
    def __init__(self, wiki, user_agent, delay=1.0, session=None):
        self.api = wiki if wiki.startswith("http") else f"https://{wiki}.fandom.com/api.php"
        self.delay = delay
        self.s = session or requests.Session()
        self.s.headers["User-Agent"] = user_agent

    def get(self, **params):
        params.update(format="json", formatversion="2")
        for attempt in range(6):
            try:
                r = self.s.get(self.api, params=params, timeout=60)
            except requests.RequestException:
                time.sleep(5 * (attempt + 1))
                continue
            if r.status_code == 429 or r.status_code >= 500:
                time.sleep(5 * (attempt + 1))
                continue
            r.raise_for_status()
            data = r.json()
            if "error" in data:
                raise RuntimeError(f"API error: {data['error']}")
            time.sleep(self.delay)
            return data
        raise RuntimeError(f"Gave up after retries: {params}")

    def query_all(self, **params):
        cont = {}
        while True:
            data = self.get(**params, **cont)
            yield data
            if "continue" not in data: return
            cont = data["continue"]

    def all_titles(self):
        titles = []
        for d in self.query_all(action="query", list="allpages", apnamespace="0", apfilterredir="nonredirects", aplimit="500"):
            titles += [p["title"] for p in d["query"]["allpages"]]
        return titles

    def category_titles(self, category, depth, seen=None):
        seen = seen if seen is not None else set()
        cat = category if category.lower().startswith("category:") else "Category:" + category
        if cat in seen: return []
        seen.add(cat)
        titles = []
        for d in self.query_all(action="query", list="categorymembers", cmtitle=cat, cmlimit="500", cmtype="page|subcat"):
            for m in d["query"]["categorymembers"]:
                if m["ns"] == 0:
                    titles.append(m["title"])
                elif m["ns"] == 14 and depth > 0:
                    titles += self.category_titles(m["title"], depth - 1, seen)
        return titles

    def fetch_pages(self, titles, cache):
        stale = list(titles)
        if cache:
            stale = []
            for batch in chunks(titles, 50):
                d = self.get(action="query", prop="info", titles="|".join(batch), redirects="1")
                for p in d["query"].get("pages", []):
                    old = cache.get(p["title"])
                    if p.get("missing") is None and (not old or old.get("revid") != p.get("lastrevid")):
                        stale.append(p["title"])
        print(f"  {len(titles) - len(stale)} pages unchanged (cached), {len(stale)} to download")
        for i, batch in enumerate(chunks(stale, 50)):
            pages = {}
            for d in self.query_all(action="query", prop="revisions|categories|info|pageimages",
                                    rvprop="content|ids", rvslots="main", inprop="url",
                                    cllimit="max", clshow="!hidden", piprop="original",
                                    redirects="1", titles="|".join(batch)):
                for p in d["query"].get("pages", []):
                    if p.get("missing") is not None: continue
                    pg = pages.setdefault(p["title"], {"categories": []})
                    if p.get("revisions"):
                        rev = p["revisions"][0]
                        pg["wikitext"] = rev["slots"]["main"]["content"]
                        pg["revid"] = rev["revid"]
                    if p.get("fullurl"):
                        pg["url"] = p["fullurl"]
                    for c in p.get("categories", []):
                        pg["categories"].append(c["title"].split(":", 1)[1])
                    if p.get("original"):
                        pg["page_image"] = p["original"]["source"]
            for t, pg in pages.items():
                if "wikitext" in pg:
                    pg["categories"] = sorted(set(pg["categories"]))
                    cache[t] = pg
            print(f"  downloaded {min((i + 1) * 50, len(stale))}/{len(stale)} pages", end="\r")
        print()
        return {t: cache[t] for t in titles if t in cache}

    def resolve_files(self, filenames):
        out = {}
        for batch in chunks(sorted(filenames), 50):
            d = self.get(action="query", prop="imageinfo", iiprop="url|mime", iiurlwidth="1600", titles="|".join("File:" + f for f in batch))
            for p in d["query"].get("pages", []):
                info = (p.get("imageinfo") or [None])[0]
                if not info: continue
                url = info.get("url")
                if info.get("mime", "").endswith("svg+xml") and info.get("thumburl"):
                    url = info["thumburl"]
                out[norm_file(p["title"])] = {"url": url, "mime": info.get("mime", "")}
        return out

def flatten(code):
    out = []
    for node in code.nodes:
        if isinstance(node, Text): out.append(str(node))
        elif isinstance(node, Wikilink):
            target = str(node.title).strip()
            if re.match(r"^(file|image|category):", target, re.I): continue
            out.append(flatten(node.text) if node.text else target.split("#")[0])
        elif isinstance(node, ExternalLink): out.append(flatten(node.title) if node.title else str(node.url))
        elif isinstance(node, Template):
            name = str(node.name).strip().lower()
            if name in ("!",): out.append("|"); continue
            vals = [flatten(p.value).strip() for p in node.params if not p.showkey]
            vals = [v for v in vals if v]
            if len(vals) == 1 and re.fullmatch(r"[a-zA-Zµ]{1,3}", name) and re.match(r"^[\d.,]+$", vals[0]):
                vals = [f"{vals[0]} {str(node.name).strip()}"]
            out.append(" ".join(vals))
        elif isinstance(node, Tag):
            tag = str(node.tag).lower()
            if tag in ("ref", "references", "gallery"): continue
            if tag == "br": out.append("\n"); continue
            if node.contents is not None: out.append(flatten(node.contents))
            if tag in ("li", "p", "div"): out.append("\n")
        elif isinstance(node, HTMLEntity): out.append(node.normalize())
        elif isinstance(node, Comment): continue
        else: out.append(str(node))
    return "".join(out)

def clean_value(code):
    s = flatten(code)
    s = re.sub(r"'{2,}", "", s)
    lines = [l.strip().lstrip("*#:").strip() for l in s.splitlines()]
    s = "; ".join(l for l in lines if l)
    s = re.sub(r"\s+", " ", s)
    s = re.sub(r"(\s*;\s*)+", "; ", s)
    return s.strip(" ;")

def pick_infobox(code):
    def named(t): return sum(1 for p in t.params if p.showkey)
    for recursive in (False, True):
        tpls = code.filter_templates(recursive=recursive)
        for t in tpls:
            if "infobox" in str(t.name).lower() and named(t) >= 1: return t
        cands = [t for t in tpls if named(t) >= 3]
        if cands: return max(cands, key=named)
    return None

def parse_page(wikitext, image_field_re):
    code = mwparserfromhell.parse(wikitext or "")
    box = pick_infobox(code)
    if not box: return "", {}, {}, {}
    fields, positional, image_raw = OrderedDict(), OrderedDict(), OrderedDict()
    for p in box.params:
        key = str(p.name).strip()
        if not p.showkey:
            v = clean_value(p.value)
            if v: positional[f"param_{key}"] = v
            continue
        if image_field_re.match(key):
            image_raw[key] = str(p.value).strip()
            continue
        v = clean_value(p.value)
        if v: fields[key] = v
    return str(box.name).strip(), fields, positional, image_raw

def filenames_from(raw):
    names = []
    for m in FILENAME_RE.finditer(raw or ""):
        n = norm_file(m.group(1))
        if n and n not in names: names.append(n)
    return names

class Classifier:
    def __init__(self, profile):
        self.p = profile
        self.non_item = {f.lower() for f in profile.get("non_item_fields", [])}
        self.entities = []
        for e in profile["entities"]:
            m = e["match"]
            self.entities.append({
                **e,
                "_ib": kw_regex(m.get("infobox_keywords")),
                "_cat": kw_regex(m.get("category_keywords")),
                "_fields": {f.lower() for f in m.get("fields_any", [])},
                "_min": m.get("min_fields", 1),
                "_decisive": m.get("decisive", False),
                "_kindmap": [(label, kw_regex(words)) for label, words in ((e.get("kind") or {}).get("keyword_map") or [])],
            })
        g = profile.get("generation") or {}
        self.gen_code_fields = [f.lower() for f in g.get("code_fields", [])]
        self.gen_text_fields = [f.lower() for f in g.get("text_fields", [])]
        self.gen_rules = [(r["name"], re.compile(r["code_regex"], re.I) if r.get("code_regex") else None, kw_regex(r.get("keywords"))) for r in g.get("rules", [])]

    def classify(self, infobox, fields, categories):
        keys = {k.lower() for k in fields}
        if keys & self.non_item: return "other"
        best, best_score = "other", 0
        for e in self.entities:
            field_hit = len(keys & e["_fields"]) >= e["_min"] if e["_fields"] else False
            if e["_decisive"] and field_hit: return e["id"]
            score = 0
            if e["_ib"] and infobox and e["_ib"].search(infobox): score += 3
            if field_hit: score += 2
            if e["_cat"] and any(e["_cat"].search(c) for c in categories): score += 1
            if score > best_score: best, best_score = e["id"], score
        return best

    def kind(self, entity, infobox, fields, categories):
        if entity == "other": return re.sub(r"(?i)\binfobox\b", "", infobox).strip(" _-") or ""
        e = next(x for x in self.entities if x["id"] == entity)
        k = e.get("kind") or {}
        low = {kk.lower(): v for kk, v in fields.items()}
        for f in k.get("from_fields", []):
            if low.get(f.lower()): return low[f.lower()]
        for source in [infobox] + list(categories):
            for label, rx in e["_kindmap"]:
                if rx and source and rx.search(source): return label
        return ""

    def generation(self, fields, categories, title):
        low = {k.lower(): v for k, v in fields.items()}
        for f in self.gen_code_fields:
            v = low.get(f, "")
            for name, code_rx, _ in self.gen_rules:
                if v and code_rx and code_rx.search(v): return name
        sources = [low.get(f, "") for f in self.gen_text_fields] + list(categories) + [title]
        for v in sources:
            for name, _, kw in self.gen_rules:
                if v and kw and kw.search(v): return name
        return ""

def to_webp(content, dest, quality):
    im = Image.open(io.BytesIO(content))
    if getattr(im, "n_frames", 1) > 1:
        im.save(dest, "WEBP", save_all=True, quality=quality, method=4, loop=0)
        return
    if im.mode in ("P", "LA", "L", "PA"): im = im.convert("RGBA")
    elif im.mode not in ("RGB", "RGBA"): im = im.convert("RGB")
    im.save(dest, "WEBP", quality=quality, method=4)

def download_images(wiki, files, img_dir, quality, workers):
    os.makedirs(img_dir, exist_ok=True)
    result, todo = {}, []
    for f in files:
        rel = os.path.join("images", slug(os.path.splitext(f)[0]) + "_" + hashlib.sha1(f.encode()).hexdigest()[:6] + ".webp")
        result[f] = [rel, ""]
        if not os.path.exists(os.path.join(os.path.dirname(img_dir), rel)): todo.append(f)
    print(f"  {len(files) - len(todo)} images already saved, {len(todo)} to download")
    info = wiki.resolve_files(set(files)) if files else {}
    for f in files: result[f][1] = (info.get(f) or {}).get("url", "")
    failed = []

    def work(f):
        url = result[f][1]
        if not url: return f, "no URL (file missing on wiki)"
        dest = os.path.join(os.path.dirname(img_dir), result[f][0])
        for attempt in range(3):
            try:
                r = wiki.s.get(url, timeout=60)
                if r.status_code == 200:
                    to_webp(r.content, dest, quality)
                    return f, None
            except Exception: pass
            time.sleep(2 * (attempt + 1))
        return f, "download/convert failed"

    with cf.ThreadPoolExecutor(max_workers=workers) as ex:
        for n, (f, err) in enumerate(ex.map(work, todo), 1):
            if err:
                failed.append((f, err))
                result[f][0] = ""
            print(f"  images {n}/{len(todo)}", end="\r")
    if todo: print()
    return result, failed

def build_canon(profile, records):
    canon = {}
    for e in profile["entities"]:
        for c in e["columns"]: canon.setdefault(c.lower(), c)
    for a, target in (profile.get("aliases") or {}).items(): canon[a.lower()] = target
    counts = defaultdict(Counter)
    for r in records:
        for k in list(r["fields"]) + list(r["image_raw"]): counts[k.lower()][k] += 1
    for low, c in counts.items(): canon.setdefault(low, c.most_common(1)[0][0])
    return canon

def write_outputs(profile, records, out_dir, wiki_name):
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
    canon = build_canon(profile, records)
    sheets = OrderedDict((e["id"], e) for e in profile["entities"])
    other = profile.get("other", {"sheet": "Other", "kind": {"column": "page_type"}})
    sheets["other"] = {"id": "other", "sheet": other["sheet"], "columns": [], "kind": other.get("kind")}
    wb = Workbook()
    wb.remove(wb.active)
    col_report = []
    head = {"core": PatternFill("solid", fgColor="1F3864"), "related": PatternFill("solid", fgColor="2F5597"),
            "unrelated": PatternFill("solid", fgColor="A6A6A6"), "meta": PatternFill("solid", fgColor="595959")}

    for eid, e in sheets.items():
        rows = []
        for r in (x for x in records if x["entity"] == eid):
            row = OrderedDict()
            row["title"], row["url"], row["entity_type"], row["generation"] = r["title"], r["url"], eid, r["generation"]
            kind_col = (e.get("kind") or {}).get("column")
            if kind_col: row[kind_col] = r["kind"]
            row["image_webp"] = r["images"][0] if r["images"] else ""
            row["all_images_webp"] = " | ".join(r["images"])
            for k, v in r["fields"].items():
                ck = canon[k.lower()]
                row[ck] = (row[ck] + "; " + v) if row.get(ck) else v
            row["_infobox"] = r["infobox"]
            row["_categories"] = "; ".join(r["categories"])
            for k, v in r["image_raw"].items():
                ck = "_raw_" + canon[k.lower()]
                row[ck] = (row[ck] + " | " + v) if row.get(ck) else v
            row["_image_source_urls"] = " | ".join(r["image_urls"])
            for k, v in r["positional"].items(): row["_" + k] = v
            rows.append(row)

        core = ["title", "url", "entity_type", "generation"] + ([e["kind"]["column"]] if e.get("kind") else []) + ["image_webp", "all_images_webp"]
        present = Counter(k for row in rows for k, v in row.items() if v)
        related = [c for c in e["columns"] if present.get(c) and c not in core]
        meta = sorted((k for k in present if k.startswith("_")), key=lambda k: (not k.startswith("_infobox"), not k.startswith("_categories"), k))
        unrelated = sorted((k for k in present if k not in core and k not in related and k not in meta), key=lambda k: (-present[k], k.lower()))
        columns = core + related + unrelated + meta
        groups = {**{c: "core" for c in core}, **{c: "related" for c in related}, **{c: "unrelated" for c in unrelated}, **{c: "meta" for c in meta}}
        headers = [c.lstrip("_") for c in columns]

        with open(os.path.join(out_dir, f"{e['sheet']}.csv"), "w", encoding="utf-8-sig", newline="") as f:
            w = csv.writer(f)
            w.writerow(headers)
            for row in rows: w.writerow([row.get(c, "") for c in columns])

        ws = wb.create_sheet(e["sheet"])
        ws.append(headers)
        for cell, c in zip(ws[1], columns):
            cell.font = Font(name="Arial", bold=True, color="FFFFFF")
            cell.fill = head[groups[c]]
            cell.alignment = Alignment(wrap_text=True, vertical="center")
        for row in rows:
            ws.append([str(row.get(c, ""))[:EXCEL_CELL_LIMIT] for c in columns])
        if unrelated:
            first = columns.index(unrelated[0]) + 1
            for cell in ws.iter_cols(min_col=first, max_col=first, min_row=1, max_row=ws.max_row):
                for c in cell: c.border = Border(left=Side(style="thick", color="C00000"))
        for i, c in enumerate(columns, 1):
            ws.column_dimensions[ws.cell(1, i).column_letter].width = 40 if c in ("title", "image_webp", "all_images_webp") else 22
        ws.freeze_panes = "B2"
        ws.auto_filter.ref = ws.dimensions
        for c in columns:
            col_report.append([e["sheet"], c.lstrip("_"), groups[c], present.get(c, 0), len(rows),
                               round(100 * present.get(c, 0) / len(rows), 1) if rows else 0,
                               next((str(row[c])[:120] for row in rows if row.get(c)), "")])
        print(f"  {e['sheet']}: {len(rows)} rows, {len(related)} related + {len(unrelated)} other columns")

    ws = wb.create_sheet("Columns")
    ws.append(["sheet", "column", "group", "filled", "rows", "filled_%", "example"])
    for r in col_report: ws.append(r)
    ws.freeze_panes = "A2"
    ws.auto_filter.ref = ws.dimensions

    ws = wb.create_sheet("Summary")
    ws.append(["infobox template", "sorted into", "pages"])
    for (ib, ent), n in sorted(Counter((r["infobox"] or "(no infobox)", r["entity"]) for r in records).items(), key=lambda x: -x[1]):
        ws.append([ib, ent, n])
    ws.append([])
    ws.append(["sheet", "generation", "pages"])
    for (ent, gen), n in sorted(Counter((r["entity"], r["generation"] or "(unknown)") for r in records).items()):
        ws.append([ent, gen, n])
    for wsx in wb.worksheets:
        for row in wsx.iter_rows(min_row=2):
            for c in row: c.font = Font(name="Arial", size=10)

    path = os.path.join(out_dir, f"{wiki_name}_data.xlsx")
    wb.save(path)
    with open(os.path.join(out_dir, f"{wiki_name}_data.json"), "w", encoding="utf-8") as f:
        json.dump(records, f, ensure_ascii=False, indent=1)
    return path

# =============================================================================
# GUI IMPLEMENTATION
# =============================================================================

class RedirectText:
    """Redirects stdout to a tkinter text widget, handling carriage returns \r gracefully."""
    def __init__(self, text_widget):
        self.text_widget = text_widget

    def write(self, string):
        self.text_widget.configure(state="normal")
        if "\r" in string:
            self.text_widget.delete("end-1c linestart", "end-1c lineend")
            string = string.replace("\r", "")
        self.text_widget.insert("end", string)
        self.text_widget.see("end")
        self.text_widget.configure(state="disabled")

    def flush(self):
        pass

class ScraperConfig:
    """Dummy class to hold arguments similar to argparse."""
    pass

class FandomScraperApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Fandom Wiki Scraper")
        self.geometry("750x650")
        self.configure(padx=10, pady=10)

        # Main Frame
        main_frame = ttk.Frame(self)
        main_frame.pack(fill=tk.BOTH, expand=True)

        # Row 0: Wiki Selection
        ttk.Label(main_frame, text="Wiki Name/URL:").grid(row=0, column=0, sticky="w", pady=5)
        self.wiki_var = tk.StringVar(value="beyblade")
        ttk.Entry(main_frame, textvariable=self.wiki_var, width=50).grid(row=0, column=1, columnspan=2, sticky="we", pady=5)

        # Row 1: Profile JSON
        ttk.Label(main_frame, text="Profile JSON:").grid(row=1, column=0, sticky="w", pady=5)
        default_profile = os.path.join(os.path.dirname(os.path.abspath(__file__)), "profile_beyblade.json")
        self.profile_var = tk.StringVar(value=default_profile)
        ttk.Entry(main_frame, textvariable=self.profile_var, width=50).grid(row=1, column=1, sticky="we", pady=5)
        ttk.Button(main_frame, text="Browse", command=self.browse_profile).grid(row=1, column=2, padx=5, pady=5)

        # Row 2: Output Directory
        ttk.Label(main_frame, text="Output Folder:").grid(row=2, column=0, sticky="w", pady=5)
        self.out_var = tk.StringVar(value="")
        ttk.Entry(main_frame, textvariable=self.out_var, width=50).grid(row=2, column=1, sticky="we", pady=5)
        ttk.Button(main_frame, text="Browse", command=self.browse_out).grid(row=2, column=2, padx=5, pady=5)

        # Row 3: Categories
        ttk.Label(main_frame, text="Categories (comma separated):").grid(row=3, column=0, sticky="w", pady=5)
        self.cat_var = tk.StringVar(value="")
        ttk.Entry(main_frame, textvariable=self.cat_var, width=50).grid(row=3, column=1, columnspan=2, sticky="we", pady=5)

        # Row 4: Checkboxes
        check_frame = ttk.Frame(main_frame)
        check_frame.grid(row=4, column=0, columnspan=3, sticky="we", pady=10)
        
        self.all_var = tk.BooleanVar(value=True)
        ttk.Checkbutton(check_frame, text="Scrape ALL Pages", variable=self.all_var).pack(side=tk.LEFT, padx=5)

        self.no_images_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(check_frame, text="Skip Images", variable=self.no_images_var).pack(side=tk.LEFT, padx=5)

        self.refresh_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(check_frame, text="Force Refresh Cache", variable=self.refresh_var).pack(side=tk.LEFT, padx=5)

        self.keep_no_ib_var = tk.BooleanVar(value=False)
        ttk.Checkbutton(check_frame, text="Keep Pages without Infobox", variable=self.keep_no_ib_var).pack(side=tk.LEFT, padx=5)

        # Row 5: Numeric Settings
        num_frame = ttk.Frame(main_frame)
        num_frame.grid(row=5, column=0, columnspan=3, sticky="we", pady=5)
        
        ttk.Label(num_frame, text="Depth:").pack(side=tk.LEFT, padx=2)
        self.depth_var = tk.IntVar(value=2)
        ttk.Entry(num_frame, textvariable=self.depth_var, width=5).pack(side=tk.LEFT, padx=2)

        ttk.Label(num_frame, text="Limit (optional):").pack(side=tk.LEFT, padx=(15, 2))
        self.limit_var = tk.StringVar(value="")
        ttk.Entry(num_frame, textvariable=self.limit_var, width=8).pack(side=tk.LEFT, padx=2)

        ttk.Label(num_frame, text="WebP Quality:").pack(side=tk.LEFT, padx=(15, 2))
        self.quality_var = tk.IntVar(value=85)
        ttk.Entry(num_frame, textvariable=self.quality_var, width=5).pack(side=tk.LEFT, padx=2)

        ttk.Label(num_frame, text="Workers:").pack(side=tk.LEFT, padx=(15, 2))
        self.workers_var = tk.IntVar(value=4)
        ttk.Entry(num_frame, textvariable=self.workers_var, width=5).pack(side=tk.LEFT, padx=2)

        ttk.Label(num_frame, text="Delay (s):").pack(side=tk.LEFT, padx=(15, 2))
        self.delay_var = tk.DoubleVar(value=1.0)
        ttk.Entry(num_frame, textvariable=self.delay_var, width=5).pack(side=tk.LEFT, padx=2)

        # Row 6: Run Button
        self.run_btn = ttk.Button(main_frame, text="Start Scraper", command=self.start_scraping)
        self.run_btn.grid(row=6, column=0, columnspan=3, pady=15)

        # Row 7: Console Output
        self.log_widget = scrolledtext.ScrolledText(main_frame, height=15, state="disabled", bg="black", fg="lightgray", font=("Consolas", 10))
        self.log_widget.grid(row=7, column=0, columnspan=3, sticky="nsew", pady=5)
        
        main_frame.rowconfigure(7, weight=1)
        main_frame.columnconfigure(1, weight=1)

        # Redirect stdout and stderr
        sys.stdout = RedirectText(self.log_widget)
        sys.stderr = RedirectText(self.log_widget)

    def browse_profile(self):
        filepath = filedialog.askopenfilename(filetypes=[("JSON Files", "*.json"), ("All Files", "*.*")])
        if filepath:
            self.profile_var.set(filepath)

    def browse_out(self):
        dirpath = filedialog.askdirectory()
        if dirpath:
            self.out_var.set(dirpath)

    def start_scraping(self):
        if not self.all_var.get() and not self.cat_var.get().strip():
            messagebox.showerror("Error", "You must select 'Scrape ALL Pages' or provide Categories.")
            return
        if not os.path.exists(self.profile_var.get()):
            messagebox.showerror("Error", f"Profile file not found:\n{self.profile_var.get()}")
            return

        # Disable button during run
        self.run_btn.config(state="disabled", text="Running...")
        self.log_widget.configure(state="normal")
        self.log_widget.delete(1.0, tk.END)
        self.log_widget.configure(state="disabled")

        # Build args mapping
        args = ScraperConfig()
        args.wiki = self.wiki_var.get().strip()
        args.all = self.all_var.get()
        args.category = [c.strip() for c in self.cat_var.get().split(",")] if self.cat_var.get().strip() else None
        args.depth = self.depth_var.get()
        args.profile = self.profile_var.get()
        args.out = self.out_var.get().strip() or None
        
        limit_val = self.limit_var.get().strip()
        args.limit = int(limit_val) if limit_val.isdigit() else None
        
        args.no_images = self.no_images_var.get()
        args.quality = self.quality_var.get()
        args.image_workers = self.workers_var.get()
        args.delay = self.delay_var.get()
        args.refresh = self.refresh_var.get()
        args.keep_no_infobox = self.keep_no_ib_var.get()

        # Run in a background thread to prevent UI freezing
        thread = threading.Thread(target=self.run_engine, args=(args,))
        thread.daemon = True
        thread.start()

    def run_engine(self, args):
        try:
            # We call the main scraper logic wrapped directly into this script.
            with open(args.profile, encoding="utf-8") as f:
                profile = json.load(f)
            wiki_name = slug(re.sub(r"^https?://|\.fandom\.com.*$|/api\.php$", "", args.wiki))
            out_dir = args.out or f"output_{wiki_name}"
            os.makedirs(os.path.join(out_dir, "cache"), exist_ok=True)
            cache_path = os.path.join(out_dir, "cache", "pages.json")
            cache = {}
            if os.path.exists(cache_path) and not args.refresh:
                with open(cache_path, encoding="utf-8") as f:
                    cache = json.load(f)

            wiki = Wiki(args.wiki, profile.get("user_agent", "FandomScraper/1.0"), args.delay, None)
            print("1/4 Listing pages...")
            titles = []
            if args.all:
                titles = wiki.all_titles()
            for cat in args.category or []:
                titles += wiki.category_titles(cat, args.depth)
            titles = list(OrderedDict.fromkeys(titles))
            if args.limit:
                titles = titles[:args.limit]
            print(f"  {len(titles)} pages found.")

            print("\n2/4 Downloading page source...")
            pages = wiki.fetch_pages(titles, cache)
            with open(cache_path, "w", encoding="utf-8") as f:
                json.dump(cache, f, ensure_ascii=False)

            print("\n3/4 Sorting pages...")
            clf = Classifier(profile)
            img_re = re.compile(profile.get("image_field_regex", r"^image\d*$"), re.I)
            records, all_files = [], set()
            for title, pg in pages.items():
                infobox, fields, positional, image_raw = parse_page(pg.get("wikitext", ""), img_re)
                if not infobox and not args.keep_no_infobox: continue
                cats = pg.get("categories", [])
                entity = clf.classify(infobox, fields, cats)
                files = [f for raw in image_raw.values() for f in filenames_from(raw)]
                if not files and pg.get("page_image"):
                    files = [norm_file(pg["page_image"].split("/revision/")[0].rsplit("/", 1)[-1].replace("%20", " "))]
                all_files.update(files)
                records.append({"title": title, "url": pg.get("url", ""), "entity": entity, "infobox": infobox,
                                "kind": clf.kind(entity, infobox, fields, cats),
                                "generation": clf.generation(fields, cats, title),
                                "categories": cats, "fields": fields, "positional": positional,
                                "image_raw": image_raw, "files": files})
            
            summary_counts = Counter(r["entity"] for r in records).items()
            count_str = ", ".join(f"{k} {v}" for k, v in summary_counts) if summary_counts else "None"
            print(f"  {len(records)} pages with an infobox: {count_str}")

            print("\n4/4 Handling Images...")
            failed = []
            img_map = {}
            if args.no_images:
                print("  skipped (--no-images)")
            else:
                img_map, failed = download_images(wiki, all_files, os.path.join(out_dir, "images"),
                                                  args.quality, args.image_workers)
            for r in records:
                r["images"] = [img_map[f][0] for f in r["files"] if f in img_map and img_map[f][0]]
                r["image_urls"] = [img_map[f][1] for f in r["files"] if f in img_map and img_map[f][1]]
            
            if failed:
                with open(os.path.join(out_dir, "failed_images.txt"), "w", encoding="utf-8") as f:
                    f.writelines(f"{n}\t{e}\n" for n, e in failed)
                print(f"  {len(failed)} images failed, listed in failed_images.txt")

            print("\nWriting output files...")
            path = write_outputs(profile, records, out_dir, wiki_name)
            print(f"\nDone! Files saved to:\n{path}")
            
            messagebox.showinfo("Complete", f"Scraping completed successfully!\nOutputs saved in {out_dir}")

        except Exception as e:
            import traceback
            traceback.print_exc()
            messagebox.showerror("Error", f"An error occurred during execution:\n{e}")
        finally:
            # Re-enable UI button safely from the main thread
            self.after(0, lambda: self.run_btn.config(state="normal", text="Start Scraper"))

if __name__ == "__main__":
    app = FandomScraperApp()
    app.mainloop()