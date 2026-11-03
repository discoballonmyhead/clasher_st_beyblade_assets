#!/usr/bin/env python3
"""
Release builder: turns the packager's output folder (data/) into the files you upload to a GitHub
release. Separate from the scraper (fandom_scraper.py) and the packager (beyblade_data.py):

    scraper  -> workbooks (beyblade_parts.xlsx, beyblade_products.xlsx, beyblade_tcg.xlsx)
    packager -> data/*.json + data/images/*.webp + data/_images_by_hobby.json
    THIS     -> _release/<tag>/
                  catalog.zip                       every data/*.json (what the app's catalog sync downloads)
                  catalog_manifest.json             {version, releaseTag, dataUrl, dataSha256, publishedAtMillis}
                                                    = what the beyblade_catalog_manifest RPC must return
                  beyblade_images_<Gen>.zip         image pack per generation, hobby "Beyblade"
                                                    (same layout as the existing beyblade_images_X.zip:
                                                    flat <sheet>-<dataID>.webp / <sheet>-<dataID>-min.webp)
                  beyblade_tcg_images_<Gen>.zip     image pack per generation, hobby "Beyblade TCG"
                  beyblade_data_<Gen>.zip           OPTIONAL data pack per hobby + generation (only that
                  beyblade_tcg_data_<Gen>.zip       generation's rows of every sheet) - for when the catalog
                                                    gets too big to download in one piece
                  packs.json                        index of every file above (hobby, generation, url, sha256,
                                                    size, counts) for an app that lets users pick packs

Before anything is written, the catalog is checked against what the app accepts (catalog_check.py): every
required sheet present, no row missing a field the app requires, no duplicate ids, ProductContents pointing at
part types the app resolves. Errors stop the build; --drop-invalid leaves those rows out instead.

Usage:
    python build_release.py --tag 9526Update --user discoballonmyhead --repo clasher_st_beyblade_assets
    python build_release.py --tag 2026-11-02 --data data --out _release --no-data-packs
    python build_release.py --tag 2026-11-02 --drop-invalid --app-assets ../clasher_st/assets/beyblade_data
Then upload everything in _release/<tag>/ to the GitHub release <tag> and point the
beyblade_catalog_manifest RPC at catalog_manifest.json's values. --app-assets also writes the bundled catalog
(the app's first-launch / offline copy) into the app's assets folder - see WORKFLOW.md.

Zips are written deterministically (fixed timestamps, sorted names), so the same data gives the same
SHA-256 - an unchanged catalog doesn't make every app re-download it.
"""
import argparse
import concurrent.futures as cf
import hashlib
import os
import io
import json
import re
import sys
import zipfile
from datetime import datetime, timezone
from pathlib import Path

from PIL import Image

import catalog_check

FIXED_TIME = (2020, 1, 1, 0, 0, 0)
SKIP_JSON = {"manifest.json"}  # bookkeeping, not catalog sheets


def slug(text):
    return re.sub(r"[^a-z0-9]+", "_", str(text).lower()).strip("_")


