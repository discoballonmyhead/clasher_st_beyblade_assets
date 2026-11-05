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
  * New rows: an empty row with the next id, a "variant" of a row (copies the shared fields, parent id set)
    or a full copy.
  * New columns: added after the last column of one or more tabs (purple header), listed in the _columns tab.
    Mark a column optional (not reported as missing) or inherited (variants copy it from their parent).
  * Change log: every change made with this tool goes into the _edit_log tab of the workbook (when, which
    tool, action, tab, row, field, old -> new). Undo removes the entry too. The packager exports it.
  Every save keeps a .bak of the workbook first.

GUI:  python missing_data_tool.py
CLI:  python missing_data_tool.py report --workbook beyblade_parts.xlsx [--sheet Parts_X_Blades] [--csv out.csv]
      python missing_data_tool.py fill   --workbook beyblade_parts.xlsx [--sheet ...] [--parent] [--siblings] [--derive] [--dry-run]
      python missing_data_tool.py set    --workbook beyblade_parts.xlsx --sheet Parts_X_Blades --id 65 --field mass --value 34.6
      python missing_data_tool.py image  --workbook beyblade_parts.xlsx --sheet Parts_X_Blades --id 65 --file found.png   (or --url)
      python missing_data_tool.py wiki   --workbook beyblade_parts.xlsx --sheet Parts_X_Blades [--ids 65 72] [--limit 20]
      python missing_data_tool.py add-column --workbook beyblade_parts.xlsx --sheet Parts_X_Bits --name tipShape [--optional] [--inherit] [--default x]
      python missing_data_tool.py add-row    --workbook beyblade_parts.xlsx --sheet Parts_X_Blades [--variant-of 65 | --copy-of 65] [--set name=Foo]
      python missing_data_tool.py log        --workbook beyblade_parts.xlsx [--sheet ...] [--limit 50]
