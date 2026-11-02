#!/usr/bin/env python3
"""
Polite, resumable Beyblade Fandom scraper that fills the three human-managed workbooks
(layout in beyblade_schema.py, packaged by beyblade_data.py):

    beyblade_parts.xlsx     targets parts:<Gen>:<part>   e.g. parts:X:blades, parts:Burst:layers
    beyblade_products.xlsx  targets products:<Gen>  read from the wiki's "List of ... products (Takara Tomy /
                            Hasbro)" pages: every release (starters, boosters, random boosters, sets, launchers,
                            stadiums, limited BX-00 releases) in a few requests; each new product's page adds the
                            box image, random-booster items (CX-05 01 ... as variants) and contents links
                            + "update" mode: re-reads the lists, then checks codes after the store's last one per
                              series and manufacturer (e.g. BX-57 -> BX-58, BX-59 ...) until a gap
    beyblade_tcg.xlsx       targets tcg:<Gen>:cards / tcg:<Gen>:sets   (Plastic = original 2000s TCG, X = X TCG)

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
CONFIG_VERSION = 4

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
    "wbolegality": ["wbo ranked league", "wbo", "wbo legality", "wbo format legality", "legality", "legal"],
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
    "effectText": ["game text", "gametext", "effect", "ability", "text", "card text", "effect text"],
    "illustrator": ["illustrator", "artist", "illustration"],
    "subtitle": ["subtitle", "sub title"],
    "battleEdge": ["battle edge", "battleedge", "edge"],
    "spinStrength": ["spin strength", "spinstrength"],
    "loreText": ["lore", "flavor", "flavor text", "flavour text", "flavortext"],
    "cardSetName": ["set", "set name", "expansion"],
    "cardSetNumber": ["set no", "set number", "setno", "set code"],
}

_EXCLUDE = r"(?i)(/gallery|/anime|/manga|\(disambiguation\))$"
# Products come from the wiki's "List of ... products (Takara Tomy / Hasbro)" pages: one table per line
# (Basic / Unique / Custom / Limited) with code, name, release date, price -> every release in a few requests.
# Explicit list pages first; others are discovered in Category:Product Lists by title regex.
_PRODUCT_LISTS = {
    "X": ["List of Beyblade X products (Takara Tomy)", "List of Beyblade X products (Hasbro)"],
}
_PRODUCT_LIST_REGEX = {
    "Plastic": r"(?i)\b(bakuten|plastic|original series|v-?force|g-?revolution)\b",
    "HMS": r"(?i)\b(hms|heavy metal)\b",
    "MetalFight": r"(?i)\b(metal fight|metal fusion|metal masters|metal fury|metal saga|4d)\b",
    "ZeroG": r"(?i)\b(zero-?g|shogun steel)\b",
    "Burst": r"(?i)\bburst\b",
    "X": r"(?i)\bbeyblade x\b",
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
        src[f"products:{gen}"] = {
            "list_pages": _PRODUCT_LISTS.get(gen, []), "list_pages_category": "Product Lists",
            "list_page_regex": _PRODUCT_LIST_REGEX.get(gen, ""),
            "fetch_product_pages": True,   # open each product's page: box image, random-booster items, contents
            "categories": [], "title_prefixes": [], "exclude_title_regex": _EXCLUDE, "aliases": {}, "extra_titles": []}
    # card games: the old 2000s TCG pages are in Category:Cards (Blade Cards, ...); X TCG names are guesses
    src["tcg:Plastic:cards"] = {"categories": ["Cards"], "category_depth": 1, "title_prefixes": [],
                                "exclude_title_regex": _EXCLUDE, "aliases": {}, "extra_titles": []}
    src["tcg:X:cards"] = {"categories": ["Beyblade X TCG Cards", "Beyblade X Trading Card Game cards"],
                          "title_prefixes": [], "exclude_title_regex": _EXCLUDE, "aliases": {}, "extra_titles": []}
    src["tcg:X:sets"] = {"categories": ["Beyblade X TCG Sets", "Beyblade X Trading Card Game sets"],
                         "title_prefixes": [], "exclude_title_regex": _EXCLUDE, "aliases": {}, "extra_titles": []}
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
        "request_deadline_seconds": 90,  # hard cap on one download, even if data keeps trickling in
        "max_response_mb": 25,
        "heartbeat_seconds": 15,         # print what is going on when nothing was logged for this long
        "variant_images": True,          # parts: also download each recolor's image from the page gallery
        "rendered_infobox": "auto",      # parts: read the rendered infobox when stats are missing (auto/always/never)
        "workbook_image_format": "webp", # images stored in the workbooks: webp (packager copies as-is) or png
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
    for old, new in (("tcg:cards", "tcg:X:cards"), ("tcg:sets", "tcg:X:sets")):  # v3 names
        if old in user.get("sources", {}):
            user["sources"][new] = user["sources"].pop(old)
    for gen in S.GENERATIONS:  # v3 guessed product categories that don't exist -> list pages now
        ps = user.get("sources", {}).get(f"products:{gen}")
        if ps is not None and user.get("config_version", 0) < 4:
            ps.pop("categories", None)
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
_LOG_FILE = {"path": None}
_LOG_LOCK = threading.Lock()
LOG_OPTS = {"quiet": False}  # quiet: per-request lines go to the log file only


class Activity:
    """What the scraper is doing right now - shown by the heartbeat and the GUI status line."""

    def __init__(self):
        self.text, self.detail, self.since, self.last_log = "idle", "", time.monotonic(), time.monotonic()

    def set(self, text, detail=""):
        self.text, self.detail, self.since = text, detail, time.monotonic()

    def describe(self):
        secs = time.monotonic() - self.since
        return f"{self.text}{' - ' + self.detail if self.detail else ''} ({secs:.0f}s)"


ACTIVITY = Activity()


def log(msg="", detail=False):
    """detail=True lines (one per HTTP request) are hidden on screen with --quiet but always go to the log file."""
    msg = str(msg)
    lead = msg[:len(msg) - len(msg.lstrip("\n"))]
    line = f"{lead}{time.strftime('%H:%M:%S')} {msg.lstrip(chr(10))}" if msg.strip() else msg
    with _LOG_LOCK:
        ACTIVITY.last_log = time.monotonic()
        if _LOG_FILE["path"]:
            try:
                with open(_LOG_FILE["path"], "a", encoding="utf-8") as f:
                    f.write(line + "\n")
            except OSError:
                pass
        if detail and LOG_OPTS["quiet"]:
            return
        if _LOG_SINK:
            _LOG_SINK(line)
        else:
            print(line, flush=True)


def set_log_file(path):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    _LOG_FILE["path"] = path
    with open(path, "a", encoding="utf-8") as f:
        f.write(f"\n===== run started {time.strftime('%Y-%m-%d %H:%M:%S')} =====\n")


def start_heartbeat(seconds=15, stop_event=None):
    """Prints what is happening whenever nothing has been logged for `seconds` - so a stall is never silent."""
    def beat():
        while not (stop_event and stop_event.is_set()):
            time.sleep(1)
            if ACTIVITY.text == "idle":
                continue  # finished (GUI keeps running between jobs) - nothing to report
            if time.monotonic() - ACTIVITY.last_log >= seconds:
                log(f"  ... still busy: {ACTIVITY.describe()}")
    t = threading.Thread(target=beat, daemon=True)
    t.start()
    return t


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
    return re.sub(r"[\s_\-]+", " ", re.sub(r"[.:#()]", "", str(k).strip().lower())).strip()


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


class SlowResponse(requests.RequestException):
    """Body took longer than request_deadline_seconds (a trickling connection) or was too large."""


def describe_api(p):
    """Short human description of an API call for the log."""
    bits = ["API"]
    for k in ("list", "prop"):
        if p.get(k):
            bits.append(f"{k}={p[k]}")
    for k in ("cmtitle", "apprefix", "srsearch"):
        if p.get(k):
            bits.append(repr(p[k]))
    if p.get("titles"):
        ts = p["titles"].split("|")
        bits.append(f"({len(ts)} titles: {ts[0][:40]}{' ...' if len(ts) > 1 else ''})")
    if any(k.endswith("continue") for k in p):
        bits.append("[continued]")
    return " ".join(bits)


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
        return max(0.0, wait)

    def _read_body(self, r, what):
        """Read the response with a hard total deadline, so a slow-trickling server can't hang the run."""
        deadline = time.monotonic() + float(self.p.get("request_deadline_seconds", 90))
        limit = float(self.p.get("max_response_mb", 25)) * 1024 * 1024
        buf = bytearray()
        try:
            for chunk in r.iter_content(64 * 1024):
                if self.stop_event.is_set():
                    raise UserStopped("Stopped by user.")
                buf += chunk
                ACTIVITY.detail = f"{len(buf) // 1024} KB received"
                if time.monotonic() > deadline:
                    raise SlowResponse(f"{what}: still downloading after "
                                       f"{self.p.get('request_deadline_seconds', 90)}s ({len(buf) // 1024} KB)")
                if len(buf) > limit:
                    raise SlowResponse(f"{what}: response larger than {self.p.get('max_response_mb', 25)} MB")
        finally:
            r.close()
        return bytes(buf)

    def _backoff(self, attempt, retry_after=None):
        if attempt >= self.p["max_retries"] - 1:
            return  # last attempt failed - no point waiting before giving up
        if retry_after:
            try:
                secs = float(retry_after)
            except ValueError:
                secs = self.p["backoff_base_seconds"]
        else:
            secs = self.p["backoff_base_seconds"] * (2 ** attempt)
        secs = min(secs, self.p["backoff_max_seconds"]) + random.uniform(0, 3)
        log(f"    ...waiting {secs:.0f}s before retrying")
        ACTIVITY.set(f"backing off {secs:.0f}s before retry {attempt + 1}", ACTIVITY.text)
        self._sleep(secs)

    def _fail(self, why):
        self.consecutive_failures += 1
        if self.consecutive_failures >= self.p["max_consecutive_failures"]:
            raise Cooldown(f"{self.consecutive_failures} failures in a row ({why}). The wiki is throttling "
                           f"or unreachable - stopping to protect your IP. Wait 15-30 min and run again.")

    def request(self, url, params=None, binary=False, what=None):
        budget = self.p.get("max_requests_per_run") or 0
        what = what or url
        with self.lock:
            for attempt in range(self.p["max_retries"]):
                if self.stop_event.is_set():
                    raise UserStopped("Stopped by user.")
                if budget and self.count >= budget:
                    raise BudgetExhausted(f"Request budget of {budget} reached for this run. Run again to continue.")
                ACTIVITY.set(f"waiting politely before request #{self.count + 1}", what)
                waited = self._wait_turn()
                self.count += 1
                n = self.count
                retry = f" retry {attempt}" if attempt else ""
                log(f"    -> #{n} {what}{retry} (waited {waited:.1f}s)", detail=True)
                ACTIVITY.set(f"request #{n}: {what}", "connecting")
                t0 = time.monotonic()
                try:
                    r = self.s.get(url, params=params, stream=True,
                                   timeout=(self.p["connect_timeout"], self.p["read_timeout"]))
                    ACTIVITY.detail = f"HTTP {r.status_code}, reading body"
                    body = self._read_body(r, what) if r.status_code < 400 else b""
                except requests.RequestException as e:
                    self.last = time.monotonic()
                    log(f"    <- #{n} network error after {time.monotonic() - t0:.1f}s: {type(e).__name__}: "
                        f"{str(e)[:160]}")
                    self._fail(type(e).__name__)
                    self._backoff(attempt)
                    continue
                self.last = time.monotonic()
                log(f"    <- #{n} HTTP {r.status_code}, {len(body) / 1024:.0f} KB in {self.last - t0:.1f}s",
                    detail=True)
                ACTIVITY.set("processing", what)

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
                    return body
                try:
                    data = json.loads(body.decode("utf-8"))
                except ValueError:
                    log(f"    <- #{n} response was not JSON (first bytes: {body[:80]!r})")
                    self._fail("bad JSON")
                    self._backoff(attempt)
                    continue
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
            self._fail("retries exhausted")  # still counts towards the circuit breaker
            if binary:
                log(f"    giving up on {what} after {self.p['max_retries']} attempts - skipped, continuing")
                return None
            raise Cooldown(f"Gave up on {what} after {self.p['max_retries']} attempts. Wait and run again.")

    # ---- MediaWiki helpers --------------------------------------------------
    def api_get(self, **params):
        what = describe_api(params)
        params.update(format="json", formatversion="2", maxlag=str(self.p["maxlag"]))
        return self.request(self.api, params=params, what=what)

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

    def rendered_lead_html(self, title):
        """Rendered HTML of the top of a page (where the infobox lives)."""
        d = self.api_get(action="parse", page=title, prop="text", section="0", disablelimitreport="1",
                         disableeditsection="1", redirects="1")
        return (d.get("parse") or {}).get("text") or ""

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
# RENDERED INFOBOX (fallback when the page source doesn't give the stats)
# =============================================================================

