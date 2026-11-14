#!/usr/bin/env python3
"""
Builds the three human-managed workbooks with every sheet, header, dropdown and README,
filled with a few example rows (real X rows from data/*.json incl. images) so you can
see how the data should look.

    python make_sample_workbooks.py              -> samples/beyblade_parts.xlsx, ..._products.xlsx, ..._tcg.xlsx
    python make_sample_workbooks.py --empty out/ -> same structure, no example rows (start a fresh store)

Rows marked "EXAMPLE" are illustrations - replace them with real data.
"""
import argparse
import io
import json
import os
import struct

from PIL import Image

import beyblade_schema as S
from beyblade_store import Book

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(HERE, "data")

# real rows from data/*.json to show (dataIDs kept). blades 65/66/72 show base + variants.
EXAMPLE_PART_IDS = {
    "blades": [65, 66, 72, 1], "ratchets": [13, 1], "bits": [13, 1], "lockChips": [1, 2],
    "mainBlades": [1, 2], "assistBlades": [1, 2], "metalBlades": [1], "overBlades": [1],
}
VARIANTS = {("blades", 66): (65, "Katsushika City Collaboration Ver."), ("blades", 72): (65, "Special Ver.")}
# who uses a part in the show (Bladers tab) and an example 3D model (path relative to the workbook's folder)
EXAMPLE_EXTRAS = {("blades", 65): {"bladerIDs": "BL1, BL2", "model3d": "models/example-triangle.glb"},
                  ("lockChips", 1): {"bladerIDs": "BL1"}}


def png_from_webp(path, width):
    if not os.path.exists(path):
        return None
    im = Image.open(path).convert("RGBA")
    if im.width > width:
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    b = io.BytesIO()
    im.save(b, "WEBP", quality=85, method=6)  # same format the scraper stores and the packager ships
    return b.getvalue()


def placeholder_png(text, size, color):
    """A plain picture standing in for a real blader picture in the samples."""
    from PIL import ImageDraw
    im = Image.new("RGB", size, color)
    ImageDraw.Draw(im).text((8, 8), text, fill="white")
    b = io.BytesIO()
    im.save(b, "PNG")
    return b.getvalue()


def example_glb(path):
    """Writes the smallest useful glTF binary (.glb): one triangle. Stands in for a real 3D model in the samples."""
    positions = struct.pack("<9f", 0, 0, 0, 1, 0, 0, 0, 1, 0)
    gltf = {"asset": {"version": "2.0", "generator": "make_sample_workbooks.py (EXAMPLE)"},
            "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
            "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
            "buffers": [{"byteLength": len(positions)}],
            "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": len(positions)}],
            "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3",
                           "min": [0, 0, 0], "max": [1, 1, 0]}]}
    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    body = struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(positions), 0x004E4942) + positions
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + len(body)) + body)


