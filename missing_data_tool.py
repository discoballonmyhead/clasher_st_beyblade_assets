#!/usr/bin/env python3
"""
Missing data tool - see what's empty in the workbooks, field by field, and fill it.

Separate from the scraper (fandom_scraper.py) and the packager (beyblade_data.py).

What it does
  * Report: per tab, how many rows miss each field (type, spinDir, stats, mass, image, ...), which rows.
    Rows marked deleted are ignored.
  * Auto-fill (you see every change before it's applied):
      parent    a variant copies shared fields from its parent row (parentPartId / parentProductId /
                parentCardId): type, spin, stats, weight, system ... - never code / edition / manufacturer
      siblings  rows with the same name (and manufacturer) agree on a stable field (type, spin, stats ...)
                -> blanks get that value; skipped when they disagree
      derive    values that follow from the row itself: series from the tab name, ratchet "3-60" ->
                protrusions 3 / height 60, currency + region from the manufacturer, hobby name
  * Fill from wiki: re-reads the wiki page(s) of the chosen rows with the scraper (same polite client,
    rendered-infobox fallback, gallery images) and fills only blank cells.
  * Manual: type a value into a field, or put an image (file / URL / clipboard) on a row - it's trimmed,
    fitted inside 600 px, a 128 px minified copy is made, both WebP.
  Every save keeps a .bak of the workbook first.

GUI:  python missing_data_tool.py
CLI:  python missing_data_tool.py report --workbook beyblade_parts.xlsx [--sheet Parts_X_Blades] [--csv out.csv]
      python missing_data_tool.py fill   --workbook beyblade_parts.xlsx [--sheet ...] [--parent] [--siblings] [--derive] [--dry-run]
      python missing_data_tool.py set    --workbook beyblade_parts.xlsx --sheet Parts_X_Blades --id 65 --field mass --value 34.6
      python missing_data_tool.py image  --workbook beyblade_parts.xlsx --sheet Parts_X_Blades --id 65 --file found.png   (or --url)
      python missing_data_tool.py wiki   --workbook beyblade_parts.xlsx --sheet Parts_X_Blades [--ids 65 72] [--limit 20]
"""
import argparse
import base64
import csv
import io
import os
import re
import sys
from collections import OrderedDict

from PIL import Image

import beyblade_schema as S
from beyblade_store import Book, norm_name

FULL_SIZE, MIN_SIZE, WEBP_QUALITY = 600, 128, 85

# Columns that are fine to leave empty (bookkeeping, optional links, game-specific extras)
OPTIONAL = {"parentPartId", "variantLabel", "updated_at", "deleted", "incompleteData", "integratedRatchet",
            "twoStat", "parentProductId", "parentCardId", "parentSetId", "linkedPartType", "linkedPartDataID",
            "illustrator", "legality", "description", "subType", "productID", "lastKnownCode"}
# Fields a variant shares with its parent
INHERIT = {"name", "type", "spinDir", "attack", "defense", "stamina", "mass", "wbolegality", "system",
           "layerComponent", "discType", "movementStyle", "baseName", "protrusions", "heightMm", "dash",
           "burstRes", "hobbyName", "hobbyGeneration",
           # products: random-booster items / re-releases share these with the box
           "productType", "currency", "region", "releaseDate", "itemCost",
           # cards: parallels share these with the base card
           "setCode", "setName", "cardNumber", "subtitle", "cardType", "attribute", "cost", "power",
           "battleEdge", "spinStrength", "effectText", "loreText"}
# Fields that don't change between releases of the same part
STABLE = {"type", "spinDir", "attack", "defense", "stamina", "wbolegality", "system", "layerComponent",
          "movementStyle", "baseName", "protrusions", "heightMm", "dash", "burstRes", "discType"}
PARENT_COL = {"dataID": ("parentPartId", "parentCardId"), "productID": ("parentProductId",),
              "setID": ("parentSetId",)}


def blank(v):
    return v is None or (isinstance(v, str) and not v.strip())


def is_deleted(row):
    return str(row.get("deleted") or "").strip().lower() == "true"


def kind_of_workbook(path):
    name = os.path.basename(path).lower()
    return "tcg" if "tcg" in name else "products" if "product" in name else "parts"


def sheet_info(sheet):
    """-> (id column, image column or None, minified image column or None) for a data tab, else None."""
    if S.parse_part_sheet(sheet):
        return ("dataID",) + tuple(S.PART_IMAGE_COLS)
    cfg = S.SHEETS.get(sheet)
    if cfg and cfg.get("id"):
        return (cfg["id"],) + (tuple(cfg["images"]) if cfg.get("images") else (None, None))
    return None


