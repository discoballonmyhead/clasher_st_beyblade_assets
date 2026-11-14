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
import glob
import io
import os
import re
import shutil
import zipfile
from copy import copy
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

HEAD_FILL = {"id": "7F6000", "variant": "806000", "data": "1F3864", "image": "375623", "meta": "595959",
             "custom": "7030A0"}  # custom = added with missing_data_tool
IMAGE_DISPLAY = {"full": 110, "min": 44}
BACKUPS_KEPT = 20
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
        "  simpleRatchet   (X Ratchets) 1 = a simple ratchet, 0 = not. Filled by hand (not on the wiki).",
        "  requiresSimpleRatchet  (X Blades, AssistBlades) 1 = only fits a simple ratchet; the app then offers",
        "                  only ratchets with simpleRatchet = 1. Filled by hand.",
        "  incompleteData  1 while a row still needs checking; set 0 when verified.",
        "  deleted         leave empty; put 'true' to hide a row without losing its dataID.",
        "  image / minifiedImage  a picture placed OVER that row's cell (Insert > Pictures > Place over Cells), or let",
        "                  the missing data tool put it there. Never 'Place in Cell': the tools can't keep those.",
        "  model3d         optional 3D model: a .glb file (path relative to this workbook's folder, e.g. models/dran.glb,",
        "                  or an absolute path) or an https link. Max 20 MB. The packager copies files to data/models/.",
        "  bladerIDs       (X Blades, LockChips) the bladers who use the part in the show: bladerIDs from the Bladers",
        "                  tab, separated by commas (BL1, BL4). Optional.",
        "",
        "Bladers          the characters who use parts in the show. bladerID = 'BL' + number, name, two optional",
        "                 pictures: image / minifiedImage (portrait) and fullBodyImage / minifiedFullBodyImage.",
        "",
        "Empty rows are skipped (the tools and the packager read every non-empty row).",
        "To remove a part, put 'true' in deleted (its dataID stays reserved); if you delete a row in Excel, use",
        "right-click > Delete, and pictures should be placed OVER cells, not 'Place in cell' (the tools can't keep those).",
        "Green headers = image columns, gold = ids/variants, blue = data, grey = bookkeeping.",
        "Dropdown values live in the Lists sheet; add new values there.",
        "_scrape_log (if present) records which wiki page each scraped row came from - the scraper uses it to avoid duplicates.",
        "Purple headers = columns added with the missing data tool (listed in _columns). _edit_log lists every change",
        "made with that tool: when, which tab/row/field, old and new value.",
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
        "StockCombos      the combos that come out of the box: one row per bey in a product (a set with 2 beys = 2 rows).",
        "                 stockComboID = 'SC' + number, productID, name (e.g. 'Dran Sword 3-60F'), then the parts:",
        "                 bladeDataID for a one-piece blade, or lockChipDataID + mainBladeDataID (or overBladeDataID +",
        "                 metalBladeDataID) + assistBladeDataID for a custom line build; ratchetDataID (empty only for an",
        "                 integrated ratchet) and bitDataID. Optional model3d (.glb path or https link) of the whole combo.",
        "CodeSeries       the release-code series per manufacturer + generation. sequential=1 means codes count up",
        "                 (BX-54 -> BX-55), which the scraper's update mode uses to look for the next releases.",
        "                 lastKnownCode is filled in by the scraper for information.",
        "",
        "itemCost is a plain number; put the currency in the currency column (JPY, USD...).",
        "releaseDate: YYYY-MM-DD.",
        "Empty rows are skipped; to remove a row use deleted = true.",
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


SPREADSHEET_DRAWING = "{http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing}"


def picture_count(path):
    """Pictures in an .xlsx's drawings (pic elements, whatever namespace prefix the writer used)."""
    import xml.etree.ElementTree as ET
    n = 0
    with zipfile.ZipFile(path) as z:
        for name in z.namelist():
            if name.startswith("xl/drawings/") and name.endswith(".xml") and "/_rels/" not in name:
                n += sum(1 for el in ET.fromstring(z.read(name)).iter(SPREADSHEET_DRAWING + "pic"))
    return n


