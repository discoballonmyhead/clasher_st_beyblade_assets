#!/usr/bin/env python3
"""
Single source of truth for the Beyblade data store layout.

Used by:
  * make_sample_workbooks.py  - builds the 3 human-managed workbooks
  * fandom_scraper.py         - fills them from the wiki
  * beyblade_data.py          - packages them into data/*.json + images

THE THREE WORKBOOKS
  1. beyblade_parts.xlsx     one sheet per generation + part type: Parts_<Gen>_<Type>
                             e.g. Parts_X_Blades, Parts_Burst_Layers, Parts_Metal_FusionWheels
  2. beyblade_products.xlsx  Products (every release: starters, boosters, sets, launchers,
                             stadiums...), Accessories (launchers, stadiums, grips, cases...),
                             ProductContents (what is inside each product), CodeSeries (the
                             release-code series per manufacturer/generation used by the updater)
  3. beyblade_tcg.xlsx       TCG_Sets, TCG_Cards

ID MODEL (same everywhere)
  dataID         integer per sheet. The missing data tool can renumber a tab to 1..N (it asks first, and
                 updates parent ids, ProductContents and TCG card links) - ids already released to the app
                 then point at other parts, so renumber before a release, not after
  parent...Id    empty for a base item; for a variant it holds the dataID/productID of the base
  variantLabel   what makes the variant different ("Metal Coat: Black", "06", "Parallel Foil")
"""
import json
import os
import re
from collections import OrderedDict

HOBBY_NAME = "Beyblade"

# Bookkeeping tabs written by missing_data_tool.py (never packaged as catalog data):
#   _edit_log  one row per change made with the tool (cell, auto-fill, image, new row/column, wiki fill)
#   _columns   columns people added to a tab with the tool, and how the tool treats them
EDIT_LOG_SHEET = "_edit_log"
EDIT_LOG_COLUMNS = ["at", "source", "action", "sheet", "rowId", "field", "oldValue", "newValue", "note"]
# _deleted  rows deleted with the tool (values as JSON + their pictures), until restored or emptied
DELETED_SHEET = "_deleted"
DELETED_COLUMNS = ["key", "deletedAt", "source", "sheet", "rowId", "name", "values"]
DELETED_IMAGE_COLS = ("image", "minifiedImage")
CUSTOM_COLUMNS_SHEET = "_columns"
CUSTOM_COLUMNS_COLUMNS = ["sheet", "column", "optional", "inherit", "note", "addedAt", "source"]
# The card game is its own hobby in the app (separate catalog, separate image/data packs),
# so its rows carry a different hobbyName. Generation still says which series ("Original" = V-Force TCG, "X").
TCG_HOBBY_NAME = "Beyblade TCG"
HOBBIES = [HOBBY_NAME, TCG_HOBBY_NAME]
MANUFACTURERS = ["Takara-Tomy", "Hasbro"]  # the only two, for all four series
REGIONS = ["JP", "US", "EU", "KR", "Global", "Other"]
CURRENCIES = ["JPY", "USD", "EUR", "KRW", "GBP", "CAD", "AUD"]
BEY_TYPES = ["attack", "defense", "stamina", "balance"]
SPIN_DIRS = ["right", "left", "both"]
YES_NO = [0, 1]
# Simple ratchets: some X blades / assist blades only fit a "simple" ratchet. Not on the wiki - filled by hand
# (missing_data_tool.py); the app only offers simple ratchets for a part that needs one.
SIMPLE_RATCHET = "simpleRatchet"                    # ratchets: 1 = this is a simple ratchet
REQUIRES_SIMPLE_RATCHET = "requiresSimpleRatchet"   # blades / assist blades: 1 = needs a simple ratchet
# 0/1 columns: the tools accept 1/0, true/false, yes/no and store 1 or 0
FLAG_COLUMNS = {"incompleteData", "wbolegality", "integratedRatchet", "twoStat", "sequential",
                SIMPLE_RATCHET, REQUIRES_SIMPLE_RATCHET}

# -----------------------------------------------------------------------------
# GENERATIONS -> part types (sheet suffix, label, extra columns, wiki words)
# -----------------------------------------------------------------------------
PART_HEAD = ["dataID", "parentPartId", "variantLabel", "manufacturer", "hobbyName",
             "hobbyGeneration", "code", "name", "edition"]
