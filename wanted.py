#!/usr/bin/env python3
"""
The "wanted" list: what's missing in the published catalog, for the app's "Help complete the catalog" page.

    python wanted.py --data data          (the packager also writes it after every package)

Writes data/_wanted.json. It starts with "_" so it never goes into catalog.zip; the app reads it from the CDN
(https://cdn.jsdelivr.net/gh/<owner>/<repo>@<branch>/data/_wanted.json) when someone opens the page. What the
app asks for follows the same rules as the missing data tool:
  * the columns the packaging profile counts (required / recommended; optional ones are never asked);
  * never ids, links, bookkeeping, credits or 3D models;
  * a missing main picture, plus a blader's full-body picture.
What people send goes to the submissions sheet (submissions/); nothing changes until you apply it in Studio.
"""
import argparse
import json
import re
from datetime import datetime, timezone
from pathlib import Path

import beyblade_schema as S

# never asked from the public: ids, links between rows, bookkeeping, things only the data team sets
NEVER_ASK = {
    "dataID", "productID", "setID", "bladerID", "stockComboID", "parentPartId", "parentProductId", "parentSetId",
    "parentCardId", "variantLabel", "manufacturer", "hobbyName", "hobbyGeneration", "code", "name", "productName",
    "setName", "incompleteData", "updated_at", "deleted", "wbolegality", "system", "layerComponent",
    "linkedPartType", "linkedPartDataID", "legality", "sku", "region", "currency", "edition", "setCode",
    "cardNumber", "productType", "accessoryType", "subType", S.CREDITS, S.MODEL_3D, S.BLADER_IDS,
    "integratedRatchet", "requiresSimpleRatchet", "simpleRatchet", "twoStat",
}
NUMERIC = {"mass", "attack", "defense", "stamina", "dash", "burstRes", "heightMm", "protrusions", "itemCost",
           "cardCount", "cost", "power", "battleEdge", "spinStrength"}
UNITS = {"mass": "g", "heightMm": "mm"}
DATES = {"releaseDate"}
HINTS = {
    "mass": "Weight in grams, e.g. 34.6",
    "type": "Attack, defense, stamina or balance",
    "spinDir": "Right, left or both",
    "movementStyle": "How the bit moves: attack, defense, stamina or balance",
    "releaseDate": "First release date (YYYY-MM-DD)",
    "itemCost": "Price when released (number only)",
    "description": "A short description",
}
# picture fields people can send: the main one on every tab with pictures, plus a blader's full body
PICTURES = {"image": "Picture", "fullBodyImage": "Full-body picture"}


def _label(name):
    """'heightMm' -> 'Height mm', 'burstRes' -> 'Burst res'."""
    words = re.sub(r"(?<!^)(?=[A-Z])", " ", name).lower()
    return words[:1].upper() + words[1:]


def _blank(v):
    return v is None or (isinstance(v, str) and not v.strip())


def _sheet_targets():
    """json sheet key -> (label, generation or None, has pictures, extra picture fields)."""
    out = {}
    for gen, key, p in S.all_part_targets():
        out[S.part_json_prefix(gen, key)] = (p["label"] + "s", gen, True, ())
    for name, cfg in S.SHEETS.items():
        if cfg["json"] in ("productContents", "codeSeries", "stockCombos"):
            continue
        extra = tuple(f for f, _ in cfg.get("extra_images", ()))
        label = {"products": "Boxes and sets", "tcgCards": "Cards", "tcgSets": "Card sets"}.get(
            cfg["json"], name.replace("_", " "))
        out[cfg["json"]] = (label, None, bool(cfg.get("images")), extra)
    return out


def _askable(sheet, columns):
    """The columns of a sheet the public may fill: counted by the packaging profile, not NEVER_ASK."""
    import missing_data_tool as M   # the same optional list the missing data tool uses
    optional = set(M.OPTIONAL)
    for c, rule in S.column_rules(sheet).items():
        if rule.get("criticality") == "optional":
            optional.add(c)
        elif rule.get("criticality") in ("required", "recommended"):
            optional.discard(c)
    skip = re.compile(r"(Url|Hash)$")
    return [c for c in columns if c not in NEVER_ASK and c not in optional and not skip.search(c)]


def _field_meta(name, choices_for):
    if name in PICTURES:
        return {"type": "image", "label": PICTURES[name]}
    meta = {"label": _label(name)}
    if name in NUMERIC:
        meta["type"] = "number"
    elif name in DATES:
        meta["type"] = "date"
    elif name in choices_for:
        meta["type"] = "choice"
        meta["choices"] = choices_for[name]
    else:
        meta["type"] = "text"
    if name in UNITS:
        meta["unit"] = UNITS[name]
    if name in HINTS:
        meta["hint"] = HINTS[name]
    return meta


def build(sheets):
    """sheets: {json sheet key: packaged rows} -> the wanted document."""
    lists = S.lists()
    choices_for = {col: [str(v) for v in lists[lst]] for col, lst in S.DROPDOWNS.items()
                   if lst != "yesNo" and lst in lists}
    targets = _sheet_targets()
    doc_sheets, items = {}, []
    for key, rows in sheets.items():
        if key not in targets or not isinstance(rows, list) or not rows:
            continue
        label, gen, has_pictures, extra_pictures = targets[key]
        idf = {"products": "productID", "tcgSets": "setID", "bladers": "bladerID"}.get(key, "dataID")
        columns = list(dict.fromkeys(c for r in rows for c in r.keys()))
        fields = _askable(key, columns)
        pictures = (["image"] if has_pictures else []) + list(extra_pictures)
        meta = {f: _field_meta(f, choices_for) for f in fields + pictures}
        used = set()
        for r in rows:
            rid = r.get(idf)
            if _blank(rid):
                continue
            missing = [f for f in fields if _blank(r.get(f))]
            for p in pictures:
                if _blank(r.get("imageUrl" if p == "image" else f"{p}Url")):
                    missing.append(p)
            if not missing:
                continue
            used.update(missing)
            items.append({
                "sheet": key,
                "id": str(rid),
                "name": str(r.get("name") or r.get("productName") or r.get("setName") or rid),
                "code": str(r.get("code") or r.get("sku") or r.get("cardNumber") or ""),
                "variant": r.get("variantLabel") or None,
                "generation": gen or r.get("hobbyGeneration") or None,
                "hobby": r.get("hobbyName") or None,
                "thumb": r.get("minifiedImageUrl") or r.get("imageUrl") or None,
                "missing": missing,
            })
        if used:
            doc_sheets[key] = {"label": label, "generation": gen,
                               "fields": {f: m for f, m in meta.items() if f in used}}
    return {
        "version": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "sheets": doc_sheets,
        "counts": {"items": len(items), "gaps": sum(len(i["missing"]) for i in items)},
        "items": items,
    }


def write(data_dir, log=print):
    import catalog_check
    doc = build(catalog_check.load_sheets(data_dir))
    path = Path(data_dir) / "_wanted.json"
    path.write_text(json.dumps(doc, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    log(f"What's missing (the app's \"Help complete the catalog\" page): {doc['counts']['items']} rows, "
        f"{doc['counts']['gaps']} gaps -> {path.name}")
    return doc


def main(argv=None):
    ap = argparse.ArgumentParser(description="Write data/_wanted.json (what's missing, for the app)")
    ap.add_argument("--data", default="data")
    write(ap.parse_args(argv).data)


if __name__ == "__main__":
    main()