def pack_name(hobby, kind, generation):
    """'Beyblade','images','X' -> beyblade_images_X.zip ; 'Beyblade TCG' -> beyblade_tcg_images_X.zip"""
    return f"{slug(hobby)}_{kind}_{generation}.zip"


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def write_zip(entries):
    """entries: [(name, bytes)] -> deterministic zip bytes."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name, data in sorted(entries, key=lambda e: e[0]):
            info = zipfile.ZipInfo(name, date_time=FIXED_TIME)
            info.compress_type = zipfile.ZIP_STORED if name.endswith(".webp") else zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, data)
    return buf.getvalue()


def as_webp(path):
    """Packs must be WebP (the app maps <sheet>-<id>.webp). Converts a stray PNG/JPG on the fly."""
    data = path.read_bytes()
    if path.suffix.lower() == ".webp":
        return data
    im = Image.open(io.BytesIO(data)).convert("RGBA")
    out = io.BytesIO()
    im.save(out, "WEBP", quality=85)
    return out.getvalue()


def find_image(images_dir, stem):
    for ext in (".webp", ".png", ".jpg", ".jpeg"):
        p = images_dir / f"{stem}{ext}"
        if p.exists():
            return p
    return None


def load_sheets(data_dir):
    sheets = {}
    for p in sorted(data_dir.glob("*.json")):
        if p.name in SKIP_JSON or p.name.startswith("_"):
            continue
        sheets[p.stem] = json.loads(p.read_text(encoding="utf-8"))
    return sheets


def images_index(data_dir):
    p = data_dir / "_images_by_hobby.json"
    if p.exists():
        return json.loads(p.read_text(encoding="utf-8"))
    p = data_dir / "_images_by_generation.json"  # data packaged before hobbies were tracked
    if p.exists():
        print("note: no _images_by_hobby.json (re-run the packager); treating every image as hobby 'Beyblade'")
        return {"Beyblade": json.loads(p.read_text(encoding="utf-8"))}
    return {}


def data_pack_rows(sheets, hobby, generation):
    """That hobby+generation's rows of every sheet. ProductContents follow their products."""
    out = {}
    product_ids = set()
    for name, rows in sheets.items():
        if not isinstance(rows, list) or not rows or not isinstance(rows[0], dict):
            continue
        if "hobbyGeneration" in rows[0]:
            keep = [r for r in rows if str(r.get("hobbyGeneration")) == generation
                    and (r.get("hobbyName") in (None, "", hobby) or "hobbyName" not in r)]
            if name == "codeSeries":  # release-code series belong to the Beyblade products, not the card game
                keep = [r for r in rows if str(r.get("hobbyGeneration")) in (generation, "")] if hobby == "Beyblade" else []
            if keep:
                out[name] = keep
                if name == "products":
                    product_ids = {str(r.get("productID")) for r in keep}
    if product_ids and "productContents" in sheets:
        pc = [r for r in sheets["productContents"] if str(r.get("productID")) in product_ids]
        if pc:
            out["productContents"] = pc
    if not set(out) - {"codeSeries"}:
        return {}  # only release-code bookkeeping, no actual data for this generation
    return out


def write_app_assets(dest, sheets, manifest):
    """The bundled catalog: exactly the sheets loadPartsDataBundle() reads, plus manifest.json. Same rows as
    catalog.zip, so a fresh install starts on this release's data."""
    dest.mkdir(parents=True, exist_ok=True)
    for name in catalog_check.APP_SHEETS:
        (dest / f"{name}.json").write_text(json.dumps(sheets.get(name, []), separators=(",", ":"),
                                                      ensure_ascii=False), encoding="utf-8")
    (dest / "manifest.json").write_text(json.dumps({**manifest, "bundled": True}, indent=2), encoding="utf-8")
    print(f"app assets: {len(catalog_check.APP_SHEETS)} sheets + manifest.json -> {dest}")


