#!/usr/bin/env python3
"""
Checks the packaged catalog (data/*.json) against what the clasher_st app accepts, before it is released or
bundled. Used by build_release.py (blocks a release) and beyblade_data.py (report after packaging); can also
run alone:

    python catalog_check.py --data data

Why it matters - how the app treats the catalog:
  * downloadCatalogSheets() rejects a release that misses ANY of the APP_SHEETS below;
  * the bundled loader (loadPartsDataBundle) crashes the first launch if one of them is missing from assets;
  * rows are parsed when a screen reads them, and one row without a required field (requiredString) makes the
    whole part type unreadable (getAllBlades() throws) - after the update has already been applied;
  * rows are stored by dataID, so a duplicate silently replaces the other row;
  * ProductContents are resolved by JSON sheet key ('blades', 'accessories', ...);
  * stockCombos are resolved into a BeybladeLoadout: one top (a blade, or lock chip + core + assist blade), a bit,
    and parts that exist; bladers and 3D models are optional extras.

Errors block a release; warnings are printed. `drop_invalid()` removes the rows with errors instead.
"""
import argparse
import json
import sys
from pathlib import Path

import beyblade_schema as S

# AppConstants.trackedBeyBladeData - the sheets the app requires, in its parser's order.
APP_PART_SHEETS = ["blades", "ratchets", "bits", "lockChips", "overBlades", "metalBlades", "mainBlades",
                   "assistBlades"]
APP_SHEETS = APP_PART_SHEETS + ["products", "accessories", "productContents"]
# Read when present, never required (kOptionalCatalogSheets in the app).
OPTIONAL_SHEETS = ["tcgCards", "tcgSets", "codeSeries", "stockCombos", "bladers"]
# Optional sheets the beyblade feature parses with requiredString(): an empty required field breaks the sheet.
STRICT_OPTIONAL = {"stockCombos", "bladers"}
# Part types a ProductContents row may point at, as the app resolves them.
CONTENT_TYPES = set(APP_PART_SHEETS) | {"accessories"}
# Every other generation's part sheet key (burstLayers, metalFightFusionWheels ...): valid in the workbook, not
# shown by the app yet.
OTHER_GEN_PART_KEYS = {S.part_json_prefix(g, k) for g, k, _ in S.all_part_targets()} - set(APP_PART_SHEETS)
TYPED_PARTS = {"blades", "overBlades", "metalBlades", "mainBlades", "assistBlades"}


def required_fields(sheet):
    """The fields the app's models read with requiredString() for this JSON sheet, plus the columns the
    packaging profile marks required (Clasher Studio -> Publish -> Packaging)."""
    req = S.app_required(sheet)
    return req + [c for c in S.profile_required(sheet) if c not in req]


def id_field(sheet):
    return {"products": "productID", "productContents": None, "tcgSets": "setID", "codeSeries": None,
            "stockCombos": "stockComboID", "bladers": "bladerID"}.get(sheet, "dataID")


def _blank(v):
    return v is None or (isinstance(v, str) and not v.strip())


class Report:
    def __init__(self):
        self.errors = []    # (sheet, rowId, message)
        self.warnings = []
        self.bad_rows = {}  # sheet -> set(row index) with errors

    def error(self, sheet, i, row_id, msg):
        self.errors.append((sheet, row_id, msg))
        if i is not None:
            self.bad_rows.setdefault(sheet, set()).add(i)

    def warn(self, sheet, row_id, msg):
        self.warnings.append((sheet, row_id, msg))

    @property
    def ok(self):
        return not self.errors

    def print(self, log=print, limit=40):
        for title, items in (("ERRORS (the app would reject or break on these)", self.errors),
                             ("warnings", self.warnings)):
            if not items:
                continue
            log(f"{title}: {len(items)}")
            for sheet, rid, msg in items[:limit]:
                log(f"  {sheet}{'' if rid is None else f' #{rid}'}: {msg}")
            if len(items) > limit:
                log(f"  ... and {len(items) - limit} more")
        if self.ok and not self.warnings:
            log("catalog check: OK")


