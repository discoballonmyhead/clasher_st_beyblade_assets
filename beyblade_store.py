#!/usr/bin/env python3
"""
Read/write helper for the human-managed workbooks (layout defined in beyblade_schema.py).
Used by fandom_scraper.py and make_sample_workbooks.py.

Rules it follows so the packager and humans stay happy:
  * rows stay contiguous (the packager stops at the first blank row)
  * header order of an existing sheet is never changed; missing columns are appended
  * images are PNGs anchored to the row's image cell
  * a .bak copy is made before the first save of a session; saves are atomic
"""
import io
import os
import re
import shutil
from datetime import datetime, timezone

import openpyxl
from openpyxl.drawing.image import Image as XLImage
from openpyxl.drawing.spreadsheet_drawing import AnchorMarker, OneCellAnchor
from openpyxl.drawing.xdr import XDRPositiveSize2D
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.utils import get_column_letter
from openpyxl.utils.units import pixels_to_EMU
from openpyxl.worksheet.datavalidation import DataValidation

import beyblade_schema as S

HEAD_FILL = {"id": "7F6000", "variant": "806000", "data": "1F3864", "image": "375623", "meta": "595959"}
IMAGE_DISPLAY = {"full": 110, "min": 44}
LOG_SHEET = "_scrape_log"
LOG_COLUMNS = ["target", "sheet", "id", "wikiTitle", "url", "revid", "imageFile", "scrapedAt"]