def data_sheets(book):
    return [n for n in book.wb.sheetnames if sheet_info(n)]


def expected_fields(book, sheet, include_optional=False):
    idc, img, mini = sheet_info(sheet)
    cols = [c for c in book.headers(book.wb[sheet]) if c not in (idc, img, mini)]
    return cols if include_optional else [c for c in cols if c not in OPTIONAL]


def parse_value(text):
    t = str(text).strip()
    if t == "":
        return None
    if re.fullmatch(r"-?\d+", t):
        return int(t)
    if re.fullmatch(r"-?\d+\.\d+", t):
        return float(t)
    return t


# ── analysis ──────────────────────────────────────────────────────────────────

def image_rows(book, sheet):
    """(rows with full image, rows with minified image) as sets of row numbers."""
    idc, img, mini = sheet_info(sheet)
    ws = book.wb[sheet]
    hdr = book.headers(ws)
    full = {i.anchor._from.row + 1 for i in ws._images if img and i.anchor._from.col + 1 == hdr.get(img)}
    small = {i.anchor._from.row + 1 for i in ws._images if mini and i.anchor._from.col + 1 == hdr.get(mini)}
    return full, small


def analyze(book, sheet, include_optional=False):
    """-> {"rows": [(r, row)], "fields": OrderedDict(field -> [row ids missing it]), "total": n}"""
    idc, img, mini = sheet_info(sheet)
    rows = [(r, x) for r, x in book.rows(book.wb[sheet]) if not is_deleted(x)]
    fields = OrderedDict((f, []) for f in expected_fields(book, sheet, include_optional))
    for r, x in rows:
        for f in fields:
            if blank(x.get(f)):
                fields[f].append(x.get(idc))
    if img:
        full, small = image_rows(book, sheet)
        fields[img] = [x.get(idc) for r, x in rows if r not in full]
        fields[mini] = [x.get(idc) for r, x in rows if r not in small]
    return {"rows": rows, "fields": fields, "total": len(rows)}


def row_missing(book, sheet, r, row, include_optional=False):
    idc, img, mini = sheet_info(sheet)
    miss = [f for f in expected_fields(book, sheet, include_optional) if blank(row.get(f))]
    if img:
        full, _ = image_rows(book, sheet)
        if r not in full:
            miss.append(img)
    return miss


def report(book, sheets=None, include_optional=False, csv_path=None, out=print):
    lines = []
    for sh in sheets or data_sheets(book):
        a = analyze(book, sh, include_optional)
        if not a["total"]:
            continue
        miss = {f: ids for f, ids in a["fields"].items() if ids}
        out(f"\n{sh}: {a['total']} rows" + ("" if miss else " - nothing missing"))
        for f, ids in sorted(miss.items(), key=lambda kv: -len(kv[1])):
            never = " (never filled in this tab)" if len(ids) == a["total"] else ""
            shown = ", ".join(str(i) for i in ids[:12]) + (" ..." if len(ids) > 12 else "")
            out(f"  {f:18s} {len(ids):5d} missing ({100 * len(ids) / a['total']:5.1f}%){never}  ids: {shown}")
            lines.append([sh, f, len(ids), a["total"], " ".join(str(i) for i in ids)])
    if csv_path:
        with open(csv_path, "w", newline="", encoding="utf-8-sig") as fh:
            w = csv.writer(fh)
            w.writerow(["sheet", "field", "missing", "rows", "ids"])
            w.writerows(lines)
        out(f"\nReport written to {csv_path}")


# ── auto-fill ─────────────────────────────────────────────────────────────────

def _ratchet_from_name(name):
    m = re.search(r"\b(\d{1,2})-(\d{2,3})\b", str(name or ""))
    return (int(m.group(1)), int(m.group(2))) if m else (None, None)