def build_parts(path, examples):
    book = Book(path, "parts")
    bladers = book.named_sheet("Bladers")
    if examples:
        model = os.path.join(os.path.dirname(path), "models", "example-triangle.glb")
        example_glb(model)
        for r, color in [({"bladerID": "BL1", "name": "EXAMPLE Blader One", "hobbyName": "Beyblade",
                           "hobbyGeneration": "X", "description": "EXAMPLE: uses blade 65 and lock chip 1"},
                          (40, 70, 160)),
                         ({"bladerID": "BL2", "name": "EXAMPLE Blader Two", "hobbyName": "Beyblade",
                           "hobbyGeneration": "X", "description": "EXAMPLE: also uses blade 65 (no pictures yet)"},
                          None)]:
            row, _, _ = book.write(bladers, dict(r, incompleteData=1), "bladerID")
            if color:
                book.set_image(bladers, row, "image", placeholder_png(r["name"], (220, 220), color))
                book.set_image(bladers, row, "minifiedImage", placeholder_png("", (96, 96), color), "min")
                book.set_image(bladers, row, "fullBodyImage", placeholder_png(r["name"], (220, 400), color))
                book.set_image(bladers, row, "minifiedFullBodyImage", placeholder_png("", (96, 174), color), "min")
    for gen, key, _ in S.all_part_targets():
        ws = book.part_sheet(gen, key)
        if not examples or gen != "X":
            continue
        src = os.path.join(DATA, f"{key}.json")
        rows = {str(r["dataID"]): r for r in json.load(open(src, encoding="utf-8"))} if os.path.exists(src) else {}
        for did in EXAMPLE_PART_IDS.get(key, []):
            r = rows.get(str(did))
            if not r:
                continue
            vals = {k: v for k, v in r.items() if not k.lower().endswith(("url", "hash"))}
            vals["dataID"] = int(did)
            if str(vals.get("parentPartId") or "") not in {str(i) for i in EXAMPLE_PART_IDS[key]}:
                vals["parentPartId"] = vals["variantLabel"] = None  # its parent isn't in the samples
            if (key, did) in VARIANTS:
                vals["parentPartId"], vals["variantLabel"] = VARIANTS[(key, did)]
            if (key, did) in EXAMPLE_EXTRAS:
                vals.update(EXAMPLE_EXTRAS[(key, did)])
            row, _, _ = book.write(ws, vals, "dataID")
            book.set_image(ws, row, "image", png_from_webp(os.path.join(DATA, "images", f"{key}-{did}.webp"), 220))
            book.set_image(ws, row, "minifiedImage",
                           png_from_webp(os.path.join(DATA, "images", f"{key}-{did}-min.webp"), 96), "min")
    book.save()


def build_products(path, examples):
    book = Book(path, "products")
    prods, acc = book.named_sheet("Products"), book.named_sheet("Accessories")
    pc, cs = book.named_sheet("ProductContents"), book.named_sheet("CodeSeries")
    sc = book.named_sheet("StockCombos")
    for s in S.CODE_SERIES:
        book.write(cs, dict(zip(S.CODE_SERIES_COLUMNS, s)))
    if examples:
        base = {"hobbyName": "Beyblade", "hobbyGeneration": "X", "incompleteData": 1}
        tt = dict(base, manufacturer="Takara-Tomy", region="JP", currency="JPY")
        rows = [
            dict(tt, productID="P1", productName="Starter DranSword 3-60F", productType="Starter", sku="BX-01",
                 releaseDate="2023-07-08", itemCost=10.00, currency="USD",
                 description="Includes Dran Sword, 3-60, F (+ launcher)"),
            dict(tt, productID="P2", productName="Xtreme Stadium", productType="Stadium", sku="BX-10",
                 description="EXAMPLE accessory product -> also has an Accessories row + ProductContents link"),
            dict(tt, productID="P3", productName="BX-50 Random Booster (EXAMPLE name)", productType="Random Booster",
                 sku="BX-50", description="EXAMPLE parent product: the random booster as a whole"),
            dict(tt, productID="P4", parentProductId="P3", variantLabel="06", productName="BX-50 Random Booster 06",
                 productType="Random Booster", sku="BX-50 06",
                 description="EXAMPLE variant: one specific item of the random booster"),
            dict(base, productID="P5", manufacturer="Hasbro", region="US", currency="USD",
                 productName="Sword Dran 3-60F Starter Pack", productType="Starter",
                 description="EXAMPLE Hasbro release of the same combo; put the Hasbro item number in sku"),
        ]
        for r in rows:
            book.write(prods, r, "productID")
        book.write(acc, dict(base, dataID=1, accessoryType="Stadium", subType="Standard", manufacturer="Takara-Tomy",
                             code="BX-10", name="Xtreme Stadium", description="EXAMPLE"), "dataID")
        for r in [("P1", "Parts_X_Blades", 65, 1), ("P1", "Parts_X_Ratchets", 13, 1), ("P1", "Parts_X_Bits", 13, 1),
                  ("P2", "Accessories", 1, 1),
                  ("P4", "Parts_X_MainBlades", 1, 1), ("P4", "Parts_X_AssistBlades", 2, 1),
                  ("P4", "Parts_X_LockChips", 2, 1), ("P4", "Parts_X_Ratchets", 1, 1), ("P4", "Parts_X_Bits", 1, 1)]:
            book.write(pc, dict(zip(S.PRODUCT_CONTENTS_COLUMNS, r)))
        # the combos that come out of each box: P1 = a one-piece blade, P4 = a custom line build
        example_glb(os.path.join(os.path.dirname(path), "models", "example-triangle.glb"))
        for r in [dict(base, stockComboID="SC1", productID="P1", name="Dran Sword 3-60F", bladeDataID=65,
                       ratchetDataID=13, bitDataID=13, model3d="models/example-triangle.glb",
                       description="EXAMPLE stock combo of the starter"),
                  dict(base, stockComboID="SC2", productID="P4", name="EXAMPLE custom line combo", lockChipDataID=2,
                       mainBladeDataID=1, assistBladeDataID=2, ratchetDataID=1, bitDataID=1,
                       description="EXAMPLE lock chip + main blade + assist blade build")]:
            book.write(sc, r, "stockComboID")
    book.save()