PART_TAIL = ["mass", "wbolegality", "incompleteData", "updated_at", "deleted"]
STATS = ["attack", "defense", "stamina"]
BLADE_LIKE = ["type", "spinDir"] + STATS
PART_IMAGE_COLS = ("image", "minifiedImage")


def _pt(sheet, label, extra, words, categories=None):
    """sheet: suffix of Parts_<Gen>_<sheet>; words: what the wiki/product pages call it."""
    return {"sheet": sheet, "label": label, "columns": PART_HEAD + extra + PART_TAIL,
            "words": words, "categories": categories or [label + "s"]}


# The four Beyblade series. Each has its own part types; "system" says which system inside the series
# a part belongs to (Plastic / HMS, Hybrid Wheel / 4D / Zero-G, Dual / God / ... / QuadDrive, ...).
# "signals" let the scraper tell which series a wiki page belongs to (series/system names, codes).
GENERATIONS = OrderedDict([
    ("Original", {
        "label": "Beyblade original series: Bakuten Shoot / V-Force / G-Revolution, plastic + HMS (1999-2004)",
        "signals": {"codes": ["A", "MA"],
                    "words": r"bakuten|plastic gen|original series|engine gear|magnacore|spin gear system|"
                             r"heavy metal|\bhms\b|v-?force|g-?revolution|first generation"},
        "parts": OrderedDict([
            ("bitChips",     _pt("BitChips", "Bit Chip", ["system"], ["bit chip", "bit-chip"])),
            ("attackRings",  _pt("AttackRings", "Attack Ring", ["system", "type", "spinDir"], ["attack ring", "ar"])),
            ("weightDisks",  _pt("WeightDisks", "Weight Disk", ["system"], ["weight disk", "weight disc", "wd"])),
            ("spinGears",    _pt("SpinGears", "Spin Gear", ["system", "spinDir"], ["spin gear", "sg"])),
            ("bladeBases",   _pt("BladeBases", "Blade Base", ["system", "type"], ["blade base", "bb", "base"])),
            ("runningCores", _pt("RunningCores", "Running Core", ["system", "type"], ["running core", "rc"])),
        ]),
    }),
    ("Metal", {
        "label": "Beyblade Metal series: Metal Fusion / Masters / Fury, 4D, Shogun Steel / Zero-G (2008-2013)",
        "signals": {"codes": ["BB", "BBG"],
                    "words": r"metal fight|metal fusion|metal masters|metal fury|metal saga|hybrid wheel|"
                             r"\b4d\b|zero-?g|shogun steel|synchrome"},
        "parts": OrderedDict([
            # Zero-G pieces live with their Metal counterparts (system = "Zero-G"):
            # Stone Face -> faceBolts, Crystal Wheel -> energyRings, Chrome Wheel -> fusionWheels, Bottom -> tips
            ("faceBolts",       _pt("FaceBolts", "Face Bolt", ["system"], ["face bolt", "stone face", "face"])),
            ("energyRings",     _pt("EnergyRings", "Energy Ring", ["system"],
                                    ["energy ring", "clear wheel", "crystal wheel"])),
            ("fusionWheels",    _pt("FusionWheels", "Fusion Wheel", ["system", "type", "spinDir"] + STATS,
                                    ["fusion wheel", "metal wheel", "chrome wheel", "wheel"])),
            ("spinTracks",      _pt("SpinTracks", "Spin Track", ["system", "heightMm"] + STATS, ["spin track", "track"])),
            ("performanceTips", _pt("PerformanceTips", "Performance Tip", ["system", "movementStyle"] + STATS,
                                    ["performance tip", "bottom", "tip"])),
        ]),
    }),
    ("Burst", {
        "label": "Beyblade Burst series (2015-2023)",
        "signals": {"codes": ["B"],
                    "words": r"\bburst\b|cho-?z|gatinko|sparking|superking|dynamite battle|quaddrive|quadstrike|"
                             r"god layer|dual layer|single layer|hypersphere|speedstorm|slingshock"},
        "parts": OrderedDict([
            # layerComponent: full | chip | weight | base | ring | chassis | core | armor | blade
            # (one sheet for every system's layer pieces keeps it simple)
            ("layers",  _pt("Layers", "Layer", ["system", "layerComponent"] + BLADE_LIKE,
                            ["layer", "energy layer", "chip", "ring", "chassis", "core", "armor", "blade",
                             "weight", "base"],
                            ["Energy Layers", "Layers"])),
            ("discs",   _pt("Discs", "Disc", ["system", "discType"], ["disc", "forge disc", "core disc"],
                            ["Forge Discs", "Discs"])),
            ("frames",  _pt("Frames", "Frame", ["system"], ["frame", "disc frame"], ["Disc Frames", "Frames"])),
            ("drivers", _pt("Drivers", "Driver", ["system", "movementStyle"] + STATS,
                            ["driver", "performance tip", "tip"], ["Performance Tips", "Drivers"])),
        ]),
    }),
    ("X", {
        "label": "Beyblade X series (2023-)",
        "signals": {"codes": ["BX", "UX", "CX", "RX", "BXG"],
                    "words": r"beyblade x\b|basic line|unique line|custom line|xtreme"},
        "parts": OrderedDict([  # column orders mirror the existing data/*.json exactly
            ("blades",       {"sheet": "Blades", "label": "Blade", "words": ["blade"],
                              "categories": ["Beyblade X Blades", "Blades (Beyblade X)"],
                              "columns": PART_HEAD + BLADE_LIKE + ["integratedRatchet", "requiresSimpleRatchet"]
                              + PART_TAIL}),
            ("ratchets",     {"sheet": "Ratchets", "label": "Ratchet", "words": ["ratchet"],
                              "categories": ["Ratchets"],
                              "columns": PART_HEAD + ["protrusions", "heightMm", "simpleRatchet"] + STATS + PART_TAIL}),
            ("bits",         {"sheet": "Bits", "label": "Bit", "words": ["bit"], "categories": ["Bits"],
                              "columns": PART_HEAD + ["baseName", "movementStyle"] + STATS +
                              ["dash", "burstRes", "twoStat", "integratedRatchet"] + PART_TAIL}),
            ("lockChips",    {"sheet": "LockChips", "label": "Lock Chip", "words": ["lock chip"],
                              "categories": ["Lock Chips"], "columns": PART_HEAD + PART_TAIL}),
            ("overBlades",   {"sheet": "OverBlades", "label": "Over Blade", "words": ["over blade"],
                              "categories": ["Over Blades"], "columns": PART_HEAD + BLADE_LIKE + PART_TAIL}),
            ("metalBlades",  {"sheet": "MetalBlades", "label": "Metal Blade", "words": ["metal blade"],
                              "categories": ["Metal Blades"], "columns": PART_HEAD + BLADE_LIKE + PART_TAIL}),
            ("mainBlades",   {"sheet": "MainBlades", "label": "Main Blade", "words": ["main blade"],
                              "categories": ["Main Blades"], "columns": PART_HEAD + BLADE_LIKE + PART_TAIL}),
            ("assistBlades", {"sheet": "AssistBlades", "label": "Assist Blade", "words": ["assist blade"],
                              "categories": ["Assist Blades"],
                              "columns": PART_HEAD + BLADE_LIKE + ["requiresSimpleRatchet"] + PART_TAIL}),
        ]),
    }),
])
GENERATION_NAMES = list(GENERATIONS)
for _g, _gd in GENERATIONS.items():  # Excel refuses sheet names longer than 31 characters
    for _k, _p in _gd["parts"].items():
        assert len(f"Parts_{_g}_{_p['sheet']}") <= 31, (_g, _k)