def check(sheets):
    """sheets: {json sheet name: rows}. -> Report"""
    r = Report()
    for name in APP_SHEETS:
        if name not in sheets:
            r.error(name, None, None, "sheet missing - the app rejects a release without it")
        elif not sheets[name]:
            r.warn(name, None, "no rows - the app would show no items of this type")
    for name in [n for n in APP_SHEETS + OPTIONAL_SHEETS if n in sheets]:
        rows = sheets[name]
        if not isinstance(rows, list):
            r.error(name, None, None, "not a JSON list")
            continue
        req = required_fields(name)
        idf = id_field(name)
        seen = {}
        for i, row in enumerate(rows):
            rid = row.get(idf) if idf else None
            missing = [f for f in req if _blank(row.get(f))]
            if missing and (name in APP_SHEETS or name in STRICT_OPTIONAL
                            or set(missing) & set(S.profile_required(name))):
                r.error(name, i, rid, f"empty required {', '.join(missing)}")
            elif name in ("tcgCards", "tcgSets") and (_blank(row.get(idf)) or _blank(row.get("name" if name == "tcgCards" else "setName"))):
                r.warn(name, rid, "no id or name - the app skips this row")
            if idf and not _blank(rid):
                key = str(rid).strip()
                if key in seen:
                    r.error(name, i, rid, f"duplicate {idf} (also row {seen[key] + 2}) - one would overwrite the other")
                else:
                    seen[key] = i
    _check_references(sheets, r)
    return r


def _check_references(sheets, r):
    ids = {n: {str(x.get("dataID")) for x in sheets.get(n, []) if isinstance(x, dict)}
           for n in APP_PART_SHEETS + ["accessories"]}
    for n in APP_PART_SHEETS + ["accessories"]:
        for row in sheets.get(n, []):
            parent = row.get("parentPartId")
            if not _blank(parent) and str(parent) not in ids[n]:
                r.warn(n, row.get("dataID"), f"parentPartId {parent} is not in {n}")
    products = {str(x.get("productID")) for x in sheets.get("products", [])}
    for i, row in enumerate(sheets.get("productContents", [])):
        pt, pid, did = row.get("partType"), str(row.get("productID")), str(row.get("partDataID"))
        if pt not in CONTENT_TYPES:
            # other generations' parts (burstLayers ...) aren't in the app yet - harmless, just not shown
            if pt not in OTHER_GEN_PART_KEYS:
                r.error("productContents", i, pid, f"partType {pt!r} is not one the app resolves "
                                                   f"({', '.join(sorted(CONTENT_TYPES))})")
            continue
        if pid not in products:
            r.warn("productContents", pid, "product not in products")
        if did not in ids.get(pt, set()):
            r.warn("productContents", pid, f"{pt} #{did} not found")
    _check_stock_combos(sheets, ids, products, r)
    _check_bladers(sheets, r)
    _check_models(sheets, r)