def unkeepable_content(path, loaded_images):
    """What's in the file that openpyxl can't read back, so a save would drop it."""
    out = []
    try:
        with zipfile.ZipFile(path) as z:
            names = z.namelist()
            rich = [n for n in names if n.startswith("xl/richData/")]
            if rich:
                out.append("pictures placed IN cells (Excel 'Place in cell'). In Excel: select those pictures, "
                           "right-click > 'Place over Cells', save, then use the tool again")
            if any(n.startswith("xl/cellimages") for n in names):
                out.append("WPS in-cell pictures (cellimages). Float them over the cells first")
    except zipfile.BadZipFile:
        return ["the file isn't a valid .xlsx"]
    pics = picture_count(path)
    if pics > loaded_images:
        out.append(f"{pics - loaded_images} picture(s) this tool can't read (grouped, linked or another format)")
    return out


def backup(path):
    """Timestamped copy into <folder>/backups/, keeping the newest BACKUPS_KEPT per workbook."""
    folder = os.path.join(os.path.dirname(os.path.abspath(path)), "backups")
    os.makedirs(folder, exist_ok=True)
    stem = os.path.splitext(os.path.basename(path))[0]
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    dest = os.path.join(folder, f"{stem}-{stamp}.xlsx")
    n = 1
    while os.path.exists(dest):
        dest = os.path.join(folder, f"{stem}-{stamp}-{n}.xlsx")
        n += 1
    shutil.copy2(path, dest)
    for old in sorted(glob.glob(os.path.join(folder, f"{stem}-*.xlsx")))[:-BACKUPS_KEPT]:
        os.remove(old)
    return dest