from html.parser import HTMLParser  # noqa: E402

_VOID_TAGS = {"br", "img", "hr", "meta", "input", "wbr", "source", "link", "col"}


class PortableInfoboxParser(HTMLParser):
    """Reads Fandom's rendered portable infobox: the labels you see on the page ("Spin Direction",
    "Weight", "Attack") and their values, plus the first infobox image. With tabbed infoboxes
    (Original / Version 2.0) the first tab wins."""

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack = []          # [(tag, attrs)]
        self.values = OrderedDict()   # data-source -> text
        self.labels = {}         # data-source -> label text
        self.image = None
        self._cap = None         # (kind, key, depth, [text])

    def _source(self):
        for tag, a in reversed(self.stack):
            if a.get("data-source"):
                return a["data-source"]
        return None

    def handle_starttag(self, tag, attrs):
        a = {k: (v or "") for k, v in attrs}
        if tag == "br" and self._cap:
            self._cap[3].append("\n")
        if tag == "img" and self.image is None and any("portable-infobox" in (x.get("class", "")) for _, x in self.stack):
            self.image = a.get("data-image-key") or a.get("data-image-name")
        if tag in _VOID_TAGS:
            return
        self.stack.append((tag, a))
        cls = a.get("class", "")
        if self._cap is None:
            kind = ("value" if re.search(r"pi-(smart-)?data-value", cls) else
                    "label" if re.search(r"pi-(smart-)?data-label", cls) else None)
            if kind:
                self._cap = (kind, a.get("data-source") or self._source(), len(self.stack), [])

    def handle_endtag(self, tag):
        if tag in _VOID_TAGS:
            return
        while self.stack:
            t, _ = self.stack.pop()
            if self._cap and len(self.stack) < self._cap[2]:
                kind, key, _, text = self._cap
                val = re.sub(r"[ \t]+", " ", "".join(text)).strip()
                val = "\n".join(x.strip() for x in val.splitlines() if x.strip())
                if key and val:
                    target = self.values if kind == "value" else self.labels
                    target.setdefault(key, val)
                self._cap = None
            if t == tag:
                break

    def handle_data(self, data):
        if self._cap:
            self._cap[3].append(data)


def rendered_infobox_fields(html):
    """-> ({normalised label or data-source: value}, infobox image filename or None)"""
    p = PortableInfoboxParser()
    try:
        p.feed(html or "")
    except Exception:
        return {}, None
    out = OrderedDict()
    for src, val in p.values.items():
        out.setdefault(norm_key(src), val)
        if p.labels.get(src):
            out.setdefault(norm_key(p.labels[src]), val)
    img = norm_file(p.image) if p.image else None
    return out, img

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
        for t in tpls:  # "Infobox Blade", "Product Information", "Card" ...
            if re.search(r"infobox|information|product|card", str(t.name), re.I) and named(t) >= 1:
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

def to_image(content, max_width, fmt="webp"):
    """Resize to max_width and encode as WebP (default: what the packager and the app use, so the
    packager copies it as-is) or PNG (for very old Excel versions that can't show WebP)."""
    im = Image.open(io.BytesIO(content))
    im.seek(0)
    im = im.convert("RGBA")
    if im.width > max_width:
        im = im.resize((max_width, max(1, round(im.height * max_width / im.width))), Image.LANCZOS)
    buf = io.BytesIO()
    if fmt == "png":
        im.save(buf, "PNG", optimize=True)
    else:
        im.save(buf, "WEBP", quality=85, method=6)
    return buf.getvalue()


def to_png(content, max_width):  # kept for older callers
    return to_image(content, max_width, "png")


# =============================================================================
# VALUE PARSING
# =============================================================================

NUM_RE = re.compile(r"-?\d+(?:\.\d+)?")
RATCHET_RE = re.compile(r"\b(\d{1,2})-(\d{2,3})\b")
# "DranSword 3-60F", "HellsReaper T4-70K" (CX: assist-blade letter before the ratchet), "Lightning L-Drago 1-60F"
COMBO_RE = re.compile(r"(?<![A-Za-z-])([A-Z][A-Za-z'-]*[A-Za-z](?:\s[A-Z][A-Za-z'-]*[A-Za-z])?)\s+"
                      r"([A-Z]{0,3})(\d{1,2}-\d{2,3})\s*([A-Z][A-Za-z]{0,3})\b")
PRODUCT_WORDS_RE = re.compile(r"(?i)\b(?:random booster|starter|booster|color choice booster|entry package)\b\s*")
MONTHS = {m: i for i, m in enumerate(["january", "february", "march", "april", "may", "june", "july", "august",
                                      "september", "october", "november", "december"], 1)}