def propose_fills(book, sheet, parent=True, siblings=True, derive=True):
    """-> [(row_number, row_id, field, new_value, source)] for blank cells only."""
    idc, _, _ = sheet_info(sheet)
    rows = [(r, x) for r, x in book.rows(book.wb[sheet]) if not is_deleted(x)]
    hdr = book.headers(book.wb[sheet])
    out, taken = [], set()

    def add(r, x, f, v, src):
        if f in hdr and blank(x.get(f)) and not blank(v) and (r, f) not in taken:
            taken.add((r, f))
            out.append((r, x.get(idc), f, v, src))

    if derive:
        part = S.parse_part_sheet(sheet)
        for r, x in rows:
            if part:
                add(r, x, "hobbyGeneration", part[0], "derive: series of this tab")
                add(r, x, "hobbyName", S.HOBBY_NAME, "derive")
                if part[1] == "ratchets":
                    p, h = _ratchet_from_name(x.get("name"))
                    add(r, x, "protrusions", p, "derive: from the name")
                    add(r, x, "heightMm", h, "derive: from the name")
            elif sheet in ("Products", "Accessories"):
                add(r, x, "hobbyName", S.HOBBY_NAME, "derive")
                manu = x.get("manufacturer")
                add(r, x, "currency", {"Takara-Tomy": "JPY", "Hasbro": "USD"}.get(manu), "derive: manufacturer")
                add(r, x, "region", {"Takara-Tomy": "JP", "Hasbro": "US"}.get(manu), "derive: manufacturer")
            elif sheet.startswith("TCG_"):
                add(r, x, "hobbyName", S.TCG_HOBBY_NAME, "derive")

    if parent:
        by_id = {str(x.get(idc)): x for _, x in rows}
        for r, x in rows:
            pid = next((x.get(c) for c in PARENT_COL.get(idc, ()) if not blank(x.get(c))), None)
            p = by_id.get(str(pid)) if pid is not None else None
            if p is None:
                continue
            for f in sorted(INHERIT):
                if f == "name" and not blank(x.get("name")):
                    continue
                add(r, x, f, p.get(f), f"parent #{pid}")

    if siblings:
        groups = {}
        for r, x in rows:
            groups.setdefault((norm_name(x.get("name")), x.get("manufacturer")), []).append((r, x))
        for (name, _), members in groups.items():
            if not name or len(members) < 2:
                continue
            for f in sorted(STABLE):
                have = [x.get(f) for _, x in members if not blank(x.get(f))]
                vals = {str(v).strip().lower(): v for v in have}
                if len(vals) == 1:
                    v = next(iter(vals.values()))
                    for r, x in members:
                        add(r, x, f, v, f"same name: {len(have)} other row(s) say so, none disagree")
    return out


def apply_fills(book, sheet, fills):
    ws = book.wb[sheet]
    hdr = book.headers(ws)
    n = 0
    for r, _, f, v, _ in fills:
        if f in hdr and blank(ws.cell(r, hdr[f]).value):
            ws.cell(r, hdr[f]).value = v
            n += 1
    if n:
        book.dirty = True
        book._rows_cache.pop(sheet, None)
    return n


def find_row(book, sheet, row_id):
    idc = sheet_info(sheet)[0]
    r, _ = book.find(book.wb[sheet], lambda x: str(x.get(idc)).strip() == str(row_id).strip())
    return r


def set_value(book, sheet, row_id, field, value):
    r = find_row(book, sheet, row_id)
    if r is None:
        raise ValueError(f"No row with {sheet_info(sheet)[0]} = {row_id} in {sheet}")
    ws = book.wb[sheet]
    hdr = book.headers(ws)
    if field not in hdr:
        raise ValueError(f"{sheet} has no column '{field}'")
    ws.cell(r, hdr[field]).value = parse_value(value) if isinstance(value, str) else value
    book.dirty = True
    book._rows_cache.pop(sheet, None)
    return r


# ── images ────────────────────────────────────────────────────────────────────

def normalize_image(data, full=FULL_SIZE, mini=MIN_SIZE):
    """Any image bytes -> (full_webp, min_webp): transparent borders trimmed, aspect kept, fitted inside
    full x full (never upscaled)."""
    im = Image.open(io.BytesIO(data))
    im.seek(0)
    im = im.convert("RGBA")
    bbox = im.getchannel("A").getbbox()
    if bbox and bbox != (0, 0, im.width, im.height):
        im = im.crop(bbox)

    def fit(img, size):
        img = img.copy()
        img.thumbnail((size, size), Image.LANCZOS)
        buf = io.BytesIO()
        img.save(buf, "WEBP", quality=WEBP_QUALITY, method=6)
        return buf.getvalue()
    return fit(im, full), fit(im, mini)


def set_row_image(book, sheet, row_id, data):
    idc, img, mini = sheet_info(sheet)
    if not img:
        raise ValueError(f"{sheet} has no image columns")
    r = find_row(book, sheet, row_id)
    if r is None:
        raise ValueError(f"No row with {idc} = {row_id} in {sheet}")
    full, small = normalize_image(data)
    ws = book.wb[sheet]
    book.set_image(ws, r, img, full, "full", replace=True)
    book.set_image(ws, r, mini, small, "min", replace=True)
    return r, full, small


def current_image(book, sheet, r):
    idc, img, _ = sheet_info(sheet)
    if not img:
        return None
    ws = book.wb[sheet]
    col = book.headers(ws).get(img)
    for im in ws._images:
        if im.anchor._from.row + 1 == r and im.anchor._from.col + 1 == col:
            return im._data()
    return None


