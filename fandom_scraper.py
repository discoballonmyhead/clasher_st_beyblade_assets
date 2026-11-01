#!/usr/bin/env python3
"""
Polite, resumable Beyblade Fandom scraper that writes a workbook in the
exact layout beyblade_data.py (the packager) reads:

    sheet  Parts_X_<Key>   (Parts_X_Blades, Parts_X_Ratchets, Parts_X_Bits, ...)
    cols   dataID, parentPartId, variantLabel, manufacturer, hobbyName,
           hobbyGeneration, code, name, edition, <part specific...>, mass,
           wbolegality, incompleteData, updated_at, deleted,
           image, minifiedImage        <- PNGs embedded/anchored in these cells

Run it one KEY at a time (blades, ratchets, bits, lockChips, ...). Every key
fills its own sheet in the SAME workbook, so you can do `blades` today and
`ratchets` tomorrow. Re-running a key resumes where it stopped, never
duplicates rows (rows are matched by wiki page title) and never overwrites
cells you edited by hand (unless --overwrite).

Why the previous version timed out / risked an IP ban, and what changed:
  * 4 image threads downloaded in parallel with NO delay   -> one request at a
    time, globally, with a minimum gap + random jitter (API *and* images).
  * Downloaded 1600px thumbnails / full originals          -> 600px thumbs
    (a fraction of the bytes), minified 128px made locally (no extra request).
  * 50 full page sources per request (slow, big responses) -> 20 per batch.
  * Retries ignored Retry-After and hammered on 429/503     -> honours
    Retry-After + maxlag, exponential backoff with jitter, and a circuit
    breaker that STOPS (and saves) after repeated throttling. HTTP 403 stops
    immediately, because that is what a block looks like.
  * Nothing was saved until the very end                   -> progress, page
    cache, image cache and workbook are checkpointed as it goes. Ctrl+C /
    Stop is safe; just run again to continue.
  * Per-run request budget (--max-requests) so a big wiki can be done in
    several short sessions instead of one long hammering run.
  * GUI wrote to Tk from a worker thread (freezes)          -> queue-based log.

Usage (CLI):
    python fandom_scraper.py --status
    python fandom_scraper.py --find-categories ratchet     # discover category names
    python fandom_scraper.py --key ratchets --list-only     # see which pages match
    python fandom_scraper.py --key ratchets --inspect 5     # see infobox field names
    python fandom_scraper.py --key ratchets                 # scrape into the sheet
    python fandom_scraper.py --next                         # next unfinished key
Run with no arguments to open the GUI (needs tkinter).

Tune categories / title prefixes / field aliases in scraper_config.json
(created on first run next to this file).
"""
import argparse
import copy
import hashlib
import io
import json
import os
import random
import re
import sys
import threading
import time
from collections import Counter, OrderedDict
from datetime import datetime, timezone

import mwparserfromhell
import requests
from mwparserfromhell.nodes import Comment, ExternalLink, HTMLEntity, Tag, Template, Text, Wikilink
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(HERE, "scraper_config.json")

# =============================================================================
# CONFIG
# =============================================================================

COMMON_HEAD = ["dataID", "parentPartId", "variantLabel", "manufacturer", "hobbyName",
               "hobbyGeneration", "code", "name", "edition"]
COMMON_TAIL = ["mass", "wbolegality", "incompleteData", "updated_at", "deleted"]
BLADE_STATS = ["type", "spinDir", "attack", "defense", "stamina"]

# Column orders mirror data/*.json exactly (what the packager produced from the master sheet).
SHEET_COLUMNS = {
    "blades":       COMMON_HEAD + BLADE_STATS + ["integratedRatchet"] + COMMON_TAIL,
    "ratchets":     COMMON_HEAD + ["protrusions", "heightMm", "attack", "defense", "stamina"] + COMMON_TAIL,
    "bits":         COMMON_HEAD + ["baseName", "movementStyle", "attack", "defense", "stamina", "dash",
                                   "burstRes", "twoStat", "integratedRatchet"] + COMMON_TAIL,
    "lockChips":    COMMON_HEAD + COMMON_TAIL,
    "overBlades":   COMMON_HEAD + BLADE_STATS + COMMON_TAIL,
    "metalBlades":  COMMON_HEAD + BLADE_STATS + COMMON_TAIL,
    "mainBlades":   COMMON_HEAD + BLADE_STATS + COMMON_TAIL,
    "assistBlades": COMMON_HEAD + BLADE_STATS + COMMON_TAIL,
}
SHEET_NAMES = {  # same as PREFIX_TO_SHEET in beyblade_data.py
    "blades": "Parts_X_Blades", "ratchets": "Parts_X_Ratchets", "bits": "Parts_X_Bits",
    "lockChips": "Parts_X_LockChips", "overBlades": "Parts_X_OverBlades",
    "metalBlades": "Parts_X_MetalBlades", "mainBlades": "Parts_X_MainBlades",
    "assistBlades": "Parts_X_AssistBlades",
}
IMAGE_COL, MIN_IMAGE_COL = "image", "minifiedImage"

# Infobox field names are matched after normalising (lowercase, spaces/_/- collapsed).
COMMON_ALIASES = {
    "name":    ["name", "english name", "part name", "title"],
    "code":    ["product code", "code", "product", "product number", "release", "first release",
                "debut", "released with", "beyblade"],
    "edition": ["edition", "release", "first release", "released with", "debut", "beyblade", "product"],
    "mass":    ["weight", "mass"],
}
BLADE_ALIASES = {
    "type":    ["type", "beyblade type", "class"],
    "spinDir": ["spin direction", "spin", "rotation", "spin dir"],
    "attack":  ["attack", "atk"],
    "defense": ["defense", "defence", "def"],
    "stamina": ["stamina", "sta"],
}

def _part(categories, prefixes, extra_aliases=None, exclude=None):
    aliases = copy.deepcopy(COMMON_ALIASES)
    aliases.update(copy.deepcopy(extra_aliases or {}))
    return {"categories": categories, "title_prefixes": prefixes,
            "exclude_title_regex": exclude or r"(?i)(/gallery|/anime|\(disambiguation\))$",
            "aliases": aliases}

