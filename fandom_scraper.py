#!/usr/bin/env python3
"""
Polite, resumable Beyblade Fandom scraper that fills the three human-managed workbooks
(layout in beyblade_schema.py, packaged by beyblade_data.py):

    beyblade_parts.xlsx     targets parts:<Gen>:<part>   e.g. parts:X:blades, parts:Burst:layers
    beyblade_products.xlsx  targets products:<Gen>       every release incl. launchers, stadiums, sets
                            + "update" mode: reads the store, finds the last release code per series and
                              manufacturer (e.g. BX-54) and checks BX-55, BX-56 ... until a gap
    beyblade_tcg.xlsx       targets tcg:sets, tcg:cards

The workbooks ARE the store: anything already in them (matched by wiki title, name+code, sku,
card number) is skipped before its page is even downloaded, so re-runs only pull what is new.
Cells you edited by hand are never overwritten (unless --overwrite).

Safety (why the old version timed out / risked an IP ban):
  * one request at a time globally (API + images), min gap + random jitter, 20 pages per batch
  * honours Retry-After + maxlag, exponential backoff, circuit breaker stops after repeated
    throttling, HTTP 403 stops immediately; per-run request budget
  * 600px thumbnails, minified image made locally; page/image cache + checkpoints -> resumable

Usage:
    python fandom_scraper.py --list-targets
    python fandom_scraper.py --find-categories "lock chip"
    python fandom_scraper.py --target parts:X:ratchets --list-only
    python fandom_scraper.py --target parts:X:ratchets --inspect 5
    python fandom_scraper.py --target parts:X:ratchets
    python fandom_scraper.py --scope parts --generation X          # every X part sheet, one after another
    python fandom_scraper.py --scope products --generation X       # list-based product scrape
    python fandom_scraper.py --update                              # next release codes for every series
    python fandom_scraper.py --update --series BX UX               # only these series
    python fandom_scraper.py --update --series BX --from-code BX-40
    python fandom_scraper.py --scope tcg
    python fandom_scraper.py --next / --status
No arguments -> GUI (needs tkinter).
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

import mwparserfromhell
import requests
from mwparserfromhell.nodes import Comment, ExternalLink, HTMLEntity, Tag, Template, Text, Wikilink
from PIL import Image

import beyblade_schema as S
from beyblade_store import Book, norm_name

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(HERE, "scraper_config.json")
CONFIG_VERSION = 3

# =============================================================================
# CONFIG
# =============================================================================

# infobox field names (normalised: lowercase, spaces/_/- collapsed) that feed each column
COLUMN_ALIASES = {
    "name": ["name", "english name", "part name", "title"],
    "code": ["product code", "code", "product number", "product", "release", "first release",
             "released with", "debut", "beyblade", "sku", "number"],
    "edition": ["edition", "release", "first release", "released with", "debut", "beyblade", "product"],
    "mass": ["weight", "mass"],
    "type": ["type", "beyblade type", "class"],
    "movementStyle": ["type", "movement", "movement style"],
    "spinDir": ["spin direction", "spin", "rotation", "spin dir"],
    "attack": ["attack", "atk"],
    "defense": ["defense", "defence", "def"],
    "stamina": ["stamina", "sta"],
    "dash": ["dash", "xtreme dash", "x dash"],
    "burstRes": ["burst resistance", "burst", "burst res"],
    "system": ["system", "series", "line"],
    "layerComponent": ["component", "layer type", "part type"],
    "discType": ["disc type", "type"],
    "heightMm": ["height", "height mm"],
    "protrusions": ["protrusions", "number of protrusions", "contact points"],
    "baseName": ["abbreviation", "short name", "initial", "symbol", "bit code"],
    # products
    "productName": ["name", "english name", "product name", "title"],
    "productType": ["product type", "type", "category", "release type"],
    "releaseDate": ["release date", "released", "japanese release", "jp release", "release date japan",
                    "release", "date", "us release"],
    "itemCost": ["price", "retail price", "cost", "msrp", "srp"],
    "manufacturer": ["manufacturer", "company", "brand", "distributor"],
    "hasbroItem": ["hasbro code", "hasbro product code", "hasbro", "item number", "upc"],
    "description": ["description", "contents", "includes", "comes with"],
    # tcg
    "setCode": ["set code", "code", "set", "series code"],
    "setName": ["name", "english name", "set name", "title"],
    "cardCount": ["cards", "card count", "number of cards", "total cards"],
    "cardNumber": ["card number", "number", "no", "card no", "id"],
    "rarity": ["rarity"],
    "cardType": ["card type", "type"],
    "attribute": ["attribute", "element", "color", "colour"],
    "cost": ["cost"],
    "power": ["power", "attack", "atk"],
    "effectText": ["effect", "ability", "text", "card text", "effect text"],
    "illustrator": ["illustrator", "artist", "illustration"],
}

_EXCLUDE = r"(?i)(/gallery|/anime|/manga|\(disambiguation\))$"
_PRODUCT_CATS = {
    "Plastic": ["Bakuten Shoot Beyblade products", "Plastic Generation products"],
    "HMS": ["HMS products", "Heavy Metal System products"],
    "MetalFight": ["Metal Fight Beyblade products", "Metal Saga products"],
    "ZeroG": ["Zero-G products", "Shogun Steel products"],
    "Burst": ["Beyblade Burst products", "Burst products"],
    "X": ["Beyblade X products", "Beyblade X Products"],
}
_GEN_FILTER = {  # pages listed by shared category names (e.g. "Attack Rings") are kept only if they match
    "Plastic": {"exclude_category_regex": r"(?i)\b(hms|heavy metal)\b"},
    "HMS": {"include_category_regex": r"(?i)\b(hms|heavy metal)\b"},
}


def default_sources():
    src = OrderedDict()
    for gen, key, p in S.all_part_targets():
        src[f"parts:{gen}:{key}"] = dict({
            "categories": p["categories"], "title_prefixes": [p["label"] + " - "],
            "exclude_title_regex": _EXCLUDE, "aliases": {}, "extra_titles": []}, **_GEN_FILTER.get(gen, {}))
    for gen in S.GENERATIONS:
        src[f"products:{gen}"] = {"categories": _PRODUCT_CATS.get(gen, []), "title_prefixes": [],
                                  "exclude_title_regex": _EXCLUDE, "aliases": {}, "extra_titles": []}
    src["tcg:sets"] = {"categories": ["Beyblade X Trading Card Game sets", "TCG Sets"], "title_prefixes": [],
                       "exclude_title_regex": _EXCLUDE, "aliases": {}, "extra_titles": []}
    src["tcg:cards"] = {"categories": ["Beyblade X Trading Card Game cards", "TCG Cards"], "title_prefixes": [],
                        "exclude_title_regex": _EXCLUDE, "aliases": {}, "extra_titles": []}
    return src


DEFAULT_CONFIG = {
    "config_version": CONFIG_VERSION,
    "wiki": "beyblade",
    # Fandom etiquette: identify yourself. PUT A WAY TO CONTACT YOU HERE.
    "user_agent": "ClasherBeybladeAssetsScraper/3.0 (personal hobby project; contact: CHANGE_ME)",
    "workbooks": dict(S.BOOK_FILES),
    "state_dir": "scrape_state",
    "politeness": {
        "delay_seconds": 2.0, "jitter_seconds": 1.0, "batch_size": 20, "connect_timeout": 10,
        "read_timeout": 45, "max_retries": 5, "backoff_base_seconds": 10, "backoff_max_seconds": 300,
        "max_consecutive_failures": 4, "max_requests_per_run": 1500, "maxlag": 5,
        "image_width": 600, "min_image_width": 128, "save_every": 15,
    },
    "update": {
        "miss_limit": 3,             # stop a series after this many codes in a row are not found
        "max_codes_per_series": 40,  # per run
        "search_hits": 4,            # wiki search results checked per code
    },
    "row_defaults": {"hobbyName": S.HOBBY_NAME, "incompleteData": 1, "wbolegality": None,
                     "updated_at": None, "deleted": None},
    "image_field_regex": r"^(image|img|picture|photo|box|box image|box art)\s*\d*$",
    "sources": default_sources(),
}


def load_config(path=CONFIG_PATH):
    cfg = copy.deepcopy(DEFAULT_CONFIG)
    if not os.path.exists(path):
        write_json(path, cfg, indent=2)
        log(f"Created {os.path.basename(path)} - edit categories/aliases there.")
        return cfg
    with open(path, encoding="utf-8") as f:
        user = json.load(f)
    if "parts" in user and "sources" not in user:  # v2 config: parts.<key> -> sources["parts:X:<key>"]
        user["sources"] = {f"parts:X:{k}": v for k, v in user.pop("parts").items()}
        user.pop("output_workbook", None)
        log("Upgraded old scraper_config.json layout (X part settings kept).")
    for k, v in user.items():
        if k == "sources":
            for sk, sv in v.items():
                cfg["sources"].setdefault(sk, {}).update(sv)
        elif isinstance(v, dict) and isinstance(cfg.get(k), dict):
            cfg[k].update(v)
        else:
            cfg[k] = v
    if user.get("config_version") != CONFIG_VERSION:
        cfg["config_version"] = CONFIG_VERSION
        write_json(path, cfg, indent=2)  # add new targets/settings, keep the user's values
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

    def search_pages(self, term, limit=5):
        d = self.api_get(action="query", list="search", srsearch=term, srnamespace="0", srlimit=str(limit),
                         srwhat="text")
        return [h["title"] for h in d["query"]["search"]]

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
# VALUE PARSING
# =============================================================================

NUM_RE = re.compile(r"-?\d+(?:\.\d+)?")
RATCHET_RE = re.compile(r"\b(\d{1,2})-(\d{2,3})\b")
X_COMBO_RE = re.compile(r"([A-Z][A-Za-z.'\s]*?[A-Za-z])\s+(\d{1,2}-\d{2,3})\s*([A-Z][A-Za-z]{0,3})\b")
MONTHS = {m: i for i, m in enumerate(["january", "february", "march", "april", "may", "june", "july", "august",
                                      "september", "october", "november", "december"], 1)}
PRODUCT_TYPE_WORDS = [  # first match wins, so specific before generic
    ("random booster", "Random Booster"), ("starter deck", "TCG Starter Deck"), ("booster pack", "TCG Booster"),
    ("launcher grip", "Launcher Grip"), ("grip", "Launcher Grip"), ("launcher", "Launcher"),
    ("stadium", "Stadium"), ("battle set", "Battle Set"), ("deck set", "Deck Set"), ("entry", "Entry Set"),
    ("customize", "Customize Set"), ("custom set", "Customize Set"), ("starter", "Starter"),
    ("booster", "Booster"), ("case", "Case"), ("tool", "Tool"), ("prize", "Prize"), ("limited", "Limited"),
    ("set", "Set"),
]


def to_number(v):
    if v is None:
        return None
    s = str(v).strip()
    if re.fullmatch(r"-?\d+(\.\d+)?", s):
        f = float(s)
        return int(f) if f.is_integer() else f
    return s or None  # keep things like "30-55" exactly as the master sheet does


def first_number(v):
    m = NUM_RE.search(str(v or "").replace(",", ""))
    if not m:
        return None
    f = float(m.group())
    return int(f) if f.is_integer() else f


def norm_type(v):
    low = str(v or "").lower()
    if "defen" in low:
        return "defense"
    for t in S.BEY_TYPES:
        if t in low:
            return t
    return None


def norm_spin(v):
    low = str(v or "").lower()
    has_r, has_l = "right" in low, "left" in low
    if has_r and has_l:
        return "both"
    return "right" if has_r else "left" if has_l else None


def norm_manufacturer(v):
    low = str(v or "").lower()
    if "takara" in low or "tomy" in low:
        return "Takara-Tomy"
    if "hasbro" in low:
        return "Hasbro"
    if "sonokong" in low:
        return "Sonokong"
    return None


def parse_date(v):
    """first date in text -> 'YYYY-MM-DD' / 'YYYY-MM' / 'YYYY'"""
    s = str(v or "")
    m = re.search(r"\b(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})\b", s)
    if m:
        return f"{m.group(1)}-{int(m.group(2)):02d}-{int(m.group(3)):02d}"
    mon = "|".join(MONTHS)
    m = re.search(rf"\b({mon})\.?\s+(\d{{1,2}})(?:st|nd|rd|th)?,?\s+(\d{{4}})", s, re.I)
    if m:
        return f"{m.group(3)}-{MONTHS[m.group(1).lower()]:02d}-{int(m.group(2)):02d}"
    m = re.search(rf"\b(\d{{1,2}})(?:st|nd|rd|th)?\s+({mon})\.?,?\s+(\d{{4}})", s, re.I)
    if m:
        return f"{m.group(3)}-{MONTHS[m.group(2).lower()]:02d}-{int(m.group(1)):02d}"
    m = re.search(rf"\b({mon})\.?,?\s+(\d{{4}})", s, re.I)
    if m:
        return f"{m.group(2)}-{MONTHS[m.group(1).lower()]:02d}"
    m = re.search(r"\b(19|20)\d{2}\b", s)
    return m.group(0) if m else None


def parse_price(v):
    s = str(v or "")
    if not s:
        return None, None
    cur = ("JPY" if re.search(r"¥|yen|円", s, re.I) else "USD" if "$" in s or "usd" in s.lower()
           else "EUR" if "€" in s else "GBP" if "£" in s else None)
    return first_number(s), cur


def product_type_from(*texts):
    for t in texts:
        low = str(t or "").lower()
        for word, label in PRODUCT_TYPE_WORDS:
            if re.search(rf"\b{re.escape(word)}", low):
                return label
    return None


def title_to_name(title, prefixes=(), label=None):
    name = title
    for pre in prefixes or ():
        if name.lower().startswith(pre.lower()):
            name = name[len(pre):]
            break
    if label:  # "Ratchet - 3-60", "Ratchet: 3-60" even when no prefix is configured
        name = re.sub(rf"^{re.escape(label)}\s*[-–:]\s*", "", name, flags=re.I)
    # drop disambiguators like "(Beyblade X)", "(Burst)", "(Layer)" but keep short ones like "(F)"
    return re.sub(r"\s*\(([^)]{4,})\)\s*$", "", name).strip()


def make_picker(fields, src_aliases):
    def pick(col, keys_only=None):
        names = (src_aliases or {}).get(col) or COLUMN_ALIASES.get(col, [])
        for a in names:
            a = norm_key(a)
            if keys_only and a not in keys_only:
                continue
            if fields.get(a):
                return fields[a]
        return None
    return pick

# =============================================================================
# ROW MAPPING -> workbook columns
# =============================================================================

def map_part(gen, key, title, fields, src):
    cols = S.GENERATIONS[gen]["parts"][key]["columns"]
    pick = make_picker(fields, src.get("aliases"))
    label = S.GENERATIONS[gen]["parts"][key]["label"]
    row = {"hobbyGeneration": gen, "name": title_to_name(title, src.get("title_prefixes"), label) or pick("name")}
    code_src = " ".join(filter(None, [pick("code"), pick("edition")]))
    c = S.parse_code(code_src)
    row["code"] = c["code"] if c else None
    row["manufacturer"] = norm_manufacturer(pick("manufacturer")) or "Takara-Tomy"
    ed = pick("edition")
    row["edition"] = ed.split(";")[0].strip()[:120] if ed else None
    row["mass"] = first_number(pick("mass"))
    if "type" in cols:
        row["type"] = norm_type(pick("type"))
    if "movementStyle" in cols:
        row["movementStyle"] = norm_type(pick("movementStyle"))
    if "spinDir" in cols:
        row["spinDir"] = norm_spin(pick("spinDir"))
    for stat in ("attack", "defense", "stamina", "dash", "burstRes"):
        if stat in cols:
            v = pick(stat)
            row[stat] = to_number(v.split(";")[0]) if v else None
    for col in ("system", "layerComponent", "discType"):
        if col in cols:
            row[col] = pick(col)
    if "heightMm" in cols:
        row["heightMm"] = first_number(pick("heightMm"))
    if key == "ratchets":
        rm = RATCHET_RE.search(row["name"] or "")
        row["protrusions"] = first_number(pick("protrusions")) or (int(rm.group(1)) if rm else None)
        row["heightMm"] = row.get("heightMm") or (int(rm.group(2)) if rm else None)
    if key == "bits":
        bn = pick("baseName")
        if not bn:
            pm = re.search(r"\(([A-Z][A-Za-z]{0,3})\)", title)
            bn = pm.group(1) if pm else None
        row["baseName"] = bn
    return {k: v for k, v in row.items() if k in cols}


def map_product(gen, title, fields, src, manufacturer_hint=None):
    pick = make_picker(fields, src.get("aliases"))
    prefixes = {s[0] for s in S.CODE_SERIES if s[2] == gen} or None
    code = (S.parse_code(" ".join(filter(None, [pick("code"), title])), prefixes)
            or S.parse_code(" ".join(filter(None, [pick("code"), title]))))
    hasbro = S.parse_hasbro_item(pick("hasbroItem") or "")
    manu = norm_manufacturer(pick("manufacturer")) or manufacturer_hint or \
        ("Hasbro" if hasbro and not code else "Takara-Tomy")
    sku = code["code"] if code else None
    if manu == "Hasbro" and hasbro:
        sku = hasbro
    name = title_to_name(title)
    if code and name.upper().startswith(code["code"]):
        name = name[len(code["code"]):].strip(" -:")
    price, cur = parse_price(pick("itemCost"))
    row = {
        "manufacturer": manu, "hobbyName": S.HOBBY_NAME, "hobbyGeneration": gen,
        "productName": name or pick("productName"),
        "productType": product_type_from(pick("productType"), title) or "Other",
        "releaseDate": parse_date(pick("releaseDate")), "itemCost": price,
        "currency": cur or ("JPY" if manu == "Takara-Tomy" else "USD" if manu == "Hasbro" else None),
        "sku": sku, "region": "JP" if manu == "Takara-Tomy" else "US" if manu == "Hasbro" else None,
        "description": (pick("description") or "")[:500] or None, "incompleteData": 1,
    }
    if code and code["sub"]:
        row["variantLabel"] = code["sub"]
    return row, code


def map_tcg_set(title, fields, src):
    pick = make_picker(fields, src.get("aliases"))
    return {"setCode": pick("setCode"), "setName": title_to_name(title) or pick("setName"),
            "manufacturer": norm_manufacturer(pick("manufacturer")) or "Takara-Tomy", "hobbyName": S.HOBBY_NAME,
            "hobbyGeneration": "X", "releaseDate": parse_date(pick("releaseDate")),
            "cardCount": first_number(pick("cardCount")), "description": (pick("description") or "")[:500] or None,
            "incompleteData": 1}


def map_tcg_card(title, fields, src):
    pick = make_picker(fields, src.get("aliases"))
    num = pick("cardNumber") or ""
    m = S.TCG_CARD_NUMBER_RE.search(num) or S.TCG_CARD_NUMBER_RE.search(title)
    return {"cardNumber": m.group(0) if m else (num or None), "setCode": m.group(1) if m else pick("setCode"),
            "name": title_to_name(title) or pick("name"), "manufacturer": norm_manufacturer(pick("manufacturer"))
            or "Takara-Tomy", "hobbyName": S.HOBBY_NAME, "hobbyGeneration": "X", "cardType": pick("cardType"),
            "rarity": pick("rarity"), "attribute": pick("attribute"), "cost": to_number(pick("cost")),
            "power": to_number(pick("power")), "effectText": pick("effectText"),
            "illustrator": pick("illustrator"), "incompleteData": 1}

# =============================================================================
# SCRAPE ENGINE
# =============================================================================

def target_kind(target):
    return target.split(":")[0]


def target_gen_key(target):
    parts = target.split(":")
    return (parts[1] if len(parts) > 1 else None), (parts[2] if len(parts) > 2 else None)


class Scraper:
    def __init__(self, cfg, stop_event=None, overwrite=False, no_images=False, relist=False, refresh_existing=False):
        self.cfg = cfg
        self.client = PoliteClient(cfg, stop_event)
        self.overwrite, self.no_images, self.relist = overwrite, no_images, relist
        self.refresh_existing = refresh_existing
        sd = cfg["state_dir"]
        self.state_dir = sd if os.path.isabs(sd) else os.path.join(HERE, sd)
        os.makedirs(os.path.join(self.state_dir, "images"), exist_ok=True)
        self.progress_path = os.path.join(self.state_dir, "progress.json")
        self.pages_path = os.path.join(self.state_dir, "pages.json")
        self.progress = read_json(self.progress_path, {})
        self.pages = read_json(self.pages_path, {})
        self.image_re = re.compile(cfg["image_field_regex"], re.I)
        self._books = {}
        self.processed = 0

    # ---- store ----------------------------------------------------------------------
    def book_path(self, kind):
        p = self.cfg["workbooks"][kind]
        return p if os.path.isabs(p) else os.path.join(HERE, p)

    def book(self, kind):
        if kind not in self._books:
            self._books[kind] = Book(self.book_path(kind), kind)
        return self._books[kind]

    def save_all(self):
        for b in self._books.values():
            b.save()
        self.save_state()

    def save_state(self):
        write_json(self.progress_path, self.progress)
        write_json(self.pages_path, self.pages)

    def checkpoint(self):
        self.processed += 1
        if self.processed % max(1, int(self.cfg["politeness"]["save_every"])) == 0:
            self.save_all()
            log(f"  -- checkpoint saved ({self.processed} this run, {self.client.count} requests)")

    def kstate(self, target):
        return self.progress.setdefault(target, {"titles": None, "done": {}, "failed": {}, "complete": False})

    def targets(self):
        order = {g: i for i, g in enumerate(["X"] + [g for g in S.GENERATIONS if g != "X"])}
        kinds = {"parts": 0, "products": 1, "tcg": 2}

        def sort_key(t):
            k = target_kind(t)
            gen, _ = target_gen_key(t)
            return (order.get(gen, 0) if k != "tcg" else 0, kinds.get(k, 9))
        return sorted(self.cfg["sources"], key=sort_key)

    # ---- wiki access ----------------------------------------------------------------
    def list_titles(self, target):
        st = self.kstate(target)
        if st["titles"] is not None and not self.relist:
            return st["titles"]
        src = self.cfg["sources"][target]
        titles = []
        for cat in src.get("categories", []):
            got = self.client.category_members(cat, depth=src.get("category_depth", 1))
            log(f"  Category:{cat} -> {len(got)} pages")
            titles += got
        for pre in src.get("title_prefixes", []):
            got = self.client.prefix_pages(pre)
            log(f"  prefix '{pre}' -> {len(got)} pages")
            titles += got
        titles += src.get("extra_titles", [])
        ex = re.compile(src["exclude_title_regex"]) if src.get("exclude_title_regex") else None
        st["titles"] = [t for t in OrderedDict.fromkeys(titles) if not (ex and ex.search(t))]
        st["complete"] = False
        self.save_state()
        return st["titles"]

    def get_pages(self, titles):
        missing = [t for t in titles if t not in self.pages]
        if self.relist:
            cached = [t for t in titles if t in self.pages]
            if cached:
                live = self.client.revids(cached)
                missing += [t for t in cached if live.get(t) and live[t] != self.pages[t].get("revid")]
        bs = max(1, min(50, int(self.cfg["politeness"]["batch_size"])))
        for i, batch in enumerate(chunks(missing, bs), 1):
            for t, pg in self.client.fetch_pages(batch).items():
                if "wikitext" in pg:
                    self.pages[t] = pg
            write_json(self.pages_path, self.pages)
            log(f"  page sources {min(i * bs, len(missing))}/{len(missing)}")
        return {t: self.pages[t] for t in titles if t in self.pages}

    def _img_cache(self, filename):
        return os.path.join(self.state_dir, "images", hashlib.sha1(filename.encode()).hexdigest()[:16])

    def images_for_pages(self, parsed):
        """parsed: {title: (pg, infobox, fields, files)} -> {title: (full_png, min_png)}"""
        out = {}
        if self.no_images:
            return out
        need = {f[0] for (_, _, _, f) in parsed.values() if f and not os.path.exists(self._img_cache(f[0]) + ".png")}
        urls = self.client.resolve_files(need) if need else {}
        p = self.cfg["politeness"]
        for t, (_, _, _, files) in parsed.items():
            if not files:
                continue
            c = self._img_cache(files[0])
            if os.path.exists(c + ".png") and os.path.exists(c + "-min.png"):
                with open(c + ".png", "rb") as a, open(c + "-min.png", "rb") as b:
                    out[t] = (a.read(), b.read())
                continue
            url = urls.get(files[0])
            raw = self.client.request(url, binary=True) if url else None
            if not raw:
                continue
            try:
                full, mini = to_png(raw, p["image_width"]), to_png(raw, p["min_image_width"])
            except Exception as e:
                log(f"    image convert failed for {files[0]}: {e}")
                continue
            with open(c + ".png", "wb") as a, open(c + "-min.png", "wb") as b:
                a.write(full)
                b.write(mini)
            out[t] = (full, mini)
        return out

    def parse(self, pages, titles):
        parsed = {}
        for t in titles:
            pg = pages.get(t)
            if not pg:
                continue
            infobox, fields, files = parse_page(pg.get("wikitext"), self.image_re)
            if not files and pg.get("page_image"):
                files = [norm_file(pg["page_image"].split("/revision/")[0].rsplit("/", 1)[-1].replace("%20", " "))]
            parsed[t] = (pg, infobox, fields, files[:1])
        return parsed

    # ---- store lookups (skip what we already have) ----------------------------------
    def existing_match(self, target, title, row=None):
        """-> (sheet_ws, row_number) of an existing row for this page, or (ws, None)."""
        kind = target_kind(target)
        if kind == "parts":
            gen, key = target_gen_key(target)
            book = self.book("parts")
            ws = book.part_sheet(gen, key)
            hit = book.log_index(target).get(title)
            if hit:
                r, _ = book.find(ws, lambda x: str(x.get("dataID")) == str(hit[1]))
                if r:
                    return ws, r
            label = S.GENERATIONS[gen]["parts"][key]["label"]
            name = norm_name((row or {}).get("name") or
                             title_to_name(title, self.cfg["sources"][target].get("title_prefixes"), label))
            code = (row or {}).get("code")
            best = None
            for r, x in book.rows(ws):
                if norm_name(x.get("name")) == name:
                    if code and x.get("code") == code:
                        return ws, r
                    if best is None and not x.get("parentPartId"):
                        best = r
            return ws, best
        if kind == "products":
            book = self.book("products")
            ws = book.named_sheet("Products")
            hit = book.log_index("products").get(title)
            if hit:
                r, _ = book.find(ws, lambda x: str(x.get("productID")) == str(hit[1]))
                if r:
                    return ws, r
            if row and row.get("sku"):
                c = S.parse_code(row["sku"])
                sequential = c and c["number"] != 0
                for r, x in book.rows(ws):
                    if str(x.get("sku") or "") == row["sku"] and x.get("manufacturer") == row.get("manufacturer"):
                        if sequential or norm_name(x.get("productName")) == norm_name(row.get("productName")):
                            return ws, r
            return ws, None
        book = self.book("tcg")
        sheet = "TCG_Sets" if target == "tcg:sets" else "TCG_Cards"
        ws = book.named_sheet(sheet)
        hit = book.log_index(target).get(title)
        if hit:
            idc = S.SHEETS[sheet]["id"]
            r, _ = book.find(ws, lambda x: str(x.get(idc)) == str(hit[1]))
            if r:
                return ws, r
        if row:
            for r, x in book.rows(ws):
                if sheet == "TCG_Sets" and row.get("setCode") and x.get("setCode") == row["setCode"]:
                    return ws, r
                if (sheet == "TCG_Cards" and row.get("cardNumber") and x.get("cardNumber") == row["cardNumber"]
                        and not x.get("parentCardId")):
                    return ws, r
        return ws, None

    def find_part(self, gen, key, name=None, code=None, base_name=None):
        if key not in S.GENERATIONS[gen]["parts"]:
            return None
        book = self.book("parts")
        ws = book.part_sheet(gen, key)
        n = norm_name(name)
        cands = [x for _, x in book.rows(ws)
                 if (n and norm_name(x.get("name")) == n) or (base_name and x.get("baseName") == base_name)]
        if not cands:
            return None
        for x in cands:
            if code and x.get("code") == code:
                return x.get("dataID")
        base = [x for x in cands if not x.get("parentPartId")]
        return (base or cands)[0].get("dataID")

    # ---- handlers -------------------------------------------------------------------
    def handle_part(self, target, title, pg, infobox, fields, files, imgs):
        gen, key = target_gen_key(target)
        src = self.cfg["sources"][target]
        cats = " ".join(pg.get("categories", []))
        if src.get("include_category_regex") and not re.search(src["include_category_regex"], cats):
            return "filtered (category)"
        if src.get("exclude_category_regex") and re.search(src["exclude_category_regex"], cats):
            return "filtered (category)"
        row = map_part(gen, key, title, fields, src)
        book = self.book("parts")
        ws, r = self.existing_match(target, title, row)
        defaults = dict(self.cfg["row_defaults"])
        r, rid, new = book.write(ws, row, "dataID", row=r, overwrite=self.overwrite, defaults=defaults)
        full, mini = imgs.get(title, (None, None))
        book.set_image(ws, r, "image", full)
        book.set_image(ws, r, "minifiedImage", mini, "min")
        if new or not book.log_index(target).get(title):
            book.add_log(target, ws.title, rid, title, pg.get("url"), pg.get("revid"), files[0] if files else None)
        return f"{'new' if new else 'upd'} #{rid}" + ("" if full or self.no_images else " (no image)")

    def handle_product(self, gen, title, pg, infobox, fields, files, imgs, manufacturer_hint=None):
        src = self.cfg["sources"].get(f"products:{gen}", {})
        row, code = map_product(gen, title, fields, src, manufacturer_hint)
        book = self.book("products")
        prods = book.named_sheet("Products")
        ws, r = self.existing_match("products", title, row)
        if code and code["sub"] and r is None:  # variant of a random booster etc.
            pr, parent = book.find(prods, lambda x: x.get("sku") == code["base"] and
                                   x.get("manufacturer") == row["manufacturer"])
            if parent:
                row["parentProductId"] = parent.get("productID")
        r, pid, new = book.write(prods, row, "productID", "P", row=r, overwrite=self.overwrite)
        full, mini = imgs.get(title, (None, None))
        book.set_image(prods, r, "boxImageUrl", full)
        book.set_image(prods, r, "minifiedBoxImage", mini, "min")
        if new or not book.log_index("products").get(title):
            book.add_log("products", "Products", pid, title, pg.get("url"), pg.get("revid"), files[0] if files else None)
        links = self.link_contents(gen, pid, row, fields, title, full, mini)
        return f"{'new' if new else 'upd'} {pid} {row.get('sku') or ''} [{row['productType']}]" + \
               (f" +{links} contents" if links else "")

    def add_content(self, pid, part_type, part_id, qty=1):
        book = self.book("products")
        pc = book.named_sheet("ProductContents")
        r, _ = book.find(pc, lambda x: str(x.get("productID")) == str(pid) and x.get("partType") == part_type
                         and str(x.get("partDataID")) == str(part_id))
        if r is None:
            book.write(pc, {"productID": pid, "partType": part_type, "partDataID": part_id, "quantity": qty})
            return 1
        return 0

    def link_contents(self, gen, pid, prow, fields, title, full, mini):
        n = 0
        book = self.book("products")
        acc_type = S.ACCESSORY_PRODUCT_TYPES.get(prow["productType"])
        if acc_type:  # launcher / stadium / grip ... is itself an accessory
            acc = book.named_sheet("Accessories")
            r, x = book.find(acc, lambda x: norm_name(x.get("name")) == norm_name(prow["productName"])
                             and x.get("manufacturer") == prow["manufacturer"])
            vals = {"accessoryType": acc_type, "manufacturer": prow["manufacturer"], "hobbyName": S.HOBBY_NAME,
                    "hobbyGeneration": gen, "code": prow.get("sku"), "name": prow["productName"],
                    "itemCost": prow.get("itemCost"), "incompleteData": 1}
            r, aid, _ = book.write(acc, vals, "dataID", row=r, overwrite=self.overwrite)
            book.set_image(acc, r, "imageUrl", full)
            book.set_image(acc, r, "minifiedImage", mini, "min")
            n += self.add_content(pid, "Accessories", aid)
        # parts named in the infobox, e.g. |blade=DranSword |ratchet=3-60 |bit=Flat
        for key, p in S.GENERATIONS[gen]["parts"].items():
            for word in p["words"]:
                v = fields.get(norm_key(word))
                if not v:
                    continue
                for name in [s.strip() for s in re.split(r";|,|/", v) if s.strip()][:3]:
                    did = self.find_part(gen, key, name, prow.get("sku"))
                    if did is not None:
                        n += self.add_content(pid, S.part_sheet(gen, key), did)
                break
        # X combos written as "DranSword 3-60F"
        if gen == "X":
            text = " ".join(filter(None, [fields.get("beyblade"), fields.get("combo"), fields.get("contents"), title]))
            for m in X_COMBO_RE.finditer(text):
                blade, ratchet, bit = m.groups()
                for key, kw in (("blades", {"name": blade}), ("ratchets", {"name": ratchet}),
                                ("bits", {"base_name": bit})):
                    did = self.find_part("X", key, code=prow.get("sku"), **kw)
                    if did is not None:
                        n += self.add_content(pid, S.part_sheet("X", key), did)
        return n

    def handle_tcg(self, target, title, pg, infobox, fields, files, imgs):
        src = self.cfg["sources"][target]
        book = self.book("tcg")
        if target == "tcg:sets":
            row, sheet, idc, pre = map_tcg_set(title, fields, src), "TCG_Sets", "setID", "S"
        else:
            row, sheet, idc, pre = map_tcg_card(title, fields, src), "TCG_Cards", "dataID", ""
        ws, r = self.existing_match(target, title, row)
        r, rid, new = book.write(ws, row, idc, pre, row=r, overwrite=self.overwrite)
        full, mini = imgs.get(title, (None, None))
        book.set_image(ws, r, "image", full)
        book.set_image(ws, r, "minifiedImage", mini, "min")
        if new or not book.log_index(target).get(title):
            book.add_log(target, sheet, rid, title, pg.get("url"), pg.get("revid"), files[0] if files else None)
        return f"{'new' if new else 'upd'} {rid} {row.get('cardNumber') or row.get('setCode') or ''}"

    # ---- runs -----------------------------------------------------------------------
    def run_target(self, target, limit=None):
        if target not in self.cfg["sources"]:
            raise SystemExit(f"Unknown target '{target}'. Use --list-targets.")
        kind = target_kind(target)
        st = self.kstate(target)
        log(f"\n=== {target} -> {os.path.basename(self.book_path(kind))} ===")
        titles = self.list_titles(target)
        if not titles:
            log("  !! nothing listed. Run --find-categories <word> and fix this target's 'categories' / "
                "'title_prefixes' in scraper_config.json")
            return
        todo = []
        skipped = 0
        for t in titles:
            if t in st["done"]:
                continue
            if not self.refresh_existing and kind != "products" and self.existing_match(target, t)[1]:
                st["done"][t] = "already in store"
                skipped += 1
                continue
            todo.append(t)
        log(f"  {len(titles)} pages listed, {skipped} already in the store (skipped without downloading), "
            f"{len(todo)} to fetch")
        if limit:
            todo = todo[:limit]
        try:
            bs = max(1, min(50, int(self.cfg["politeness"]["batch_size"])))
            for batch in chunks(todo, bs):
                pages = self.get_pages(batch)
                parsed = self.parse(pages, batch)
                for t in batch:
                    if t not in parsed:
                        st["failed"][t] = "page missing"
                imgs = self.images_for_pages(parsed)
                for t, (pg, infobox, fields, files) in parsed.items():
                    if kind == "parts":
                        res = self.handle_part(target, t, pg, infobox, fields, files, imgs)
                    elif kind == "products":
                        gen, _ = target_gen_key(target)
                        res = self.handle_product(gen, t, pg, infobox, fields, files, imgs)
                    else:
                        res = self.handle_tcg(target, t, pg, infobox, fields, files, imgs)
                    st["done"][t] = res
                    st["failed"].pop(t, None)
                    log(f"  [{res}] {t}")
                    self.checkpoint()
            st["complete"] = all(t in st["done"] for t in titles)
        finally:
            self.save_all()
            log(f"  saved: {len(st['done'])}/{len(titles)} pages handled for {target}, "
                f"{self.client.count} requests used this run")

    # ---- update by release code -----------------------------------------------------
    def code_series(self):
        book = self.book("products")
        cs = book.named_sheet("CodeSeries")
        if not book.rows(cs):
            for s in S.CODE_SERIES:
                book.write(cs, dict(zip(S.CODE_SERIES_COLUMNS, s)))
        return book, cs

    def run_update(self, prefixes=None, generation=None, manufacturer=None, from_code=None):
        book, cs = self.code_series()
        series = []
        for r, x in book.rows(cs):
            if str(x.get("sequential") or "0") not in ("1", "True", "true", "TRUE"):
                continue
            if prefixes and x.get("seriesPrefix") not in prefixes:
                continue
            if generation and x.get("hobbyGeneration") != generation:
                continue
            if manufacturer and x.get("manufacturer") != manufacturer:
                continue
            series.append((r, x))
        if not series:
            log("No matching sequential series in the CodeSeries sheet.")
            return
        try:
            for r, x in series:
                self.update_series(book, cs, r, x, from_code)
        finally:
            self.save_all()

    def update_series(self, book, cs, cs_row, s, from_code=None):
        prefix, manu, gen = s["seriesPrefix"], s["manufacturer"], s["hobbyGeneration"]
        digits = int(s.get("digits") or 2)
        prods = book.named_sheet("Products")
        have = set()
        for _, x in book.rows(prods):
            c = S.parse_code(x.get("sku"), {prefix})
            if c and x.get("manufacturer") == manu and c["number"] > 0:
                have.add(c["number"])
        last = max(have, default=0)
        start = last + 1
        fc = S.parse_code(from_code, {prefix}) if from_code else None
        if fc:
            start = fc["number"]
        up = self.cfg["update"]
        log(f"\n=== update {prefix} ({manu}, {gen}): store has up to "
            f"{S.format_code(prefix, last, digits) if last else 'nothing'}, checking from "
            f"{S.format_code(prefix, start, digits)} ===")
        misses = checked = 0
        n = start
        found_max = last
        while misses < int(up["miss_limit"]) and checked < int(up["max_codes_per_series"]):
            if n in have:
                n += 1
                continue
            code = S.format_code(prefix, n, max(digits, len(str(n))))
            if self.probe_code(code, prefix, gen, manu):
                misses = 0
                found_max = max(found_max, n)
            else:
                misses += 1
                log(f"  {code}: not found ({misses}/{up['miss_limit']})")
            n += 1
            checked += 1
        if found_max:
            hdr = book.headers(cs)
            cs.cell(cs_row, hdr["lastKnownCode"], S.format_code(prefix, found_max, max(digits, len(str(found_max)))))
        log(f"  {prefix}: stopped after {checked} codes checked "
            f"({'gap of ' + str(misses) if misses >= int(up['miss_limit']) else 'per-run limit'})")

    def probe_code(self, code, prefix, gen, manu):
        titles = self.client.search_pages(f'"{code}"', int(self.cfg["update"]["search_hits"]))
        part_prefixes = tuple(p.lower() for t, s in self.cfg["sources"].items() if t.startswith("parts:")
                              for p in s.get("title_prefixes", []))
        titles = [t for t in titles if not t.lower().startswith(part_prefixes)]
        if not titles:
            return False
        parsed = self.parse(self.get_pages(titles), titles)
        part_words = {w for _, _, p in S.all_part_targets() for w in [p["label"].lower()]}
        scored = []
        for t, (pg, infobox, fields, files) in parsed.items():
            score = 0
            if code.lower() in t.lower():
                score += 3
            for k, v in fields.items():
                c = S.parse_code(v, {prefix})
                if c and c["base"] == code:
                    score += 2 if k in ("product code", "code", "product number", "sku", "number") else 1
                    break
            ib = infobox.lower()
            if any(w in ib for w in part_words) and "product" not in ib:
                score -= 5
            if score >= 2:
                scored.append((score, t))
        if not scored:
            return False
        scored.sort(reverse=True)
        best = [t for sc, t in scored if sc == scored[0][0]][:3]
        imgs = self.images_for_pages({t: parsed[t] for t in best})
        for t in best:
            pg, infobox, fields, files = parsed[t]
            res = self.handle_product(gen, t, pg, infobox, fields, files, imgs, manufacturer_hint=manu)
            log(f"  {code}: [{res}] {t}")
            self.checkpoint()
        return True

    # ---- helpers for humans ---------------------------------------------------------
    def inspect(self, target, n):
        titles = self.list_titles(target)[:n]
        pages = self.get_pages(titles)
        seen = Counter()
        kind = target_kind(target)
        src = self.cfg["sources"][target]
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
            if kind == "parts":
                gen, key = target_gen_key(target)
                log(f"    => {map_part(gen, key, t, fields, src)}")
            elif kind == "products":
                gen, _ = target_gen_key(target)
                log(f"    => {map_product(gen, t, fields, src)[0]}")
            else:
                log(f"    => {(map_tcg_set if target == 'tcg:sets' else map_tcg_card)(t, fields, src)}")
        log("\nField names seen (add useful ones to this target's 'aliases' in scraper_config.json):")
        for k, c in seen.most_common():
            log(f"  {c:3d}x  {k}")
        self.save_state()

    def status(self):
        for kind in S.BOOK_FILES:
            log(f"{kind:9s} workbook: {self.book_path(kind)}")
        for t in self.targets():
            st = self.progress.get(t)
            if not st or st.get("titles") is None:
                continue
            n, d = len(st["titles"]), len(st["done"])
            log(f"  {t:28s} {d}/{n} handled, {len(st['failed'])} failed{'  COMPLETE' if st.get('complete') else ''}")
        if os.path.exists(self.book_path("products")):
            book = self.book("products")
            for _, x in book.rows(book.named_sheet("CodeSeries")):
                if x.get("lastKnownCode"):
                    log(f"  series {x['seriesPrefix']:6s} {x['manufacturer']:12s} last known {x['lastKnownCode']}")

    def next_target(self):
        for t in self.targets():
            if not self.progress.get(t, {}).get("complete"):
                return t
        return None

# =============================================================================
# CLI
# =============================================================================

def resolve_targets(cfg, a):
    ts = list(a.target or [])
    for k in a.key or []:  # old --key blades
        ts.append(k if ":" in k else f"parts:X:{k}")
    if a.scope:
        for t in cfg["sources"]:
            kind = target_kind(t)
            gen, key = target_gen_key(t)
            if kind != a.scope:
                continue
            if a.generation and kind != "tcg" and gen != a.generation:
                continue
            if a.part and key not in a.part:
                continue
            ts.append(t)
    return list(OrderedDict.fromkeys(ts))


def run_cli(argv):
    ap = argparse.ArgumentParser(description="Polite, resumable Beyblade wiki scraper -> parts/products/tcg workbooks")
    ap.add_argument("--target", action="append", help="e.g. parts:X:blades, products:X, tcg:cards (repeatable)")
    ap.add_argument("--scope", choices=["parts", "products", "tcg"], help="all targets of one workbook")
    ap.add_argument("--generation", choices=S.GENERATION_NAMES, help="limit --scope / --update to a generation")
    ap.add_argument("--part", nargs="+", help="with --scope parts: only these part keys")
    ap.add_argument("--key", action="append", help=argparse.SUPPRESS)
    ap.add_argument("--update", action="store_true", help="look for releases after the last code in the store")
    ap.add_argument("--series", nargs="+", help="with --update: series prefixes, e.g. BX UX CX B")
    ap.add_argument("--manufacturer", choices=S.MANUFACTURERS, help="with --update")
    ap.add_argument("--from-code", help="with --update: start here instead of after the store's last code")
    ap.add_argument("--next", action="store_true", help="scrape the next target that is not complete")
    ap.add_argument("--limit", type=int, help="max pages per target this run")
    ap.add_argument("--max-requests", type=int, help="request budget for this run (0 = unlimited)")
    ap.add_argument("--delay", type=float, help="minimum seconds between requests (>= 0.5)")
    ap.add_argument("--no-images", action="store_true")
    ap.add_argument("--overwrite", action="store_true", help="overwrite filled cells (default: fill blanks only)")
    ap.add_argument("--refresh-existing", action="store_true",
                    help="also fetch pages already in the store to fill their blank cells")
    ap.add_argument("--relist", action="store_true", help="re-list pages (find new ones) and refetch changed ones")
    ap.add_argument("--reset", metavar="TARGET", help="forget scrape progress for TARGET (workbook rows kept)")
    ap.add_argument("--list-only", action="store_true")
    ap.add_argument("--inspect", type=int, metavar="N", help="show infobox fields of the first N pages")
    ap.add_argument("--find-categories", metavar="WORD")
    ap.add_argument("--list-targets", action="store_true")
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
    sc = Scraper(cfg, overwrite=a.overwrite, no_images=a.no_images, relist=a.relist,
                 refresh_existing=a.refresh_existing)
    if a.list_targets:
        for t in sc.targets():
            log(f"  {t}")
        return 0
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
        if a.update:
            sc.run_update(a.series, a.generation, a.manufacturer, a.from_code)
            return 0
        targets = resolve_targets(cfg, a)
        if a.next:
            t = sc.next_target()
            if not t:
                log("All targets complete.")
                return 0
            targets = [t]
        if not targets:
            ap.print_help()
            return 1
        for t in targets:
            if a.list_only:
                ts = sc.list_titles(t)
                log(f"{t}: {len(ts)} pages")
                for x in ts:
                    log(f"  {x}")
            elif a.inspect:
                sc.inspect(t, a.inspect)
            else:
                sc.run_target(t, a.limit)
    except StopScrape as e:
        log(f"\nSTOPPED SAFELY: {e}")
        log("Everything done so far is saved. Run the same command again to continue.")
        return 2
    except KeyboardInterrupt:
        sc.save_all()
        log("\nInterrupted - progress saved. Run again to continue.")
        return 130
    return 0

# =============================================================================
# GUI (optional)
# =============================================================================

def run_gui():
    import queue
    import tkinter as tk
    from tkinter import ttk, scrolledtext

    global _LOG_SINK
    q = queue.Queue()
    _LOG_SINK = q.put
    cfg = load_config()

    root = tk.Tk()
    root.title("Beyblade Wiki Scraper (polite / resumable)")
    root.geometry("900x700")
    frm = ttk.Frame(root, padding=10)
    frm.pack(fill=tk.BOTH, expand=True)

    top = ttk.Frame(frm)
    top.grid(row=0, column=0, sticky="w")
    ttk.Label(top, text="Workbook:").pack(side=tk.LEFT)
    scope = tk.StringVar(value="parts")
    ttk.Combobox(top, textvariable=scope, values=["parts", "products", "tcg"], width=10, state="readonly"
                 ).pack(side=tk.LEFT, padx=4)
    ttk.Label(top, text="Generation:").pack(side=tk.LEFT, padx=(10, 0))
    gen = tk.StringVar(value="X")
    ttk.Combobox(top, textvariable=gen, values=S.GENERATION_NAMES, width=11, state="readonly").pack(side=tk.LEFT, padx=4)

    tf = ttk.LabelFrame(frm, text="Targets (processed one after another, each into its own sheet)", padding=6)
    tf.grid(row=1, column=0, sticky="we", pady=6)
    tvars = {}

    def rebuild(*_):
        for w in tf.winfo_children():
            w.destroy()
        tvars.clear()
        for i, t in enumerate(x for x in cfg["sources"] if target_kind(x) == scope.get()
                              and (scope.get() == "tcg" or target_gen_key(x)[0] == gen.get())):
            tvars[t] = tk.BooleanVar(value=True)
            ttk.Checkbutton(tf, text=t.split(":", 1)[1], variable=tvars[t]).grid(row=i // 4, column=i % 4,
                                                                                  sticky="w", padx=6)
    scope.trace_add("write", rebuild)
    gen.trace_add("write", rebuild)
    rebuild()

    opts = ttk.Frame(frm)
    opts.grid(row=2, column=0, sticky="w", pady=4)
    no_img, overwrite, relist, refresh = (tk.BooleanVar() for _ in range(4))
    for text, var in (("Skip images", no_img), ("Overwrite filled cells", overwrite),
                      ("Re-list (find new pages)", relist), ("Refresh rows already in store", refresh)):
        ttk.Checkbutton(opts, text=text, variable=var).pack(side=tk.LEFT, padx=4)
    ttk.Label(opts, text="Limit:").pack(side=tk.LEFT, padx=(10, 2))
    limit_var = tk.StringVar()
    ttk.Entry(opts, textvariable=limit_var, width=5).pack(side=tk.LEFT)
    ttk.Label(opts, text="Delay s:").pack(side=tk.LEFT, padx=(10, 2))
    delay_var = tk.StringVar(value=str(cfg["politeness"]["delay_seconds"]))
    ttk.Entry(opts, textvariable=delay_var, width=5).pack(side=tk.LEFT)

    up = ttk.Frame(frm)
    up.grid(row=3, column=0, sticky="w", pady=4)
    ttk.Label(up, text="Update series (blank = all):").pack(side=tk.LEFT)
    series_var = tk.StringVar()
    ttk.Entry(up, textvariable=series_var, width=18).pack(side=tk.LEFT, padx=4)
    ttk.Label(up, text="from code:").pack(side=tk.LEFT)
    from_var = tk.StringVar()
    ttk.Entry(up, textvariable=from_var, width=10).pack(side=tk.LEFT, padx=4)

    btns = ttk.Frame(frm)
    btns.grid(row=4, column=0, sticky="w", pady=6)
    out = scrolledtext.ScrolledText(frm, height=22, state="disabled", bg="black", fg="lightgray",
                                    font=("Consolas", 10))
    out.grid(row=5, column=0, sticky="nsew")
    frm.rowconfigure(5, weight=1)
    frm.columnconfigure(0, weight=1)
    stop_event = threading.Event()
    worker = {"t": None}
    action_btns = []

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
            for b in action_btns:
                b.config(state="normal")
        root.after(150, pump)

    def launch(fn):
        if worker["t"]:
            return
        stop_event.clear()
        c = copy.deepcopy(cfg)
        try:
            c["politeness"]["delay_seconds"] = max(0.5, float(delay_var.get()))
        except ValueError:
            pass

        def job():
            sc = Scraper(c, stop_event, overwrite.get(), no_img.get(), relist.get(), refresh.get())
            try:
                fn(sc)
                log("\nDone.")
            except StopScrape as e:
                log(f"\nSTOPPED SAFELY: {e}\nProgress saved - start again to continue.")
                sc.save_all()
            except Exception:
                import traceback
                log(traceback.format_exc())
        for b in action_btns:
            b.config(state="disabled")
        worker["t"] = threading.Thread(target=job, daemon=True)
        worker["t"].start()

    def start_selected():
        ts = [t for t, v in tvars.items() if v.get()]
        lim = int(limit_var.get()) if limit_var.get().strip().isdigit() else None
        launch(lambda sc: [sc.run_target(t, lim) for t in ts])

    def start_update():
        ser = series_var.get().split() or None
        launch(lambda sc: sc.run_update(ser, None if ser else gen.get(), None, from_var.get().strip() or None))

    def start_next():
        def fn(sc):
            t = sc.next_target()
            sc.run_target(t) if t else log("All targets complete.")
        launch(fn)

    for text, cmd in (("Start selected", start_selected), ("Update releases (next codes)", start_update),
                      ("Next unfinished target", start_next)):
        b = ttk.Button(btns, text=text, command=cmd)
        b.pack(side=tk.LEFT, padx=4)
        action_btns.append(b)
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