def fetch_url(url):
    import requests
    r = requests.get(url, timeout=(10, 30), headers={"User-Agent": "ClasherMissingDataTool/1.0"})
    r.raise_for_status()
    return r.content


# ── fill from wiki (uses the scraper) ─────────────────────────────────────────

def wiki_pages_for(book, sheet, ids):
    """Wiki page titles (and scraper target) for rows: from the _scrape_log, else a guess from the name."""
    idc = sheet_info(sheet)[0]
    want = {str(i) for i in ids}
    titles, target = [], None
    if "_scrape_log" in book.wb.sheetnames:
        for row in book.wb["_scrape_log"].iter_rows(min_row=2, values_only=True):
            if row and row[1] == sheet and str(row[2]) in want and row[3] and "::" not in str(row[3]):
                titles.append(str(row[3]).split("#")[0])
                target = target or row[0]
    part = S.parse_part_sheet(sheet)
    if part and not target:
        target = f"parts:{part[0]}:{part[1]}"
    found = {str(row[2]) for row in (book.wb["_scrape_log"].iter_rows(min_row=2, values_only=True)
                                     if "_scrape_log" in book.wb.sheetnames else []) if row and row[1] == sheet}
    if part and part[2]:
        label = part[2]["label"]
        for r, x in book.rows(book.wb[sheet]):
            if str(x.get(idc)) in want and str(x.get(idc)) not in found and x.get("name"):
                titles.append(f"{label} - {str(x['name']).replace(' ', '')}")  # wiki writes "DranSword"
    return list(OrderedDict.fromkeys(titles)), target


def wiki_fill(book_path, sheet, ids, limit=None, log=print, stop_event=None, cfg=None):
    """Re-scrape the rows' pages: fills blank cells (stats, images, variants) only. Saves the workbook."""
    import fandom_scraper as fs
    book = Book(book_path, kind_of_workbook(book_path))
    titles, target = wiki_pages_for(book, sheet, ids)
    if not titles or not target:
        log("No wiki page known for these rows (not in _scrape_log and no part name to guess from).")
        return 0
    if limit:
        titles = titles[:limit]
    cfg = cfg or fs.load_config()
    cfg["workbooks"][kind_of_workbook(book_path)] = os.path.abspath(book_path)
    sc = fs.Scraper(cfg, stop_event=stop_event, refresh_existing=True)
    log(f"Re-reading {len(titles)} wiki page(s) for {sheet} ({target}) - fills blank cells only ...")
    try:
        bs = max(1, int(cfg["politeness"]["batch_size"]))
        done = 0
        for i in range(0, len(titles), bs):
            done = sc.process_batch(target, titles[i:i + bs], done_n=done, total=len(titles))
    except fs.StopScrape as e:
        log(f"Stopped safely: {e}")
    finally:
        sc.save_all()
    return len(titles)


# ── CLI ───────────────────────────────────────────────────────────────────────