def part_sheet(gen, key):
    return f"Parts_{gen}_{GENERATIONS[gen]['parts'][key]['sheet']}"


def part_json_prefix(gen, key):
    """X keeps the original file names (blades.json ...); other generations are prefixed
    (burstLayers.json, metalFightFusionWheels.json) so nothing collides."""
    if gen == "X":
        return key
    g = gen.lower() if gen.isupper() else gen[0].lower() + gen[1:]
    return g + key[0].upper() + key[1:]


def all_part_targets():
    for gen, g in GENERATIONS.items():
        for key, p in g["parts"].items():
            yield gen, key, p


def parse_part_sheet(sheet_name):
    """'Parts_X_Blades' -> ('X', 'blades', columns) ; unknown -> None"""
    for gen, key, p in all_part_targets():
        if part_sheet(gen, key) == sheet_name:
            return gen, key, p
    m = re.match(r"^Parts_([A-Za-z0-9]+)_([A-Za-z0-9]+)$", sheet_name or "")
    if m:  # a sheet the user added themselves - still package it
        gen, suffix = m.groups()
        key = suffix[0].lower() + suffix[1:]
        return gen, key, None
    return None

# -----------------------------------------------------------------------------
# PRODUCTS WORKBOOK
# -----------------------------------------------------------------------------
PRODUCT_TYPES = ["Starter", "Booster", "Random Booster", "Set", "Battle Set", "Deck Set", "Entry Set",
                 "Customize Set", "Launcher", "Launcher Grip", "Stadium", "Case", "Tool", "Accessory Set",
                 "Battle Pass", "Limited", "Prize", "TCG Booster", "TCG Starter Deck", "TCG Accessory", "Other"]