DEFAULT_CONFIG = {
    "wiki": "beyblade",
    # Fandom/Wikimedia etiquette: identify yourself. PUT A WAY TO CONTACT YOU HERE.
    "user_agent": "ClasherBeybladeAssetsScraper/2.0 (personal hobby project; contact: CHANGE_ME)",
    "output_workbook": "scraped_master.xlsx",
    "state_dir": "scrape_state",
    "politeness": {
        "delay_seconds": 2.0,          # minimum gap between ANY two requests
        "jitter_seconds": 1.0,         # + random 0..jitter on top
        "batch_size": 20,              # page sources per API call (max 50)
        "connect_timeout": 10,
        "read_timeout": 45,
        "max_retries": 5,              # per request
        "backoff_base_seconds": 10,
        "backoff_max_seconds": 300,
        "max_consecutive_failures": 4, # circuit breaker: stop the run, resume later
        "max_requests_per_run": 1500,  # budget; 0 = unlimited
        "maxlag": 5,
        "image_width": 600,            # px of the thumbnail requested from the wiki
        "min_image_width": 128,        # px of the locally made minified image
        "save_every": 15,              # save workbook every N processed pages
    },
    "row_defaults": {"manufacturer": "Takara-Tomy", "hobbyName": "Beyblade", "hobbyGeneration": "X",
                     "incompleteData": 1, "wbolegality": None, "updated_at": None, "deleted": None},
    "image_field_regex": r"^(image|img|picture|photo)\s*\d*$",
    "parts": {
        "blades":       _part(["Beyblade X Blades", "Blades (Beyblade X)"], ["Blade - "], BLADE_ALIASES),
        "ratchets":     _part(["Ratchets", "Beyblade X Ratchets"], ["Ratchet - "],
                              {"protrusions": ["protrusions", "number of protrusions", "contact points"],
                               "heightMm": ["height", "height mm"],
                               "attack": ["attack"], "defense": ["defense", "defence"], "stamina": ["stamina"]}),
        "bits":         _part(["Bits", "Beyblade X Bits"], ["Bit - "],
                              {"baseName": ["abbreviation", "short name", "initial", "symbol", "bit code"],
                               "movementStyle": ["type", "movement", "movement style"],
                               "attack": ["attack"], "defense": ["defense", "defence"], "stamina": ["stamina"],
                               "dash": ["dash", "xtreme dash", "x dash"],
                               "burstRes": ["burst resistance", "burst", "burst res"]}),
        "lockChips":    _part(["Lock Chips", "Beyblade X Lock Chips"], ["Lock Chip - "]),
        "mainBlades":   _part(["Main Blades", "Beyblade X Main Blades"], ["Main Blade - "], BLADE_ALIASES),
        "assistBlades": _part(["Assist Blades", "Beyblade X Assist Blades"], ["Assist Blade - "], BLADE_ALIASES),
        "metalBlades":  _part(["Metal Blades", "Beyblade X Metal Blades"], ["Metal Blade - "], BLADE_ALIASES),
        "overBlades":   _part(["Over Blades", "Beyblade X Over Blades"], ["Over Blade - "], BLADE_ALIASES),
    },
}
KEY_ORDER = list(SHEET_NAMES)


def load_config(path=CONFIG_PATH):
    if not os.path.exists(path):
        write_json(path, DEFAULT_CONFIG, indent=2)
        log(f"Created {os.path.basename(path)} with default settings - edit categories/aliases there.")
        return copy.deepcopy(DEFAULT_CONFIG)
    with open(path, encoding="utf-8") as f:
        user = json.load(f)
    cfg = copy.deepcopy(DEFAULT_CONFIG)
    for k, v in user.items():  # shallow merge, one level deeper for dict sections
        if isinstance(v, dict) and isinstance(cfg.get(k), dict) and k != "parts":
            cfg[k].update(v)
        elif k == "parts":
            for pk, pv in v.items():
                cfg["parts"].setdefault(pk, {}).update(pv)
        else:
            cfg[k] = v
    return cfg

# =============================================================================
# SMALL UTILITIES
# =============================================================================

_LOG_SINK = None  # GUI installs a callable here


def log(msg=""):
    if _LOG_SINK:
        _LOG_SINK(str(msg))
    else:
        print(msg, flush=True)


def write_json(path, data, indent=None):
    """Atomic: write to temp then rename, so a crash never leaves half a file."""
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=indent)
    os.replace(tmp, path)


