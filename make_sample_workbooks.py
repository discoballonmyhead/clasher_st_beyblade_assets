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


def png_from_webp(path, width):
    if not os.path.exists(path):
        return None
    im = Image.open(path).convert("RGBA")
    if im.width > width:
        im = im.resize((width, round(im.height * width / im.width)), Image.LANCZOS)
    b = io.BytesIO()
    im.save(b, "WEBP", quality=85, method=6)  # same format the scraper stores and the packager ships
    return b.getvalue()


def build_parts(path, examples):
    book = Book(path, "parts")
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
            if (key, did) in VARIANTS:
                vals["parentPartId"], vals["variantLabel"] = VARIANTS[(key, did)]
            row, _, _ = book.write(ws, vals, "dataID")
            book.set_image(ws, row, "image", png_from_webp(os.path.join(DATA, "images", f"{key}-{did}.webp"), 220))
            book.set_image(ws, row, "minifiedImage",
                           png_from_webp(os.path.join(DATA, "images", f"{key}-{did}-min.webp"), 96), "min")
    book.save()


def build_products(path, examples):
    book = Book(path, "products")
    prods, acc = book.named_sheet("Products"), book.named_sheet("Accessories")
    pc, cs = book.named_sheet("ProductContents"), book.named_sheet("CodeSeries")
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
                  ("P4", "Parts_X_LockChips", 2, 1)]:
            book.write(pc, dict(zip(S.PRODUCT_CONTENTS_COLUMNS, r)))
    book.save()


def build_tcg(path, examples):
    book = Book(path, "tcg")
    sets, cards = book.named_sheet("TCG_Sets"), book.named_sheet("TCG_Cards")
    if examples:
        base = {"manufacturer": "Takara-Tomy", "hobbyName": "Beyblade TCG", "hobbyGeneration": "X", "incompleteData": 1}
        book.write(sets, dict(base, setID="S1", setCode="EX01", setName="EXAMPLE Set 1", region="JP",
                              cardCount=100, description="EXAMPLE - replace with the real first set"), "setID")
        book.write(sets, {"setID": "S2", "setCode": "1", "setName": "Collision", "hobbyName": "Beyblade TCG",
                          "hobbyGeneration": "Plastic", "description": "Original 2000s Beyblade TCG, set no. 1",
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
            dict(dataID=4, hobbyName="Beyblade TCG", hobbyGeneration="Plastic", setCode="1", setName="Collision",
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