# Must match the app's AccessoryType.parse (lower-cased, no spaces): stadium, launcher, grip, deckbox,
# battlepass. Anything else is read as "unknown" by the app.
ACCESSORY_TYPES = ["Stadium", "Launcher", "Grip", "DeckBox", "BattlePass", "Other"]
# product types that are themselves an accessory -> also get an Accessories row (value = accessoryType)
ACCESSORY_PRODUCT_TYPES = {"Launcher": "Launcher", "Launcher Grip": "Grip", "Stadium": "Stadium",
                           "Case": "DeckBox", "Battle Pass": "BattlePass"}

# Columns the app's models read with requiredString(); the packager warns when they're empty.
APP_REQUIRED = {
    "_part": ["dataID", "manufacturer", "hobbyName", "hobbyGeneration", "code", "name", "wbolegality"],
    "_typed": ["type", "spinDir"],                      # blades, over/metal/main/assist blades
    "bits": ["baseName", "movementStyle"],
    "products": ["productID", "manufacturer", "hobbyName", "hobbyGeneration", "productName"],
    "productContents": ["productID", "partType", "partDataID"],
    "accessories": ["dataID", "accessoryType", "manufacturer", "hobbyName", "hobbyGeneration", "name"],
}

PRODUCTS_COLUMNS = ["productID", "parentProductId", "variantLabel", "manufacturer", "hobbyName",
                    "hobbyGeneration", "productName", "productType", "releaseDate", "itemCost", "currency",
                    "sku", "region", "description", "incompleteData", "updated_at", "deleted"]
PRODUCTS_IMAGE_COLS = ("boxImageUrl", "minifiedBoxImage")   # names the packager already uses
ACCESSORIES_COLUMNS = ["dataID", "parentPartId", "variantLabel", "accessoryType", "subType", "manufacturer",
                       "hobbyName", "hobbyGeneration", "code", "name", "itemCost", "description",
                       "incompleteData", "updated_at", "deleted"]
ACCESSORIES_IMAGE_COLS = ("imageUrl", "minifiedImage")
PRODUCT_CONTENTS_COLUMNS = ["productID", "partType", "partDataID", "quantity"]
CODE_SERIES_COLUMNS = ["seriesPrefix", "manufacturer", "hobbyGeneration", "region", "sequential", "digits",
                       "example", "description", "lastKnownCode"]

# Release code series. sequential=1 -> the updater checks last+1, last+2 ... until a gap.
# These are editable in the CodeSeries sheet; anything marked "verify" is a best guess.
CODE_SERIES = [
    # prefix, manufacturer, generation, region, sequential, digits, example, description
    ("A",   "Takara-Tomy", "Original",   "JP", 1, 2, "A-01",  "Bakuten Shoot releases (verify range)"),
    ("MA",  "Takara-Tomy", "Original",   "JP", 1, 2, "MA-01", "HMS releases (verify)"),
    ("BB",  "Takara-Tomy", "Metal",      "JP", 1, 2, "BB-01", "Metal Fight Beyblade releases"),
    ("BB",  "Hasbro",      "Metal",      "US", 1, 2, "BB-01", "Hasbro Metal Fusion/Masters (own numbering, verify)"),
    ("BBG", "Takara-Tomy", "Metal",      "JP", 1, 2, "BBG-01", "Zero-G / Shogun Steel releases"),
    ("B",   "Takara-Tomy", "Burst",      "JP", 1, 2, "B-01",  "Beyblade Burst releases (B-100+ uses 3 digits)"),
    ("BX",  "Takara-Tomy", "X",          "JP", 1, 2, "BX-01", "Beyblade X Basic Line releases"),
    ("UX",  "Takara-Tomy", "X",          "JP", 1, 2, "UX-01", "Beyblade X Unique Line releases"),
    ("CX",  "Takara-Tomy", "X",          "JP", 1, 2, "CX-01", "Beyblade X Custom Line releases"),
    ("RX",  "Takara-Tomy", "X",          "JP", 1, 2, "RX-01", "Beyblade X upcoming RX line (verify)"),
    ("BXG", "Takara-Tomy", "X",          "JP", 0, 2, "BXG-01", "Beyblade X limited/G3 releases (verify)"),
    ("HASBRO", "Hasbro",   "",           "US", 0, 4, "F9580", "Hasbro item numbers (letter + 4 digits, not sequential)"),
]