def read_json(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return default


def chunks(seq, n):
    seq = list(seq)
    for i in range(0, len(seq), n):
        yield seq[i:i + n]


def norm_key(k):
    return re.sub(r"[\s_\-]+", " ", str(k).strip().lower())


def norm_file(name):
    name = re.sub(r"^(File|Image):", "", name.strip(), flags=re.I).strip().replace("_", " ")
    return name[:1].upper() + name[1:] if name else name

# =============================================================================
# POLITE HTTP CLIENT
# =============================================================================

class StopScrape(Exception):
    """Raised to end the run cleanly. Progress is saved; run again to resume."""


class Blocked(StopScrape): pass
class Cooldown(StopScrape): pass
class BudgetExhausted(StopScrape): pass
class UserStopped(StopScrape): pass


class PoliteClient:
    """One request at a time (API and images alike), spaced out, with backoff."""

    def __init__(self, cfg, stop_event=None):
        p = cfg["politeness"]
        wiki = cfg["wiki"]
        self.api = wiki if wiki.startswith("http") else f"https://{wiki}.fandom.com/api.php"
        self.p = p
        self.stop_event = stop_event or threading.Event()
        self.s = requests.Session()
        self.s.headers.update({"User-Agent": cfg["user_agent"], "Accept-Encoding": "gzip, deflate"})
        self.lock = threading.Lock()
        self.last = 0.0
        self.count = 0
        self.consecutive_failures = 0

    def _sleep(self, seconds):
        end = time.monotonic() + seconds
        while True:
            if self.stop_event.is_set():
                raise UserStopped("Stopped by user.")
            left = end - time.monotonic()
            if left <= 0:
                return
            time.sleep(min(0.5, left))

    def _wait_turn(self):
        gap = self.p["delay_seconds"] + random.uniform(0, self.p["jitter_seconds"])
        wait = self.last + gap - time.monotonic()
        if wait > 0:
            self._sleep(wait)

    def _backoff(self, attempt, retry_after=None):
        if retry_after:
            try:
                secs = float(retry_after)
            except ValueError:
                secs = self.p["backoff_base_seconds"]
        else:
            secs = self.p["backoff_base_seconds"] * (2 ** attempt)
        secs = min(secs, self.p["backoff_max_seconds"]) + random.uniform(0, 3)
        log(f"    ...waiting {secs:.0f}s before retrying")
        self._sleep(secs)

    def _fail(self, why):
        self.consecutive_failures += 1
        if self.consecutive_failures >= self.p["max_consecutive_failures"]:
            raise Cooldown(f"{self.consecutive_failures} failures in a row ({why}). The wiki is throttling "
                           f"or unreachable - stopping to protect your IP. Wait 15-30 min and run again.")

    def request(self, url, params=None, binary=False):
        budget = self.p.get("max_requests_per_run") or 0
        with self.lock:
            for attempt in range(self.p["max_retries"]):
                if self.stop_event.is_set():
                    raise UserStopped("Stopped by user.")
                if budget and self.count >= budget:
                    raise BudgetExhausted(f"Request budget of {budget} reached for this run. Run again to continue.")
                self._wait_turn()
                self.count += 1
                try:
                    r = self.s.get(url, params=params,
                                   timeout=(self.p["connect_timeout"], self.p["read_timeout"]))
                except requests.RequestException as e:
                    self.last = time.monotonic()
                    log(f"    network error: {type(e).__name__}")
                    self._fail(type(e).__name__)
                    self._backoff(attempt)
                    continue
                self.last = time.monotonic()

                if r.status_code == 403:
                    raise Blocked("HTTP 403 Forbidden - the wiki is refusing this client. Stop for a few hours; "
                                  "make sure user_agent in scraper_config.json has real contact info.")
                if r.status_code == 404 and binary:
                    self.consecutive_failures = 0
                    return None
                if r.status_code in (429, 502, 503, 504) or r.status_code >= 500:
                    log(f"    HTTP {r.status_code} (throttled/overloaded)")
                    self._fail(f"HTTP {r.status_code}")
                    self._backoff(attempt, r.headers.get("Retry-After"))
                    continue
                r.raise_for_status()

                if binary:
                    self.consecutive_failures = 0
                    return r.content
                data = r.json()
                err = data.get("error") if isinstance(data, dict) else None
                if err and err.get("code") == "maxlag":
                    log("    wiki servers lagging (maxlag)")
                    self._backoff(attempt, r.headers.get("Retry-After") or 5)
                    continue
                if err and err.get("code") in ("ratelimited", "toomanyvalues"):
                    self._fail(err.get("code"))
                    self._backoff(attempt)
                    continue
                if err:
                    raise RuntimeError(f"API error: {err}")
                self.consecutive_failures = 0
                return data
            self._fail("retries exhausted")
            raise Cooldown(f"Gave up after {self.p['max_retries']} attempts. Wait and run again.")

    # ---- MediaWiki helpers --------------------------------------------------
    def api_get(self, **params):
        params.update(format="json", formatversion="2", maxlag=str(self.p["maxlag"]))
        return self.request(self.api, params=params)

    def query_all(self, **params):
        cont = {}
        while True:
            d = self.api_get(**params, **cont)
            yield d
            if "continue" not in d:
                return
            cont = d["continue"]

    def category_members(self, category, depth=1, seen=None):
        seen = seen if seen is not None else set()
        cat = category if category.lower().startswith("category:") else "Category:" + category
        if cat in seen:
            return []
        seen.add(cat)
        titles = []
        for d in self.query_all(action="query", list="categorymembers", cmtitle=cat,
                                cmlimit="500", cmtype="page|subcat"):
            for m in d["query"]["categorymembers"]:
                if m["ns"] == 0:
                    titles.append(m["title"])
                elif m["ns"] == 14 and depth > 0:
                    titles += self.category_members(m["title"], depth - 1, seen)
        return titles

    def prefix_pages(self, prefix):
        titles = []
        for d in self.query_all(action="query", list="allpages", apprefix=prefix, apnamespace="0",
                                apfilterredir="nonredirects", aplimit="500"):
            titles += [p["title"] for p in d["query"]["allpages"]]
        return titles

    def search_categories(self, term):
        d = self.api_get(action="query", list="search", srsearch=term, srnamespace="14", srlimit="50")
        return [(h["title"], h.get("size")) for h in d["query"]["search"]]

    def revids(self, titles):
        out = {}
        for batch in chunks(titles, 50):
            d = self.api_get(action="query", prop="info", titles="|".join(batch))
            for p in d["query"].get("pages", []):
                if p.get("missing") is None:
                    out[p["title"]] = p.get("lastrevid")
        return out

    def fetch_pages(self, titles):
        pages = {}
        for d in self.query_all(action="query", prop="revisions|categories|info|pageimages",
                                rvprop="content|ids", rvslots="main", inprop="url", cllimit="max",
                                clshow="!hidden", piprop="original", titles="|".join(titles)):
            for p in d["query"].get("pages", []):
                if p.get("missing") is not None:
                    continue
                pg = pages.setdefault(p["title"], {"categories": []})
                if p.get("revisions"):
                    rev = p["revisions"][0]
                    pg["wikitext"] = rev["slots"]["main"]["content"]
                    pg["revid"] = rev["revid"]
                if p.get("fullurl"):
                    pg["url"] = p["fullurl"]
                pg["categories"] += [c["title"].split(":", 1)[1] for c in p.get("categories", [])]
                if p.get("original"):
                    pg["page_image"] = p["original"]["source"]
        for pg in pages.values():
            pg["categories"] = sorted(set(pg["categories"]))
        return pages

    def resolve_files(self, filenames):
        out = {}
        for batch in chunks(sorted(filenames), 50):
            d = self.api_get(action="query", prop="imageinfo", iiprop="url|mime",
                             iiurlwidth=str(self.p["image_width"]),
                             titles="|".join("File:" + f for f in batch))
            for p in d["query"].get("pages", []):
                info = (p.get("imageinfo") or [None])[0]
                if info:
                    out[norm_file(p["title"])] = info.get("thumburl") or info.get("url")
        return out

# =============================================================================
# WIKITEXT PARSING
# =============================================================================

IMAGE_EXT = r"(?:png|jpe?g|gif|webp|svg|bmp|tiff?)"
FILENAME_RE = re.compile(r"(?:(?:File|Image):)?\s*([^\[\]|{}\n<>=#]+?\." + IMAGE_EXT + r")\b", re.I)


def flatten(code):
    out = []
    for node in code.nodes:
        if isinstance(node, Text):
            out.append(str(node))
        elif isinstance(node, Wikilink):
            target = str(node.title).strip()
            if re.match(r"^(file|image|category):", target, re.I):
                continue
            out.append(flatten(node.text) if node.text else target.split("#")[0])
        elif isinstance(node, ExternalLink):
            out.append(flatten(node.title) if node.title else str(node.url))
        elif isinstance(node, Template):
            name = str(node.name).strip().lower()
            if name == "!":
                out.append("|")
                continue
            vals = [flatten(p.value).strip() for p in node.params if not p.showkey]
            out.append(" ".join(v for v in vals if v))
        elif isinstance(node, Tag):
            tag = str(node.tag).lower()
            if tag in ("ref", "references", "gallery"):
                continue
            if tag == "br":
                out.append("\n")
                continue
            if node.contents is not None:
                out.append(flatten(node.contents))
            if tag in ("li", "p", "div"):
                out.append("\n")
        elif isinstance(node, HTMLEntity):
            out.append(node.normalize())
        elif isinstance(node, Comment):
            continue
        else:
            out.append(str(node))
    return "".join(out)


def clean_value(code):
    s = re.sub(r"'{2,}", "", flatten(code))
    lines = [l.strip().lstrip("*#:").strip() for l in s.splitlines()]
    s = re.sub(r"\s+", " ", "; ".join(l for l in lines if l))
    return re.sub(r"(\s*;\s*)+", "; ", s).strip(" ;")


def pick_infobox(code):
    def named(t):
        return sum(1 for p in t.params if p.showkey)
    for recursive in (False, True):
        tpls = code.filter_templates(recursive=recursive)
        for t in tpls:
            if "infobox" in str(t.name).lower() and named(t) >= 1:
                return t
        cands = [t for t in tpls if named(t) >= 3]
        if cands:
            return max(cands, key=named)
    return None


def parse_page(wikitext, image_re):
    """-> (infobox_name, {normalised_field: value}, [image filenames])"""
    code = mwparserfromhell.parse(wikitext or "")
    box = pick_infobox(code)
    if not box:
        return "", {}, []
    fields, files = OrderedDict(), []
    for p in box.params:
        if not p.showkey:
            continue
        key = norm_key(p.name)
        if image_re.match(key):
            for m in FILENAME_RE.finditer(str(p.value)):
                n = norm_file(m.group(1))
                if n and n not in files:
                    files.append(n)
            continue
        v = clean_value(p.value)
        if v:
            fields[key] = v
    return str(box.name).strip(), fields, files

# =============================================================================
# FIELD MAPPING -> packager columns
# =============================================================================

CODE_RE = re.compile(r"\b((?:BXG|UXG|CXG|BX|UX|CX)-\d{2,3})\b", re.I)
NUM_RE = re.compile(r"-?\d+(?:\.\d+)?")
RATCHET_RE = re.compile(r"\b(\d{1,2})-(\d{2,3})\b")
TYPES = ("attack", "defense", "stamina", "balance")


def to_number(v):
    if v is None:
        return None
    s = str(v).strip()
    if re.fullmatch(r"-?\d+(\.\d+)?", s):
        f = float(s)
        return int(f) if f.is_integer() else f
    return s or None  # keep things like "30-55" exactly as the master sheet does


def first_number(v):
    m = NUM_RE.search(str(v or "").replace(",", "."))
    if not m:
        return None
    f = float(m.group())
    return int(f) if f.is_integer() else f


def norm_type(v):
    low = str(v or "").lower()
    if "defen" in low:
        return "defense"
    for t in TYPES:
        if t in low:
            return t
    return None


def norm_spin(v):
    low = str(v or "").lower()
    has_r, has_l = "right" in low, "left" in low
    if has_r and has_l:
        return "both"
    return "right" if has_r else "left" if has_l else None


def title_to_name(title, prefixes):
    name = title
    for pre in prefixes:
        if name.lower().startswith(pre.lower()):
            name = name[len(pre):]
            break
    return re.sub(r"\s*\((?:Beyblade X|X|Blade|Ratchet|Bit|part)\)\s*$", "", name, flags=re.I).strip()


def map_row(key, part_cfg, title, fields):
    aliases = {col: [norm_key(a) for a in names] for col, names in part_cfg["aliases"].items()}

    def pick(col):
        for a in aliases.get(col, []):
            if fields.get(a):
                return fields[a]
        return None

    row = {}
    row["name"] = title_to_name(title, part_cfg.get("title_prefixes", [])) or pick("name")
    code_src = " ".join(filter(None, [pick("code")] + [fields.get(a) for a in aliases.get("edition", [])]))
    m = CODE_RE.search(code_src)
    row["code"] = m.group(1).upper() if m else None
    ed = pick("edition")
    row["edition"] = ed.split(";")[0].strip()[:120] if ed else None
    row["mass"] = first_number(pick("mass"))

    if "type" in SHEET_COLUMNS[key]:
        row["type"] = norm_type(pick("type"))
    if "spinDir" in SHEET_COLUMNS[key]:
        row["spinDir"] = norm_spin(pick("spinDir"))
    for stat in ("attack", "defense", "stamina", "dash", "burstRes"):
        if stat in SHEET_COLUMNS[key]:
            v = pick(stat)
            row[stat] = to_number(v.split(";")[0]) if v else None
    if key == "ratchets":
        rm = RATCHET_RE.search(row["name"] or "")
        row["protrusions"] = first_number(pick("protrusions")) or (int(rm.group(1)) if rm else None)
        row["heightMm"] = first_number(pick("heightMm")) or (int(rm.group(2)) if rm else None)
    if key == "bits":
        row["movementStyle"] = norm_type(pick("movementStyle"))
        bn = pick("baseName")
        if not bn:  # "Flat (F)" style names
            pm = re.search(r"\(([A-Z][A-Za-z]{0,3})\)", title)
            bn = pm.group(1) if pm else None
        row["baseName"] = bn
    return {k: v for k, v in row.items() if k in SHEET_COLUMNS[key]}

# =============================================================================
# IMAGES
# =============================================================================

def to_png(content, max_width):
    im = Image.open(io.BytesIO(content))
    im.seek(0)
    im = im.convert("RGBA")
    if im.width > max_width:
        im = im.resize((max_width, max(1, round(im.height * max_width / im.width))), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, "PNG", optimize=True)
    return buf.getvalue()

# =============================================================================
# WORKBOOK (upsert into the packager's layout)
# =============================================================================

class MasterWorkbook:
    def __init__(self, path):
        import openpyxl
        self.path = path
        if os.path.exists(path):
            self.wb = openpyxl.load_workbook(path)  # keeps already-embedded images
            for ws in self.wb.worksheets:
                for img in ws._images:
                    self._pin(img, img._data())
        else:
            self.wb = openpyxl.Workbook()
            self.wb.remove(self.wb.active)
        self.backed_up = False

    @staticmethod
    def _pin(img, data):
        """openpyxl closes an image's buffer on save, so a 2nd save (checkpoints!) would crash.
        Pin the bytes so the workbook can be saved any number of times."""
        img._data = lambda data=data: data

    def sheet(self, key):
        from openpyxl.styles import Font, PatternFill
        name = SHEET_NAMES[key]
        wanted = SHEET_COLUMNS[key] + [IMAGE_COL, MIN_IMAGE_COL]
        if name not in self.wb.sheetnames:
            ws = self.wb.create_sheet(name)
            ws.append(wanted)
            for c in ws[1]:
                c.font = Font(bold=True, color="FFFFFF")
                c.fill = PatternFill("solid", fgColor="1F3864")
            ws.freeze_panes = "B2"
            for i, col in enumerate(wanted, 1):
                ws.column_dimensions[ws.cell(1, i).column_letter].width = \
                    18 if col == IMAGE_COL else 10 if col == MIN_IMAGE_COL else 14
        ws = self.wb[name]
        headers = [c.value for c in ws[1]]
        for col in wanted:  # add any missing column at the end, never reorder user's sheet
            if col not in headers:
                ws.cell(1, len(headers) + 1, col)
                headers.append(col)
        return ws

    def log_sheet(self):
        if "_scrape_log" not in self.wb.sheetnames:
            ws = self.wb.create_sheet("_scrape_log")
            ws.append(["key", "dataID", "wikiTitle", "url", "revid", "infobox", "imageFile", "scrapedAt"])
        return self.wb["_scrape_log"]

    def title_index(self, key):
        """wiki title -> sheet row number, from the _scrape_log sheet."""
        ws, lg = self.sheet(key), self.log_sheet()
        headers = [c.value for c in ws[1]]
        id_col = headers.index("dataID") + 1
        id_to_row = {}
        for r in range(2, ws.max_row + 1):
            v = ws.cell(r, id_col).value
            if v not in (None, ""):
                id_to_row[str(v)] = r
        idx = {}
        for row in lg.iter_rows(min_row=2, values_only=True):
            if row and row[0] == key and str(row[1]) in id_to_row:
                idx[row[2]] = id_to_row[str(row[1])]
        return idx

    def next_row_and_id(self, ws):
        headers = [c.value for c in ws[1]]
        id_col = headers.index("dataID") + 1
        last, max_id = 1, 0
        for r in range(2, ws.max_row + 1):
            vals = [ws.cell(r, c).value for c in range(1, len(headers) + 1)]
            if not any(v not in (None, "") for v in vals):
                break  # packager stops at first blank row, so we must stay contiguous
            last = r
            try:
                max_id = max(max_id, int(ws.cell(r, id_col).value))
            except (TypeError, ValueError):
                pass
        return last + 1, max_id + 1

    def has_image(self, ws, row, col):
        for img in ws._images:
            a = img.anchor
            if hasattr(a, "_from") and a._from.row + 1 == row and a._from.col + 1 == col:
                return True
        return False

    def add_image(self, ws, row, col, png, display_w):
        from openpyxl.drawing.image import Image as XLImage
        from openpyxl.drawing.spreadsheet_drawing import OneCellAnchor, AnchorMarker
        from openpyxl.drawing.xdr import XDRPositiveSize2D
        from openpyxl.utils.units import pixels_to_EMU
        img = XLImage(io.BytesIO(png))
        ratio = display_w / img.width if img.width else 1
        img.width, img.height = display_w, max(1, int(img.height * ratio))
        # explicit anchor object (not "J5" string) so has_image() also sees images added this run
        img.anchor = OneCellAnchor(_from=AnchorMarker(col=col - 1, row=row - 1),
                                   ext=XDRPositiveSize2D(pixels_to_EMU(img.width), pixels_to_EMU(img.height)))
        self._pin(img, png)
        ws.add_image(img)
        cur = ws.row_dimensions[row].height or 15
        ws.row_dimensions[row].height = max(cur, img.height * 0.75 + 4)

    def upsert(self, key, title, row_values, defaults, full_png, min_png, meta, overwrite=False):
        ws = self.sheet(key)
        headers = [c.value for c in ws[1]]
        col = {h: i + 1 for i, h in enumerate(headers)}
        idx = self.title_index(key)
        if title in idx:
            r = idx[title]
            data_id = ws.cell(r, col["dataID"]).value
            new = False
        else:
            r, data_id = self.next_row_and_id(ws)
            ws.cell(r, col["dataID"], data_id)
            new = True
        values = dict(defaults) if new else {}
        values.update({k: v for k, v in row_values.items() if v not in (None, "")})
        for k, v in values.items():
            if k not in col or k == "dataID":
                continue
            cell = ws.cell(r, col[k])
            if new or overwrite or cell.value in (None, ""):
                cell.value = v
        if full_png and not self.has_image(ws, r, col[IMAGE_COL]):
            self.add_image(ws, r, col[IMAGE_COL], full_png, 120)
        if min_png and not self.has_image(ws, r, col[MIN_IMAGE_COL]):
            self.add_image(ws, r, col[MIN_IMAGE_COL], min_png, 48)
        if new:
            self.log_sheet().append([key, data_id, title, meta.get("url"), meta.get("revid"),
                                     meta.get("infobox"), meta.get("imageFile"),
                                     datetime.now(timezone.utc).isoformat(timespec="seconds")])
        return data_id, new

    def save(self):
        if os.path.exists(self.path) and not self.backed_up:
            import shutil
            shutil.copy2(self.path, self.path + ".bak")
            self.backed_up = True
        tmp = self.path + ".tmp.xlsx"
        self.wb.save(tmp)
        os.replace(tmp, self.path)

# =============================================================================
# SCRAPE ENGINE
# =============================================================================

class Scraper:
    def __init__(self, cfg, stop_event=None, overwrite=False, no_images=False, relist=False):
        self.cfg = cfg
        self.client = PoliteClient(cfg, stop_event)
        self.overwrite, self.no_images, self.relist = overwrite, no_images, relist
        self.state_dir = os.path.join(HERE, cfg["state_dir"]) if not os.path.isabs(cfg["state_dir"]) else cfg["state_dir"]
        os.makedirs(os.path.join(self.state_dir, "images"), exist_ok=True)
        self.progress_path = os.path.join(self.state_dir, "progress.json")
        self.pages_path = os.path.join(self.state_dir, "pages.json")
        self.progress = read_json(self.progress_path, {})
        self.pages = read_json(self.pages_path, {})
        self.image_re = re.compile(cfg["image_field_regex"], re.I)
        out = cfg["output_workbook"]
        self.wb_path = out if os.path.isabs(out) else os.path.join(HERE, out)

    # --- state ---------------------------------------------------------------
    def kstate(self, key):
        return self.progress.setdefault(key, {"titles": None, "done": {}, "failed": {}, "complete": False})

    def save_state(self):
        write_json(self.progress_path, self.progress)
        write_json(self.pages_path, self.pages)

    # --- steps ---------------------------------------------------------------
    def list_titles(self, key):
        st = self.kstate(key)
        if st["titles"] is not None and not self.relist:
            return st["titles"]
        part = self.cfg["parts"][key]
        titles = []
        for cat in part.get("categories", []):
            got = self.client.category_members(cat, depth=part.get("category_depth", 1))
            log(f"  Category:{cat} -> {len(got)} pages")
            titles += got
        for pre in part.get("title_prefixes", []):
            got = self.client.prefix_pages(pre)
            log(f"  prefix '{pre}' -> {len(got)} pages")
            titles += got
        for t in part.get("extra_titles", []):
            titles.append(t)
        ex = re.compile(part["exclude_title_regex"]) if part.get("exclude_title_regex") else None
        titles = [t for t in OrderedDict.fromkeys(titles) if not (ex and ex.search(t))]
        st["titles"] = titles
        st["complete"] = False
        self.save_state()
        return titles

    def get_pages(self, titles):
        """Page sources, from cache when unchanged. Batched + checkpointed."""
        missing = [t for t in titles if t not in self.pages]
        if self.relist:
            cached = [t for t in titles if t in self.pages]
            if cached:
                live = self.client.revids(cached)
                missing += [t for t in cached if live.get(t) and live[t] != self.pages[t].get("revid")]
        bs = max(1, min(50, int(self.cfg["politeness"]["batch_size"])))
        for i, batch in enumerate(chunks(missing, bs), 1):
            got = self.client.fetch_pages(batch)
            for t, pg in got.items():
                if "wikitext" in pg:
                    self.pages[t] = pg
            write_json(self.pages_path, self.pages)
            log(f"  page sources {min(i * bs, len(missing))}/{len(missing)}")
        return {t: self.pages[t] for t in titles if t in self.pages}

    def image_for(self, filename, url):
        cache = os.path.join(self.state_dir, "images", hashlib.sha1(filename.encode()).hexdigest()[:16])
        full_p, min_p = cache + ".png", cache + "-min.png"
        if os.path.exists(full_p) and os.path.exists(min_p):
            with open(full_p, "rb") as a, open(min_p, "rb") as b:
                return a.read(), b.read()
        if not url:
            return None, None
        raw = self.client.request(url, binary=True)
        if not raw:
            return None, None
        p = self.cfg["politeness"]
        full, mini = to_png(raw, p["image_width"]), to_png(raw, p["min_image_width"])
        with open(full_p, "wb") as a, open(min_p, "wb") as b:
            a.write(full)
            b.write(mini)
        return full, mini

    def run_key(self, key, limit=None):
        if key not in self.cfg["parts"]:
            raise SystemExit(f"Unknown key '{key}'. Known: {', '.join(self.cfg['parts'])}")
        part, st = self.cfg["parts"][key], self.kstate(key)
        log(f"\n=== {key} -> sheet {SHEET_NAMES[key]} in {os.path.basename(self.wb_path)} ===")
        log("1) listing pages")
        titles = self.list_titles(key)
        todo = [t for t in titles if t not in st["done"]]
        log(f"  {len(titles)} pages for this key, {len(titles) - len(todo)} already done, {len(todo)} to go")
        if not titles:
            log("  !! nothing found. Run --find-categories <word> and fix 'categories'/'title_prefixes' "
                f"for '{key}' in scraper_config.json")
            return
        if limit:
            todo = todo[:limit]
        wb = MasterWorkbook(self.wb_path)
        defaults = self.cfg["row_defaults"]
        processed = 0
        save_every = max(1, int(self.cfg["politeness"]["save_every"]))
        try:
            bs = max(1, min(50, int(self.cfg["politeness"]["batch_size"])))
            for batch in chunks(todo, bs):
                log("2) fetching page sources")
                pages = self.get_pages(batch)
                parsed = {}
                for t in batch:
                    pg = pages.get(t)
                    if not pg:
                        st["failed"][t] = "page missing"
                        continue
                    infobox, fields, files = parse_page(pg.get("wikitext"), self.image_re)
                    if not files and pg.get("page_image"):
                        files = [norm_file(pg["page_image"].split("/revision/")[0].rsplit("/", 1)[-1]
                                           .replace("%20", " "))]
                    parsed[t] = (pg, infobox, fields, files[:1])
                urls = {}
                if not self.no_images:
                    need = set()
                    for t, (_, _, _, files) in parsed.items():
                        for f in files:
                            c = os.path.join(self.state_dir, "images", hashlib.sha1(f.encode()).hexdigest()[:16])
                            if not os.path.exists(c + ".png"):
                                need.add(f)
                    if need:
                        log(f"3) resolving {len(need)} image URLs")
                        urls = self.client.resolve_files(need)
                for t, (pg, infobox, fields, files) in parsed.items():
                    full = mini = None
                    if files and not self.no_images:
                        full, mini = self.image_for(files[0], urls.get(files[0]))
                    row = map_row(key, part, t, fields)
                    meta = {"url": pg.get("url"), "revid": pg.get("revid"), "infobox": infobox,
                            "imageFile": files[0] if files else None}
                    data_id, new = wb.upsert(key, t, row, defaults, full, mini, meta, self.overwrite)
                    st["done"][t] = {"dataID": data_id, "revid": pg.get("revid"), "image": bool(full)}
                    st["failed"].pop(t, None)
                    processed += 1
                    log(f"  [{'new' if new else 'upd'}] #{data_id} {t}"
                        f"{'' if full or self.no_images else '  (no image)'}")
                    if processed % save_every == 0:
                        wb.save()
                        self.save_state()
                        log(f"  -- checkpoint saved ({processed} this run, {self.client.count} requests)")
            st["complete"] = all(t in st["done"] for t in titles)
        finally:
            wb.save()
            self.save_state()
            log(f"  saved {SHEET_NAMES[key]}: {processed} rows processed this run, "
                f"{len(st['done'])}/{len(titles)} total, {self.client.count} requests used")

    def inspect(self, key, n):
        titles = self.list_titles(key)[:n]
        pages = self.get_pages(titles)
        seen = Counter()
        for t in titles:
            pg = pages.get(t)
            if not pg:
                continue
            infobox, fields, files = parse_page(pg.get("wikitext"), self.image_re)
            seen.update(fields.keys())
            log(f"\n--- {t}  [infobox: {infobox or 'NONE'}]  categories: {', '.join(pg['categories'][:6])}")
            for k, v in fields.items():
                log(f"    {k!r}: {v[:90]}")
            log(f"    images: {files or pg.get('page_image')}")
            log(f"    => mapped row: {map_row(key, self.cfg['parts'][key], t, fields)}")
        log("\nField names seen (add the useful ones to 'aliases' in scraper_config.json):")
        for k, c in seen.most_common():
            log(f"  {c:3d}x  {k}")
        self.save_state()

    def status(self):
        log(f"Workbook: {self.wb_path}")
        for key in self.cfg["parts"]:
            st = self.progress.get(key)
            if not st or st.get("titles") is None:
                log(f"  {key:13s} not started")
                continue
            n, d = len(st["titles"]), len(st["done"])
            imgs = sum(1 for v in st["done"].values() if v.get("image"))
            log(f"  {key:13s} {d}/{n} done, {imgs} with image, {len(st['failed'])} failed"
                f"{'  COMPLETE' if st.get('complete') else ''}")

    def next_key(self):
        for key in [k for k in KEY_ORDER if k in self.cfg["parts"]] + \
                   [k for k in self.cfg["parts"] if k not in KEY_ORDER]:
            if not self.progress.get(key, {}).get("complete"):
                return key
        return None

# =============================================================================
# CLI
# =============================================================================

def run_cli(argv):
    ap = argparse.ArgumentParser(description="Polite, resumable Beyblade wiki scraper -> packager workbook")
    ap.add_argument("--key", action="append", help="part key to scrape (repeatable), e.g. blades, ratchets, bits")
    ap.add_argument("--next", action="store_true", help="scrape the next key that is not complete yet")
    ap.add_argument("--all", action="store_true", help="scrape every key in order (one sheet after another)")
    ap.add_argument("--limit", type=int, help="max pages to process per key this run")
    ap.add_argument("--max-requests", type=int, help="override request budget for this run")
    ap.add_argument("--delay", type=float, help="override minimum seconds between requests")
    ap.add_argument("--no-images", action="store_true")
    ap.add_argument("--overwrite", action="store_true", help="overwrite non-empty cells (default: only fill blanks)")
    ap.add_argument("--relist", action="store_true", help="re-list pages and re-fetch changed ones")
    ap.add_argument("--reset", metavar="KEY", help="forget progress for KEY (sheet rows are kept)")
    ap.add_argument("--list-only", action="store_true", help="only list matching page titles")
    ap.add_argument("--inspect", type=int, metavar="N", help="show infobox fields of the first N pages of --key")
    ap.add_argument("--find-categories", metavar="WORD", help="search wiki category names")
    ap.add_argument("--status", action="store_true")
    ap.add_argument("--config", default=CONFIG_PATH)
    a = ap.parse_args(argv)

    cfg = load_config(a.config)
    if a.max_requests is not None:
        cfg["politeness"]["max_requests_per_run"] = a.max_requests
    if a.delay is not None:
        cfg["politeness"]["delay_seconds"] = max(0.5, a.delay)
    if "CHANGE_ME" in cfg["user_agent"]:
        log("NOTE: set a contact in 'user_agent' in scraper_config.json - Fandom asks bots to identify themselves.")

    sc = Scraper(cfg, overwrite=a.overwrite, no_images=a.no_images, relist=a.relist)
    if a.reset:
        sc.progress.pop(a.reset, None)
        sc.save_state()
        log(f"Progress for {a.reset} cleared.")
        return 0
    if a.status:
        sc.status()
        return 0
    try:
        if a.find_categories:
            for title, _ in sc.client.search_categories(a.find_categories):
                log(f"  {title}")
            return 0
        keys = a.key or []
        if a.all:
            keys = [k for k in KEY_ORDER if k in cfg["parts"]]
        if a.next:
            k = sc.next_key()
            if not k:
                log("All keys complete.")
                return 0
            keys = [k]
        if not keys:
            ap.print_help()
            return 1
        for key in keys:
            if a.list_only:
                ts = sc.list_titles(key)
                log(f"{key}: {len(ts)} pages")
                for t in ts:
                    log(f"  {t}")
            elif a.inspect:
                sc.inspect(key, a.inspect)
            else:
                sc.run_key(key, a.limit)
    except StopScrape as e:
        log(f"\nSTOPPED SAFELY: {e}")
        log("Everything done so far is saved. Run the same command again to continue.")
        return 2
    except KeyboardInterrupt:
        sc.save_state()
        log("\nInterrupted - progress saved. Run again to continue.")
        return 130
    return 0

# =============================================================================
# GUI (optional)
# =============================================================================

def run_gui():
    import queue
    import tkinter as tk
    from tkinter import ttk, scrolledtext, messagebox

    global _LOG_SINK
    q = queue.Queue()
    _LOG_SINK = q.put
    cfg = load_config()

    root = tk.Tk()
    root.title("Beyblade Wiki Scraper (polite / resumable)")
    root.geometry("820x640")
    frm = ttk.Frame(root, padding=10)
    frm.pack(fill=tk.BOTH, expand=True)

    ttk.Label(frm, text="Keys (sheets) to scrape, processed one after another:").grid(row=0, column=0, columnspan=4, sticky="w")
    key_vars = {}
    kf = ttk.Frame(frm)
    kf.grid(row=1, column=0, columnspan=4, sticky="w", pady=4)
    for i, k in enumerate(cfg["parts"]):
        key_vars[k] = tk.BooleanVar(value=False)
        ttk.Checkbutton(kf, text=k, variable=key_vars[k]).grid(row=i // 4, column=i % 4, sticky="w", padx=6)

    opts = ttk.Frame(frm)
    opts.grid(row=2, column=0, columnspan=4, sticky="w", pady=6)
    no_img, overwrite, relist = tk.BooleanVar(), tk.BooleanVar(), tk.BooleanVar()
    ttk.Checkbutton(opts, text="Skip images", variable=no_img).pack(side=tk.LEFT, padx=4)
    ttk.Checkbutton(opts, text="Overwrite filled cells", variable=overwrite).pack(side=tk.LEFT, padx=4)
    ttk.Checkbutton(opts, text="Re-list / refresh changed pages", variable=relist).pack(side=tk.LEFT, padx=4)
    ttk.Label(opts, text="Limit/key:").pack(side=tk.LEFT, padx=(12, 2))
    limit_var = tk.StringVar()
    ttk.Entry(opts, textvariable=limit_var, width=6).pack(side=tk.LEFT)
    ttk.Label(opts, text="Delay s:").pack(side=tk.LEFT, padx=(12, 2))
    delay_var = tk.StringVar(value=str(cfg["politeness"]["delay_seconds"]))
    ttk.Entry(opts, textvariable=delay_var, width=5).pack(side=tk.LEFT)

    btns = ttk.Frame(frm)
    btns.grid(row=3, column=0, columnspan=4, sticky="w", pady=6)
    out = scrolledtext.ScrolledText(frm, height=24, state="disabled", bg="black", fg="lightgray",
                                    font=("Consolas", 10))
    out.grid(row=4, column=0, columnspan=4, sticky="nsew")
    frm.rowconfigure(4, weight=1)
    frm.columnconfigure(3, weight=1)
    stop_event = threading.Event()
    worker = {"t": None}

    def pump():
        try:
            while True:
                line = q.get_nowait()
                out.configure(state="normal")
                out.insert("end", line + "\n")
                out.see("end")
                out.configure(state="disabled")
        except queue.Empty:
            pass
        if worker["t"] and not worker["t"].is_alive():
            worker["t"] = None
            start_btn.config(state="normal")
            next_btn.config(state="normal")
        root.after(150, pump)

    def launch(keys):
        if worker["t"]:
            return
        if not keys:
            messagebox.showerror("Nothing selected", "Tick at least one key.")
            return
        stop_event.clear()
        c = copy.deepcopy(cfg)
        try:
            c["politeness"]["delay_seconds"] = max(0.5, float(delay_var.get()))
        except ValueError:
            pass
        lim = int(limit_var.get()) if limit_var.get().strip().isdigit() else None

        def job():
            sc = Scraper(c, stop_event, overwrite.get(), no_img.get(), relist.get())
            try:
                for k in keys:
                    sc.run_key(k, lim)
                log("\nDone.")
            except StopScrape as e:
                log(f"\nSTOPPED SAFELY: {e}\nProgress saved - press Start again to continue.")
            except Exception:
                import traceback
                log(traceback.format_exc())
        start_btn.config(state="disabled")
        next_btn.config(state="disabled")
        worker["t"] = threading.Thread(target=job, daemon=True)
        worker["t"].start()

    def next_key():
        sc = Scraper(cfg)
        k = sc.next_key()
        if k:
            launch([k])
        else:
            log("All keys complete.")

    start_btn = ttk.Button(btns, text="Start selected", command=lambda: launch([k for k, v in key_vars.items() if v.get()]))
    start_btn.pack(side=tk.LEFT, padx=4)
    next_btn = ttk.Button(btns, text="Next unfinished key", command=next_key)
    next_btn.pack(side=tk.LEFT, padx=4)
    ttk.Button(btns, text="Stop (saves progress)", command=stop_event.set).pack(side=tk.LEFT, padx=4)
    ttk.Button(btns, text="Status", command=lambda: Scraper(cfg).status()).pack(side=tk.LEFT, padx=4)

    def on_close():
        stop_event.set()
        root.after(300, root.destroy)
    root.protocol("WM_DELETE_WINDOW", on_close)
    pump()
    root.mainloop()


if __name__ == "__main__":
    if len(sys.argv) > 1:
        sys.exit(run_cli(sys.argv[1:]))
    try:
        run_gui()
    except ImportError:
        print("tkinter not available - use the command line. Try: python fandom_scraper.py --help")
        sys.exit(1)