def main(argv=None):
    ap = argparse.ArgumentParser(description="Build GitHub release files from the packager's data folder")
    ap.add_argument("--data", default="data", help="packager output folder (default: data)")
    ap.add_argument("--out", default="_release", help="output folder (default: _release)")
    ap.add_argument("--tag", required=True, help="GitHub release tag the files will be uploaded to")
    ap.add_argument("--version", help="catalog version string (default: today's date)")
    ap.add_argument("--user", default="discoballonmyhead")
    ap.add_argument("--repo", default="clasher_st_beyblade_assets")
    ap.add_argument("--no-data-packs", action="store_true", help="skip the per hobby/generation data packs")
    ap.add_argument("--drop-invalid", action="store_true",
                    help="leave out rows the app can't read (listed) instead of stopping")
    ap.add_argument("--force", action="store_true", help="build even with catalog errors (not recommended)")
    ap.add_argument("--app-assets", metavar="DIR",
                    help="also write the bundled catalog (the app's required sheets + manifest.json) to DIR, "
                         "the folder AppConstants.beyBladePartsAssetpaths points at")
    a = ap.parse_args(argv)

    data_dir = Path(a.data)
    if not data_dir.is_dir():
        sys.exit(f"{data_dir} not found - run the packager first.")
    out = Path(a.out) / a.tag
    out.mkdir(parents=True, exist_ok=True)
    base_url = f"https://github.com/{a.user}/{a.repo}/releases/download/{a.tag}/"
    version = a.version or datetime.now(timezone.utc).strftime("%Y-%m-%d")
    packs = []

    def emit(kind, hobby, generation, filename, data, **counts):
        (out / filename).write_bytes(data)
        entry = {"kind": kind, "hobby": hobby, "generation": generation, "file": filename,
                 "url": base_url + filename, "sha256": sha256(data), "bytes": len(data), **counts}
        packs.append(entry)
        print(f"  {filename:38s} {len(data) / 1024 / 1024:7.2f} MB  {counts}")
        return entry

    # 0) the gate: what the app would reject or fail to read
    sheets = load_sheets(data_dir)
    if not sheets:
        sys.exit(f"No sheet JSON files in {data_dir}.")
    report = catalog_check.check(sheets)
    report.print()
    if not report.ok:
        if a.drop_invalid:
            sheets, dropped = catalog_check.drop_invalid(sheets, report)
            print(f"--drop-invalid: left out {dropped} rows; fix them in the workbook (missing_data_tool.py) "
                  f"and they come back in the next release")
            again = catalog_check.check(sheets)
            if not again.ok:  # e.g. a required sheet is missing - dropping rows can't fix that
                again.print()
                sys.exit("Catalog still has errors; nothing written.")
        elif not a.force:
            sys.exit("\nNothing written. Fix these in the workbooks (missing_data_tool.py shows them per field), "
                     "re-run the packager, or use --drop-invalid to release without those rows.")

    # 1) catalog.zip - every sheet, the file the app's catalog sync downloads and verifies
    print(f"catalog: {len(sheets)} sheets")
    cat = emit("catalog", None, None, "catalog.zip",
               write_zip([(f"{n}.json", json.dumps(r, separators=(",", ":"), ensure_ascii=False).encode("utf-8"))
                          for n, r in sheets.items()]),
               sheets=len(sheets), rows=sum(len(r) for r in sheets.values() if isinstance(r, list)))
    manifest = {"version": version, "releaseTag": a.tag, "dataUrl": cat["url"], "dataSha256": cat["sha256"],
                "publishedAtMillis": int(datetime.now(timezone.utc).timestamp() * 1000)}
    (out / "catalog_manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    if a.app_assets:
        write_app_assets(Path(a.app_assets), sheets, manifest)

    # 2) image packs per hobby + generation
    images_dir = data_dir / "images"
    index = images_index(data_dir)
    print("image packs:")
    for hobby, gens in index.items():
        for gen, by_prefix in gens.items():
            stems = [f"{prefix}-{did}{suf}" for prefix, ids in by_prefix.items() for did in ids for suf in ("", "-min")]

            def load(stem):  # read (+ convert a stray PNG) - in parallel, the image work releases the GIL
                p = find_image(images_dir, stem)
                return (f"{stem}.webp", as_webp(p)) if p else None
            with cf.ThreadPoolExecutor(max_workers=max(2, min(16, os.cpu_count() or 4))) as ex:
                loaded = list(ex.map(load, stems))
            entries = [e for e in loaded if e]
            missing = len(loaded) - len(entries)
            if not entries:
                continue
            emit("images", hobby, gen, pack_name(hobby, "images", gen), write_zip(entries),
                 files=len(entries), missingFiles=missing)

    # 3) optional data packs per hobby + generation
    if not a.no_data_packs:
        print("data packs:")
        combos = sorted({(r.get("hobbyName") or "Beyblade", str(r.get("hobbyGeneration")))
                         for name, rows in sheets.items() if isinstance(rows, list) and name != "codeSeries"
                         for r in rows if isinstance(r, dict) and r.get("hobbyGeneration")})
        for hobby, gen in combos:
            rows = data_pack_rows(sheets, hobby, gen)
            if not rows:
                continue
            emit("data", hobby, gen, pack_name(hobby, "data", gen),
                 write_zip([(f"{n}.json", json.dumps(r, separators=(",", ":"), ensure_ascii=False).encode("utf-8"))
                            for n, r in rows.items()]),
                 sheets=len(rows), rows=sum(len(r) for r in rows.values()))

    (out / "packs.json").write_text(json.dumps({"version": version, "releaseTag": a.tag, "packs": packs},
                                               indent=2), encoding="utf-8")
    print(f"\nWrote {len(packs)} files + catalog_manifest.json + packs.json to {out}")
    print(f"Upload them to the GitHub release '{a.tag}', then make beyblade_catalog_manifest return:")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