# -----------------------------------------------------------------------------
# TCG WORKBOOK
# -----------------------------------------------------------------------------
TCG_RARITIES = ["C", "U", "R", "RR", "SR", "SEC", "Promo", "Other"]
TCG_CARD_TYPES = ["Bey", "Blade", "Blader", "Bit-Beast", "Action", "Stadium", "Other"]
TCG_SETS_COLUMNS = ["setID", "parentSetId", "variantLabel", "setCode", "setName", "manufacturer", "hobbyName",
                    "hobbyGeneration", "region", "releaseDate", "cardCount", "productID", "description",
                    "incompleteData", "updated_at", "deleted"]
TCG_SETS_IMAGE_COLS = ("image", "minifiedImage")
# hobbyGeneration tells the card games apart: "Original" = the V-Force TCG
# (Battle Edge / Spin Strength cards), "X" = the Beyblade X TCG. Stats a game doesn't use stay empty.
TCG_CARDS_COLUMNS = ["dataID", "parentCardId", "variantLabel", "manufacturer", "hobbyName", "hobbyGeneration",
                     "setCode", "setName", "cardNumber", "name", "subtitle", "cardType", "rarity", "attribute",
                     "cost", "power", "battleEdge", "spinStrength", "effectText", "loreText",
                     "linkedPartType", "linkedPartDataID", "illustrator", "legality",
                     "incompleteData", "updated_at", "deleted"]
TCG_CARDS_IMAGE_COLS = ("image", "minifiedImage")
TCG_CARD_NUMBER_RE = re.compile(r"\b([A-Z0-9]{2,6})-(\d{2,4})\b")

# -----------------------------------------------------------------------------
# Every non-part sheet: workbook, id column, image columns, json name
# -----------------------------------------------------------------------------
SHEETS = OrderedDict([
    ("Products",        {"book": "products", "columns": PRODUCTS_COLUMNS, "id": "productID",
                         "id_prefix": "P", "images": PRODUCTS_IMAGE_COLS, "json": "products"}),
    ("Accessories",     {"book": "products", "columns": ACCESSORIES_COLUMNS, "id": "dataID",
                         "id_prefix": "", "images": ACCESSORIES_IMAGE_COLS, "json": "accessories"}),
    ("ProductContents", {"book": "products", "columns": PRODUCT_CONTENTS_COLUMNS, "id": None,
                         "images": None, "json": "productContents"}),
    ("CodeSeries",      {"book": "products", "columns": CODE_SERIES_COLUMNS, "id": None,
                         "images": None, "json": "codeSeries"}),
    ("TCG_Sets",        {"book": "tcg", "columns": TCG_SETS_COLUMNS, "id": "setID",
                         "id_prefix": "S", "images": TCG_SETS_IMAGE_COLS, "json": "tcgSets"}),
    ("TCG_Cards",       {"book": "tcg", "columns": TCG_CARDS_COLUMNS, "id": "dataID",
                         "id_prefix": "", "images": TCG_CARDS_IMAGE_COLS, "json": "tcgCards"}),
])

BOOK_FILES = {"parts": "beyblade_parts.xlsx", "products": "beyblade_products.xlsx", "tcg": "beyblade_tcg.xlsx"}

# -----------------------------------------------------------------------------
# Release codes
# -----------------------------------------------------------------------------
CODE_RE = re.compile(r"(?<![A-Za-z0-9])([A-Z]{1,4})-(\d{2,3})(?:\s+(\d{2}))?(?![0-9])")
HASBRO_ITEM_RE = re.compile(r"(?<![A-Za-z0-9])([A-Z]\d{4})(?![0-9])")


def parse_code(text, prefixes=None):
    """'BX-50 06' -> {'prefix':'BX','number':50,'sub':'06','base':'BX-50','code':'BX-50 06'}"""
    for m in CODE_RE.finditer(str(text or "")):
        pre = m.group(1)
        if prefixes and pre not in prefixes:
            continue
        base = f"{pre}-{m.group(2)}"
        return {"prefix": pre, "number": int(m.group(2)), "sub": m.group(3), "base": base,
                "code": base + (f" {m.group(3)}" if m.group(3) else "")}
    return None