class Book:
    def __init__(self, path, kind):
        self.path, self.kind = path, kind
        self.backed_up = False
        self.dirty = not os.path.exists(path)
        self.unsupported = []  # content in the file this library can't keep -> save() refuses
        if os.path.exists(path):
            self.wb = openpyxl.load_workbook(path)
            for ws in self.wb.worksheets:
                for img in ws._images:
                    # keep the original bytes: img._data() would re-encode WebP as PNG
                    raw = img.ref.getvalue() if hasattr(img.ref, "getvalue") else None
                    self._pin(img, raw or img._data())
            self.unsupported = unkeepable_content(path, self.image_count())
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
                         "fullBodyImage": 16, "minifiedFullBodyImage": 8, "model3d": 24, "bladerIDs": 14,
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
            if col not in headers:  # a newer schema column on an existing tab: appended, images stay put
                cell = ws.cell(1, len(headers) + 1, col)
                cell.font = Font(bold=True, color="FFFFFF")
                cell.fill = PatternFill("solid", fgColor=HEAD_FILL["data"])
                cell.alignment = Alignment(vertical="center", wrap_text=True)
                ws.column_dimensions[get_column_letter(len(headers) + 1)].width = 13
                if col in S.DROPDOWNS and "Lists" in self.wb.sheetnames:
                    self._validation(ws, len(headers) + 1, S.DROPDOWNS[col])
                self.dirty = True
                self.__dict__.get("_hdr_cache", {}).pop(name, None)
                self._rows_cache.pop(name, None)
                headers.append(col)
                self.__dict__.setdefault("added_columns", []).append((name, col))
        return ws

    def ensure_schema_columns(self):
        """Adds columns a newer schema defines to the part tabs this workbook already has.
        -> [(tab, column)] added (the workbook is then dirty)."""
        before = len(self.__dict__.get("added_columns", []))
        for name in list(self.wb.sheetnames):
            part = S.parse_part_sheet(name)
            if part and part[2]:
                self.part_sheet(part[0], part[1])
        return self.__dict__.get("added_columns", [])[before:]

    def part_sheet(self, gen, key):
        p = S.GENERATIONS[gen]["parts"][key]
        return self.sheet(S.part_sheet(gen, key), p["columns"], S.PART_IMAGE_COLS)

    def named_sheet(self, name):
        cfg = S.SHEETS[name]
        return self.sheet(name, cfg["columns"], [c for pair in S.image_pairs(name) for c in pair])

    # ---- reading --------------------------------------------------------------------
    def headers(self, ws):
        """{column name: column number} - cached per sheet (cleared when sheet() adds a column)."""
        cache = self.__dict__.setdefault("_hdr_cache", {})
        if ws.title not in cache:
            cache[ws.title] = {c.value: i + 1 for i, c in enumerate(ws[1]) if c.value}
        return cache[ws.title]

    def rows(self, ws):
        """[(row_number, {header: value})] for every non-empty row. Empty rows are skipped, not treated as the
        end: a cleared row in the middle used to hide everything below it."""
        if ws.title in self._rows_cache:
            return self._rows_cache[ws.title]
        hdr = self.headers(ws)
        out = []
        for r, vals in enumerate(ws.iter_rows(min_row=2, max_col=max(hdr.values()), values_only=True), 2):
            if any(v not in (None, "") for v in vals):
                out.append((r, {h: vals[i - 1] for h, i in hdr.items()}))
        self._rows_cache[ws.title] = out
        return out

    def next_row(self, ws):
        """Where a new row goes: after the last non-empty one (never into a gap, never over data)."""
        rows = self.rows(ws)
        return (rows[-1][0] if rows else 1) + 1

    def gaps(self, ws):
        """Empty rows between data rows (harmless now, but worth tidying in Excel)."""
        nums = [r for r, _ in self.rows(ws)]
        return [r for a, b in zip(nums, nums[1:]) for r in range(a + 1, b)]

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
            row = self.next_row(ws)
            vals = dict(defaults or {})
            vals.update({k: v for k, v in values.items() if v not in (None, "")})
            if id_col and vals.get(id_col) in (None, ""):
                vals[id_col] = self.next_id(ws, id_col, id_prefix)
        else:
            vals = {k: v for k, v in values.items() if v not in (None, "")}
        changed = False
        for k, v in vals.items():
            if k not in hdr or k == "updated_at":
                continue
            cell = ws.cell(row, hdr[k])
            if new or overwrite or cell.value in (None, ""):
                if cell.value != v:
                    cell.value = v
                    changed = True
        if changed:
            self.touch(ws, row)
        self._refresh_cached_row(ws, row, new)
        rid = ws.cell(row, hdr[id_col]).value if id_col else None
        return row, rid, new

    def touch(self, ws, row):
        """Row changed: stamp updated_at (last edited, UTC) and mark the workbook for saving."""
        self.dirty = True
        col = self.headers(ws).get("updated_at")
        if col and row > 1:
            ws.cell(row, col).value = now_iso()
            self._refresh_cached_row(ws, row, False)

    def _refresh_cached_row(self, ws, row, new):
        """Keep the rows() cache current instead of re-reading the whole sheet after every write."""
        cache = self._rows_cache.get(ws.title)
        if cache is None:
            return
        hdr = self.headers(ws)
        vals = {h: ws.cell(row, i).value for h, i in hdr.items()}
        if new and (not cache or cache[-1][0] == row - 1):
            cache.append((row, vals))
            return
        for i, (r, _) in enumerate(cache):
            if r == row:
                cache[i] = (row, vals)
                return
        self._rows_cache.pop(ws.title, None)  # unexpected shape: rebuild on next read

    def image_index(self, ws):
        """{(row, col): image} for a sheet - built once, kept current by set_image()."""
        idx = self.__dict__.setdefault("_img_idx", {})
        if ws.title not in idx:
            idx[ws.title] = {(i.anchor._from.row + 1, i.anchor._from.col + 1): i
                             for i in ws._images if hasattr(i.anchor, "_from")}
        return idx[ws.title]

    def has_image(self, ws, row, col_name):
        col = self.headers(ws).get(col_name)
        return (row, col) in self.image_index(ws)

    def set_image(self, ws, row, col_name, png, size="full", replace=False):
        if not png:
            return False
        col = self.headers(ws)[col_name]
        index = self.image_index(ws)
        if (row, col) in index:
            if not replace:
                return False
            old = index.pop((row, col))
            ws._images = [i for i in ws._images if i is not old]
        img = XLImage(io.BytesIO(png))
        w = IMAGE_DISPLAY[size]
        img.height = max(1, int(img.height * w / img.width)) if img.width else w
        img.width = w
        img.anchor = OneCellAnchor(_from=AnchorMarker(col=col - 1, row=row - 1),
                                   ext=XDRPositiveSize2D(pixels_to_EMU(img.width), pixels_to_EMU(img.height)))
        self._pin(img, png)
        ws.add_image(img)
        index[(row, col)] = img
        self.touch(ws, row)
        ws.row_dimensions[row].height = max(ws.row_dimensions[row].height or 15, img.height * 0.75 + 4)
        return True

    # ---- custom columns + change log (missing_data_tool) -------------------------------
    def add_column(self, ws, name):
        """Append a column after the last one (images stay anchored where they are). -> column number"""
        hdr = self.headers(ws)
        if name in hdr:
            raise ValueError(f"{ws.title} already has a column '{name}'")
        col = max(hdr.values()) + 1
        cell = ws.cell(1, col, name)
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = PatternFill("solid", fgColor=HEAD_FILL["custom"])
        cell.alignment = Alignment(vertical="center", wrap_text=True)
        ws.column_dimensions[get_column_letter(col)].width = 14
        self._forget(ws)
        return col

    def remove_column(self, ws, col):
        """Undo of add_column: clear the header and every value in that column."""
        for r in range(1, ws.max_row + 1):
            ws.cell(r, col).value = None
        ws.cell(1, col).fill = PatternFill(fill_type=None)
        self._forget(ws)

    def clear_row(self, ws, row):
        """Undo of an appended row: empty every cell and drop its images."""
        for c in range(1, ws.max_column + 1):
            ws.cell(row, c).value = None
        idx = self.image_index(ws)
        gone = [k for k in idx if k[0] == row]
        for k in gone:
            img = idx.pop(k)
            ws._images = [i for i in ws._images if i is not img]
        self._forget(ws)

    def delete_row(self, ws, row):
        """Removes a row the way Excel's right-click -> Delete does, but keeps everything aligned: rows below move
        up together with their pictures and heights. -> snapshot for insert_row() (values, styles, height,
        pictures as {column: bytes})"""
        hdr_n = ws.max_column
        snap = {"values": [ws.cell(row, c).value for c in range(1, hdr_n + 1)],
                "styles": [copy(ws.cell(row, c)._style) for c in range(1, hdr_n + 1)],
                "height": ws.row_dimensions[row].height, "pictures": {}}
        here = []
        for i in ws._images:
            if hasattr(i.anchor, "_from") and i.anchor._from.row == row - 1:
                snap["pictures"][i.anchor._from.col + 1] = i._data()
                here.append(i)
        self.remove_pictures(ws, here)
        heights = {r: (d.height, d.hidden) for r, d in list(ws.row_dimensions.items()) if r > row}
        ws.delete_rows(row, 1)
        for i in ws._images:
            a = i.anchor
            if hasattr(a, "_from") and a._from.row >= row:
                a._from.row -= 1
                if getattr(a, "to", None) is not None:
                    a.to.row -= 1
        for r in sorted(heights):
            h, hidden = heights[r]
            ws.row_dimensions[r - 1].height, ws.row_dimensions[r - 1].hidden = h, hidden
        if heights:
            last = max(heights)
            ws.row_dimensions[last].height, ws.row_dimensions[last].hidden = None, False
        self._after_shift(ws)
        return snap

    def insert_row(self, ws, row, snap):
        """Puts a row deleted with delete_row() back where it was (undo)."""
        heights = {r: (d.height, d.hidden) for r, d in list(ws.row_dimensions.items()) if r >= row}
        ws.insert_rows(row, 1)
        for i in ws._images:
            a = i.anchor
            if hasattr(a, "_from") and a._from.row >= row - 1:
                a._from.row += 1
                if getattr(a, "to", None) is not None:
                    a.to.row += 1
        for r in sorted(heights, reverse=True):
            h, hidden = heights[r]
            ws.row_dimensions[r + 1].height, ws.row_dimensions[r + 1].hidden = h, hidden
        self._after_shift(ws)
        names = {v: k for k, v in self.headers(ws).items()}
        for col, data in snap["pictures"].items():
            name = str(names.get(col) or "")
            self.put_picture(ws, row, col, data, "min" if "mini" in name.lower() else "full")
        for c, (v, st) in enumerate(zip(snap["values"], snap["styles"]), 1):
            cell = ws.cell(row, c)
            cell.value = v
            cell._style = copy(st)
        ws.row_dimensions[row].height = snap["height"]
        self._after_shift(ws)

    def put_picture(self, ws, row, col, data, size="full"):
        """A picture anchored at (row, col) with its own size (no updated_at stamp)."""
        img = XLImage(io.BytesIO(data))
        w = IMAGE_DISPLAY[size]
        img.height = max(1, int(img.height * w / img.width)) if img.width else w
        img.width = w
        img.anchor = OneCellAnchor(_from=AnchorMarker(col=col - 1, row=row - 1),
                                   ext=XDRPositiveSize2D(pixels_to_EMU(img.width), pixels_to_EMU(img.height)))
        self._pin(img, data)
        ws.add_image(img)
        self.__dict__.get("_img_idx", {}).pop(ws.title, None)
        rd = ws.row_dimensions[row]
        rd.height = max(rd.height or 15, img.height * 0.75 + 4)
        return img

    def _after_shift(self, ws):
        self.__dict__.get("_img_idx", {}).pop(ws.title, None)
        self.__dict__.get("_next_row", {}).pop(ws.title, None)
        self._forget(ws)

    def _forget(self, ws):
        self.dirty = True
        self.__dict__.get("_hdr_cache", {}).pop(ws.title, None)
        self._rows_cache.pop(ws.title, None)
        if ws.title == S.CUSTOM_COLUMNS_SHEET:
            self.__dict__.pop("_custom_cols", None)

    def custom_columns(self):
        """{sheet: {column: {"optional", "inherit", "note", "addedAt", "source"}}} from the _columns tab."""
        cache = self.__dict__.get("_custom_cols")
        if cache is None:
            cache = {}
            if S.CUSTOM_COLUMNS_SHEET in self.wb.sheetnames:
                for _, x in self.rows(self.wb[S.CUSTOM_COLUMNS_SHEET]):
                    if x.get("sheet") and x.get("column"):
                        cache.setdefault(x["sheet"], {})[x["column"]] = {
                            "optional": str(x.get("optional") or "").strip().lower() in ("1", "true", "yes"),
                            "inherit": str(x.get("inherit") or "").strip().lower() in ("1", "true", "yes"),
                            "note": x.get("note") or "", "addedAt": str(x.get("addedAt") or ""),
                            "source": x.get("source") or ""}
            self._custom_cols = cache
        return cache

    def append_rows(self, sheet_name, columns, entries):
        """Append dicts to a bookkeeping tab (created on first use). -> row numbers written"""
        ws = self.sheet(sheet_name, columns)
        nxt = self.__dict__.setdefault("_next_row", {})
        if sheet_name not in nxt:
            nxt[sheet_name] = self.next_row(ws)
        hdr = self.headers(ws)
        start = nxt[sheet_name]
        for i, e in enumerate(entries):
            for k, v in e.items():
                if k in hdr:
                    ws.cell(start + i, hdr[k]).value = v
        nxt[sheet_name] = start + len(entries)
        self._rows_cache.pop(ws.title, None)
        if sheet_name == S.CUSTOM_COLUMNS_SHEET:
            self.__dict__.pop("_custom_cols", None)
        self.dirty = True
        return list(range(start, start + len(entries)))

    def remove_appended(self, sheet_name, rows):
        """Undo of append_rows (rows are the last ones written)."""
        if sheet_name not in self.wb.sheetnames or not rows:
            return
        ws = self.wb[sheet_name]
        for r in rows:
            for c in range(1, ws.max_column + 1):
                ws.cell(r, c).value = None
        nxt = self.__dict__.setdefault("_next_row", {})
        nxt[sheet_name] = min(min(rows), nxt.get(sheet_name, min(rows)))
        self._forget(ws)

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

    def pictures_at(self, ws, row, col):
        """Every picture anchored at this cell (more than one when pictures got stacked)."""
        return [i for i in ws._images if hasattr(i.anchor, "_from")
                and (i.anchor._from.row + 1, i.anchor._from.col + 1) == (row, col)]

    def remove_pictures(self, ws, pictures):
        drop = {id(i) for i in pictures}
        ws._images = [i for i in ws._images if id(i) not in drop]
        self.__dict__.get("_img_idx", {}).pop(ws.title, None)

    def normalize_pictures(self):
        """Gives every picture its own size, anchored to its cell, the way set_image() writes them.
        Pictures Excel saved are sized by the cells they span ("two-cell" anchors), so deleting or resizing
        rows and columns can shrink them to nothing: still in the file, invisible in Excel. -> pictures fixed"""
        from PIL import Image as PILImage
        fixed = 0
        min_px = pixels_to_EMU(8)
        for ws in self.wb.worksheets:
            names = {v: k for k, v in self.headers(ws).items()} if ws.max_row else {}
            for img in ws._images:
                a = img.anchor
                if not hasattr(a, "_from"):
                    continue
                if isinstance(a, OneCellAnchor) and a.ext is not None \
                        and a.ext.width >= min_px and a.ext.height >= min_px:
                    continue
                try:
                    pw, ph = PILImage.open(io.BytesIO(img._data())).size
                except Exception:
                    pw, ph = img.width or 1, img.height or 1
                name = str(names.get(a._from.col + 1) or "")
                w = IMAGE_DISPLAY["min" if "mini" in name.lower() else "full"]
                h = max(1, int(ph * w / pw)) if pw else w
                img.width, img.height = w, h
                img.anchor = OneCellAnchor(_from=AnchorMarker(col=a._from.col, row=a._from.row),
                                           ext=XDRPositiveSize2D(pixels_to_EMU(w), pixels_to_EMU(h)))
                rd = ws.row_dimensions[a._from.row + 1]
                rd.height = max(rd.height or 15, h * 0.75 + 4)
                rd.hidden = False
                fixed += 1
        return fixed

    def anchor_report(self, ws):
        """{"oneCell": n, "twoCell": n, "absolute": n, "tiny": n} - how the pictures of a tab are placed."""
        out = {"oneCell": 0, "twoCell": 0, "absolute": 0, "tiny": 0}
        min_px = pixels_to_EMU(8)
        for i in ws._images:
            a = i.anchor
            kind = type(a).__name__
            if kind == "OneCellAnchor":
                out["oneCell"] += 1
                if a.ext is None or a.ext.width < min_px or a.ext.height < min_px:
                    out["tiny"] += 1
            elif kind == "TwoCellAnchor":
                out["twoCell"] += 1
                if a.to is not None and (a.to.row, a.to.rowOff) <= (a._from.row, a._from.rowOff + min_px // 2):
                    out["tiny"] += 1
                elif a.to is not None and (a.to.col, a.to.colOff) <= (a._from.col, a._from.colOff + min_px // 2):
                    out["tiny"] += 1
            else:
                out["absolute"] += 1
        return out

    def image_count(self):
        return sum(len(ws._images) for ws in self.wb.worksheets)

    def save(self):
        """Writes the workbook - but never one that would lose pictures:
          * refuses when the file has pictures this library can't keep (Excel "Place in cell" pictures ...);
          * writes to a temp file, checks every picture is in it, and only then replaces the workbook;
          * keeps a timestamped copy of the previous file in backups/ (last BACKUPS_KEPT) plus the .bak."""
        if self.unsupported:
            raise RuntimeError("Not saved - saving would lose part of this workbook:\n  "
                               + "\n  ".join(self.unsupported)
                               + "\nThe file on disk is unchanged.")
        os.makedirs(os.path.dirname(os.path.abspath(self.path)), exist_ok=True)
        tmp = self.path + ".tmp.xlsx"
        self.normalize_pictures()
        self.wb.save(tmp)
        expected = self.image_count()
        written = picture_count(tmp)
        if written < expected:
            os.remove(tmp)
            raise RuntimeError(f"Not saved - the written file had {written} pictures instead of {expected}. "
                               "The file on disk is unchanged.")
        if os.path.exists(self.path):
            backup(self.path)
            if not self.backed_up:
                shutil.copy2(self.path, self.path + ".bak")
                self.backed_up = True
        os.replace(tmp, self.path)
        self.dirty = False