README = {
    "parts": [
        "BEYBLADE PARTS WORKBOOK",
        "",
        "One sheet per generation + part type, named Parts_<Generation>_<PartType>.",
        "  X:          Blades, Ratchets, Bits, LockChips, MainBlades, AssistBlades, MetalBlades, OverBlades",
        "  Burst:      Layers (layerComponent = full/chip/weight/base/ring/chassis/core/armor/blade), Discs, Frames, Drivers",
        "  Metal:      FaceBolts, EnergyRings, FusionWheels, SpinTracks, PerformanceTips (Zero-G parts too, system = Zero-G)",
        "  Original:   BitChips, AttackRings, WeightDisks, SpinGears, BladeBases, RunningCores (system = Plastic / HMS ...)",
        "",
        "COLUMNS",
        "  dataID          whole number, unique in its sheet. Never reuse or renumber (apps and ProductContents point at it).",
        "  parentPartId    empty for the base part. For a recolor / coating / edition, put the base part's dataID here.",
        "  variantLabel    what makes the variant different, e.g. 'Metal Coat: Black'. Empty for the base part.",
        "  code            release code the part first came in (BX-01, UX-02, B-150, BB-70 ...).",
        "  edition         which release/version, free text, e.g. 'Starter (S6-60V)'.",
        "  wbolegality     1 = WBO legal, 0 = not, empty = unknown.",
        "  incompleteData  1 while a row still needs checking; set 0 when verified.",
        "  deleted         leave empty; put 'true' to hide a row without losing its dataID.",
        "  image / minifiedImage  paste a PNG INTO that row's cell (Insert > Pictures > Place in cell / over cell).",
        "",
        "Keep rows contiguous: the packager stops reading at the first completely blank row.",
        "Green headers = image columns, gold = ids/variants, blue = data, grey = bookkeeping.",
        "Dropdown values live in the Lists sheet; add new values there.",
        "_scrape_log (if present) records which wiki page each scraped row came from - the scraper uses it to avoid duplicates.",
    ],
    "products": [
        "BEYBLADE PRODUCTS & RELEASES WORKBOOK",
        "",
        "Products         every release you can buy: starters, boosters, random boosters, sets, launchers, stadiums, TCG packs...",
        "                 productID = 'P' + number (P1, P2 ...), unique and never reused.",
        "                 sku = release code (BX-01, UX-12, B-150) or the Hasbro item number (F9580).",
        "                 Variants: a random booster's individual items, store-exclusive recolors, region versions ->",
        "                 own row with parentProductId = the base productID and variantLabel ('06', 'Hasbro US', 'Black Ver.').",
        "                 manufacturer: Takara-Tomy or Hasbro (same release in both = two rows, one per manufacturer).",
        "Accessories      launchers, grips, stadiums, cases, tools, winders. dataID = whole number. Same parent/variant rule.",
        "ProductContents  one row per thing inside a product: productID, partType (sheet name, e.g. Parts_X_Blades or",
        "                 Accessories, TCG_Cards), partDataID (the dataID in that sheet), quantity.",
        "CodeSeries       the release-code series per manufacturer + generation. sequential=1 means codes count up",
        "                 (BX-54 -> BX-55), which the scraper's update mode uses to look for the next releases.",
        "                 lastKnownCode is filled in by the scraper for information.",
        "",
        "itemCost is a plain number; put the currency in the currency column (JPY, USD...).",
        "releaseDate: YYYY-MM-DD.",
        "Keep rows contiguous: the packager stops at the first blank row.",
    ],
    "tcg": [
        "BEYBLADE TCG WORKBOOK",
        "",
        "hobbyName is 'Beyblade TCG' on every row: the card game is its own hobby in the app",
        "(own catalog, own image and data packs), separate from the 'Beyblade' parts and products.",
        "Holds every Beyblade card game, told apart by hobbyGeneration:",
        "  Original = the V-Force TCG (Blade / Bit-Beast cards with Battle Edge, Spin Strength, Game Text, Lore)",
        "  X        = the Beyblade X TCG (not released yet)",
        "Columns a game doesn't use stay empty (e.g. battleEdge for X, cost for the old game).",
        "",
        "TCG_Sets   one row per set/expansion. setID = 'S' + number. setCode = the code printed on cards (e.g. BXT01).",
        "           productID links to the booster/deck in the Products workbook if you have it.",
        "TCG_Cards  one row per card. dataID = whole number, unique, never reused.",
        "           cardNumber = number printed on the card, e.g. BXT01-001.",
        "           Variants (parallel/foil/alt-art/promo reprints): own row, parentCardId = dataID of the base card,",
        "           variantLabel = 'Parallel Foil', 'Alt Art' ... (same model as parts).",
        "           linkedPartType + linkedPartDataID: optional link to the physical part (e.g. Parts_X_Blades + 12).",
        "Card mechanics columns (cardType, attribute, cost, power, effectText) are generic; add columns at the end",
        "if the game needs more - the packager passes every column through.",
        "image / minifiedImage: paste the card scan into the row's cell.",
    ],
}


def now_iso():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def norm_name(s):
    return re.sub(r"[^a-z0-9]+", "", str(s or "").lower())