PRODUCT_TYPE_WORDS = [  # first match wins, so specific before generic
    ("random booster", "Random Booster"), ("starter deck", "TCG Starter Deck"), ("booster pack", "TCG Booster"),
    ("battle pass", "Battle Pass"), ("beybattle pass", "Battle Pass"),
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
    row["mass"] = first_number(pick("mass"))  # "34.6 grams (first mold)\n35.1 grams" -> 34.6
    wbo = pick("wbolegality")
    if wbo:
        row["wbolegality"] = 0 if re.search(r"(?i)\u274c|\u2716|\u2718|\bno\b|\bban|illegal|\bnot\b", wbo) else \
            1 if re.search(r"(?i)\u2714|\u2705|\byes\b|\blegal|\ballowed", wbo) else None
    if "type" in cols:
        row["type"] = norm_type(pick("type"))
    if "movementStyle" in cols:
        row["movementStyle"] = norm_type(pick("movementStyle"))
    if "spinDir" in cols:
        row["spinDir"] = norm_spin(pick("spinDir"))
    for stat in ("attack", "defense", "stamina", "dash", "burstRes"):
        if stat in cols:
            v = pick(stat)  # "55\n60 (2.0)" (first mold / version 2.0) -> 55
            row[stat] = to_number(re.split(r"[;\n]", v)[0].strip()) if v else None
    if "attack" in cols and row.get("attack") is None:
        nums = NUM_RE.findall(fields.get("stats") or "")  # |stats={{Stats|25|10|25}} -> "25 10 25"
        if len(nums) >= 3:
            row["attack"], row["defense"], row["stamina"] = (to_number(n) for n in nums[:3])
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


def map_tcg_set(title, fields, src, gen="X"):
    pick = make_picker(fields, src.get("aliases"))
    return {"setCode": pick("setCode"), "setName": title_to_name(title) or pick("setName"),
            "manufacturer": norm_manufacturer(pick("manufacturer")), "hobbyName": S.TCG_HOBBY_NAME,
            "hobbyGeneration": gen, "releaseDate": parse_date(pick("releaseDate")),
            "cardCount": first_number(pick("cardCount")), "description": (pick("description") or "")[:500] or None,
            "incompleteData": 1}


def card_name(title):
    return title_to_name(re.sub(r"\s*\((?:TCG|card|trading card game)\)\s*$", "", title, flags=re.I))


def map_tcg_card(title, fields, src, gen="X", categories=()):
    pick = make_picker(fields, src.get("aliases"))
    num = pick("cardNumber") or ""
    m = S.TCG_CARD_NUMBER_RE.search(num) or S.TCG_CARD_NUMBER_RE.search(title)
    ctype = re.sub(r"(?i)\s*card$", "", pick("cardType") or "").strip() or None
    if not ctype:  # "Blade Cards" category -> Blade
        for c in categories:
            cm = re.match(r"^(.+?) Cards$", c)
            if cm:
                ctype = cm.group(1)
                break
    return {"cardNumber": m.group(0) if m else (num or None),
            "setCode": m.group(1) if m else pick("cardSetNumber"), "setName": pick("cardSetName"),
            "name": card_name(title) or pick("name"), "subtitle": pick("subtitle"),
            "manufacturer": norm_manufacturer(pick("manufacturer")), "hobbyName": S.TCG_HOBBY_NAME,
            "hobbyGeneration": gen, "cardType": ctype, "rarity": pick("rarity"), "attribute": pick("attribute"),
            "cost": to_number(pick("cost")), "power": to_number(pick("power")),
            "battleEdge": to_number(pick("battleEdge")), "spinStrength": to_number(pick("spinStrength")),
            "effectText": pick("effectText"), "loreText": pick("loreText"),
            "illustrator": pick("illustrator"), "incompleteData": 1}

# =============================================================================
# PRODUCT LIST PAGES ("List of Beyblade X products (Takara Tomy)")
# =============================================================================

def _split_outside_links(line, sep):
    """Split a wikitable row on '||' / '!!' but not inside [[...]] or {{...}}."""
    out, buf, depth, i = [], "", 0, 0
    while i < len(line):
        two = line[i:i + 2]
        if two in ("[[", "{{"):
            depth += 1
            buf += two
            i += 2
        elif two in ("]]", "}}"):
            depth = max(0, depth - 1)
            buf += two
            i += 2
        elif depth == 0 and two == sep:
            out.append(buf)
            buf = ""
            i += 2
        else:
            buf += line[i]
            i += 1
    out.append(buf)
    return out


_CELL_ATTR_RE = re.compile(r'^\s*((?:[\w-]+\s*=\s*(?:"[^"]*"|\'[^\']*\'|[^\s|]+)\s*)+)\|(?!\|)(.*)$', re.S)


def _strip_cell_attrs(cell):
    m = _CELL_ATTR_RE.match(cell)
    return m.group(2) if m else cell


def parse_wikitables(wikitext):
    """-> [{'section': heading, 'headers': [cell wikitext], 'rows': [[cell wikitext]]}]"""
    tables, section, cur, row = [], "", None, None
    for raw in (wikitext or "").splitlines():
        line = raw.strip()
        h = re.match(r"^(=+)\s*(.*?)\s*\1$", line)
        if h and cur is None:
            section = clean_value(mwparserfromhell.parse(h.group(2)))
            continue
        if line.startswith("{|"):
            cur, row = {"section": section, "headers": [], "rows": []}, None
            continue
        if cur is None:
            continue
        if line.startswith("|}"):
            if row:
                cur["rows"].append(row)
            tables.append(cur)
            cur, row = None, None
        elif line.startswith("|+"):
            continue
        elif line.startswith("|-"):
            if row:
                cur["rows"].append(row)
            row = None
        elif line.startswith("!"):
            cells = [_strip_cell_attrs(c) for c in _split_outside_links(line[1:], "!!")]
            if not cur["rows"] and row is None:
                cur["headers"] += cells
            else:
                row = (row or []) + cells
        elif line.startswith("|"):
            row = (row or []) + [_strip_cell_attrs(c) for c in _split_outside_links(line[1:], "||")]
        elif row:
            row[-1] += "\n" + raw
    return tables


def cell_text_link(cell):
    m = re.search(r"\[\[(?!(?:File|Image|Category):)([^\]|#]+)", cell or "", re.I)
    return clean_value(mwparserfromhell.parse(cell or "")), (m.group(1).strip() if m else None)


def product_entries(list_title, wikitext, gen):
    """Rows of every product table on a list page."""
    manu = norm_manufacturer(list_title) or "Takara-Tomy"
    entries = []
    for tb in parse_wikitables(wikitext):
        hdr = [norm_key(cell_text_link(h)[0]) for h in tb["headers"]]

        def col(*words, skip=()):
            return next((i for i, h in enumerate(hdr) if i not in skip and any(w in h for w in words)), None)
        ci = col("code", "number", "item", "sku")
        ni = col("name", skip=(ci,))
        if ni is None:
            ni = col("product", "title", skip=(ci,))
        di = col("release", "date")
        pi = col("price", "msrp", "srp", "cost")
        if ni is None or (ci is None and di is None):
            continue
        for r in tb["rows"]:
            def get(i):
                return cell_text_link(r[i]) if i is not None and i < len(r) else ("", None)
            name, link = get(ni)
            if not name:
                continue
            entries.append({"list": list_title, "section": tb["section"], "manufacturer": manu,
                            "code": get(ci)[0], "name": name, "link": link, "date": get(di)[0], "price": get(pi)[0]})
    return entries


def entry_to_row(gen, e):
    c = S.parse_code(e["code"])
    sku = c["code"] if c else (S.parse_hasbro_item(e["code"]) or e["code"] or None)
    limited = bool(re.search(r"(?i)limited|exclusive|prize|event", e["section"]))
    dm = re.match(r"^(.*?)\s*\((.+?)\)?\s*$", e["date"] or "")
    date_part, note = (dm.group(1), dm.group(2)) if dm and "(" in (e["date"] or "") else (e["date"], None)
    price, cur = parse_price(e["price"]) if not re.search(r"(?i)n/?a", e["price"] or "") else (None, None)
    manu = e["manufacturer"]
    row = {"manufacturer": manu, "hobbyName": S.HOBBY_NAME, "hobbyGeneration": gen, "productName": e["name"],
           "productType": product_type_from(e["name"]) or ("Limited" if limited else "Other"),
           "releaseDate": parse_date(date_part), "itemCost": price,
           "currency": cur or ("JPY" if manu == "Takara-Tomy" else "USD" if manu == "Hasbro" else None),
           "sku": sku, "region": "JP" if manu == "Takara-Tomy" else "US" if manu == "Hasbro" else None,
           "description": "; ".join(x for x in [("Limited release" if limited else e["section"] or None), note]
                                    if x) or None,
           "incompleteData": 1}
    return row, limited, note


def entry_key(e):
    return f"{e['list']}::{e['code']}::{e['name']}::{e['date']}"


def parse_assortment(wikitext):
    """'* CX-05 01: [[HellsReaper T4-70K]] (Prize)' -> [{'base','sub','code','name','note'}]"""
    out = []
    for line in (wikitext or "").splitlines():
        if not line.lstrip().startswith(("*", "#")):
            continue
        txt = clean_value(mwparserfromhell.parse(line.lstrip("*#: ")))
        m = re.match(r"^([A-Z]{1,4}-\d{2,3})\s+(\d{2})\s*[:\-\u2013]\s*(.+?)\s*(?:\(([^)]*)\))?\s*$", txt)
        if m:
            out.append({"base": m.group(1), "sub": m.group(2), "code": f"{m.group(1)} {m.group(2)}",
                        "name": m.group(3).strip(), "note": m.group(4)})
    return out


_NOTE_STOP = {"ver", "version", "the", "and", "of", "a"}


def note_tokens(text):
    """'Metal Coat: Bronze' -> {'metal','coat','bronze'}; 'Katsushika City Ver.' -> {'katsushika','city'};
    'Version 2.0' / 'Ver. 2' / 'V2' -> {'v2'}"""
    t = str(text or "").lower()
    t = re.sub(r"\b(?:version|ver\.?)\s*(\d+)(?:\.0)?\b", r" v\1 ", t)
    t = re.sub(r"\bv(\d+)\.0\b", r"v\1", t)
    return set(re.findall(r"[a-z0-9]+", t)) - _NOTE_STOP


def parse_product_line(txt, manufacturer=None):
    """One line of a part page's Products section, e.g.
        'BX-01 DranSword 3-60F'
        'BX-07 Start Dash Set - DranSword 3-60F (Special Ver.)'
        'BX-14 Random Booster Vol. 1 - 03: DranSword 3-80B'
        'BX-00 DranSword 3-60F (Metal Coat: Bronze) (G1 Prize)'
        'BX-00 "'DranSword 3-60F 'Version 2.0"'
        'G0197 Tail Viper and Sword Dran Dual Pack - Sword Dran 3-60F (Red Ver.)'   (Hasbro item number)
    -> {manufacturer, base, sub, code, product, combo, note, extra}"""
    txt = re.sub(r"[\"\u201c\u201d]|'(?=\S)|(?<=\S)'", " ", (txt or "")).strip()
    txt = re.sub(r"\s+", " ", txt)
    m = re.match(r"^([A-Z]{1,4}-\d{2,3})(?:\s+(\d{2})(?=\s|:|$))?\s*[:\-\u2013]?\s*(.*)$", txt)
    if m:
        base, sub, rest = m.group(1), m.group(2), m.group(3)
        manu = manufacturer or "Takara-Tomy"
    else:
        m = re.match(r"^([A-Z]\d{4})\s*[:\-\u2013]?\s*(.*)$", txt)
        if not m:
            return None
        base, sub, rest, manu = m.group(1), None, m.group(2), "Hasbro"
    product, combo = rest, None
    mm = re.match(r"^(.*?)\s+[-\u2013]\s+(?:(\d{2})\s*:\s*)?(.+)$", rest)   # 'Set - [03:] Combo'
    if mm:
        product, sub, combo = mm.group(1), mm.group(2) or sub, mm.group(3)
    else:
        mm = re.match(r"^(.*?)\s*:\s*(.+)$", rest)                          # 'Random Booster Vol. 1: Combo'
        if mm and COMBO_RE.search(mm.group(2)):
            product, combo = mm.group(1), mm.group(2)
    tail = combo or product or ""
    notes = re.findall(r"\(([^()]*)\)", tail)
    note = notes[0].strip() if notes else None
    extra = "; ".join(n.strip() for n in notes[1:]) or None
    if not note:  # 'DranSword 3-60F Version 2.0' / 'DranSword V2'
        vm = re.search(r"\b(Version \d+(?:\.\d+)?|Ver\. ?\d+(?:\.\d+)?|V\d+(?:\.\d+)?)\s*$", tail)
        note = vm.group(1) if vm else None
    return {"manufacturer": manu, "base": base, "sub": sub, "code": base + (f" {sub}" if sub else ""),
            "product": (product or "").strip() or None, "combo": (combo or "").strip() or None,
            "note": note, "extra": extra, "line": txt}


def parse_part_products(wikitext):
    """'== Products ==' section of a part page -> one entry per product the part came in (both manufacturers)."""
    out, in_products, manu = [], False, None
    for raw in (wikitext or "").splitlines():
        line = raw.strip()
        h = re.match(r"^(=+)\s*(.*?)\s*\1$", line)
        if h:
            level, name = len(h.group(1)), clean_value(mwparserfromhell.parse(h.group(2)))
            if level <= 2:
                in_products, manu = name.lower().startswith(("product", "release")), None
            elif in_products:
                manu = norm_manufacturer(name) or manu
            continue
        if in_products and line.startswith(("*", "#")):
            e = parse_product_line(clean_value(mwparserfromhell.parse(line.lstrip("*#: "))), manu)
            if e and (e["manufacturer"], e["code"], e["product"], e["combo"]) not in {
                    (x["manufacturer"], x["code"], x["product"], x["combo"]) for x in out}:
                out.append(e)
    return out


def release_edition(e):
    """'Random Booster Vol. 6 06 (HellsReaper T4-70K)' style edition text for a release."""
    prod = e["product"] or ""
    if e["sub"] and e["combo"]:
        return f"{prod} {e['sub']} ({e['combo']})".strip()
    return (prod + (f" ({e['combo']})" if e["combo"] else "")).strip() or None


def parse_gallery(wikitext):
    """<gallery> lines 'MainBladeReaper2.png|Reaper (CX-05 02/G2746)' -> [(filename, [codes], caption)]"""
    out = []
    for block in re.findall(r"<gallery[^>]*>(.*?)</gallery>", wikitext or "", re.S | re.I):
        for line in block.splitlines():
            m = re.match(r"^\s*(?:File:|Image:)?\s*([^|\n]+?\." + IMAGE_EXT + r")\s*(?:\|(.*))?$", line, re.I)
            if not m:
                continue
            cap = clean_value(mwparserfromhell.parse(m.group(2) or ""))
            codes = [f"{c.group(1)}-{c.group(2)}" + (f" {c.group(3)}" if c.group(3) else "")
                     for c in S.CODE_RE.finditer(cap)] + S.HASBRO_ITEM_RE.findall(cap)
            out.append((norm_file(m.group(1)), codes, cap))
    return out


def gallery_file_for(gallery, e):
    """Gallery image for a release. Captions look like 'DranSword (BX-01/F9580)',
    'DranSword (Red Ver.; BX-17/G0197)', 'DranSword (Metal Coat: Bronze)' (no code at all).
    A release with a note (recolor) only takes a caption naming that note; a plain release takes the
    caption with its code that doesn't belong to a sibling recolor."""
    code = e["code"]
    want = note_tokens(e.get("note"))
    hits = [(f, cap) for f, codes, cap in gallery if code in codes or (" " not in code and e["base"] in codes)]
    if want:
        for f, cap in hits:
            if want <= note_tokens(cap):
                return f
        for f, codes, cap in gallery:
            if want <= note_tokens(cap):
                return f
        return None
    sibling = [note_tokens(n) for n in e.get("_sibling_notes", []) if n]
    for f, cap in hits:
        if not any(t and t <= note_tokens(cap) for t in sibling):
            return f
    return None


def combo_parts(text):
    """'Starter HellsReaper T4-70K' -> {'blade':'HellsReaper','assist':'T','ratchet':'4-70','bit':'K'}"""
    m = COMBO_RE.search(PRODUCT_WORDS_RE.sub("", text or "").strip())
    if not m:
        return None
    return {"blade": m.group(1), "assist": m.group(2) or None, "ratchet": m.group(3), "bit": m.group(4)}

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
            path = self.book_path(kind)
            ACTIVITY.set(f"opening {os.path.basename(path)}")
            t0 = time.monotonic()
            log(f"  opening {os.path.basename(path)}{'' if os.path.exists(path) else ' (new file)'} ...")
            self._books[kind] = Book(path, kind)
            log(f"  opened in {time.monotonic() - t0:.1f}s")
        return self._books[kind]

    def save_all(self):
        for kind, b in self._books.items():
            if not b.dirty:
                continue  # only read from - don't rewrite it (a big parts workbook takes a while to save)
            n_img = sum(len(ws._images) for ws in b.wb.worksheets)
            ACTIVITY.set(f"saving {os.path.basename(b.path)}", f"{n_img} images")
            t0 = time.monotonic()
            b.save()
            log(f"  saved {os.path.basename(b.path)} ({n_img} images) in {time.monotonic() - t0:.1f}s")
        ACTIVITY.set("saving progress files", f"{len(self.pages)} cached pages")
        t0 = time.monotonic()
        self.save_state()
        if time.monotonic() - t0 > 2:
            log(f"  saved progress files in {time.monotonic() - t0:.1f}s")

    def save_state(self):
        write_json(self.progress_path, self.progress)
        write_json(self.pages_path, self.pages)

    def checkpoint(self):
        self.processed += 1
        if self.processed % max(1, int(self.cfg["politeness"]["save_every"])) == 0:
            self.save_all()
            log(f"  -- checkpoint saved ({self.processed} this run, {self.client.count} requests)")

    def kstate(self, target):
        st = self.progress.setdefault(target, {"titles": None, "done": {}, "failed": {}, "complete": False})
        if target_kind(target) == "parts" and st.get("schema", 1) < 3:
            # earlier runs stored one row per part and could miss stats; revisit every page once for its
            # variants + stats (page sources come from the local cache, so no extra page downloads)
            st["done"], st["complete"], st["schema"] = {}, False, 3
        return st

    def targets(self):
        order = {g: i for i, g in enumerate(["X"] + [g for g in S.GENERATIONS if g != "X"])}
        kinds = {"parts": 0, "products": 1, "tcg": 2}

        def sort_key(t):
            k = target_kind(t)
            gen, _ = target_gen_key(t)
            return (order.get(gen, 0), kinds.get(k, 9))
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

    def get_pages(self, titles, refresh=False):
        missing = [t for t in titles if t not in self.pages]
        if self.relist or refresh:
            cached = [t for t in titles if t in self.pages]
            if cached:
                live = self.client.revids(cached)
                missing += [t for t in cached if live.get(t) and live[t] != self.pages[t].get("revid")]
        bs = max(1, min(50, int(self.cfg["politeness"]["batch_size"])))
        cached = len(titles) - len(missing)
        if cached:
            log(f"  {cached} page sources from cache")
        for i, batch in enumerate(chunks(missing, bs), 1):
            log(f"  downloading page sources {(i - 1) * bs + 1}-{(i - 1) * bs + len(batch)} of {len(missing)} ...")
            for t, pg in self.client.fetch_pages(batch).items():
                if "wikitext" in pg:
                    self.pages[t] = pg
            ACTIVITY.set("writing page cache", f"{len(self.pages)} pages")
            write_json(self.pages_path, self.pages)
            log(f"  page sources {min(i * bs, len(missing))}/{len(missing)} done")
        return {t: self.pages[t] for t in titles if t in self.pages}

    def fill_from_rendered(self, target, parsed):
        """Pages whose source didn't give type / spin / stats / weight: read the rendered infobox
        (same labels as on the page) and fill the gaps. One request per such page, cached."""
        mode = self.cfg["politeness"].get("rendered_infobox", "auto")
        if mode == "never":
            return
        gen, key = target_gen_key(target)
        src = self.cfg["sources"][target]
        cols = S.GENERATIONS[gen]["parts"][key]["columns"]
        want = [c for c in ("type", "spinDir", "attack", "mass") if c in cols]
        need = []
        for t, (pg, infobox, fields, files) in parsed.items():
            row = map_part(gen, key, t, fields, src)
            if mode == "always" or any(row.get(c) in (None, "") for c in want):
                need.append(t)
        if not need:
            return
        log(f"  {len(need)} pages lack stats in their source - reading their rendered infobox ...")
        for i, t in enumerate(need, 1):
            pg, infobox, fields, files = parsed[t]
            cached = pg.get("rendered_fields")
            if cached is None:
                ACTIVITY.set(f"rendered infobox {i}/{len(need)}", t)
                try:
                    rf, img = rendered_infobox_fields(self.client.rendered_lead_html(t))
                except RuntimeError as e:
                    log(f"    {t}: could not render ({e})")
                    rf, img = {}, None
                pg["rendered_fields"], pg["rendered_image"] = dict(rf), img
                if i % 10 == 0:
                    write_json(self.pages_path, self.pages)
            for k, v in (pg.get("rendered_fields") or {}).items():
                fields.setdefault(k, v)
            if not files and pg.get("rendered_image"):
                files.append(pg["rendered_image"])
            got = map_part(gen, key, t, fields, src)
            log(f"    {t}: " + ", ".join(f"{c}={got.get(c)}" for c in want + ["defense", "stamina"] if c in cols))
        write_json(self.pages_path, self.pages)

    def completeness_report(self, target):
        """How many rows of the sheet still have blanks in the columns that matter."""
        if target_kind(target) != "parts":
            return
        gen, key = target_gen_key(target)
        book = self.book("parts")
        ws = book.part_sheet(gen, key)
        rows = [x for _, x in book.rows(ws)]
        cols = [c for c in ("code", "type", "spinDir", "attack", "defense", "stamina", "mass", "wbolegality",
                            "baseName", "protrusions", "heightMm")
                if c in S.GENERATIONS[gen]["parts"][key]["columns"]]
        hdr = book.headers(ws)
        img_rows = {im.anchor._from.row + 1 for im in ws._images if im.anchor._from.col + 1 == hdr.get("image")}
        blanks = {c: sum(1 for x in rows if x.get(c) in (None, "")) for c in cols}
        n_img = sum(1 for r, _ in book.rows(ws) if r in img_rows)
        log(f"  {ws.title}: {len(rows)} rows ({sum(1 for x in rows if x.get('parentPartId'))} variants), "
            f"{n_img} with image; still blank: " +
            (", ".join(f"{c} {n}" for c, n in blanks.items() if n) or "nothing"))

    def _img_cache(self, filename):
        return os.path.join(self.state_dir, "images", hashlib.sha1(filename.encode()).hexdigest()[:16])

    def _cached_image(self, fname, fmt, p):
        """(full, mini) from the local cache; converts a cache of the other format without re-downloading."""
        c = self._img_cache(fname)
        if os.path.exists(f"{c}.{fmt}") and os.path.exists(f"{c}-min.{fmt}"):
            with open(f"{c}.{fmt}", "rb") as a, open(f"{c}-min.{fmt}", "rb") as b:
                return a.read(), b.read()
        other = "png" if fmt == "webp" else "webp"
        if os.path.exists(f"{c}.{other}"):
            with open(f"{c}.{other}", "rb") as a:
                src = a.read()
            full, mini = to_image(src, p["image_width"], fmt), to_image(src, p["min_image_width"], fmt)
            with open(f"{c}.{fmt}", "wb") as a, open(f"{c}-min.{fmt}", "wb") as b:
                a.write(full)
                b.write(mini)
            return full, mini
        return None

    def fetch_images(self, filenames, label="images"):
        """{filename: (full, mini)} for wiki files (WebP by default), from the local cache when possible."""
        out = {}
        filenames = [f for f in OrderedDict.fromkeys(filenames) if f]
        if self.no_images or not filenames:
            return out
        p = self.cfg["politeness"]
        fmt = p.get("workbook_image_format", "webp")
        need = [f for f in filenames if not any(os.path.exists(f"{self._img_cache(f)}.{x}") for x in ("webp", "png"))]
        log(f"  {label}: {len(filenames)} files, {len(filenames) - len(need)} cached, {len(need)} to download")
        if need:
            log(f"  looking up {len(need)} image URLs ...")
        urls = self.client.resolve_files(set(need)) if need else {}
        for i, fname in enumerate(filenames, 1):
            c = self._img_cache(fname)
            cached = self._cached_image(fname, fmt, p)
            if cached:
                out[fname] = cached
                continue
            url = urls.get(fname)
            if not url:
                log(f"  image {i}/{len(filenames)}: {fname} - no URL on the wiki (file missing?), skipped")
                continue
            log(f"  image {i}/{len(filenames)}: {fname}")
            raw = self.client.request(url, binary=True, what=f"image {fname}")
            if not raw:
                log("    no image data - row will be written without an image (rerun with --refresh-existing later)")
                continue
            ACTIVITY.set(f"converting image {fname}", f"{len(raw) // 1024} KB")
            try:
                full, mini = to_image(raw, p["image_width"], fmt), to_image(raw, p["min_image_width"], fmt)
            except Exception as e:
                log(f"    image convert failed for {fname}: {e}")
                continue
            with open(f"{c}.{fmt}", "wb") as a, open(f"{c}-min.{fmt}", "wb") as b:
                a.write(full)
                b.write(mini)
            out[fname] = (full, mini)
        return out

    def images_for_pages(self, parsed):
        """parsed: {title: (pg, infobox, fields, files)} -> {title: (full_png, min_png)} (main image per page)"""
        got = self.fetch_images([v[3][0] for v in parsed.values() if v[3]], "main images")
        return {t: got[v[3][0]] for t, v in parsed.items() if v[3] and v[3][0] in got}

    def parse(self, pages, titles):
        parsed = {}
        log(f"  parsing {len(titles)} pages ...")
        for t in titles:
            pg = pages.get(t)
            if not pg:
                log(f"  ! {t}: not returned by the wiki (deleted / renamed?)")
                continue
            ACTIVITY.set("parsing page", t)
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
        gen, key = target_gen_key(target)
        sheet = "TCG_Sets" if key == "sets" else "TCG_Cards"
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
                if sheet == "TCG_Cards" and not x.get("parentCardId"):
                    if row.get("cardNumber") and x.get("cardNumber") == row["cardNumber"]:
                        return ws, r
                    if (not row.get("cardNumber") and x.get("hobbyGeneration") == gen
                            and norm_name(x.get("name")) == norm_name(row.get("name"))
                            and norm_name(x.get("setName")) == norm_name(row.get("setName"))):
                        return ws, r
        elif sheet == "TCG_Cards":  # before download: same name + generation already there
            n = norm_name(card_name(title))
            for r, x in book.rows(ws):
                if x.get("hobbyGeneration") == gen and norm_name(x.get("name")) == n and not x.get("parentCardId"):
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
        """One part page -> the main-release row + one variant row per other product it came in
        (recolors, random-booster items, limited releases, Hasbro releases), each with its own code and,
        when the wiki gallery has it, its own image. Variants get parentPartId = the main release's dataID."""
        gen, key = target_gen_key(target)
        src = self.cfg["sources"][target]
        cats = " ".join(pg.get("categories", []))
        if src.get("include_category_regex") and not re.search(src["include_category_regex"], cats):
            return "filtered (category)"
        if src.get("exclude_category_regex") and re.search(src["exclude_category_regex"], cats):
            return "filtered (category)"
        row = map_part(gen, key, title, fields, src)
        wt = pg.get("wikitext") or ""
        releases = parse_part_products(wt)
        gallery = parse_gallery(wt)
        gimgs = getattr(self, "_gallery_imgs", {})

        # main release = first Takara Tomy product with the debut code from the infobox
        main = None
        tt = [e for e in releases if e["manufacturer"] == "Takara-Tomy"]
        debut = (row.get("code") or "").split(" ")[0]
        main = next((e for e in tt if e["base"] == debut), None) or (tt[0] if tt else None) or \
            (releases[0] if releases else None)
        if main:
            row["code"] = main["code"]
            row["edition"] = release_edition(main)
            row["manufacturer"] = main["manufacturer"]

        book = self.book("parts")
        ws, r = self.existing_match(target, title, row)
        if releases and r is not None:
            # never take another release's row (e.g. the BX-50 06 recolor) as the main release
            other_codes = {e["code"] for e in releases if e is not main}
            x = dict(book.rows(ws)).get(r, {})
            if str(x.get("code") or "") in other_codes and str(x.get("code") or "") != row.get("code"):
                r = None
                n = norm_name(row["name"])
                for rr, xx in book.rows(ws):
                    if norm_name(xx.get("name")) == n and str(xx.get("code") or "") == row.get("code"):
                        r = rr
                        break
        defaults = dict(self.cfg["row_defaults"])
        r, rid, new = book.write(ws, row, "dataID", row=r, overwrite=self.overwrite, defaults=defaults)
        for e in releases:  # releases sharing a code: their notes tell the gallery images apart
            e["_sibling_notes"] = [x["note"] for x in releases if x["code"] == e["code"] and x is not e]
        gfile = gallery_file_for(gallery, main) if main else None
        full, mini = gimgs.get(gfile) if gfile in gimgs else imgs.get(title, (None, None))
        book.set_image(ws, r, "image", full)
        book.set_image(ws, r, "minifiedImage", mini, "min")
        if new or not book.log_index(target).get(title):
            book.add_log(target, ws.title, rid, title, pg.get("url"), pg.get("revid"), gfile or (files[0] if files else None))
        if main:
            self.link_part_to_product(main, ws.title, rid)

        # variants
        shared = {k: v for k, v in row.items() if k not in ("code", "edition", "manufacturer", "dataID")}
        shared["name"] = book.rows(ws)[r - 2][1].get("name") or row["name"]  # keep the store's spelling
        n_new = n_upd = n_img = 0
        for e in releases:
            if e is main:
                continue
            vals = dict(shared, code=e["code"], edition=release_edition(e), manufacturer=e["manufacturer"],
                        parentPartId=rid, variantLabel=e["note"] or e["combo"] or e["product"])
            vr = self.find_variant_row(book, ws, row["name"], e)
            if vr == r:
                continue  # that row is the main release itself
            vr, vid, vnew = book.write(ws, vals, "dataID", row=vr, overwrite=self.overwrite, defaults=defaults)
            vf = gallery_file_for(gallery, e)
            if vf is None and not e.get("note") and not e.get("sub") and gfile:
                vf = gfile  # standard-color re-release (Entry Package, Hasbro single) looks like the main one
            if vf in gimgs:
                n_img += book.set_image(ws, vr, "image", gimgs[vf][0])
                book.set_image(ws, vr, "minifiedImage", gimgs[vf][1], "min")
            key_title = f"{title}#{e['manufacturer']}#{e['code']}#{e['product']}"
            if vnew or not book.log_index(target).get(key_title):
                book.add_log(target, ws.title, vid, key_title, pg.get("url"), pg.get("revid"), vf)
            self.link_part_to_product(e, ws.title, vid)
            n_new += vnew
            n_upd += not vnew
        res = f"{'new' if new else 'upd'} #{rid}" + ("" if full or self.no_images else " (no image)")
        if releases:
            res += f", {len(releases) - (1 if main else 0)} variants ({n_new} new, {n_upd} updated, {n_img} new images)"
        return res

    def find_variant_row(self, book, ws, name, e):
        """Existing row for this release of the part. Same name and the same code family (BX-17 matches a
        store row 'BX-17 01'); a recolor must also share its note words with the row's edition/label
        ('Red Ver.' -> 'Red Version'), so BX-00 recolors never collapse into one row."""
        n = norm_name(name)
        cands = []
        for r, x in book.rows(ws):
            code = str(x.get("code") or "")
            if norm_name(x.get("name")) != n or x.get("manufacturer") not in (None, "", e["manufacturer"]):
                continue
            if code == e["code"] or code.split(" ")[0] == e["base"]:
                cands.append((r, x))
        want = note_tokens(e.get("note"))
        if want:
            for r, x in cands:
                if want <= note_tokens(f"{x.get('edition') or ''} {x.get('variantLabel') or ''}"):
                    return r
            return None
        exact = [(r, x) for r, x in cands if str(x.get("code") or "") == e["code"]]
        plain = [(r, x) for r, x in exact if not re.search(r"[\"(]", str(x.get("edition") or ""))
                 or not x.get("variantLabel")]
        pick = plain or exact
        return pick[0][0] if len(pick) == 1 else None

    def link_part_to_product(self, e, sheet, did):
        """If the products workbook has this release (sku = code), record the part in its contents."""
        if not os.path.exists(self.book_path("products")) and "products" not in self._books:
            return
        book = self.book("products")
        pr, prow = book.find(book.named_sheet("Products"), lambda x: str(x.get("sku") or "") == e["code"]
                             and x.get("manufacturer") == e["manufacturer"])
        if pr:
            self.add_content(prow.get("productID"), sheet, did)

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
            vm = re.match(r"^(.*?)\s*\(([^()]+)\)\s*$", prow["productName"])  # "String Launcher (White Ver.)"
            if r is None and vm:
                pr_, base = book.find(acc, lambda x: norm_name(x.get("name")) == norm_name(vm.group(1))
                                      and x.get("manufacturer") == prow["manufacturer"] and not x.get("parentPartId"))
                if base:
                    vals.update(parentPartId=base.get("dataID"), variantLabel=vm.group(2).strip())
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
        if gen == "X":
            for text in filter(None, [prow.get("productName"), fields.get("beyblade"), fields.get("combo"), title]):
                got = self.link_combo(pid, text, prow.get("sku"))
                if got is not None:
                    n += got
                    break
        return n

    def link_combo(self, pid, text, sku=None):
        """X combo name -> ProductContents rows. BX/UX: Blade + Ratchet + Bit.
        CX ('HellsReaper T4-70K'): Lock Chip 'Hells' + Main Blade 'Reaper' + Ratchet + Bit.
        Returns number of links added, or None if the text is not a combo name."""
        c = combo_parts(text)
        if not c:
            return None
        n = 0
        did = self.find_part("X", "blades", c["blade"], sku)
        if did is not None:
            n += self.add_content(pid, S.part_sheet("X", "blades"), did)
        else:
            words = re.findall(r"[A-Z][a-z']+", c["blade"])
            if len(words) >= 2:
                for key, name in (("lockChips", words[0]), ("mainBlades", "".join(words[1:]))):
                    did = self.find_part("X", key, name, sku)
                    if did is not None:
                        n += self.add_content(pid, S.part_sheet("X", key), did)
        did = self.find_part("X", "ratchets", c["ratchet"], sku)
        if did is not None:
            n += self.add_content(pid, S.part_sheet("X", "ratchets"), did)
        did = self.find_part("X", "bits", code=sku, base_name=c["bit"])
        if did is not None:
            n += self.add_content(pid, S.part_sheet("X", "bits"), did)
        return n

    def handle_tcg(self, target, title, pg, infobox, fields, files, imgs):
        src = self.cfg["sources"][target]
        book = self.book("tcg")
        gen, key = target_gen_key(target)
        if key == "sets":
            row, sheet, idc, pre = map_tcg_set(title, fields, src, gen), "TCG_Sets", "setID", "S"
        else:
            row = map_tcg_card(title, fields, src, gen, pg.get("categories", []))
            sheet, idc, pre = "TCG_Cards", "dataID", ""
            self.ensure_tcg_set(gen, row.get("setName"), row.get("setCode"))
        ws, r = self.existing_match(target, title, row)
        r, rid, new = book.write(ws, row, idc, pre, row=r, overwrite=self.overwrite)
        full, mini = imgs.get(title, (None, None))
        book.set_image(ws, r, "image", full)
        book.set_image(ws, r, "minifiedImage", mini, "min")
        if new or not book.log_index(target).get(title):
            book.add_log(target, sheet, rid, title, pg.get("url"), pg.get("revid"), files[0] if files else None)
        return f"{'new' if new else 'upd'} {rid} {row.get('cardNumber') or row.get('setName') or row.get('setCode') or ''}"

    def ensure_tcg_set(self, gen, set_name, set_code):
        """Cards name their set ('Collision', set no. 1) -> make sure TCG_Sets has a row for it."""
        if not (set_name or set_code):
            return
        book = self.book("tcg")
        ws = book.named_sheet("TCG_Sets")
        r, _ = book.find(ws, lambda x: x.get("hobbyGeneration") == gen and (
            (set_name and norm_name(x.get("setName")) == norm_name(set_name)) or
            (not set_name and set_code and str(x.get("setCode")) == str(set_code))))
        if r is None:
            book.write(ws, {"setCode": set_code, "setName": set_name, "hobbyName": S.TCG_HOBBY_NAME,
                            "hobbyGeneration": gen, "incompleteData": 1}, "setID", "S")
            log(f"    + new TCG set: {set_name or set_code} ({gen})")

    # ---- runs -----------------------------------------------------------------------
    def run_target(self, target, limit=None):
        if target not in self.cfg["sources"]:
            raise SystemExit(f"Unknown target '{target}'. Use --list-targets.")
        if target_kind(target) == "products":
            return self.run_products(target_gen_key(target)[0], limit)
        return self._run_listed(target, limit)

    def _run_listed(self, target, limit=None):
        """Category / title-prefix listing -> one row per page."""
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
        log(f"  checking the store for {len(titles)} listed pages ...")
        for t in titles:
            ACTIVITY.set("checking store", t)
            if t in st["done"]:
                continue
            if not self.refresh_existing and kind == "tcg":
                # parts are skipped only via progress (st["done"] above): every part page is handled once
                # by this version so its variants + stats land, even when a row for it already exists
                if self.existing_match(target, t)[1]:
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
            n_batches = (len(todo) + bs - 1) // bs
            done_n = 0
            for bi, batch in enumerate(chunks(todo, bs), 1):
                log(f"\n  --- batch {bi}/{n_batches}: pages {done_n + 1}-{done_n + len(batch)} of {len(todo)} ---")
                pages = self.get_pages(batch)
                parsed = self.parse(pages, batch)
                for t in batch:
                    if t not in parsed:
                        st["failed"][t] = "page missing"
                if kind == "parts":
                    self.fill_from_rendered(target, parsed)
                imgs = self.images_for_pages(parsed)
                self._gallery_imgs = {}
                if kind == "parts" and self.cfg["politeness"].get("variant_images", True):
                    # every gallery image: recolor captions often have no code ("DranSword (Metal Coat: Bronze)")
                    gal = [f for (pg, _, _, _) in parsed.values() for f, _, _ in parse_gallery(pg.get("wikitext"))]
                    self._gallery_imgs = self.fetch_images(gal, "variant images (gallery)")
                log(f"  writing {len(parsed)} rows into the workbook ...")
                for t, (pg, infobox, fields, files) in parsed.items():
                    done_n += 1
                    ACTIVITY.set(f"writing row {done_n}/{len(todo)}", t)
                    if kind == "parts":
                        res = self.handle_part(target, t, pg, infobox, fields, files, imgs)
                    elif kind == "products":
                        gen, _ = target_gen_key(target)
                        res = self.handle_product(gen, t, pg, infobox, fields, files, imgs)
                    else:
                        res = self.handle_tcg(target, t, pg, infobox, fields, files, imgs)
                    st["done"][t] = res
                    st["failed"].pop(t, None)
                    log(f"  [{done_n}/{len(todo)}] [{res}] {t}")
                    self.checkpoint()
            st["complete"] = all(t in st["done"] for t in titles)
        finally:
            self.save_all()
            log(f"  saved: {len(st['done'])}/{len(titles)} pages handled for {target}, "
                f"{self.client.count} requests used this run")
            self.completeness_report(target)

    # ---- products from the wiki's product list pages ---------------------------------
    def list_pages_for(self, gen, refresh=False):
        src = self.cfg["sources"].get(f"products:{gen}", {})
        pages = list(src.get("list_pages", []))
        rx, cat = src.get("list_page_regex"), src.get("list_pages_category")
        if rx and cat:
            cache = self.progress.setdefault("_product_list_pages", {})
            if cat not in cache or refresh or self.relist:
                log(f"  discovering product list pages in Category:{cat} ...")
                cache[cat] = self.client.category_members(cat, depth=0)
                self.save_state()
            pages += [t for t in cache[cat] if re.search(rx, t) and t not in pages]
        return pages

    def match_entry(self, row, limited, key):
        """Is this list row already in Products? -> (row_number or None, parent productID for a limited re-release)"""
        book = self.book("products")
        ws = book.named_sheet("Products")
        hit = book.log_index("products").get(key)
        if hit:
            r, _ = book.find(ws, lambda x: str(x.get("productID")) == str(hit[1]))
            if r:
                return r, None
        n, parent = norm_name(row["productName"]), None
        for r, x in book.rows(ws):
            if x.get("manufacturer") != row["manufacturer"] or str(x.get("sku") or "") != str(row.get("sku") or ""):
                continue
            if norm_name(x.get("productName")) != n:
                continue
            if not limited or str(x.get("releaseDate") or "")[:10] == str(row.get("releaseDate") or "")[:10]:
                return r, None
            if not x.get("parentProductId"):
                parent = x.get("productID")  # same product released earlier/again as a limited -> variant
        return None, parent

    def run_products(self, gen, limit=None, update=False):
        target = f"products:{gen}"
        src = self.cfg["sources"].get(target, {})
        st = self.kstate(target)
        log(f"\n=== {target} -> {os.path.basename(self.book_path('products'))} ===")
        lists = self.list_pages_for(gen, refresh=update)
        if not lists:
            if src.get("categories") or src.get("title_prefixes") or src.get("extra_titles"):
                log("  no product list pages for this generation - using categories / title prefixes instead")
                return self._run_listed(target, limit)
            log(f"  !! no product list pages found for {gen}. Add the page titles to sources['{target}']"
                f"['list_pages'] in scraper_config.json (they are in Category:Product Lists on the wiki)")
            return
        log(f"  product list pages: {'; '.join(lists)}")
        pages = self.get_pages(lists, refresh=update)
        entries = []
        for t in lists:
            pg = pages.get(t)
            if not pg:
                log(f"  ! list page not found on the wiki: {t}")
                continue
            es = product_entries(t, pg.get("wikitext"), gen)
            secs = Counter(e["section"] or "(no heading)" for e in es)
            log(f"  {t}: {len(es)} products ({', '.join(f'{k}: {v}' for k, v in secs.items()) or 'no tables found'})")
            entries += es
        if not entries:
            log("  !! no product tables recognised (a table needs a Name column plus a Code or Release Date column)")
            return
        st["titles"] = [entry_key(e) for e in entries]
        book = self.book("products")
        prods = book.named_sheet("Products")
        log(f"  checking {len(entries)} products against the store ...")
        todo = []
        for e in entries:
            k = entry_key(e)
            row, limited, note = entry_to_row(gen, e)
            r, parent = self.match_entry(row, limited, k)
            if r is not None and not self.refresh_existing:
                st["done"][k] = "in store"
                continue
            todo.append((e, k, row, note, r, parent))
        log(f"  {len(entries) - len(todo)} already in the store, {len(todo)} to add" +
            (" / refresh" if self.refresh_existing else ""))
        if limit:
            todo = todo[:limit]
        enrich = []
        try:
            for i, (e, k, row, note, r, parent) in enumerate(todo, 1):
                ACTIVITY.set(f"writing product {i}/{len(todo)}", e["name"])
                if parent and r is None:
                    row["parentProductId"], row["variantLabel"] = parent, note or "Limited"
                r, pid, new = book.write(prods, row, "productID", "P", row=r, overwrite=self.overwrite)
                if new:
                    book.add_log("products", "Products", pid, k, url=e["list"])
                st["done"][k] = pid
                links = self.link_contents(gen, pid, row, {}, e["name"], None, None)
                log(f"  [{i}/{len(todo)}] [{'new' if new else 'upd'} {pid}] {row.get('sku') or '-'} {e['name']} "
                    f"[{row['productType']}]{' variant of ' + str(parent) if parent and new else ''}"
                    f"{f' +{links} contents' if links else ''}")
                if e["link"] and src.get("fetch_product_pages", True):
                    enrich.append((pid, row, e["link"]))
                self.checkpoint()
            if enrich:
                self.enrich_products(gen, enrich)
            st["complete"] = all(entry_key(e) in st["done"] for e in entries)
        finally:
            self.save_all()
            log(f"  saved: {len(st['done'])}/{len(entries)} products handled, {self.client.count} requests used")

    def enrich_products(self, gen, items):
        """Open each new product's own page: box image, random-booster items (variants), contents."""
        book = self.book("products")
        prods = book.named_sheet("Products")
        src = self.cfg["sources"].get(f"products:{gen}", {})
        links = list(OrderedDict.fromkeys(link for _, _, link in items))
        log(f"\n  opening {len(links)} product pages (box image, random-booster items, contents) ...")
        bs = max(1, min(50, int(self.cfg["politeness"]["batch_size"])))
        for bi, batch in enumerate(chunks(links, bs), 1):
            log(f"\n  --- product pages batch {bi}/{(len(links) + bs - 1) // bs} ---")
            parsed = self.parse(self.get_pages(batch), batch)
            imgs = self.images_for_pages(parsed)
            for pid, prow, link in [it for it in items if it[2] in batch]:
                if link not in parsed:
                    continue
                pg, infobox, fields, files = parsed[link]
                r, _ = book.find(prods, lambda x: str(x.get("productID")) == str(pid))
                if r is None:
                    continue
                info, _ = map_product(gen, link, fields, src, prow["manufacturer"])
                book.write(prods, {k: info.get(k) for k in ("releaseDate", "itemCost", "currency")}, row=r)
                full, mini = imgs.get(link, (None, None))
                book.set_image(prods, r, "boxImageUrl", full)
                book.set_image(prods, r, "minifiedBoxImage", mini, "min")
                n = self.link_contents(gen, pid, prow, fields, link, full, mini)
                v = self.add_variants(gen, pid, prow, pg.get("wikitext"))
                log(f"  {pid} {prow.get('sku') or ''} {prow['productName']}: {'box image' if full else 'no image'}"
                    f"{f', +{n} contents' if n else ''}{f', {v} random-booster items' if v else ''}")
                self.checkpoint()

    def add_variants(self, gen, pid, prow, wikitext):
        """Random booster items 'CX-05 01: HellsReaper T4-70K (Prize)' -> variant products of the booster."""
        base = S.parse_code(prow.get("sku") or "")
        items = [a for a in parse_assortment(wikitext) if base and a["base"] == base["base"]]
        book = self.book("products")
        prods = book.named_sheet("Products")
        for a in items:
            vrow = {k: prow.get(k) for k in ("manufacturer", "hobbyName", "hobbyGeneration", "productType",
                                              "releaseDate", "itemCost", "currency", "region")}
            vrow.update({"productName": a["name"], "sku": a["code"], "parentProductId": pid,
                         "variantLabel": a["sub"], "description": a["note"], "incompleteData": 1})
            key = f"variant::{a['code']}::{a['name']}"
            _, r = self.existing_match("products", key, vrow)
            r, vid, new = book.write(prods, vrow, "productID", "P", row=r, overwrite=self.overwrite)
            if new:
                book.add_log("products", "Products", vid, key)
            links = self.link_combo(vid, a["name"], a["code"]) if gen == "X" else None
            log(f"      {'new' if new else 'upd'} {vid} {a['code']} {a['name']}{' (' + a['note'] + ')' if a['note'] else ''}"
                f"{f' +{links} contents' if links else ''}")
        return len(items)

    # ---- update by release code -----------------------------------------------------
    def code_series(self):
        book = self.book("products")
        cs = book.named_sheet("CodeSeries")
        have = {(x.get("seriesPrefix"), x.get("manufacturer")) for _, x in book.rows(cs)}
        for s in S.CODE_SERIES:  # add series that are new in the schema (e.g. RX) to an existing sheet
            if (s[0], s[1]) not in have:
                book.write(cs, dict(zip(S.CODE_SERIES_COLUMNS, s)))
        return book, cs

    def run_update(self, prefixes=None, generation=None, manufacturer=None, from_code=None, probe=True):
        """1) re-read the product list pages (cheap: skipped rows are never downloaded) and add new releases,
        2) search for codes after the store's last one per series (the lists lag behind / have gaps)."""
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
        if generation:
            gens = [generation]
        elif prefixes:
            gens = sorted({x["hobbyGeneration"] for _, x in series if x.get("hobbyGeneration")})
        else:
            gens = [g for g in S.GENERATIONS if f"products:{g}" in self.cfg["sources"]]
        log(f"\n##### update step 1: product list pages for {', '.join(gens) or '-'} #####")
        for gen in gens:
            self.run_products(gen, update=True)
        if not probe:
            return
        log("\n##### update step 2: searching for codes newer than the store's last one #####")
        if not series:
            log("No matching sequential series in the CodeSeries sheet.")
            return
        book, cs = self.code_series()
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
            val = S.format_code(prefix, found_max, max(digits, len(str(found_max))))
            if cs.cell(cs_row, hdr["lastKnownCode"]).value != val:
                cs.cell(cs_row, hdr["lastKnownCode"], val)
                book.dirty = True
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
        kind = target_kind(target)
        if kind == "products":
            return self.inspect_products(target_gen_key(target)[0], n)
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
                gen, key = target_gen_key(target)
                log(f"    => {map_tcg_set(t, fields, src, gen) if key == 'sets' else map_tcg_card(t, fields, src, gen, pg['categories'])}")
        log("\nField names seen (add useful ones to this target's 'aliases' in scraper_config.json):")
        for k, c in seen.most_common():
            log(f"  {c:3d}x  {k}")
        self.save_state()

    def inspect_products(self, gen, n):
        lists = self.list_pages_for(gen)
        log(f"product list pages for {gen}: {lists or 'NONE - set list_pages in scraper_config.json'}")
        pages = self.get_pages(lists)
        links = []
        for t in lists:
            pg = pages.get(t)
            if not pg:
                log(f"  ! not found: {t}")
                continue
            tables = parse_wikitables(pg.get("wikitext"))
            log(f"\n--- {t}: {len(tables)} tables")
            for tb in tables:
                log(f"    [{tb['section']}] headers={[cell_text_link(h)[0] for h in tb['headers']]} rows={len(tb['rows'])}")
            es = product_entries(t, pg.get("wikitext"), gen)
            for e in es[:n]:
                log(f"    {e}")
                log(f"      => {entry_to_row(gen, e)[0]}")
            links += [e["link"] for e in es[:n] if e["link"]]
        links = list(OrderedDict.fromkeys(links))[:n]
        if links:
            parsed = self.parse(self.get_pages(links), links)
            for t, (pg, infobox, fields, files) in parsed.items():
                log(f"\n--- product page {t} [infobox: {infobox or 'NONE'}] categories: {', '.join(pg['categories'][:6])}")
                for k, v in fields.items():
                    log(f"    {k!r}: {v[:90]}")
                log(f"    image: {files or pg.get('page_image')}")
                for a in parse_assortment(pg.get("wikitext")):
                    log(f"    random-booster item: {a}")
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
            if a.generation and gen != a.generation:
                continue
            if a.part and key not in a.part:
                continue
            ts.append(t)
    return list(OrderedDict.fromkeys(ts))


def run_cli(argv):
    ap = argparse.ArgumentParser(description="Polite, resumable Beyblade wiki scraper -> parts/products/tcg workbooks")
    ap.add_argument("--target", action="append", help="e.g. parts:X:blades, products:X, tcg:Plastic:cards (repeatable)")
    ap.add_argument("--scope", choices=["parts", "products", "tcg"], help="all targets of one workbook")
    ap.add_argument("--generation", choices=S.GENERATION_NAMES, help="limit --scope / --update to a generation")
    ap.add_argument("--part", nargs="+", help="with --scope parts: only these part keys")
    ap.add_argument("--key", action="append", help=argparse.SUPPRESS)
    ap.add_argument("--update", action="store_true", help="look for releases after the last code in the store")
    ap.add_argument("--series", nargs="+", help="with --update: series prefixes, e.g. BX UX CX B")
    ap.add_argument("--manufacturer", choices=S.MANUFACTURERS, help="with --update")
    ap.add_argument("--from-code", help="with --update: start here instead of after the store's last code")
    ap.add_argument("--no-probe", action="store_true",
                    help="with --update: only read the product list pages, don't search for newer codes")
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
    ap.add_argument("--quiet", action="store_true", help="hide the per-request lines on screen (still in the log file)")
    ap.add_argument("--log-file", help="default: <state_dir>/scrape.log")
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
    LOG_OPTS["quiet"] = a.quiet
    set_log_file(a.log_file or os.path.join(sc.state_dir, "scrape.log"))
    log(f"Log file: {_LOG_FILE['path']}  (every request and step is recorded there)")
    start_heartbeat(int(cfg["politeness"].get("heartbeat_seconds", 15)))
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
            sc.run_update(a.series, a.generation, a.manufacturer, a.from_code, probe=not a.no_probe)
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
                              and target_gen_key(x)[0] == gen.get()):
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
    status_var = tk.StringVar(value="idle")
    ttk.Label(frm, textvariable=status_var, foreground="#0066cc").grid(row=6, column=0, sticky="w", pady=(4, 0))
    frm.rowconfigure(5, weight=1)
    frm.columnconfigure(0, weight=1)
    stop_event = threading.Event()
    worker = {"t": None}
    action_btns = []
    sd = cfg["state_dir"] if os.path.isabs(cfg["state_dir"]) else os.path.join(HERE, cfg["state_dir"])
    set_log_file(os.path.join(sd, "scrape.log"))
    start_heartbeat(int(cfg["politeness"].get("heartbeat_seconds", 15)))

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
        status_var.set(("Now: " + ACTIVITY.describe()) if worker["t"] else
                       f"idle - full log: {_LOG_FILE['path']}")
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
                ACTIVITY.set("idle")
                log("\nDone.")
            except StopScrape as e:
                log(f"\nSTOPPED SAFELY: {e}\nProgress saved - start again to continue.")
                sc.save_all()
            except Exception:
                import traceback
                log(traceback.format_exc())
            finally:
                ACTIVITY.set("idle")
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