def run_cli(argv):
    ap = argparse.ArgumentParser(description="Find and fill missing data in the workbooks")
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("report", "fill", "set", "image", "wiki"):
        p = sub.add_parser(name)
        p.add_argument("--workbook", required=True)
        p.add_argument("--sheet", required=name in ("set", "image"))
        if name == "report":
            p.add_argument("--csv")
            p.add_argument("--all-columns", action="store_true", help="also count optional columns")
        if name == "fill":
            for f in ("parent", "siblings", "derive"):
                p.add_argument(f"--{f}", action="store_true")
            p.add_argument("--dry-run", action="store_true")
        if name in ("set", "image"):
            p.add_argument("--id", required=True)
        if name == "set":
            p.add_argument("--field", required=True)
            p.add_argument("--value", required=True)
        if name == "image":
            p.add_argument("--file")
            p.add_argument("--url")
        if name == "wiki":
            p.add_argument("--ids", nargs="*", help="row ids (default: every row with something missing)")
            p.add_argument("--limit", type=int)
    a = ap.parse_args(argv)
    book = Book(a.workbook, kind_of_workbook(a.workbook))
    sheets = [a.sheet] if a.sheet else data_sheets(book)
    for sh in sheets:
        if sh not in book.wb.sheetnames or not sheet_info(sh):
            sys.exit(f"'{sh}' isn't a data tab of {a.workbook}. Tabs: {', '.join(data_sheets(book))}")

    if a.cmd == "report":
        report(book, sheets, a.all_columns, a.csv)
    elif a.cmd == "fill":
        use = {k: getattr(a, k) for k in ("parent", "siblings", "derive")}
        if not any(use.values()):
            use = dict.fromkeys(use, True)
        total = 0
        for sh in sheets:
            fills = propose_fills(book, sh, **use)
            for r, rid, f, v, src in fills:
                print(f"  {sh} #{rid}: {f} = {v!r}   ({src})")
            if not a.dry_run:
                total += apply_fills(book, sh, fills)
        if a.dry_run:
            print("\n(dry run - nothing written)")
        elif total:
            book.save()
            print(f"\n{total} cells filled, {a.workbook} saved (.bak kept)")
        else:
            print("\nNothing to fill.")
    elif a.cmd == "set":
        try:
            r = set_value(book, a.sheet, a.id, a.field, a.value)
        except ValueError as e:
            sys.exit(str(e))
        book.save()
        print(f"{a.sheet} row {r} (id {a.id}): {a.field} = {a.value}")
    elif a.cmd == "image":
        if not (a.file or a.url):
            sys.exit("Give --file or --url.")
        data = fetch_url(a.url) if a.url else open(a.file, "rb").read()
        try:
            r, full, small = set_row_image(book, a.sheet, a.id, data)
        except ValueError as e:
            sys.exit(str(e))
        book.save()
        print(f"{a.sheet} row {r} (id {a.id}): image {len(full) // 1024} KB + minified {len(small) // 1024} KB saved")
    elif a.cmd == "wiki":
        for sh in sheets:
            ids = a.ids or sorted({i for f, lst in analyze(book, sh)["fields"].items() for i in lst}, key=str)
            if ids:
                wiki_fill(a.workbook, sh, ids, a.limit)


# ── GUI ───────────────────────────────────────────────────────────────────────