def build_tcg(path, examples):
    book = Book(path, "tcg")
    sets, cards = book.named_sheet("TCG_Sets"), book.named_sheet("TCG_Cards")
    if examples:
        base = {"manufacturer": "Takara-Tomy", "hobbyName": "Beyblade TCG", "hobbyGeneration": "X", "incompleteData": 1}
        book.write(sets, dict(base, setID="S1", setCode="EX01", setName="EXAMPLE Set 1", region="JP",
                              cardCount=100, description="EXAMPLE - replace with the real first set"), "setID")
        book.write(sets, {"setID": "S2", "setCode": "1", "setName": "Collision", "hobbyName": "Beyblade TCG",
                          "hobbyGeneration": "Original", "description": "V-Force TCG, set no. 1",
                          "incompleteData": 1}, "setID")
        for r in [
            dict(base, dataID=1, setCode="EX01", cardNumber="EX01-001", name="EXAMPLE Dran Sword card", cardType="Bey",
                 rarity="R", linkedPartType="Parts_X_Blades", linkedPartDataID=65, effectText="EXAMPLE effect text"),
            dict(base, dataID=2, parentCardId=1, variantLabel="Parallel Foil", setCode="EX01", cardNumber="EX01-001",
                 name="EXAMPLE Dran Sword card", cardType="Bey", rarity="SR", linkedPartType="Parts_X_Blades",
                 linkedPartDataID=65, effectText="EXAMPLE variant of card 1 (same number, different finish)"),
            dict(base, dataID=3, setCode="EX01", cardNumber="EX01-002", name="EXAMPLE Blader card",
                 cardType="Blader", rarity="C"),
            # real card from the original 2000s Beyblade TCG (wiki page "Batranzer (TCG)")
            dict(dataID=4, hobbyName="Beyblade TCG", hobbyGeneration="Original", setCode="1", setName="Collision",
                 name="Batranzer", subtitle="Swooping Beyblade", cardType="Blade", rarity="Uncommon",
                 battleEdge=3, spinStrength=7,
                 effectText="When you make an opponent lose a blue card from his or her spin pile, you gain 1 spin.",
                 loreText="This Beyblade is able to jump high in the air, then drop down in a powerful Bat Attack.",
                 incompleteData=1),
        ]:
            book.write(cards, r, "dataID")
    book.save()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--empty", metavar="DIR", help="write empty workbooks (structure only) into DIR")
    a = ap.parse_args()
    out = a.empty or os.path.join(HERE, "samples")
    os.makedirs(out, exist_ok=True)
    for kind, fn in S.BOOK_FILES.items():
        p = os.path.join(out, fn)
        if os.path.exists(p):
            if a.empty:
                raise SystemExit(f"{p} exists - not overwriting your store.")
            os.remove(p)
        {"parts": build_parts, "products": build_products, "tcg": build_tcg}[kind](p, not a.empty)
        print("wrote", p)


if __name__ == "__main__":
    main()