def parse_hasbro_item(text):
    m = HASBRO_ITEM_RE.search(str(text or ""))
    return m.group(1) if m else None


def format_code(prefix, number, digits=2):
    return f"{prefix}-{number:0{digits}d}"


def series_for(prefix, manufacturer=None):
    for s in CODE_SERIES:
        if s[0] == prefix and (manufacturer is None or s[1] == manufacturer):
            return dict(zip(CODE_SERIES_COLUMNS, s))
    return None


def lists():
    """Values for the dropdown 'Lists' sheet in each workbook."""
    return OrderedDict([
        ("manufacturer", MANUFACTURERS), ("hobbyName", HOBBIES), ("hobbyGeneration", GENERATION_NAMES), ("type", BEY_TYPES),
        ("spinDir", SPIN_DIRS), ("productType", PRODUCT_TYPES), ("accessoryType", ACCESSORY_TYPES),
        ("region", REGIONS), ("currency", CURRENCIES), ("rarity", TCG_RARITIES), ("cardType", TCG_CARD_TYPES),
        ("yesNo", YES_NO),
    ])


# column name -> list name used for dropdown validation
DROPDOWNS = {"manufacturer": "manufacturer", "hobbyName": "hobbyName", "hobbyGeneration": "hobbyGeneration", "type": "type",
             "movementStyle": "type", "spinDir": "spinDir", "productType": "productType",
             "accessoryType": "accessoryType", "region": "region", "currency": "currency",
             "rarity": "rarity", "cardType": "cardType", "incompleteData": "yesNo", "wbolegality": "yesNo",
             "sequential": "yesNo", "simpleRatchet": "yesNo", "requiresSimpleRatchet": "yesNo"}


# -----------------------------------------------------------------------------
# Packaging profiles: what each JSON sheet carries and how critical each column is
# -----------------------------------------------------------------------------
# packaging_profiles.json (next to this file, edited in Clasher Studio -> Publish -> Packaging):
#   {"version": 1, "sheets": {"blades": {"columns": {"notes": {"include": false},
#                                                    "requiresSimpleRatchet": {"criticality": "required"}}}}}
# criticality: required    an empty cell blocks the release (catalog check error) and counts as missing
#              recommended counts as missing in the missing data tool (the default for ordinary columns)
#              optional    never counted as missing
# include: false leaves the column out of the JSON. Columns the app reads as required, ids and images can't be
# left out or made less than required.
PROFILES_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "packaging_profiles.json")
CRITICALITY = ("required", "recommended", "optional")
_profiles_cache = {"mtime": None, "path": None, "data": None}


def load_profiles(path=None):
    path = path or PROFILES_FILE
    try:
        mtime = os.path.getmtime(path)
    except OSError:
        return {"version": 1, "sheets": {}}
    c = _profiles_cache
    if c["path"] != path or c["mtime"] != mtime:
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
        except (OSError, ValueError):
            data = {"version": 1, "sheets": {}}
        data.setdefault("sheets", {})
        c.update(path=path, mtime=mtime, data=data)
    return c["data"]


def save_profiles(data, path=None):
    path = path or PROFILES_FILE
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False, sort_keys=True)
        f.write("\n")
    os.replace(tmp, path)
    _profiles_cache["mtime"] = None


TYPED_PART_KEYS = {"blades", "overBlades", "metalBlades", "mainBlades", "assistBlades"}


def app_required(json_sheet):
    """Fields the app's models read with requiredString() for this JSON sheet."""
    if json_sheet in {"blades", "ratchets", "bits", "lockChips", "overBlades", "metalBlades", "mainBlades",
                      "assistBlades"}:
        req = list(APP_REQUIRED["_part"])
        if json_sheet in TYPED_PART_KEYS:
            req += APP_REQUIRED["_typed"]
        return req + list(APP_REQUIRED.get(json_sheet, []))
    return list(APP_REQUIRED.get(json_sheet, []))


def column_rules(json_sheet):
    """{column: {"include": bool, "criticality": str}} set in the profile (only what was changed)."""
    return (load_profiles().get("sheets", {}).get(json_sheet) or {}).get("columns", {}) or {}


def profile_required(json_sheet):
    return [c for c, r in column_rules(json_sheet).items() if r.get("criticality") == "required"]


def profile_excluded(json_sheet):
    locked = set(app_required(json_sheet))
    return {c for c, r in column_rules(json_sheet).items() if r.get("include") is False and c not in locked}