def run_gui(workbook=""):
    import queue
    import threading
    import tkinter as tk
    from tkinter import ttk, filedialog, messagebox

    root = tk.Tk()
    root.title("Missing data tool")
    root.geometry("1280x760")
    st = {"book": None, "path": "", "sheet": None, "rows": [], "row": None, "new_img": None, "editors": {}}
    q = queue.Queue()

    # top bar
    top = ttk.Frame(root, padding=6)
    top.pack(fill=tk.X)
    wb_var, sheet_var, filt_var = tk.StringVar(value=workbook), tk.StringVar(), tk.StringVar()
    field_filter = tk.StringVar(value="")
    all_cols = tk.BooleanVar(value=False)
    ttk.Label(top, text="Workbook:").pack(side=tk.LEFT)
    ttk.Entry(top, textvariable=wb_var, width=50).pack(side=tk.LEFT, padx=4)
    ttk.Button(top, text="Browse...", command=lambda: (wb_var.set(
        filedialog.askopenfilename(filetypes=[("Excel", "*.xlsx")]) or wb_var.get()), open_book())).pack(side=tk.LEFT)
    ttk.Button(top, text="Open / reload", command=lambda: open_book()).pack(side=tk.LEFT, padx=4)
    ttk.Label(top, text="Tab:").pack(side=tk.LEFT, padx=(12, 2))
    sheet_box = ttk.Combobox(top, textvariable=sheet_var, width=30, state="readonly")
    sheet_box.pack(side=tk.LEFT)
    ttk.Checkbutton(top, text="Count optional columns", variable=all_cols,
                    command=lambda: refresh()).pack(side=tk.LEFT, padx=8)

    actions = ttk.Frame(root, padding=(6, 0))
    actions.pack(fill=tk.X)
    ttk.Button(actions, text="Auto-fill (preview)...", command=lambda: autofill()).pack(side=tk.LEFT)
    ttk.Button(actions, text="Fill selected rows from wiki", command=lambda: wiki(selected_only=True)).pack(side=tk.LEFT, padx=4)
    ttk.Button(actions, text="Fill all rows of this field from wiki", command=lambda: wiki(selected_only=False)).pack(side=tk.LEFT)
    ttk.Button(actions, text="Export report (CSV)...", command=lambda: export()).pack(side=tk.LEFT, padx=4)

    panes = ttk.PanedWindow(root, orient=tk.HORIZONTAL)
    panes.pack(fill=tk.BOTH, expand=True, padx=6, pady=6)
    # fields summary
    lf = ttk.Frame(panes)
    ttk.Label(lf, text="Missing per field (click to filter rows)").pack(anchor="w")
    ftree = ttk.Treeview(lf, columns=("missing", "pct"), height=20)
    ftree.heading("#0", text="field")
    ftree.heading("missing", text="missing")
    ftree.heading("pct", text="%")
    ftree.column("#0", width=140)
    ftree.column("missing", width=70, anchor="e")
    ftree.column("pct", width=60, anchor="e")
    ftree.pack(fill=tk.BOTH, expand=True)
    panes.add(lf, weight=1)
    # rows
    mf = ttk.Frame(panes)
    rowbar = ttk.Frame(mf)
    rowbar.pack(fill=tk.X)
    ttk.Label(rowbar, text="Rows  filter:").pack(side=tk.LEFT)
    ttk.Entry(rowbar, textvariable=filt_var, width=24).pack(side=tk.LEFT, padx=4)
    filt_lbl = ttk.Label(rowbar, text="")
    filt_lbl.pack(side=tk.LEFT)
    rtree = ttk.Treeview(mf, columns=("name", "code", "missing"), selectmode="extended")
    for c, w, t in (("#0", 60, "id"), ("name", 160, "name"), ("code", 90, "code"), ("missing", 360, "missing")):
        rtree.heading(c, text=t)
        rtree.column(c, width=w)
    rtree.pack(fill=tk.BOTH, expand=True)
    panes.add(mf, weight=3)
    # editor
    ef = ttk.Frame(panes)
    sel_lbl = ttk.Label(ef, text="Pick a row", wraplength=330, font=("", 10, "bold"))
    sel_lbl.pack(anchor="w")
    canvas = tk.Canvas(ef, width=340, height=330, highlightthickness=0)
    canvas.pack(fill=tk.X)
    form = ttk.Frame(canvas)
    canvas.create_window((0, 0), window=form, anchor="nw")
    form.bind("<Configure>", lambda e: canvas.configure(scrollregion=canvas.bbox("all")))
    ttk.Button(ef, text="Save field values", command=lambda: save_fields()).pack(fill=tk.X, pady=(4, 8))
    imgs = ttk.Frame(ef)
    imgs.pack(fill=tk.X)
    cur_img, new_img = ttk.Label(imgs, text="(no image)"), ttk.Label(imgs, text="")
    ttk.Label(imgs, text="current").grid(row=0, column=0)
    ttk.Label(imgs, text="new").grid(row=0, column=1)
    cur_img.grid(row=1, column=0, padx=4)
    new_img.grid(row=1, column=1, padx=4)
    url_var = tk.StringVar()
    ib = ttk.Frame(ef)
    ib.pack(fill=tk.X, pady=4)
    ttk.Button(ib, text="Image file...", command=lambda: load_img("file")).pack(side=tk.LEFT)
    ttk.Button(ib, text="Paste", command=lambda: load_img("clipboard")).pack(side=tk.LEFT, padx=2)
    ttk.Button(ib, text="Use parent's image", command=lambda: load_img("parent")).pack(side=tk.LEFT)
    ub = ttk.Frame(ef)
    ub.pack(fill=tk.X)
    ttk.Entry(ub, textvariable=url_var).pack(side=tk.LEFT, fill=tk.X, expand=True)
    ttk.Button(ub, text="From URL", command=lambda: load_img("url")).pack(side=tk.LEFT)
    save_img_btn = ttk.Button(ef, text="Save image to this row", state="disabled", command=lambda: save_img())
    save_img_btn.pack(fill=tk.X, pady=4)
    panes.add(ef, weight=2)

    logbox = tk.Text(root, height=7, state="disabled", bg="#111", fg="#ddd", font=("Consolas", 9))
    logbox.pack(fill=tk.X, padx=6, pady=(0, 6))

    def log(msg):
        q.put(str(msg))

    def pump():
        try:
            while True:
                line = q.get_nowait()
                logbox.configure(state="normal")
                logbox.insert("end", line + "\n")
                logbox.see("end")
                logbox.configure(state="disabled")
        except queue.Empty:
            pass
        root.after(150, pump)

    def thumb(widget, data, size=150):
        if not data:
            widget.config(image="", text="(no image)")
            widget.image = None
            return
        im = Image.open(io.BytesIO(data)).convert("RGBA")
        im.thumbnail((size, size))
        buf = io.BytesIO()
        im.save(buf, "PNG")
        ph = tk.PhotoImage(data=base64.b64encode(buf.getvalue()))
        widget.config(image=ph, text="")
        widget.image = ph

    def open_book():
        path = wb_var.get().strip()
        if not path or not os.path.exists(path):
            log("Choose an existing workbook.")
            return
        st["book"], st["path"] = Book(path, kind_of_workbook(path)), path
        sheets = [s for s in data_sheets(st["book"]) if st["book"].rows(st["book"].wb[s])]
        sheet_box.config(values=sheets)
        if sheets and sheet_var.get() not in sheets:
            sheet_var.set(sheets[0])
        log(f"Opened {os.path.basename(path)}: {len(sheets)} tabs with rows")
        refresh()

    def refresh(*_):
        book, sh = st["book"], sheet_var.get()
        if not book or not sh:
            return
        st["sheet"] = sh
        a = analyze(book, sh, all_cols.get())
        ftree.delete(*ftree.get_children())
        ftree.insert("", "end", iid="__all__", text="(all rows)", values=(a["total"], ""))
        for f, ids in sorted(a["fields"].items(), key=lambda kv: -len(kv[1])):
            pct = 100 * len(ids) / a["total"] if a["total"] else 0
            ftree.insert("", "end", iid=f, text=f, values=(len(ids), f"{pct:.0f}"))
        fill_rows()

    def fill_rows(*_):
        book, sh = st["book"], st["sheet"]
        if not book:
            return
        rtree.delete(*rtree.get_children())
        idc = sheet_info(sh)[0]
        fwant, txt = field_filter.get(), filt_var.get().strip().lower()
        st["rows"] = {}
        full, _ = image_rows(book, sh)
        exp = expected_fields(book, sh, all_cols.get())
        img_col = sheet_info(sh)[1]
        n = 0
        for r, x in book.rows(book.wb[sh]):
            if is_deleted(x):
                continue
            miss = [f for f in exp if blank(x.get(f))] + ([img_col] if img_col and r not in full else [])
            if fwant and fwant not in miss:
                continue
            label = f"{x.get(idc)} {x.get('name') or x.get('productName') or ''} {x.get('code') or x.get('sku') or ''}"
            if txt and txt not in label.lower():
                continue
            iid = f"r{r}"
            st["rows"][iid] = r
            rtree.insert("", "end", iid=iid, text=str(x.get(idc)),
                         values=(x.get("name") or x.get("productName") or x.get("setName") or "",
                                 x.get("code") or x.get("sku") or x.get("cardNumber") or "", ", ".join(miss)))
            n += 1
        filt_lbl.config(text=f"{n} rows" + (f" missing '{fwant}'" if fwant else ""))

    def on_field(_=None):
        sel = ftree.selection()
        field_filter.set("" if not sel or sel[0] == "__all__" else sel[0])
        fill_rows()

    def on_row(_=None):
        sel = rtree.selection()
        if not sel:
            return
        r = st["rows"][sel[0]]
        st["row"] = r
        book, sh = st["book"], st["sheet"]
        x = dict(book.rows(book.wb[sh])).get(r, {})
        sel_lbl.config(text=f"{sh}  #{x.get(sheet_info(sh)[0])}  {x.get('name') or x.get('productName') or ''}")
        for w in form.winfo_children():
            w.destroy()
        st["editors"] = {}
        for i, f in enumerate(expected_fields(book, sh, True)):
            ttk.Label(form, text=f).grid(row=i, column=0, sticky="w")
            var = tk.StringVar(value="" if blank(x.get(f)) else str(x.get(f)))
            e = tk.Entry(form, textvariable=var, width=30, bg="#ffe2b8" if blank(x.get(f)) else "white")
            e.grid(row=i, column=1, sticky="we", padx=4, pady=1)
            st["editors"][f] = (var, x.get(f))
        thumb(cur_img, current_image(book, sh, r))
        save_img_btn.config(state="normal" if st["new_img"] else "disabled")

    def save_fields():
        book, sh, r = st["book"], st["sheet"], st["row"]
        if not r:
            return
        ws = book.wb[sh]
        hdr = book.headers(ws)
        n = 0
        for f, (var, old) in st["editors"].items():
            new = parse_value(var.get())
            if str(new if new is not None else "") != str(old if old is not None else ""):
                ws.cell(r, hdr[f]).value = new  # (ws.cell(r, c, None) would NOT clear a cell)
                n += 1
        if n:
            book.dirty = True
            book._rows_cache.pop(sh, None)
            book.save()
            log(f"Saved {n} field(s) on {sh} row {r}.")
            refresh()

    def load_img(how):
        try:
            if how == "file":
                p = filedialog.askopenfilename(filetypes=[("Images", "*.png *.jpg *.jpeg *.webp *.gif *.bmp")])
                if not p:
                    return
                data = open(p, "rb").read()
            elif how == "url":
                data = fetch_url(url_var.get().strip())
            elif how == "parent":
                book, sh, r = st["book"], st["sheet"], st["row"]
                idc = sheet_info(sh)[0]
                x = dict(book.rows(book.wb[sh])).get(r, {})
                pid = next((x.get(c) for c in PARENT_COL.get(idc, ()) if not blank(x.get(c))), None)
                pr = find_row(book, sh, pid) if pid is not None else None
                data = current_image(book, sh, pr) if pr else None
                if not data:
                    log("This row has no parent with an image.")
                    return
            else:
                from PIL import ImageGrab
                clip = ImageGrab.grabclipboard()
                if clip is None:
                    log("No image on the clipboard (copy the image itself).")
                    return
                if isinstance(clip, list):
                    data = open(clip[0], "rb").read()
                else:
                    buf = io.BytesIO()
                    clip.save(buf, "PNG")
                    data = buf.getvalue()
            full, _ = normalize_image(data)
        except Exception as e:
            messagebox.showerror("Image", f"Couldn't load that image:\n{e}")
            return
        st["new_img"] = data
        thumb(new_img, full)
        save_img_btn.config(state="normal" if st["row"] else "disabled")

    def save_img():
        book, sh, r = st["book"], st["sheet"], st["row"]
        if not (r and st["new_img"]):
            return
        idc = sheet_info(sh)[0]
        rid = dict(book.rows(book.wb[sh])).get(r, {}).get(idc)
        try:
            set_row_image(book, sh, rid, st["new_img"])
            book.save()
        except Exception as e:
            messagebox.showerror("Image", str(e))
            return
        log(f"Image saved on {sh} #{rid}.")
        st["new_img"] = None
        thumb(new_img, None)
        refresh()

    def autofill():
        book, sh = st["book"], st["sheet"]
        if not book:
            return
        fills = propose_fills(book, sh)
        if not fills:
            messagebox.showinfo("Auto-fill", "Nothing can be filled automatically in this tab.")
            return
        win = tk.Toplevel(root)
        win.title(f"Auto-fill {sh}: {len(fills)} proposed values")
        win.geometry("820x480")
        tv = ttk.Treeview(win, columns=("field", "value", "source"))
        for c, w, t in (("#0", 70, "id"), ("field", 130, "field"), ("value", 220, "new value"), ("source", 340, "from")):
            tv.heading(c, text=t)
            tv.column(c, width=w)
        for i, (r, rid, f, v, src) in enumerate(fills):
            tv.insert("", "end", iid=str(i), text=str(rid), values=(f, v, src))
        tv.pack(fill=tk.BOTH, expand=True)
        tv.selection_set(tv.get_children())

        def apply():
            chosen = [fills[int(i)] for i in tv.selection()]
            n = apply_fills(book, sh, chosen)
            if n:
                book.save()
            log(f"Auto-fill: {n} cells filled in {sh} (saved, .bak kept).")
            win.destroy()
            refresh()
        bar = ttk.Frame(win, padding=6)
        bar.pack(fill=tk.X)
        ttk.Label(bar, text="All rows are selected; deselect what you don't want (Ctrl/Shift-click).").pack(side=tk.LEFT)
        ttk.Button(bar, text="Apply selected", command=apply).pack(side=tk.RIGHT)

    def wiki(selected_only):
        book, sh = st["book"], st["sheet"]
        if not book:
            return
        idc = sheet_info(sh)[0]
        rows = dict(book.rows(book.wb[sh]))
        if selected_only:
            ids = [rows[st["rows"][i]].get(idc) for i in rtree.selection()]
        else:
            ids = [rows[r].get(idc) for r in st["rows"].values()]
        if not ids:
            log("Select rows first.")
            return
        if book.dirty:
            book.save()
        path = st["path"]

        def job():
            import fandom_scraper as fs
            fs._LOG_SINK = log
            try:
                wiki_fill(path, sh, ids, log=log)
            except Exception as e:
                log(f"Wiki fill failed: {e}")
            root.after(0, open_book)  # reload what the scraper wrote
        threading.Thread(target=job, daemon=True).start()

    def export():
        if not st["book"]:
            return
        p = filedialog.asksaveasfilename(defaultextension=".csv", filetypes=[("CSV", "*.csv")])
        if p:
            report(st["book"], None, all_cols.get(), p, out=log)

    ftree.bind("<<TreeviewSelect>>", on_field)
    rtree.bind("<<TreeviewSelect>>", on_row)
    sheet_box.bind("<<ComboboxSelected>>", refresh)
    filt_var.trace_add("write", fill_rows)
    pump()
    if workbook:
        root.after(100, open_book)
    root.mainloop()


if __name__ == "__main__":
    if len(sys.argv) > 1:
        run_cli(sys.argv[1:])
    else:
        try:
            run_gui()
        except ImportError:
            print("tkinter not available - use the command line: python missing_data_tool.py --help")
            sys.exit(1)