"""
import argparse
import base64
import csv
import io
import os
import re
import sys
from collections import OrderedDict
from datetime import datetime, timezone

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
           S.SIMPLE_RATCHET, S.REQUIRES_SIMPLE_RATCHET,
           "layerComponent", "discType", "movementStyle", "baseName", "protrusions", "heightMm", "dash",
           "burstRes", "hobbyName", "hobbyGeneration",
           # products: random-booster items / re-releases share these with the box
           "productType", "currency", "region", "releaseDate", "itemCost",
           # cards: parallels share these with the base card
           "setCode", "setName", "cardNumber", "subtitle", "cardType", "attribute", "cost", "power",
           "battleEdge", "spinStrength", "effectText", "loreText"}
# Fields that don't change between releases of the same part
STABLE = {"type", "spinDir", "attack", "defense", "stamina", "wbolegality", "system", "layerComponent",
          S.SIMPLE_RATCHET, S.REQUIRES_SIMPLE_RATCHET,
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


def custom_columns(book, sheet):
    """Columns added to this tab with the tool -> {name: {"optional", "inherit", ...}}"""
    return book.custom_columns().get(sheet, {}) if hasattr(book, "custom_columns") else {}


def expected_fields(book, sheet, include_optional=False):
    idc, img, mini = sheet_info(sheet)
    cols = [c for c in book.headers(book.wb[sheet]) if c not in (idc, img, mini)]
    optional = OPTIONAL | {c for c, m in custom_columns(book, sheet).items() if m["optional"]}
    return cols if include_optional else [c for c in cols if c not in optional]


COLUMN_NAME = re.compile(r"^[A-Za-z][A-Za-z0-9_]{0,40}$")


def now_iso():
    """UTC, to the millisecond (the packager compares log entries with its own timestamp)."""
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds")


def _short(v, n=200):
    if v is None:
        return None
    t = v if isinstance(v, (int, float)) else str(v)
    return t[:n] if isinstance(t, str) else t


FLAG_TRUE = {"1", "true", "yes", "y", "x"}
FLAG_FALSE = {"0", "false", "no", "n"}


def cell_value(field, v):
    """What a typed value is stored as: 0/1 for flag columns (simpleRatchet, requiresSimpleRatchet ...),
    numbers as numbers, blanks as None."""
    if isinstance(v, str):
        v = parse_value(v)
    if field in S.FLAG_COLUMNS and v is not None:
        t = str(v).strip().lower()
        if t in FLAG_TRUE:
            return 1
        if t in FLAG_FALSE:
            return 0
        raise ValueError(f"{field} takes 1 or 0 (yes/no, true/false), not {v!r}")
    return v


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
    idx = book.image_index(ws)
    full = {r for (r, c) in idx if img and c == hdr.get(img)}
    small = {r for (r, c) in idx if mini and c == hdr.get(mini)}
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
            inherit = INHERIT | {c for c, m in custom_columns(book, sheet).items() if m["inherit"]}
            for f in sorted(inherit):
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
    touched = set()
    for r, _, f, v, _ in fills:
        if f in hdr and blank(ws.cell(r, hdr[f]).value):
            ws.cell(r, hdr[f]).value = v
            touched.add(r)
            n += 1
    for r in touched:
        book.touch(ws, r)  # last edited
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
    ws.cell(r, hdr[field]).value = cell_value(field, value)
    book.touch(ws, r)
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
    im = book.image_index(ws).get((r, book.headers(ws).get(img)))
    return im._data() if im is not None else None


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


# ── engine (shared by the Tk GUI, the CLI "serve" mode and the Flutter app) ────

class Engine:
    """Keeps one workbook open and answers questions about it. Edits stay in memory until save()
    (saving a big workbook with hundreds of images takes seconds, so it's never done per edit).
    Every edit stamps the row's updated_at and can be undone."""

    def __init__(self, log=print, source="missing_data_tool"):
        self.log = log
        self.source = source       # written into _edit_log ("missing_data_tool" / "missing_data_app" / "cli")
        self.book = None
        self.path = None
        self.cfg = None            # scraper config override (tests)
        self._cache = {}           # sheet -> {"rows": {r: row}, "missing": {r: [..]}, "opt": bool}
        self._undo = []            # [(label, [(kind, sheet, r, col, old)])]
        self.last_saved = None

    # ---- workbook ---------------------------------------------------------------
    def open(self, path):
        self.book = Book(path, kind_of_workbook(path))
        self.path = path
        self._cache.clear()
        self._undo.clear()
        self.last_saved = os.path.getmtime(path) if os.path.exists(path) else None
        # Columns a newer schema added (e.g. simpleRatchet) appear on existing tabs right away, empty,
        # instead of only after the next scrape. Logged; saved with the next save.
        self.added_on_open = self.book.ensure_schema_columns()
        if self.added_on_open:
            self.book.append_rows(S.EDIT_LOG_SHEET, S.EDIT_LOG_COLUMNS, [
                {"at": now_iso(), "source": self.source, "action": "add_column", "sheet": tab, "field": col,
                 "note": "new schema column, added when the workbook was opened"} for tab, col in self.added_on_open])
            self.log("Added new columns from the schema (save to keep): "
                     + ", ".join(f"{t}.{c}" for t, c in self.added_on_open))
        return self.summary()

    # ---- change log -------------------------------------------------------------
    def _logged(self, label, changes, entries):
        """Write entries to _edit_log and push one undo step that also removes them."""
        if not changes and not entries:
            return
        if entries:
            stamp = now_iso()
            rows = self.book.append_rows(S.EDIT_LOG_SHEET, S.EDIT_LOG_COLUMNS, [
                {"at": stamp, "source": self.source, **{k: _short(v) for k, v in e.items()}} for e in entries])
            changes = list(changes) + [("logrows", S.EDIT_LOG_SHEET, rows, None, None)]
        self._push(label, changes)

    def edit_log(self, limit=200, sheet=None, action=None, query=""):
        """Changes made with the tool, newest first."""
        if S.EDIT_LOG_SHEET not in self.book.wb.sheetnames:
            return {"total": 0, "entries": []}
        q = (query or "").strip().lower()
        out = []
        for _, x in self.book.rows(self.book.wb[S.EDIT_LOG_SHEET]):
            if sheet and x.get("sheet") != sheet or action and x.get("action") != action:
                continue
            e = {k: (v if isinstance(v, (int, float, str)) or v is None else str(v)) for k, v in x.items()}
            if q and q not in " ".join(str(v) for v in e.values() if v is not None).lower():
                continue
            out.append(e)
        out.reverse()
        return {"total": len(out), "entries": out[:limit] if limit else out}

    def columns(self, sheet):
        """Every column of a tab and whether it was added with the tool."""
        idc, img, mini = sheet_info(sheet)
        custom = custom_columns(self.book, sheet)
        return {"sheet": sheet, "idColumn": idc, "columns": [
            {"name": c, "custom": c in custom, "optional": c in OPTIONAL or custom.get(c, {}).get("optional", False),
             "inherit": c in INHERIT or custom.get(c, {}).get("inherit", False),
             "note": custom.get(c, {}).get("note", ""), "image": c in (img, mini), "id": c == idc}
            for c in self.book.headers(self.book.wb[sheet])]}

    # ---- structure: new columns / rows -----------------------------------------
    def add_column(self, sheets, name, optional=False, inherit=False, default=None, note=""):
        name = (name or "").strip()
        if not COLUMN_NAME.match(name):
            raise ValueError("Column names start with a letter and use letters, digits or _ (e.g. tipShape).")
        sheets = [sheets] if isinstance(sheets, str) else list(sheets)
        for sh in sheets:
            if not sheet_info(sh):
                raise ValueError(f"{sh} is not a data tab")
            if name in self.book.headers(self.book.wb[sh]):
                raise ValueError(f"{sh} already has a column '{name}'")
        default = parse_value(default) if isinstance(default, str) else default
        changes, entries, registry = [], [], []
        for sh in sheets:
            ws = self.book.wb[sh]
            col = self.book.add_column(ws, name)
            changes.append(("column", sh, None, col, None))
            filled = 0
            if not blank(default):
                for r, x in self.book.rows(ws):
                    if not is_deleted(x):
                        ws.cell(r, col).value = default
                        filled += 1
                self.book._rows_cache.pop(sh, None)
            registry.append({"sheet": sh, "column": name, "optional": 1 if optional else 0,
                             "inherit": 1 if inherit else 0, "note": note or None, "addedAt": now_iso(),
                             "source": self.source})
            entries.append({"action": "add_column", "sheet": sh, "field": name, "newValue": default,
                            "note": "; ".join(x for x in (
                                "optional" if optional else "", "variants inherit it" if inherit else "",
                                f"default set on {filled} rows" if filled else "", note or "") if x) or None})
            self._cache.pop(sh, None)
        reg_rows = self.book.append_rows(S.CUSTOM_COLUMNS_SHEET, S.CUSTOM_COLUMNS_COLUMNS, registry)
        changes.append(("registry", S.CUSTOM_COLUMNS_SHEET, reg_rows, None, None))
        self._logged(f"add column {name} ({len(sheets)} tab{'s' if len(sheets) != 1 else ''})", changes, entries)
        return {"added": sheets, "column": name}

    def add_row(self, sheet, values=None, copy_from=None, mode="variant"):
        """New row with the next id. mode: "empty" (only values + what follows from the tab), "variant" (copies
        the fields a variant shares, parent id = copy_from's root) or "copy" (every field of copy_from)."""
        info = sheet_info(sheet)
        if not info:
            raise ValueError(f"{sheet} is not a data tab")
        idc, _, _ = info
        ws = self.book.wb[sheet]
        hdr = self.book.headers(ws)
        prefix = "" if S.parse_part_sheet(sheet) else (S.SHEETS.get(sheet, {}).get("id_prefix") or "")
        vals, note = {}, "new"
        part = S.parse_part_sheet(sheet)
        if part:
            vals.update({"hobbyGeneration": part[0], "hobbyName": S.HOBBY_NAME})
        elif sheet.startswith("TCG_"):
            vals["hobbyName"] = S.TCG_HOBBY_NAME
        if copy_from not in (None, "") and mode != "empty":
            sr = find_row(self.book, sheet, copy_from)
            if sr is None:
                raise ValueError(f"No row {copy_from} in {sheet}")
            src = dict(self.book.rows(ws))[sr]
            skip = {idc, "updated_at", "deleted"}
            if mode == "copy":
                vals.update({k: v for k, v in src.items() if k not in skip and not blank(v)})
                note = f"copy of #{copy_from}"
            else:
                share = INHERIT | {"manufacturer"} | {c for c, m in custom_columns(self.book, sheet).items()
                                                     if m["inherit"]}
                vals.update({k: v for k, v in src.items() if k in share and not blank(v)})
                pcol = next((c for c in PARENT_COL.get(idc, ()) if c in hdr), None)
                if pcol:  # always point at the base part, never at another variant
                    vals[pcol] = src.get(pcol) if not blank(src.get(pcol)) else src.get(idc)
                note = f"variant of #{vals.get(pcol, copy_from)}"
        for k, v in (values or {}).items():
            vals[k] = cell_value(k, v)
        if blank(vals.get(idc)):
            vals.pop(idc, None)  # next free id
        r, rid, _ = self.book.write(ws, vals, id_col=idc, id_prefix=prefix)
        self.book.touch(ws, r)
        self._refresh_row(sheet, r)
        self._logged(f"new row {sheet} #{rid}", [("row", sheet, r, None, None)],
                     [{"action": "add_row", "sheet": sheet, "rowId": rid, "note": note}])
        return {"row": r, "id": rid}

    def summary(self):
        sheets = []
        for name in data_sheets(self.book):
            rows = [x for _, x in self.book.rows(self.book.wb[name]) if not is_deleted(x)]
            if not rows:
                continue
            idx = self._index(name)
            sheets.append({"name": name, "rows": len(rows),
                           "rowsWithMissing": sum(1 for m in idx["missing"].values() if m),
                           "hasImages": bool(sheet_info(name)[1])})
        log_rows = (len(self.book.rows(self.book.wb[S.EDIT_LOG_SHEET]))
                    if S.EDIT_LOG_SHEET in self.book.wb.sheetnames else 0)
        return {"path": self.path, "kind": kind_of_workbook(self.path), "sheets": sheets,
                "dirty": bool(self.book.dirty), "undo": len(self._undo), "lastSaved": self.last_saved,
                "logEntries": log_rows,
                "addedColumns": [f"{t}.{c}" for t, c in getattr(self, "added_on_open", [])],
                "customColumns": sum(len(v) for v in self.book.custom_columns().values())}

    def save(self):
        if self.book.dirty:
            self.book.save()
            self.last_saved = os.path.getmtime(self.path)
        return {"saved": True, "lastSaved": self.last_saved}

    # ---- analysis (cached per sheet, rows refreshed one by one after edits) -----
    def _index(self, sheet, include_optional=False):
        c = self._cache.get(sheet)
        if c is None or c["opt"] != include_optional:
            ws = self.book.wb[sheet]
            exp = expected_fields(self.book, sheet, include_optional)
            img = sheet_info(sheet)[1]
            full, _ = image_rows(self.book, sheet)
            rows, missing = {}, {}
            for r, x in self.book.rows(ws):
                if is_deleted(x):
                    continue
                rows[r] = x
                missing[r] = [f for f in exp if blank(x.get(f))] + ([img] if img and r not in full else [])
            c = self._cache[sheet] = {"rows": rows, "missing": missing, "opt": include_optional, "exp": exp}
        return c

    def _refresh_row(self, sheet, r):
        c = self._cache.get(sheet)
        if not c:
            return
        x = dict(self.book.rows(self.book.wb[sheet])).get(r)
        if x is None or is_deleted(x):
            c["rows"].pop(r, None)
            c["missing"].pop(r, None)
            return
        img = sheet_info(sheet)[1]
        has = img and self.book.has_image(self.book.wb[sheet], r, img)
        c["rows"][r] = x
        c["missing"][r] = [f for f in c["exp"] if blank(x.get(f))] + ([img] if img and not has else [])

    def analyze(self, sheet, include_optional=False):
        c = self._index(sheet, include_optional)
        idc = sheet_info(sheet)[0]
        counts = OrderedDict()
        for f in c["exp"] + [x for x in sheet_info(sheet)[1:] if x]:
            counts[f] = [c["rows"][r].get(idc) for r, m in c["missing"].items() if f in m]
        if sheet_info(sheet)[2]:  # minified image
            _, small = image_rows(self.book, sheet)
            counts[sheet_info(sheet)[2]] = [x.get(idc) for r, x in c["rows"].items() if r not in small]
        total = len(c["rows"])
        custom = custom_columns(self.book, sheet)
        return {"sheet": sheet, "total": total,
                "fields": [{"field": f, "missing": len(ids), "ids": ids[:500],
                            "never": total > 0 and len(ids) == total, "custom": f in custom}
                           for f, ids in counts.items()]}

    def _row_summary(self, sheet, r):
        c = self._cache[sheet]
        x = c["rows"][r]
        idc, img, _ = sheet_info(sheet)
        return {"row": r, "id": x.get(idc), "name": x.get("name") or x.get("productName") or x.get("setName") or "",
                "code": x.get("code") or x.get("sku") or x.get("cardNumber") or x.get("setCode") or "",
                "edition": x.get("variantLabel") or x.get("edition") or "",
                "updatedAt": str(x.get("updated_at") or ""), "missing": c["missing"][r],
                "hasImage": bool(img) and img not in c["missing"][r]}

    def rows(self, sheet, field=None, query="", sort="sheet", include_optional=False, offset=0, limit=None):
        c = self._index(sheet, include_optional)
        q = (query or "").strip().lower()
        out = []
        for r in c["rows"]:
            if field and field not in c["missing"][r]:
                continue
            s = self._row_summary(sheet, r)
            if q and q not in f"{s['id']} {s['name']} {s['code']} {s['edition']}".lower():
                continue
            out.append(s)
        if sort == "updated":
            out.sort(key=lambda s: s["updatedAt"], reverse=True)
        elif sort == "missing":
            out.sort(key=lambda s: -len(s["missing"]))
        total = len(out)
        return {"total": total, "rows": out[offset:offset + limit] if limit else out[offset:]}

    def row(self, sheet, row_id, with_image=True):
        r = find_row(self.book, sheet, row_id)
        if r is None:
            raise ValueError(f"No row {row_id} in {sheet}")
        self._index(sheet)
        x = dict(self.book.rows(self.book.wb[sheet])).get(r, {})
        idc = sheet_info(sheet)[0]
        pid = next((x.get(cn) for cn in PARENT_COL.get(idc, ()) if not blank(x.get(cn))), None)
        data = current_image(self.book, sheet, r) if with_image else None
        return {"row": r, "id": x.get(idc), "parentId": pid, "updatedAt": str(x.get("updated_at") or ""),
                "fields": expected_fields(self.book, sheet, True),
                "customFields": sorted(custom_columns(self.book, sheet)),
                "values": {k: (v if isinstance(v, (int, float, str, bool)) or v is None else str(v)) for k, v in x.items()},
                "missing": self._cache[sheet]["missing"].get(r, []),
                "image": base64.b64encode(data).decode() if data else None}

    # ---- edits (in memory, undoable) ------------------------------------------
    def _push(self, label, changes):
        if changes:
            self._undo.append((label, changes))
            del self._undo[:-50]

    def set_values(self, sheet, row_id, values):
        r = find_row(self.book, sheet, row_id)
        if r is None:
            raise ValueError(f"No row {row_id} in {sheet}")
        ws = self.book.wb[sheet]
        hdr = self.book.headers(ws)
        changes, entries = [], []
        for f, v in values.items():
            if f not in hdr:
                continue
            new = cell_value(f, v)
            cell = ws.cell(r, hdr[f])
            if str(cell.value if cell.value is not None else "") != str(new if new is not None else ""):
                changes.append(("cell", sheet, r, hdr[f], cell.value))
                entries.append({"action": "set", "sheet": sheet, "rowId": row_id, "field": f,
                                "oldValue": cell.value, "newValue": new})
                cell.value = new
        if changes:
            changes.append(("cell", sheet, r, hdr.get("updated_at"), ws.cell(r, hdr["updated_at"]).value)
                           if hdr.get("updated_at") else ("noop", sheet, r, None, None))
            self.book.touch(ws, r)
            self._logged(f"edit {sheet} #{row_id}", changes, entries)
            self._refresh_row(sheet, r)
        return {"changed": len([c for c in changes if c[0] == "cell" and c[3] != hdr.get("updated_at")])}

    def proposals(self, sheet, parent=True, siblings=True, derive=True):
        return [{"row": r, "id": rid, "field": f, "value": v, "source": src}
                for r, rid, f, v, src in propose_fills(self.book, sheet, parent, siblings, derive)]

    def apply(self, sheet, items):
        ws = self.book.wb[sheet]
        hdr = self.book.headers(ws)
        changes, rows, entries = [], set(), []
        idc = sheet_info(sheet)[0]
        for it in items:
            r, f = int(it["row"]), it["field"]
            if f in hdr and blank(ws.cell(r, hdr[f]).value):
                changes.append(("cell", sheet, r, hdr[f], None))
                ws.cell(r, hdr[f]).value = it["value"]
                rows.add(r)
                entries.append({"action": "auto-fill", "sheet": sheet,
                                "rowId": it.get("id", ws.cell(r, hdr[idc]).value), "field": f,
                                "newValue": it["value"], "note": it.get("source")})
        for r in rows:
            if hdr.get("updated_at"):
                changes.append(("cell", sheet, r, hdr["updated_at"], ws.cell(r, hdr["updated_at"]).value))
            self.book.touch(ws, r)
            self._refresh_row(sheet, r)
        self._logged(f"auto-fill {sheet} ({len(rows)} rows)", changes, entries)
        return {"filled": len([c for c in changes if c[3] != hdr.get("updated_at")]), "rows": len(rows)}

    def set_image(self, sheet, row_id, data):
        idc, img, mini = sheet_info(sheet)
        r = find_row(self.book, sheet, row_id)
        ws = self.book.wb[sheet]
        hdr = self.book.headers(ws)
        idx = self.book.image_index(ws)
        old = [("image", sheet, r, hdr[c], idx[(r, hdr[c])]._data() if (r, hdr[c]) in idx else None) for c in (img, mini)]
        if hdr.get("updated_at"):
            old.append(("cell", sheet, r, hdr["updated_at"], ws.cell(r, hdr["updated_at"]).value))
        had = any(o[4] for o in old if o[0] == "image")
        set_row_image(self.book, sheet, row_id, data)
        self._logged(f"image {sheet} #{row_id}", old, [{"action": "image", "sheet": sheet, "rowId": row_id,
                                                         "field": img, "oldValue": "image" if had else None,
                                                         "newValue": f"image ({len(data) // 1024} KB source)"}])
        self._refresh_row(sheet, r)
        return {"row": r}

    def parent_image(self, sheet, row_id):
        info = self.row(sheet, row_id, with_image=False)
        if info["parentId"] is None:
            return None
        pr = find_row(self.book, sheet, info["parentId"])
        data = current_image(self.book, sheet, pr) if pr else None
        return base64.b64encode(data).decode() if data else None

    def undo(self):
        if not self._undo:
            return {"undone": None, "undo": 0}
        label, changes = self._undo.pop()
        for kind, sheet, r, col, old in reversed(changes):
            if kind in ("logrows", "registry"):
                self.book.remove_appended(sheet, r)
                continue
            ws = self.book.wb[sheet]
            if kind == "column":
                self.book.remove_column(ws, col)
                self._cache.pop(sheet, None)
                continue
            if kind == "row":
                self.book.clear_row(ws, r)
                self._cache.pop(sheet, None)
                continue
            if kind == "cell" and col:
                ws.cell(r, col).value = old
            elif kind == "image":
                idx = self.book.image_index(ws)
                cur = idx.pop((r, col), None)
                if cur is not None:
                    ws._images = [i for i in ws._images if i is not cur]
                if old:
                    name = [k for k, v in self.book.headers(ws).items() if v == col][0]
                    self.book.set_image(ws, r, name, old, "min" if "min" in name.lower() else "full")
            self.book.dirty = True
            self.book._refresh_cached_row(ws, r, False)
            self._refresh_row(sheet, r)
        return {"undone": label, "undo": len(self._undo)}

    def recent_edits(self, limit=30):
        out = []
        for name in data_sheets(self.book):
            idc = sheet_info(name)[0]
            for r, x in self.book.rows(self.book.wb[name]):
                if x.get("updated_at"):
                    out.append({"sheet": name, "id": x.get(idc), "updatedAt": str(x["updated_at"]),
                                "name": x.get("name") or x.get("productName") or x.get("setName") or ""})
        return sorted(out, key=lambda e: e["updatedAt"], reverse=True)[:limit]

    def wiki(self, sheet, ids, limit=None, stop_event=None):
        """Re-scrape rows' pages (saves first, reloads after - the scraper writes the file)."""
        self.save()
        n = wiki_fill(self.path, sheet, ids, limit, log=self.log, stop_event=stop_event, cfg=self.cfg)
        self.open(self.path)
        if n:  # the scraper wrote the cells; record that it ran, and keep the record
            self.book.append_rows(S.EDIT_LOG_SHEET, S.EDIT_LOG_COLUMNS, [{
                "at": now_iso(), "source": self.source, "action": "wiki", "sheet": sheet,
                "rowId": ", ".join(str(i) for i in ids[:20]) + (" ..." if len(ids) > 20 else ""),
                "note": f"re-read {n} wiki page(s); only blank cells were filled"}])
            self.save()
        return {"pages": n}


def serve(stdin=None, stdout=None):
    """JSON lines over stdin/stdout - the bridge the Flutter app uses.
    Request: {"id": 1, "cmd": "rows", "args": {...}}   Response: {"id": 1, "ok": true, "result": ...}
    Events (no id): {"event": "log", "message": "..."}"""
    import json
    import threading
    stdin = stdin or sys.stdin
    stdout = stdout or sys.stdout
    lock = threading.Lock()

    def send(obj):
        with lock:
            stdout.write(json.dumps(obj, default=str) + "\n")
            stdout.flush()

    eng = Engine(log=lambda m: send({"event": "log", "message": str(m)}), source="missing_data_app")
    try:
        import fandom_scraper as fs
        fs._LOG_SINK = lambda m: send({"event": "log", "message": str(m)})
    except Exception:
        pass
    stop = threading.Event()
    commands = {
        "ping": lambda a: {"pong": True, "version": 2},
        "open": lambda a: eng.open(a["path"]),
        "summary": lambda a: eng.summary(),
        "analyze": lambda a: eng.analyze(a["sheet"], a.get("includeOptional", False)),
        "rows": lambda a: eng.rows(a["sheet"], a.get("field"), a.get("query", ""), a.get("sort", "sheet"),
                                   a.get("includeOptional", False), a.get("offset", 0), a.get("limit")),
        "row": lambda a: eng.row(a["sheet"], a["id"]),
        "set": lambda a: eng.set_values(a["sheet"], a["id"], a["values"]),
        "proposals": lambda a: eng.proposals(a["sheet"], a.get("parent", True), a.get("siblings", True),
                                             a.get("derive", True)),
        "apply": lambda a: eng.apply(a["sheet"], a["items"]),
        "image": lambda a: eng.set_image(a["sheet"], a["id"], base64.b64decode(a["base64"]) if a.get("base64")
                                         else fetch_url(a["url"]) if a.get("url") else open(a["path"], "rb").read()),
        "parentImage": lambda a: {"image": eng.parent_image(a["sheet"], a["id"])},
        "undo": lambda a: eng.undo(),
        "save": lambda a: eng.save(),
        "recent": lambda a: eng.recent_edits(a.get("limit", 30)),
        "log": lambda a: eng.edit_log(a.get("limit", 200), a.get("sheet"), a.get("action"), a.get("query", "")),
        "columns": lambda a: eng.columns(a["sheet"]),
        "addColumn": lambda a: eng.add_column(a.get("sheets") or [a["sheet"]], a["name"], a.get("optional", False),
                                              a.get("inherit", False), a.get("default"), a.get("note", "")),
        "addRow": lambda a: eng.add_row(a["sheet"], a.get("values"), a.get("copyFrom"), a.get("mode", "variant")),
        "wiki": lambda a: eng.wiki(a["sheet"], a["ids"], a.get("limit"), stop),
        "stop": lambda a: (stop.set(), {"stopping": True})[1],
    }
    send({"event": "ready", "version": 2})
    for line in stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except ValueError:
            send({"event": "error", "message": "bad JSON"})
            continue
        rid, cmd, args = req.get("id"), req.get("cmd"), req.get("args") or {}
        if cmd == "quit":
            send({"id": rid, "ok": True, "result": {"bye": True}})
            break

        def run(rid=rid, cmd=cmd, args=args):
            try:
                if cmd not in commands:
                    raise ValueError(f"unknown command {cmd}")
                if cmd == "wiki":
                    stop.clear()
                send({"id": rid, "ok": True, "result": commands[cmd](args)})
            except Exception as e:
                send({"id": rid, "ok": False, "error": f"{type(e).__name__}: {e}"})
        if cmd in ("wiki", "stop"):
            threading.Thread(target=run, daemon=True).start()  # long-running; other requests keep flowing
        else:
            run()


# ── CLI ───────────────────────────────────────────────────────────────────────

def run_cli(argv):
    if argv and argv[0] == "serve":  # JSON bridge for the Flutter app
        return serve()
    ap = argparse.ArgumentParser(description="Find and fill missing data in the workbooks")
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("report", "fill", "set", "image", "wiki", "add-column", "add-row", "log"):
        p = sub.add_parser(name)
        p.add_argument("--workbook", required=True)
        p.add_argument("--sheet", required=name in ("set", "image", "add-row"),
                       action="append" if name == "add-column" else "store",
                       help="add-column: repeat for several tabs, or --all-tabs")
        if name == "add-column":
            p.add_argument("--name", required=True)
            p.add_argument("--all-tabs", action="store_true", help="every data tab of the workbook")
            p.add_argument("--optional", action="store_true", help="don't report it as missing")
            p.add_argument("--inherit", action="store_true", help="variants copy it from their parent")
            p.add_argument("--default", help="value for every existing row")
            p.add_argument("--note", default="")
        if name == "add-row":
            g = p.add_mutually_exclusive_group()
            g.add_argument("--variant-of", help="copy the shared fields of this id, parent id set")
            g.add_argument("--copy-of", help="copy every field of this id")
            p.add_argument("--set", nargs="*", default=[], metavar="FIELD=VALUE")
        if name == "log":
            p.add_argument("--limit", type=int, default=50)
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
    if a.cmd in ("add-column", "add-row", "log"):  # through the engine: logged in _edit_log, saved
        eng = Engine(source="cli")
        eng.open(a.workbook)
        try:
            if a.cmd == "add-column":
                tabs = data_sheets(eng.book) if a.all_tabs else (a.sheet or [])
                if not tabs:
                    sys.exit("Give --sheet (repeatable) or --all-tabs.")
                res = eng.add_column(tabs, a.name, a.optional, a.inherit, a.default, a.note)
                print(f"Column {res['column']} added to {', '.join(res['added'])}")
            elif a.cmd == "add-row":
                values = dict(kv.split("=", 1) for kv in a.set)
                src = a.variant_of or a.copy_of
                res = eng.add_row(a.sheet, values, src, "copy" if a.copy_of else "variant" if src else "empty")
                print(f"{a.sheet}: new row {res['id']} (sheet row {res['row']})")
            else:
                for e in eng.edit_log(a.limit, a.sheet)["entries"]:
                    what = (f"{e['field']}: {e.get('oldValue')!r} -> {e.get('newValue')!r}"
                            if e.get("action") in ("set", "auto-fill", "image") else e.get("field") or "")
                    print(f"{e.get('at')}  {e.get('source'):<17} {e.get('action'):<10} {e.get('sheet')} "
                          f"#{e.get('rowId') or ''} {what} {e.get('note') or ''}".rstrip())
                return
        except ValueError as e:
            sys.exit(str(e))
        eng.save()
        print(f"{a.workbook} saved (.bak kept); the change is in its _edit_log tab")
        return
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
    import threading
    import time
    import tkinter as tk
    from tkinter import ttk, filedialog, messagebox
    import tk_ui

    root = tk.Tk()
    root.title("Missing data tool")
    root.geometry("1400x820")
    tk_ui.apply_theme(root)
    prefs = tk_ui.Prefs("missing_data_tool")
    eng = Engine(log=lambda m: runner.call_ui(add_log, m))
    st = {"sheet": None, "field": None, "rows": [], "row": None, "new_img": None, "editors": {},
          "sort": prefs.get("sort", "sheet"), "stop": threading.Event()}

    # ── layout ──
    tb = ttk.Frame(root, padding=(8, 6))
    tb.pack(fill=tk.X)
    ttk.Button(tb, text="Open...", command=lambda: choose_workbook()).pack(side=tk.LEFT)
    recent_btn = ttk.Menubutton(tb, text="Recent")
    recent_menu = tk.Menu(recent_btn, tearoff=False)
    recent_btn["menu"] = recent_menu
    recent_btn.pack(side=tk.LEFT, padx=4)
    save_btn = ttk.Button(tb, text="Save  (Ctrl+S)", command=lambda: do_save(), style="Accent.TButton")
    save_btn.pack(side=tk.LEFT, padx=(12, 4))
    undo_btn = ttk.Button(tb, text="Undo  (Ctrl+Z)", command=lambda: do_undo())
    undo_btn.pack(side=tk.LEFT)
    ttk.Separator(tb, orient=tk.VERTICAL).pack(side=tk.LEFT, fill=tk.Y, padx=10)
    ttk.Button(tb, text="Auto-fill...", command=lambda: autofill()).pack(side=tk.LEFT)
    ttk.Button(tb, text="Wiki: selected rows", command=lambda: wiki(True)).pack(side=tk.LEFT, padx=4)
    ttk.Button(tb, text="Wiki: all listed rows", command=lambda: wiki(False)).pack(side=tk.LEFT)
    stop_btn = ttk.Button(tb, text="Stop", command=lambda: st["stop"].set(), state="disabled")
    stop_btn.pack(side=tk.LEFT, padx=4)
    tb2 = ttk.Frame(root, padding=(8, 0, 8, 6))  # second row: structure, history, options
    tb2.pack(fill=tk.X)
    ttk.Button(tb2, text="Add column...", command=lambda: add_column_dialog()).pack(side=tk.LEFT)
    ttk.Button(tb2, text="Change log", command=lambda: log_dialog()).pack(side=tk.LEFT, padx=4)
    ttk.Button(tb2, text="Recently edited", command=lambda: recent_dialog()).pack(side=tk.LEFT)
    ttk.Button(tb2, text="Export CSV...", command=lambda: export()).pack(side=tk.LEFT, padx=4)
    autosave = tk.BooleanVar(value=prefs.get("autosave", True))
    ttk.Checkbutton(tb2, text="Autosave every 2 min", variable=autosave,
                    command=lambda: prefs.set("autosave", autosave.get())).pack(side=tk.RIGHT)
    all_cols = tk.BooleanVar(value=False)
    ttk.Checkbutton(tb2, text="Count optional columns", variable=all_cols,
                    command=lambda: reload_sheet()).pack(side=tk.RIGHT, padx=8)

    panes = ttk.PanedWindow(root, orient=tk.HORIZONTAL)
    panes.pack(fill=tk.BOTH, expand=True, padx=8)

    left = ttk.Frame(panes)
    ttk.Label(left, text="Tabs", style="Title.TLabel").pack(anchor="w")
    stree = ttk.Treeview(left, columns=("rows", "gaps"), height=9, selectmode="browse")
    for c, w, t in (("#0", 170, "tab"), ("rows", 50, "rows"), ("gaps", 60, "w/ gaps")):
        stree.heading(c, text=t)
        stree.column(c, width=w, anchor="w" if c == "#0" else "e")
    stree.pack(fill=tk.X)
    ttk.Label(left, text="Missing per field", style="Title.TLabel").pack(anchor="w", pady=(10, 0))
    ftree = ttk.Treeview(left, columns=("missing", "pct"), selectmode="browse")
    for c, w, t in (("#0", 150, "field"), ("missing", 60, "missing"), ("pct", 50, "%")):
        ftree.heading(c, text=t)
        ftree.column(c, width=w, anchor="w" if c == "#0" else "e")
    ftree.pack(fill=tk.BOTH, expand=True)
    panes.add(left, weight=1)

    mid = ttk.Frame(panes)
    bar = ttk.Frame(mid)
    bar.pack(fill=tk.X)
    filt_var = tk.StringVar()
    ttk.Label(bar, text="Search (Ctrl+F):").pack(side=tk.LEFT)
    filt = ttk.Entry(bar, textvariable=filt_var, width=28)
    filt.pack(side=tk.LEFT, padx=4)
    rows_lbl = ttk.Label(bar, text="", style="Muted.TLabel")
    rows_lbl.pack(side=tk.LEFT, padx=6)
    rowbar = ttk.Frame(mid)  # row actions on their own line: always visible, whatever the width
    rowbar.pack(fill=tk.X, pady=(4, 4))
    ttk.Button(rowbar, text="New row", command=lambda: new_row("empty")).pack(side=tk.LEFT)
    ttk.Button(rowbar, text="Duplicate as variant", command=lambda: new_row("variant")).pack(side=tk.LEFT, padx=4)
    ttk.Button(rowbar, text="Copy row", command=lambda: new_row("copy")).pack(side=tk.LEFT)
    ttk.Label(rowbar, text="variant = shared fields + parent id; copy = every field", style="Muted.TLabel").pack(
        side=tk.LEFT, padx=8)
    rtree = ttk.Treeview(mid, columns=("name", "code", "edition", "n", "updated", "missing"), selectmode="extended")
    for c, w, t in (("#0", 60, "id"), ("name", 150, "name"), ("code", 80, "code"), ("edition", 170, "edition / label"),
                    ("n", 40, "gaps"), ("updated", 140, "last edited"), ("missing", 280, "missing")):
        rtree.heading(c, text=t, command=lambda c=c: sort_by(c))
        rtree.column(c, width=w, anchor="e" if c == "n" else "w")
    rsb = ttk.Scrollbar(mid, command=rtree.yview)
    rtree.configure(yscrollcommand=rsb.set)
    rsb.pack(side=tk.RIGHT, fill=tk.Y)
    rtree.pack(fill=tk.BOTH, expand=True)
    panes.add(mid, weight=4)

    right = ttk.Frame(panes, padding=(8, 0))
    sel_lbl = ttk.Label(right, text="Pick a row", style="Title.TLabel", wraplength=360)
    sel_lbl.pack(anchor="w")
    meta_lbl = ttk.Label(right, text="", style="Muted.TLabel")
    meta_lbl.pack(anchor="w")
    canvas = tk.Canvas(right, width=360, height=360, highlightthickness=0, bg=tk_ui.COLORS["bg"])
    csb = ttk.Scrollbar(right, command=canvas.yview)
    canvas.configure(yscrollcommand=csb.set)
    form = ttk.Frame(canvas)
    canvas.create_window((0, 0), window=form, anchor="nw")
    form.bind("<Configure>", lambda e: canvas.configure(scrollregion=canvas.bbox("all")))
    canvas.pack(fill=tk.X)
    eb = ttk.Frame(right)
    eb.pack(fill=tk.X, pady=4)
    ttk.Button(eb, text="Apply (Enter)", command=lambda: apply_fields(), style="Accent.TButton").pack(side=tk.LEFT)
    ttk.Button(eb, text="Next gap (Ctrl+Enter)", command=lambda: next_missing()).pack(side=tk.LEFT, padx=4)
    imgf = ttk.Frame(right)
    imgf.pack(fill=tk.X, pady=(6, 0))
    ttk.Label(imgf, text="current", style="Muted.TLabel").grid(row=0, column=0)
    ttk.Label(imgf, text="new", style="Muted.TLabel").grid(row=0, column=1)
    cur_img, new_img = ttk.Label(imgf, text="(no image)"), ttk.Label(imgf, text="")
    cur_img.grid(row=1, column=0, padx=4)
    new_img.grid(row=1, column=1, padx=4)
    ib = ttk.Frame(right)
    ib.pack(fill=tk.X, pady=4)
    for txt, how in (("File...", "file"), ("Paste", "clipboard"), ("Parent image", "parent")):
        ttk.Button(ib, text=txt, command=lambda h=how: load_img(h)).pack(side=tk.LEFT, padx=(0, 3), expand=True, fill=tk.X)
    url_var = tk.StringVar()
    ub = ttk.Frame(right)
    ub.pack(fill=tk.X)
    ttk.Entry(ub, textvariable=url_var).pack(side=tk.LEFT, fill=tk.X, expand=True)
    ttk.Button(ub, text="URL", command=lambda: load_img("url")).pack(side=tk.LEFT)
    img_btn = ttk.Button(right, text="Put image on this row", state="disabled", command=lambda: save_img())
    img_btn.pack(fill=tk.X, pady=4)
    panes.add(right, weight=2)

    logbox = tk.Text(root, height=6, state="disabled", bg="#151922", fg="#d7dce5", font=("Consolas", 9), relief="flat")
    logbox.pack(fill=tk.X, padx=8, pady=(4, 0))
    sbar, set_status = tk_ui.status_bar(root)
    sbar.pack(fill=tk.X)

    def on_busy(busy, label):
        set_status(label or None, busy)
        stop_btn.config(state="normal" if busy and "wiki" in (label or "").lower() else "disabled")
    runner = tk_ui.BackgroundRunner(root, on_busy)

    # ── helpers ──
    def add_log(msg):
        logbox.configure(state="normal")
        logbox.insert("end", str(msg) + "\n")
        logbox.see("end")
        logbox.configure(state="disabled")

    def err(e):
        add_log(f"Error: {e}")
        messagebox.showerror("Missing data tool", str(e))

    def refresh_title():
        if not eng.book:
            return
        dirty = eng.book.dirty
        root.title(f"{'* ' if dirty else ''}{os.path.basename(eng.path)} - Missing data tool")
        undo_btn.config(state="normal" if eng._undo else "disabled")
        saved = time.strftime("%H:%M:%S", time.localtime(eng.last_saved)) if eng.last_saved else "-"
        set_status(f"{'Unsaved changes' if dirty else 'All changes saved'} - last saved {saved} - "
                   f"{len(eng._undo)} undo step(s)")

    def thumb(widget, data, size=160):
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

    def build_recent():
        recent_menu.delete(0, tk.END)
        for pth in prefs.get("recent", []):
            recent_menu.add_command(label=pth, command=lambda p=pth: open_workbook(p))

    # ── workbook / sheets ──
    def choose_workbook():
        pth = filedialog.askopenfilename(filetypes=[("Excel", "*.xlsx")])
        if pth:
            open_workbook(pth)

    def open_workbook(pth):
        if eng.book and eng.book.dirty and not messagebox.askyesno("Unsaved changes", "Discard unsaved changes?"):
            return
        if not os.path.exists(pth):
            err(f"{pth} not found")
            return

        def done(summary):
            prefs.add_recent(pth)
            prefs.set("last", pth)
            build_recent()
            stree.delete(*stree.get_children())
            for sh in summary["sheets"]:
                stree.insert("", "end", iid=sh["name"], text=sh["name"], values=(sh["rows"], sh["rowsWithMissing"]))
            tk_ui.stripe(stree)
            last = prefs.get("last_sheet")
            pick = last if last in stree.get_children() else (stree.get_children() or [None])[0]
            if pick:
                stree.selection_set(pick)
            add_log(f"Opened {pth}")
            refresh_title()
        runner.run(lambda: eng.open(pth), done, err, f"Opening {os.path.basename(pth)} ...")

    def on_sheet(_=None):
        sel = stree.selection()
        if sel:
            st["sheet"], st["field"] = sel[0], None
            prefs.set("last_sheet", sel[0])
            reload_sheet()

    def reload_sheet():
        sh = st["sheet"]
        if not (eng.book and sh):
            return

        def done(a):
            ftree.delete(*ftree.get_children())
            ftree.insert("", "end", iid="__all__", text="(all rows)", values=(a["total"], ""))
            for f in sorted(a["fields"], key=lambda f: -f["missing"]):
                if f["missing"]:
                    ftree.insert("", "end", iid=f["field"], text=f["field"] + (" *" if f["never"] else ""),
                                 values=(f["missing"], f"{100 * f['missing'] / max(1, a['total']):.0f}"))
            tk_ui.stripe(ftree)
            fill_rows()
            refresh_title()
        opt = all_cols.get()  # Tk variables are read on the UI thread, never in the worker
        runner.run(lambda: eng.analyze(sh, opt), done, err, f"Analysing {sh} ...")

    def on_field(_=None):
        sel = ftree.selection()
        st["field"] = None if not sel or sel[0] == "__all__" else sel[0]
        fill_rows()

    _debounce = {"job": None}

    def fill_rows_later(*_):
        if _debounce["job"]:
            root.after_cancel(_debounce["job"])
        _debounce["job"] = root.after(200, fill_rows)

    def fill_rows(keep=None):
        sh = st["sheet"]
        if not sh:
            return
        res = eng.rows(sh, st["field"], filt_var.get(), st["sort"], all_cols.get())
        sel_ids = keep if keep is not None else [rtree.item(i, "text") for i in rtree.selection()]
        rtree.delete(*rtree.get_children())
        st["rows"] = res["rows"]
        for i, rw in enumerate(res["rows"]):
            rtree.insert("", "end", iid=str(rw["row"]), text=str(rw["id"]),
                         values=(rw["name"], rw["code"], rw["edition"], len(rw["missing"]),
                                 rw["updatedAt"][:19].replace("T", " "), ", ".join(rw["missing"])))
        tk_ui.stripe(rtree)
        again = [i for i in rtree.get_children() if rtree.item(i, "text") in [str(x) for x in sel_ids]]
        if again:
            rtree.selection_set(again)
        rows_lbl.config(text=f"{res['total']} rows" + (f" missing {st['field']}" if st["field"] else "")
                        + f" - sorted by {st['sort']}")

    def sort_by(col):
        st["sort"] = {"updated": "updated", "n": "missing", "missing": "missing"}.get(col, "sheet")
        prefs.set("sort", st["sort"])
        fill_rows()

    # ── row editor ──
    def on_row(_=None):
        sel = rtree.selection()
        if not sel or not st["sheet"]:
            return
        rw = next((x for x in st["rows"] if str(x["row"]) == sel[0]), None)
        if not rw:
            return
        info = eng.row(st["sheet"], rw["id"])
        st["row"] = info
        sel_lbl.config(text=f"#{info['id']}  {rw['name']}")
        meta_lbl.config(text=f"{st['sheet']} - last edited: {info['updatedAt'][:19].replace('T', ' ') or 'never'}"
                             + (f" - parent #{info['parentId']}" if info["parentId"] is not None else ""))
        for w in form.winfo_children():
            w.destroy()
        st["editors"] = {}
        missing = set(info["missing"])
        custom = set(info.get("customFields", []))
        for i, f in enumerate(info["fields"]):
            v = info["values"].get(f)
            optional = f in OPTIONAL
            lbl = ttk.Label(form, text=f + ("  +" if f in custom else ""),
                            style="Muted.TLabel" if optional else "TLabel")
            if f in custom:  # added with this tool (purple header in the workbook)
                lbl.configure(foreground="#7030A0")
            lbl.grid(row=i, column=0, sticky="w", padx=(0, 6))
            var = tk.StringVar(value="" if blank(v) else str(v))
            e = tk.Entry(form, textvariable=var, width=30, relief="solid", bd=1,
                         bg=tk_ui.COLORS["warn_bg"] if f in missing else "white")
            e.grid(row=i, column=1, sticky="we", pady=1)
            e.bind("<Return>", lambda ev: apply_fields())
            e.bind("<Control-Return>", lambda ev: (apply_fields(), next_missing()))
            st["editors"][f] = (var, v)
        thumb(cur_img, base64.b64decode(info["image"]) if info["image"] else None)
        img_btn.config(state="normal" if st["new_img"] else "disabled")

    def apply_fields():
        info = st["row"]
        if not info:
            return
        changed = {f: var.get() for f, (var, old) in st["editors"].items()
                   if var.get().strip() != ("" if blank(old) else str(old))}
        if not changed:
            return
        res = eng.set_values(st["sheet"], info["id"], changed)
        add_log(f"{st['sheet']} #{info['id']}: {res['changed']} field(s) changed")
        fill_rows(keep=[info["id"]])
        update_counts()
        on_row()
        refresh_title()

    def next_missing():
        rows = rtree.get_children()
        if not rows:
            return
        sel = rtree.selection()
        start = rows.index(sel[0]) + 1 if sel else 0
        for iid in list(rows[start:]) + list(rows[:start]):
            if int(rtree.set(iid, "n") or 0) > 0:
                rtree.selection_set(iid)
                rtree.see(iid)
                return

    def update_counts():
        a = eng.analyze(st["sheet"], all_cols.get())
        for f in a["fields"]:
            if ftree.exists(f["field"]):
                ftree.set(f["field"], "missing", f["missing"])
        if stree.exists(st["sheet"]):
            stree.set(st["sheet"], "gaps", sum(1 for x in eng._cache[st["sheet"]]["missing"].values() if x))

    # ── images ──
    def load_img(how):
        try:
            if how == "file":
                pth = filedialog.askopenfilename(filetypes=[("Images", "*.png *.jpg *.jpeg *.webp *.gif *.bmp")])
                if not pth:
                    return
                data = open(pth, "rb").read()
            elif how == "url":
                data = fetch_url(url_var.get().strip())
            elif how == "parent":
                b64 = eng.parent_image(st["sheet"], st["row"]["id"]) if st["row"] else None
                if not b64:
                    add_log("This row has no parent with an image.")
                    return
                data = base64.b64decode(b64)
            else:
                from PIL import ImageGrab
                clip = ImageGrab.grabclipboard()
                if clip is None:
                    add_log("No image on the clipboard (copy the image itself).")
                    return
                if isinstance(clip, list):
                    data = open(clip[0], "rb").read()
                else:
                    buf = io.BytesIO()
                    clip.save(buf, "PNG")
                    data = buf.getvalue()
            full, _ = normalize_image(data)
        except Exception as e:
            err(f"Couldn't load that image: {e}")
            return
        st["new_img"] = data
        thumb(new_img, full)
        img_btn.config(state="normal" if st["row"] else "disabled")

    def save_img():
        if not (st["row"] and st["new_img"]):
            return
        eng.set_image(st["sheet"], st["row"]["id"], st["new_img"])
        add_log(f"Image put on {st['sheet']} #{st['row']['id']} (save to keep it)")
        st["new_img"] = None
        thumb(new_img, None)
        fill_rows(keep=[st["row"]["id"]])
        update_counts()
        on_row()
        refresh_title()

    # ── actions ──
    def do_save():
        if eng.book and eng.book.dirty:
            runner.run(eng.save, lambda r: (add_log("Saved (.bak kept)."), refresh_title()), err, "Saving ...")

    def do_undo():
        if not eng.book:
            return
        res = eng.undo()
        if res["undone"]:
            add_log(f"Undid: {res['undone']}")
            reload_sheet()
        refresh_title()

    def autofill():
        sh = st["sheet"]
        if not sh:
            return
        props = eng.proposals(sh)
        if not props:
            messagebox.showinfo("Auto-fill", "Nothing can be filled automatically in this tab.")
            return
        win = tk.Toplevel(root)
        win.title(f"Auto-fill {sh}: {len(props)} proposed values")
        win.geometry("900x520")
        flt = ttk.Frame(win, padding=6)
        flt.pack(fill=tk.X)
        srcs = sorted({p["source"].split(":")[0].split(" #")[0] for p in props})
        use = {s: tk.BooleanVar(value=True) for s in srcs}
        tv = ttk.Treeview(win, columns=("field", "value", "source"), selectmode="extended")
        for c, w, t in (("#0", 70, "id"), ("field", 130, "field"), ("value", 220, "new value"), ("source", 380, "from")):
            tv.heading(c, text=t)
            tv.column(c, width=w)

        def fill_tv():
            tv.delete(*tv.get_children())
            for i, p in enumerate(props):
                if use[p["source"].split(":")[0].split(" #")[0]].get():
                    tv.insert("", "end", iid=str(i), text=str(p["id"]), values=(p["field"], p["value"], p["source"]))
            tk_ui.stripe(tv)
            tv.selection_set(tv.get_children())
        for s_ in srcs:
            ttk.Checkbutton(flt, text=s_, variable=use[s_], command=fill_tv).pack(side=tk.LEFT, padx=4)
        tv.pack(fill=tk.BOTH, expand=True)
        fill_tv()

        def apply():
            res = eng.apply(sh, [props[int(i)] for i in tv.selection()])
            add_log(f"Auto-fill: {res['filled']} cells in {res['rows']} rows (undo with Ctrl+Z; save to keep)")
            win.destroy()
            reload_sheet()
            refresh_title()
        b = ttk.Frame(win, padding=6)
        b.pack(fill=tk.X)
        ttk.Label(b, text="Everything listed is selected - Ctrl/Shift-click to deselect.", style="Muted.TLabel").pack(side=tk.LEFT)
        ttk.Button(b, text="Apply selected", command=apply, style="Accent.TButton").pack(side=tk.RIGHT)

    def wiki(selected_only):
        sh = st["sheet"]
        if not sh:
            return
        if selected_only:
            ids = [rtree.item(i, "text") for i in rtree.selection()]
        else:
            ids = [str(r["id"]) for r in st["rows"]]
        if not ids:
            add_log("Select rows first.")
            return
        if not selected_only and not messagebox.askyesno(
                "Fill from wiki", f"Re-read the wiki pages of {len(ids)} rows? Requests stay one at a time "
                                  "(safe for your IP), so this can take a while."):
            return
        st["stop"].clear()
        runner.run(lambda: eng.wiki(sh, ids, stop_event=st["stop"]),
                   lambda r: (add_log(f"Wiki fill done ({r['pages']} pages)."), open_workbook_after_wiki()),
                   err, f"Wiki fill: {len(ids)} rows ...")

    def open_workbook_after_wiki():
        on_sheet()
        refresh_title()

    def recent_dialog():
        if not eng.book:
            return
        win = tk.Toplevel(root)
        win.title("Recently edited")
        win.geometry("640x420")
        tv = ttk.Treeview(win, columns=("sheet", "name", "when"))
        for c, w, t in (("#0", 60, "id"), ("sheet", 180, "tab"), ("name", 180, "name"), ("when", 170, "last edited")):
            tv.heading(c, text=t)
            tv.column(c, width=w)
        for i, e in enumerate(eng.recent_edits(100)):
            tv.insert("", "end", iid=str(i), text=str(e["id"]), values=(e["sheet"], e["name"], e["updatedAt"][:19].replace("T", " ")))
        tk_ui.stripe(tv)
        tv.pack(fill=tk.BOTH, expand=True)

        def go(_=None):
            sel = tv.selection()
            if not sel:
                return
            sheet, rid = tv.set(sel[0], "sheet"), tv.item(sel[0], "text")
            stree.selection_set(sheet)
            root.after(300, lambda: [rtree.selection_set(i) or rtree.see(i)
                                     for i in rtree.get_children() if rtree.item(i, "text") == rid])
            win.destroy()
        tv.bind("<Double-1>", go)
        ttk.Label(win, text="Double-click to jump to the row.", style="Muted.TLabel").pack(anchor="w", padx=6, pady=4)

    # ── structure: rows / columns, and the change log ──
    def refresh_tabs():
        summary = eng.summary()
        for sh in summary["sheets"]:
            if stree.exists(sh["name"]):
                stree.item(sh["name"], values=(sh["rows"], sh["rowsWithMissing"]))

    def new_row(mode):
        sh = st["sheet"]
        if not sh:
            return
        src = None
        if mode != "empty":
            if not st["row"]:
                add_log("Pick the row to copy first.")
                return
            src = st["row"]["id"]
        values = None
        if mode == "empty":
            from tkinter import simpledialog
            name = simpledialog.askstring("New row", f"Name of the new row in {sh} (you can fill the rest after):",
                                          parent=root)
            if name is None:
                return
            values = {"name": name} if name.strip() and "name" in eng.book.headers(eng.book.wb[sh]) else None
        try:
            res = eng.add_row(sh, values, src, mode)
        except ValueError as e:
            err(e)
            return
        add_log(f"{sh}: new row #{res['id']} ({mode}{f' of #{src}' if src is not None else ''}) - save to keep")
        refresh_tabs()
        reload_sheet()
        root.after(400, lambda: [rtree.selection_set(i) or rtree.see(i)
                                 for i in rtree.get_children() if rtree.item(i, "text") == str(res["id"])])

    def add_column_dialog():
        if not eng.book or not st["sheet"]:
            return
        win = tk.Toplevel(root)
        win.title("Add a column")
        win.transient(root)
        f = ttk.Frame(win, padding=12)
        f.pack(fill=tk.BOTH, expand=True)
        name_v, default_v, note_v = tk.StringVar(), tk.StringVar(), tk.StringVar()
        scope_v = tk.StringVar(value="this")
        opt_v, inh_v = tk.BooleanVar(value=False), tk.BooleanVar(value=True)
        ttk.Label(f, text="Column name (letters, digits, _), e.g. tipShape").grid(row=0, column=0, columnspan=2, sticky="w")
        ent = ttk.Entry(f, textvariable=name_v, width=34)
        ent.grid(row=1, column=0, columnspan=2, sticky="we", pady=(0, 8))
        ttk.Radiobutton(f, text=f"This tab ({st['sheet']})", variable=scope_v, value="this").grid(row=2, column=0, columnspan=2, sticky="w")
        ttk.Radiobutton(f, text="Every data tab in this workbook", variable=scope_v, value="all").grid(row=3, column=0, columnspan=2, sticky="w")
        ttk.Checkbutton(f, text="Variants copy it from their parent (auto-fill)", variable=inh_v).grid(row=4, column=0, columnspan=2, sticky="w", pady=(8, 0))
        ttk.Checkbutton(f, text="Optional (don't report it as missing)", variable=opt_v).grid(row=5, column=0, columnspan=2, sticky="w")
        ttk.Label(f, text="Value for every existing row (optional)").grid(row=6, column=0, sticky="w", pady=(8, 0))
        ttk.Entry(f, textvariable=default_v).grid(row=7, column=0, columnspan=2, sticky="we")
        ttk.Label(f, text="Note (what it's for)").grid(row=8, column=0, sticky="w", pady=(8, 0))
        ttk.Entry(f, textvariable=note_v).grid(row=9, column=0, columnspan=2, sticky="we")
        ttk.Label(f, text="Added after the last column (purple header), listed in the _columns tab.\n"
                          "The packager puts it into the JSON; the app ignores fields it doesn't know.",
                  style="Muted.TLabel").grid(row=10, column=0, columnspan=2, sticky="w", pady=(8, 0))

        def ok():
            tabs = data_sheets(eng.book) if scope_v.get() == "all" else [st["sheet"]]
            try:
                res = eng.add_column(tabs, name_v.get(), opt_v.get(), inh_v.get(), default_v.get() or None,
                                     note_v.get())
            except ValueError as e:
                messagebox.showerror("Add a column", str(e), parent=win)
                return
            add_log(f"Column {res['column']} added to {len(res['added'])} tab(s) - save to keep (Ctrl+Z undoes)")
            win.destroy()
            reload_sheet()
            refresh_title()
        b = ttk.Frame(f)
        b.grid(row=11, column=0, columnspan=2, sticky="e", pady=(12, 0))
        ttk.Button(b, text="Cancel", command=win.destroy).pack(side=tk.RIGHT)
        ttk.Button(b, text="Add column", command=ok, style="Accent.TButton").pack(side=tk.RIGHT, padx=6)
        ent.focus_set()
        win.bind("<Return>", lambda e: ok())

    def log_dialog():
        if not eng.book:
            return
        win = tk.Toplevel(root)
        win.title("Change log - everything changed with the missing data tool")
        win.geometry("1100x520")
        top = ttk.Frame(win, padding=6)
        top.pack(fill=tk.X)
        q_v, this_v = tk.StringVar(), tk.BooleanVar(value=False)
        ttk.Label(top, text="Search:").pack(side=tk.LEFT)
        ttk.Entry(top, textvariable=q_v, width=30).pack(side=tk.LEFT, padx=4)
        ttk.Checkbutton(top, text="This tab only", variable=this_v, command=lambda: fill()).pack(side=tk.LEFT, padx=8)
        count = ttk.Label(top, text="", style="Muted.TLabel")
        count.pack(side=tk.RIGHT)
        cols = ("source", "action", "sheet", "rowId", "field", "oldValue", "newValue", "note")
        tv = ttk.Treeview(win, columns=cols)
        for c, w, t in (("#0", 150, "when"), ("source", 110, "tool"), ("action", 80, "action"), ("sheet", 140, "tab"),
                        ("rowId", 55, "id"), ("field", 110, "field"), ("oldValue", 120, "old"),
                        ("newValue", 120, "new"), ("note", 200, "note")):
            tv.heading(c, text=t)
            tv.column(c, width=w)
        sb = ttk.Scrollbar(win, command=tv.yview)
        tv.configure(yscrollcommand=sb.set)
        sb.pack(side=tk.RIGHT, fill=tk.Y)
        tv.pack(fill=tk.BOTH, expand=True)

        def fill(*_):
            res = eng.edit_log(1000, st["sheet"] if this_v.get() else None, None, q_v.get())
            tv.delete(*tv.get_children())
            for i, e in enumerate(res["entries"]):
                tv.insert("", "end", iid=str(i), text=str(e.get("at") or "")[:19].replace("T", " "),
                          values=tuple("" if e.get(c) is None else e.get(c) for c in cols))
            tk_ui.stripe(tv)
            count.config(text=f"{res['total']} change(s)" + (" - showing the newest 1000" if res["total"] > 1000 else ""))
        q_v.trace_add("write", fill)

        def go(_=None):
            sel = tv.selection()
            if not sel:
                return
            sheet, rid = tv.set(sel[0], "sheet"), tv.set(sel[0], "rowId")
            if not stree.exists(sheet):
                return
            stree.selection_set(sheet)
            root.after(300, lambda: [rtree.selection_set(i) or rtree.see(i)
                                     for i in rtree.get_children() if rtree.item(i, "text") == rid])
        tv.bind("<Double-1>", go)
        ttk.Label(win, text="Kept in the workbook's _edit_log tab; the packager exports it to data/_edit_log.json. "
                            "Double-click to jump to the row.", style="Muted.TLabel").pack(anchor="w", padx=6, pady=4)
        fill()

    def export():
        if not eng.book:
            return
        pth = filedialog.asksaveasfilename(defaultextension=".csv", filetypes=[("CSV", "*.csv")])
        if pth:
            report(eng.book, None, all_cols.get(), pth, out=add_log)

    def tick_autosave():
        if autosave.get() and eng.book and eng.book.dirty and not runner.busy:
            runner.run(eng.save, lambda r: (add_log("Autosaved."), refresh_title()), err, "Autosaving ...")
        root.after(120000, tick_autosave)

    def on_close():
        if eng.book and eng.book.dirty:
            ans = messagebox.askyesnocancel("Unsaved changes", "Save changes before closing?")
            if ans is None:
                return
            if ans:
                eng.save()
        root.destroy()

    stree.bind("<<TreeviewSelect>>", on_sheet)
    ftree.bind("<<TreeviewSelect>>", on_field)
    rtree.bind("<<TreeviewSelect>>", on_row)
    filt_var.trace_add("write", fill_rows_later)
    root.bind("<Control-s>", lambda e: do_save())
    root.bind("<Control-z>", lambda e: do_undo())
    root.bind("<Control-f>", lambda e: filt.focus_set())
    root.protocol("WM_DELETE_WINDOW", on_close)
    build_recent()
    root.after(120000, tick_autosave)
    start = workbook or prefs.get("last")
    if start and os.path.exists(start):
        root.after(150, lambda: open_workbook(start))
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