def _check_stock_combos(sheets, ids, products, r):
    """Each stock combo must resolve into a build the app can show (BeybladeLoadout + ResolveBeybladeUseCase)."""
    contents = {}
    for row in sheets.get("productContents", []):
        contents.setdefault(str(row.get("productID")), set()).add((row.get("partType"), str(row.get("partDataID"))))
    by_id = {n: {str(x.get("dataID")): x for x in sheets.get(n, []) if isinstance(x, dict)} for n in APP_PART_SHEETS}
    for i, row in enumerate(sheets.get("stockCombos", [])):
        rid, pid = row.get("stockComboID"), str(row.get("productID"))
        have = {c: str(row[c]).strip() for c in S.STOCK_COMBO_PART_COLUMNS if not _blank(row.get(c))}
        bad = []
        for col, sheet in S.STOCK_COMBO_PART_COLUMNS.items():
            if col in have and have[col] not in ids.get(sheet, set()):
                bad.append(f"{col} {have[col]} is not in {sheet}")
        unibody = "bladeDataID" in have
        custom = [c for c in ("lockChipDataID", "overBladeDataID", "metalBladeDataID", "mainBladeDataID",
                              "assistBladeDataID") if c in have]
        if unibody and custom:
            bad.append("has a blade AND custom line parts - use one or the other")
        elif not unibody:
            core_main, core_om = "mainBladeDataID" in have, {"overBladeDataID", "metalBladeDataID"} <= have.keys()
            if not custom:
                bad.append("no blade - set bladeDataID, or lockChipDataID + mainBladeDataID (or over + metal blade)"
                           " + assistBladeDataID")
            elif "lockChipDataID" not in have or "assistBladeDataID" not in have or core_main == core_om:
                bad.append("a custom line combo needs lockChipDataID, assistBladeDataID and either mainBladeDataID "
                           "or overBladeDataID + metalBladeDataID")
        for msg in bad:
            r.error("stockCombos", i, rid, msg + " - the app can't build this combo")
        if bad:
            continue
        if "ratchetDataID" not in have:
            blade = by_id["blades"].get(have.get("bladeDataID", ""), {})
            bit = by_id["bits"].get(have.get("bitDataID", ""), {})
            if not (blade.get("integratedRatchet") or bit.get("integratedRatchet")):
                r.warn("stockCombos", rid, "no ratchetDataID and neither the blade nor the bit has an integrated "
                                           "ratchet")
        if pid not in products:
            r.warn("stockCombos", rid, f"product {pid} not in products")
        elif pid in contents:
            missing = [f"{S.STOCK_COMBO_PART_COLUMNS[c]} #{v}" for c, v in have.items()
                       if (S.STOCK_COMBO_PART_COLUMNS[c], v) not in contents[pid]]
            if missing:
                r.warn("stockCombos", rid, f"not in product {pid}'s ProductContents: {', '.join(missing)}")


def _check_bladers(sheets, r):
    known = {str(x.get("bladerID")) for x in sheets.get("bladers", []) if isinstance(x, dict)}
    for n in APP_PART_SHEETS:
        for row in sheets.get(n, []):
            v = row.get(S.BLADER_IDS)
            if _blank(v):
                continue
            if not isinstance(v, list):
                r.warn(n, row.get("dataID"), f"{S.BLADER_IDS} should be a list (package with beyblade_data.py)")
                continue
            unknown = [b for b in v if str(b) not in known]
            if unknown:
                r.warn(n, row.get("dataID"), f"blader(s) {', '.join(map(str, unknown))} not in bladers")


def _check_models(sheets, r):
    for n, rows in sheets.items():
        if not isinstance(rows, list):
            continue
        idf = id_field(n)
        for row in rows:
            url = row.get("model3dUrl") if isinstance(row, dict) else None
            if _blank(url):
                continue
            if not str(url).lower().startswith("https://"):
                r.warn(n, row.get(idf) if idf else None, f"model3dUrl isn't https: {url}")
            elif not str(url).lower().split("?")[0].endswith(S.MODEL_3D_EXTS):
                r.warn(n, row.get(idf) if idf else None, f"model3dUrl doesn't end in .glb: {url}")


def drop_invalid(sheets, report):
    """Copy of sheets without the rows that have errors. -> (sheets, dropped count)"""
    out, dropped = {}, 0
    for name, rows in sheets.items():
        bad = report.bad_rows.get(name)
        if bad and isinstance(rows, list):
            out[name] = [x for i, x in enumerate(rows) if i not in bad]
            dropped += len(rows) - len(out[name])
        else:
            out[name] = rows
    return out, dropped


def load_sheets(data_dir):
    sheets = {}
    for p in sorted(Path(data_dir).glob("*.json")):
        if p.name == "manifest.json" or p.name.startswith("_"):
            continue
        sheets[p.stem] = json.loads(p.read_text(encoding="utf-8"))
    return sheets


def main(argv=None):
    ap = argparse.ArgumentParser(description="Check data/*.json against what the clasher_st app accepts")
    ap.add_argument("--data", default="data")
    a = ap.parse_args(argv)
    rep = check(load_sheets(a.data))
    rep.print()
    return 0 if rep.ok else 1


if __name__ == "__main__":
    sys.exit(main())