class Book:
    def __init__(self, path, kind):
        self.path, self.kind = path, kind
        self.backed_up = False
        self.dirty = not os.path.exists(path)
        if os.path.exists(path):
            self.wb = openpyxl.load_workbook(path)
            for ws in self.wb.worksheets:
                for img in ws._images:
                    # keep the original bytes: img._data() would re-encode WebP as PNG
                    raw = img.ref.getvalue() if hasattr(img.ref, "getvalue") else None
                    self._pin(img, raw or img._data())
        else:
            self.wb = openpyxl.Workbook()
            ws = self.wb.active
            ws.title = "README"
            for line in README[kind]:
                ws.append([line])
            ws["A1"].font = Font(bold=True, size=14)
            ws.column_dimensions["A"].width = 140
            self._lists_sheet()
        self._rows_cache = {}

    # ---- structure ------------------------------------------------------------------
    @staticmethod
    def _pin(img, data):
        """openpyxl closes an image's buffer on save; pin the bytes so we can save repeatedly."""
        img._data = lambda data=data: data

    def _lists_sheet(self):
        if "Lists" in self.wb.sheetnames:
            return self.wb["Lists"]
        ws = self.wb.create_sheet("Lists")
        for c, (name, values) in enumerate(S.lists().items(), 1):
            ws.cell(1, c, name).font = Font(bold=True)
            for r, val in enumerate(values, 2):
                ws.cell(r, c, val)
            ws.column_dimensions[get_column_letter(c)].width = 18
        return ws

    def _validation(self, ws, col_idx, list_name):
        names = list(S.lists())
        if list_name not in names:
            return
        lc = get_column_letter(names.index(list_name) + 1)
        n = len(S.lists()[list_name]) + 1
        dv = DataValidation(type="list", formula1=f"=Lists!${lc}$2:${lc}${n + 40}", allow_blank=True,
                            showErrorMessage=False)  # warn-free: humans may type new values
        L = get_column_letter(col_idx)
        dv.add(f"{L}2:{L}5000")
        ws.add_data_validation(dv)

    def sheet(self, name, columns, image_cols=None):
        """Get or create a sheet with these columns (+ image columns at the end)."""
        wanted = list(columns) + list(image_cols or ())
        if name not in self.wb.sheetnames:
            self.dirty = True
            ws = self.wb.create_sheet(name)
            ws.append(wanted)
            for i, col in enumerate(wanted, 1):
                cell = ws.cell(1, i)
                group = ("image" if image_cols and col in image_cols else
                         "id" if i == 1 else
                         "variant" if col.startswith("parent") or col == "variantLabel" else
                         "meta" if col in ("incompleteData", "updated_at", "deleted") else "data")
                cell.font = Font(bold=True, color="FFFFFF")
                cell.fill = PatternFill("solid", fgColor=HEAD_FILL[group])
                cell.alignment = Alignment(vertical="center", wrap_text=True)
                width = {"image": 16, "minifiedImage": 8, "minifiedBoxImage": 8, "boxImageUrl": 16,
                         "imageUrl": 16, "name": 22, "productName": 34, "description": 40, "edition": 26,
                         "effectText": 50, "setName": 28}.get(col, 13)
                ws.column_dimensions[get_column_letter(i)].width = width
                if col in S.DROPDOWNS:
                    self._validation(ws, i, S.DROPDOWNS[col])
            ws.freeze_panes = "B2"
            ws.row_dimensions[1].height = 30
        ws = self.wb[name]
        headers = [c.value for c in ws[1]]
        for col in wanted:
            if col not in headers:
                ws.cell(1, len(headers) + 1, col).font = Font(bold=True)
                self.dirty = True
                headers.append(col)
        return ws

    def part_sheet(self, gen, key):
        p = S.GENERATIONS[gen]["parts"][key]
        return self.sheet(S.part_sheet(gen, key), p["columns"], S.PART_IMAGE_COLS)

    def named_sheet(self, name):
        cfg = S.SHEETS[name]
        return self.sheet(name, cfg["columns"], cfg["images"])

    # ---- reading --------------------------------------------------------------------
    @staticmethod
    def headers(ws):
        return {c.value: i + 1 for i, c in enumerate(ws[1]) if c.value}

    def rows(self, ws):
        """[(row_number, {header: value})] for the contiguous block the packager will read."""
        if ws.title in self._rows_cache:
            return self._rows_cache[ws.title]
        hdr = self.headers(ws)
        out = []
        for r, vals in enumerate(ws.iter_rows(min_row=2, max_col=max(hdr.values()), values_only=True), 2):
            if not any(v not in (None, "") for v in vals):
                break
            out.append((r, {h: vals[i - 1] for h, i in hdr.items()}))
        self._rows_cache[ws.title] = out
        return out

    def find(self, ws, pred):
        for r, row in self.rows(ws):
            if pred(row):
                return r, row
        return None, None

    def next_id(self, ws, id_col, prefix=""):
        best = 0
        for _, row in self.rows(ws):
            m = re.search(r"(\d+)$", str(row.get(id_col) or ""))
            if m:
                best = max(best, int(m.group(1)))
        n = best + 1
        return f"{prefix}{n}" if prefix else n

    # ---- writing --------------------------------------------------------------------
    def write(self, ws, values, id_col=None, id_prefix="", row=None, overwrite=False, defaults=None):
        """Append (row=None) or update a row. Updates only fill empty cells unless overwrite.
        Returns (row_number, id, is_new)."""
        hdr = self.headers(ws)
        new = row is None
        if new:
            row = len(self.rows(ws)) + 2
            vals = dict(defaults or {})
            vals.update({k: v for k, v in values.items() if v not in (None, "")})
            if id_col and vals.get(id_col) in (None, ""):
                vals[id_col] = self.next_id(ws, id_col, id_prefix)
        else:
            vals = {k: v for k, v in values.items() if v not in (None, "")}
        for k, v in vals.items():
            if k not in hdr:
                continue
            cell = ws.cell(row, hdr[k])
            if new or overwrite or cell.value in (None, ""):
                if cell.value != v:
                    cell.value = v
                    self.dirty = True
        self._rows_cache.pop(ws.title, None)
        rid = ws.cell(row, hdr[id_col]).value if id_col else None
        return row, rid, new

    def has_image(self, ws, row, col_name):
        col = self.headers(ws).get(col_name)
        for img in ws._images:
            a = img.anchor
            if hasattr(a, "_from") and a._from.row + 1 == row and a._from.col + 1 == col:
                return True
        return False

    def set_image(self, ws, row, col_name, png, size="full", replace=False):
        if not png:
            return False
        col = self.headers(ws)[col_name]
        if self.has_image(ws, row, col_name):
            if not replace:
                return False
            ws._images = [i for i in ws._images if not (i.anchor._from.row + 1 == row and i.anchor._from.col + 1 == col)]
        img = XLImage(io.BytesIO(png))
        w = IMAGE_DISPLAY[size]
        img.height = max(1, int(img.height * w / img.width)) if img.width else w
        img.width = w
        img.anchor = OneCellAnchor(_from=AnchorMarker(col=col - 1, row=row - 1),
                                   ext=XDRPositiveSize2D(pixels_to_EMU(img.width), pixels_to_EMU(img.height)))
        self._pin(img, png)
        ws.add_image(img)
        self.dirty = True
        ws.row_dimensions[row].height = max(ws.row_dimensions[row].height or 15, img.height * 0.75 + 4)
        return True

    # ---- scrape log -----------------------------------------------------------------
    def log_sheet(self):
        if LOG_SHEET not in self.wb.sheetnames:
            ws = self.wb.create_sheet(LOG_SHEET)
            ws.append(LOG_COLUMNS)
            for c in ws[1]:
                c.font = Font(bold=True)
        return self.wb[LOG_SHEET]

    def log_index(self, target):
        """wikiTitle -> (sheet, id) for rows previously created by the scraper for this target (cached)."""
        cache = self.__dict__.setdefault("_log_cache", {})
        if target not in cache:
            out = {}
            if LOG_SHEET in self.wb.sheetnames:
                for row in self.wb[LOG_SHEET].iter_rows(min_row=2, values_only=True):
                    if row and row[0] == target:
                        out[row[3]] = (row[1], row[2])
            cache[target] = out
        return cache[target]

    def add_log(self, target, sheet, rid, title, url=None, revid=None, image_file=None):
        self.log_sheet().append([target, sheet, rid, title, url, revid, image_file, now_iso()])
        self.dirty = True
        self.log_index(target)[title] = (sheet, rid)

    def save(self):
        os.makedirs(os.path.dirname(os.path.abspath(self.path)), exist_ok=True)
        if os.path.exists(self.path) and not self.backed_up:
            shutil.copy2(self.path, self.path + ".bak")
            self.backed_up = True
        tmp = self.path + ".tmp.xlsx"
        self.wb.save(tmp)
        os.replace(tmp, self.path)
        self.dirty = False
