#!/usr/bin/env python3
"""
Offline packager: turns the human-managed workbooks into data/*.json + data/images/*.webp.

Inputs (any combination; a single legacy master workbook also works):
    beyblade_parts.xlsx      Parts_<Gen>_<Type> sheets      -> blades.json, burstLayers.json, ...
    beyblade_products.xlsx   Products / Accessories /
                             ProductContents / CodeSeries   -> products.json, accessories.json, ...
    beyblade_tcg.xlsx        TCG_Sets / TCG_Cards           -> tcgSets.json, tcgCards.json

Images are PNGs embedded in the image columns of each row (anchored to that row's cell).

GUI:  python beyblade_data.py
Missing values / images: use the separate missing_data_tool.py.
CLI:  python beyblade_data.py --parts beyblade_parts.xlsx --products beyblade_products.xlsx \
          --tcg beyblade_tcg.xlsx --out data --user discoballonmyhead --repo clasher_st_beyblade_assets
"""
import argparse
import concurrent.futures as cf
import datetime as dt
import os
import hashlib
import io
import json
import sys
import threading
from datetime import datetime, timezone
from pathlib import Path

import openpyxl
from PIL import Image as PILImage

import beyblade_schema as S

WEBP_QUALITY = 85
# Image encoding releases the GIL, so a thread per core encodes that many images at once.
WORKERS = max(2, min(16, (os.cpu_count() or 4)))
NO_IMAGE_SHEETS = {name: cfg["json"] for name, cfg in S.SHEETS.items() if not cfg["images"]}

# --- Core Logic Helpers ---


def read_sheet_rows_numbered(ws):
    """[(sheet row number, row)] for every non-empty row. Empty rows are skipped, not the end: a cleared row
    used to hide every row below it."""
    headers = [str(c.value) if c.value else "" for c in ws[1]]
    out = []
    for r, row in enumerate(ws.iter_rows(min_row=2, values_only=True), 2):
        if any(v not in (None, "") for v in row):
            out.append((r, {h: v for h, v in zip(headers, row) if h}))
    return out


def read_sheet_rows(ws):
    return [row for _, row in read_sheet_rows_numbered(ws)]


def png_bytes_to_webp(png_bytes: bytes) -> bytes:
    """Any embedded image -> WebP. Already WebP (what the scraper stores) is copied as-is: no second
    lossy encode, and the same image always gives the same file/hash."""
    if png_bytes[:4] == b"RIFF" and png_bytes[8:12] == b"WEBP":
        return png_bytes
    img = PILImage.open(io.BytesIO(png_bytes)).convert("RGBA")
    buf = io.BytesIO()
    img.save(buf, format="WEBP", quality=WEBP_QUALITY)
    return buf.getvalue()


def extract_embedded_images(ws, img_col_1idx: int, min_col_1idx: int):
    """Returns {row_number_1idx: {'full': bytes, 'min': bytes}}"""
    result = {}
    for img in ws._images:
        row = img.anchor._from.row + 1
        col = img.anchor._from.col + 1
        # original bytes: img._data() re-encodes WebP as PNG
        raw = img.ref.getvalue() if hasattr(img.ref, "getvalue") else img._data()
        if col == img_col_1idx:
            result.setdefault(row, {})["full"] = raw
        elif col == min_col_1idx:
            result.setdefault(row, {})["min"] = raw
    return result


def build_jsdelivr_url(username: str, repo: str, branch: str = "main") -> str:
    """Built from three separately-validated pieces, never hand-typed as one long URL."""
    return f"https://cdn.jsdelivr.net/gh/{username}/{repo}@{branch}/data/"


def _json_default(v):
    if isinstance(v, (dt.datetime, dt.date)):
        return v.date().isoformat() if isinstance(v, dt.datetime) and v.time() == dt.time() else v.isoformat()
    if isinstance(v, dt.time):
        return v.isoformat()
    return str(v)


def _dump(path: Path, rows):
    path.write_text(json.dumps(rows, separators=(",", ":"), ensure_ascii=False, default=_json_default),
                    encoding="utf-8")


def check_required(sheet_key, rows, log):
    """Warn about empty columns the app's models read with requiredString()."""
    req = list(S.APP_REQUIRED.get(sheet_key, []))
    part = next((p for g, k, p in S.all_part_targets() if S.part_json_prefix(g, k) == sheet_key), None)
    if part:
        req = S.APP_REQUIRED["_part"] + (S.APP_REQUIRED["_typed"] if "spinDir" in part["columns"] else []) + req
    empty = {c: sum(1 for r in rows if r.get(c) in (None, "")) for c in req if any(c in r for r in rows) or rows}
    empty = {c: n for c, n in empty.items() if n}
    if empty:
        log(f"    note: {sheet_key}: empty required columns (the app reads these as required): "
            + ", ".join(f"{c} x{n}" for c, n in empty.items()))


def is_deleted(row):
    """Rows marked deleted stay in the workbook (dataIDs are never reused) but never reach the app."""
    return str(row.get("deleted") or "").strip().lower() in ("true", "1", "yes")


def drop_deleted(rows):
    keep = [r for r in rows if not is_deleted(r)]
    return keep, len(rows) - len(keep)


# Id columns are text in the app (requiredString / String? fields); Excel hands back 65 or 65.0 for them.
ID_FIELDS = {"dataID", "parentPartId", "productID", "parentProductId", "partDataID", "setID", "parentSetId",
             "parentCardId", "linkedPartDataID", "productId"}


def flags_01(row):
    """0/1 columns (simpleRatchet, requiresSimpleRatchet, integratedRatchet ...) as 1 / 0; blank stays blank
    (the app reads blank as 0). Hand-typed TRUE / yes / x become 1."""
    for k in S.FLAG_COLUMNS & row.keys():
        v = row[k]
        if v is None or (isinstance(v, str) and not v.strip()):
            row[k] = None
            continue
        t = str(v).strip().lower()
        row[k] = 1 if t in ("1", "1.0", "true", "yes", "y", "x") else 0 if t in ("0", "0.0", "false", "no", "n") else v
    return row


def text_ids(row):
    for k in ID_FIELDS & row.keys():
        v = row[k]
        if isinstance(v, float) and v.is_integer():
            v = int(v)
        if v is not None and not isinstance(v, str):
            row[k] = str(v)
        elif isinstance(v, str):
            row[k] = v.strip() or None
    return row


def app_part_type(value):
    """ProductContents.partType as the app looks it up: the JSON sheet key, e.g. 'Parts_X_Blades' -> 'blades',
    'Parts_Burst_Layers' -> 'burstLayers', 'Accessories' -> 'accessories'. Already-short keys pass through."""
    v = str(value or "").strip()
    part = S.parse_part_sheet(v)
    if part:
        return S.part_json_prefix(part[0], part[1])
    if v in S.SHEETS and S.SHEETS[v].get("json"):
        return S.SHEETS[v]["json"]
    return v


def process_image_sheet(ws, prefix, id_field, img_field, min_field, out_dir, base_url,
                        images_by_generation, manifest, log, images_by_hobby=None):
    headers = [str(c.value) if c.value else "" for c in ws[1]]
    missing = [f for f in (id_field, img_field, min_field) if f not in headers]
    if missing:
        log(f"  SKIP {ws.title}: missing columns {missing}")
        return
    img_col, min_col = headers.index(img_field) + 1, headers.index(min_field) + 1
    numbered = read_sheet_rows_numbered(ws)  # images are matched by the real sheet row, gaps or not
    raw_rows = [row for _, row in numbered]
    row_no = [r for r, _ in numbered]
    images_by_row = extract_embedded_images(ws, img_col, min_col)
    out_images_dir = out_dir / "images"
    out_images_dir.mkdir(parents=True, exist_ok=True)

    # 1) encode every image in parallel (the slow part when the workbook holds PNG/JPEG)
    jobs = {}
    for i, row in enumerate(raw_rows):
        data_id = row.get(id_field)
        for kind, suffix in (("full", ""), ("min", "-min")):
            data = images_by_row.get(row_no[i], {}).get(kind)
            if data_id not in (None, "") and data and not is_deleted(row):
                jobs[(i, kind)] = (f"{prefix}-{data_id}{suffix}.webp", data)

    def encode(item):
        key, (name, data) = item
        webp = png_bytes_to_webp(data)
        (out_images_dir / name).write_bytes(webp)
        return key, (name, hashlib.sha1(webp).hexdigest()[:12])

    encoded = {}
    if jobs:
        with cf.ThreadPoolExecutor(max_workers=WORKERS) as ex:
            encoded = dict(ex.map(encode, jobs.items()))

    rows, seen_ids = [], set()
    with_image = without_image = no_id = n_deleted = 0
    for i, row in enumerate(raw_rows):
        data_id = row.get(id_field)
        if is_deleted(row):
            n_deleted += 1
            continue
        if data_id in (None, ""):
            no_id += 1
            continue
        if str(data_id) in seen_ids:
            log(f"  WARNING {ws.title}: duplicate {id_field} {data_id!r} (row {row_no[i]})")
        seen_ids.add(str(data_id))
        row.pop(img_field, None)
        row.pop(min_field, None)
        text_ids(row)
        flags_01(row)

        if (i, "full") in encoded:
            name, digest = encoded[(i, "full")]
            row["imageUrl"] = f"{base_url}images/{name}"
            row["imageHash"] = digest
            with_image += 1
            gen = row.get("hobbyGeneration") or "unknown"
            images_by_generation.setdefault(gen, {}).setdefault(prefix, []).append(str(data_id))
            if images_by_hobby is not None:
                hobby = row.get("hobbyName") or "unknown"
                images_by_hobby.setdefault(hobby, {}).setdefault(gen, {}).setdefault(prefix, []).append(str(data_id))
        else:
            row["imageUrl"] = None
            row["imageHash"] = None
            without_image += 1

        if (i, "min") in encoded:
            name, digest = encoded[(i, "min")]
            row["minifiedImageUrl"] = f"{base_url}images/{name}"
            row["minifiedImageHash"] = digest
        else:
            row["minifiedImageUrl"] = None
            row["minifiedImageHash"] = None
        rows.append(row)

    _dump(out_dir / f"{prefix}.json", rows)
    check_required(prefix, rows, log)
    manifest["sheets"][prefix] = {"rowCount": len(rows), "withImage": with_image, "withoutImage": without_image}
    extra = f", {no_id} rows without {id_field} skipped" if no_id else ""
    extra += f", {n_deleted} deleted rows left out" if n_deleted else ""
    log(f"  {ws.title} -> {prefix}.json: {len(rows)} rows ({with_image} with image, {without_image} without{extra})")


# ── what changed: vs the previous package, and what the missing data tool did ──

ROW_KEY = {"productContents": ("productID", "partType", "partDataID"), "codeSeries": ("seriesPrefix", "manufacturer")}
UNCOMPARED = {"updated_at"}  # a re-stamp alone isn't a change


def _row_key(sheet, row):
    keys = ROW_KEY.get(sheet)
    if keys:
        return "|".join(str(row.get(k)) for k in keys)
    for k in ("dataID", "productID", "setID"):
        if k in row:
            return str(row.get(k))
    return None


def load_previous(out_dir):
    """The package currently in out_dir (before it's overwritten): ({sheet: rows}, packagedAt or None)."""
    prev, when = {}, None
    for p in Path(out_dir).glob("*.json"):
        if p.name.startswith("_"):
            continue
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if p.name == "manifest.json":
            when = data.get("packagedAt") if isinstance(data, dict) else None
        elif isinstance(data, list):
            prev[p.stem] = data
    return prev, when


def package_diff(prev, out_dir):
    """Per sheet: rows added / removed / changed and columns added / removed since the previous package."""
    out = {}
    for p in sorted(Path(out_dir).glob("*.json")):
        if p.name.startswith("_") or p.name == "manifest.json":
            continue
        new = json.loads(p.read_text(encoding="utf-8"))
        old = prev.get(p.stem)
        if not isinstance(new, list):
            continue
        new_cols = sorted({k for r in new for k in r})
        if old is None:
            out[p.stem] = {"newSheet": True, "rows": len(new), "columns": new_cols}
            continue
        old_cols = {k for r in old for k in r}
        old_by = {_row_key(p.stem, r): r for r in old}
        new_by = {_row_key(p.stem, r): r for r in new}
        added = [k for k in new_by if k not in old_by]
        removed = [k for k in old_by if k not in new_by]
        changed = []
        for k, r in new_by.items():
            o = old_by.get(k)
            if o is not None and any(r.get(f) != o.get(f) for f in (set(r) | set(o)) - UNCOMPARED):
                changed.append(k)
        cols_added = sorted(set(new_cols) - old_cols)
        entry = {k: v for k, v in {
            "rowsAdded": added, "rowsRemoved": removed, "rowsChanged": changed,
            "columnsAdded": [{"column": c, "filled": sum(1 for r in new if r.get(c) not in (None, ""))}
                             for c in cols_added],
            "columnsRemoved": sorted(old_cols - set(new_cols))}.items() if v}
        if entry:
            out[p.stem] = entry
    return out


def read_bookkeeping(wb, workbook_name):
    """_edit_log and _columns of one workbook -> (log entries, custom columns), tagged with the workbook."""
    def rows(name):
        return [{**r, "workbook": workbook_name} for r in read_sheet_rows(wb[name])] \
            if name in wb.sheetnames else []
    return rows(S.EDIT_LOG_SHEET), rows(S.CUSTOM_COLUMNS_SHEET)


def package(workbooks, out_dir: Path, base_url: str, log=print):
    """workbooks: list of xlsx paths (parts / products / tcg, or one legacy master)."""
    if not base_url.endswith("/"):
        base_url += "/"
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    prev, prev_when = load_previous(out_dir)
    manifest = {"packagedAt": datetime.now(timezone.utc).isoformat(), "workbooks": [], "sheets": {}}
    edit_log, custom_cols = [], []
    images_by_generation = {}
    images_by_hobby = {}  # hobby -> generation -> sheet prefix -> [dataID]; used by build_release.py
    done = {}

    for path in [Path(p) for p in workbooks if p]:
        log(f"Loading workbook (this may take a moment): {path.name}...")
        wb = openpyxl.load_workbook(path, data_only=True)  # data_only: formulas -> values
        manifest["workbooks"].append(path.name)
        entries, cols = read_bookkeeping(wb, path.name)
        edit_log += entries
        custom_cols += cols
        for name in wb.sheetnames:
            if name in done:
                log(f"  WARNING: sheet {name} also in {done[name]} - skipped the copy in {path.name}")
                continue
            ws = wb[name]
            part = S.parse_part_sheet(name)
            if part:
                gen, key, _ = part
                process_image_sheet(ws, S.part_json_prefix(gen, key), "dataID", *S.PART_IMAGE_COLS,
                                    out_dir, base_url, images_by_generation, manifest, log, images_by_hobby)
            elif name in S.SHEETS and S.SHEETS[name]["images"]:
                cfg = S.SHEETS[name]
                process_image_sheet(ws, cfg["json"], cfg["id"], *cfg["images"],
                                    out_dir, base_url, images_by_generation, manifest, log, images_by_hobby)
            elif name in NO_IMAGE_SHEETS:
                rows, _ = drop_deleted(read_sheet_rows(ws))
                for r in rows:
                    text_ids(r)
                    flags_01(r)
                if NO_IMAGE_SHEETS[name] == "productContents":  # the app resolves contents by JSON sheet key
                    for r in rows:
                        r["partType"] = app_part_type(r.get("partType"))
                _dump(out_dir / f"{NO_IMAGE_SHEETS[name]}.json", rows)
                check_required(NO_IMAGE_SHEETS[name], rows, log)
                manifest["sheets"][NO_IMAGE_SHEETS[name]] = {"rowCount": len(rows)}
                log(f"  {name} -> {NO_IMAGE_SHEETS[name]}.json: {len(rows)} rows (no images)")
            else:
                continue  # README, Lists, _scrape_log, ...
            done[name] = path.name

    manifest["imagesByGeneration"] = {g: {k: len(v) for k, v in s.items()} for g, s in images_by_generation.items()}
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    (out_dir / "_images_by_generation.json").write_text(json.dumps(images_by_generation), encoding="utf-8")
    (out_dir / "_images_by_hobby.json").write_text(json.dumps(images_by_hobby), encoding="utf-8")
    manifest["imagesByHobby"] = {h: {g: sum(len(v) for v in s.values()) for g, s in gs.items()}
                                 for h, gs in images_by_hobby.items()}
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    report_changes(out_dir, prev, prev_when, edit_log, custom_cols, manifest, log)

    # what the app would reject or fail to read (build_release.py blocks on these)
    import catalog_check
    log("\nChecking the catalog against what the app accepts...")
    catalog_check.check(catalog_check.load_sheets(out_dir)).print(log=log, limit=15)
    log(f"\nDone. Output in {out_dir}")
    return manifest


def report_changes(out_dir, prev, prev_when, edit_log, custom_cols, manifest, log):
    """Writes _package_diff.json, _edit_log.json, _custom_columns.json and prints what's new."""
    out_dir = Path(out_dir)
    diff = package_diff(prev, out_dir) if prev else {}
    (out_dir / "_package_diff.json").write_text(json.dumps(
        {"previousPackagedAt": prev_when, "packagedAt": manifest["packagedAt"], "sheets": diff},
        indent=1, default=_json_default), encoding="utf-8")
    (out_dir / "_edit_log.json").write_text(json.dumps(edit_log, indent=1, default=_json_default), encoding="utf-8")
    (out_dir / "_custom_columns.json").write_text(json.dumps(custom_cols, indent=1, default=_json_default),
                                                  encoding="utf-8")
    def when(v):
        try:
            return datetime.fromisoformat(str(v))
        except ValueError:
            return None
    cutoff = when(prev_when) if prev_when else None
    since = [e for e in edit_log if cutoff is None or (when(e.get("at")) or cutoff) > cutoff]
    by_action = {}
    for e in since:
        by_action[e.get("action")] = by_action.get(e.get("action"), 0) + 1
    manifest["changes"] = {
        "previousPackagedAt": prev_when,
        "sheets": {k: {kk: (len(v) if isinstance(v, list) else v) for kk, v in d.items()} for k, d in diff.items()},
        "missingDataTool": {"entriesSincePrevious": len(since), "byAction": by_action, "totalEntries": len(edit_log)},
        "customColumns": [f"{c.get('sheet')}.{c.get('column')}" for c in custom_cols]}
    (out_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")

    log("\nWhat changed " + (f"since the last package ({prev_when[:19].replace('T', ' ')} UTC):" if prev_when
                             else "(no earlier package in this folder to compare with):"))
    if not prev:
        pass
    elif not diff:
        log("  nothing - same rows and columns as the last package")
    for sheet, d in diff.items():
        if d.get("newSheet"):
            log(f"  {sheet}: new file ({d['rows']} rows)")
            continue
        bits = []
        if d.get("rowsAdded"):
            ids = d["rowsAdded"]
            bits.append(f"+{len(ids)} rows ({', '.join(ids[:8])}{' ...' if len(ids) > 8 else ''})")
        if d.get("rowsRemoved"):
            bits.append(f"-{len(d['rowsRemoved'])} rows")
        if d.get("rowsChanged"):
            bits.append(f"{len(d['rowsChanged'])} changed")
        for c in d.get("columnsAdded", []):
            bits.append(f"new column {c['column']} ({c['filled']} filled)")
        if d.get("columnsRemoved"):
            bits.append(f"columns gone: {', '.join(d['columnsRemoved'])}")
        log(f"  {sheet}: " + "; ".join(bits))
    if since:
        log(f"Made with the missing data tool{' since then' if prev_when else ''}: {len(since)} change(s) - "
            + ", ".join(f"{n} {a}" for a, n in sorted(by_action.items(), key=lambda x: -x[1])))
        log("  details: _edit_log.json (who/when/old -> new), _package_diff.json (rows/columns per file)")
    if custom_cols:
        log("Columns added with the tool: " + ", ".join(f"{c.get('sheet')}.{c.get('column')}" for c in custom_cols))


def validate_piece(label, raw):
    """Catch pasted newlines / whitespace BEFORE stripping (after .strip() the evidence is gone)."""
    if raw and (raw != raw.strip() or "\n" in raw or "\r" in raw):
        return (f"The {label} field has a newline or leading/trailing whitespace in it -- this would "
                f"corrupt every image URL in the output. Please retype it directly instead of pasting.")
    return None

# --- UI Application ---


def run_gui():
    import tkinter as tk
    from tkinter import ttk, filedialog, messagebox
    from tkinter.scrolledtext import ScrolledText

    import queue
    import time
    import tk_ui

    root = tk.Tk()
    root.title("Beyblade packager")
    root.geometry("860x720")
    tk_ui.apply_theme(root)
    prefs = tk_ui.Prefs("packager")
    v = {k: tk.StringVar(value=prefs.get(k, "")) for k in ("parts", "products", "tcg", "out", "user", "repo")}
    v["branch"] = tk.StringVar(value=prefs.get("branch", "main"))
    for k, fn in S.BOOK_FILES.items():
        if not v[k].get() and Path(fn).exists():
            v[k].set(str(Path(fn).resolve()))

    cf = ttk.LabelFrame(root, text="Configuration", padding=10)
    cf.pack(fill=tk.X, padx=10, pady=10)
    r = 0
    for k, label in (("parts", "Parts workbook:"), ("products", "Products workbook:"), ("tcg", "TCG workbook:")):
        ttk.Label(cf, text=label).grid(row=r, column=0, sticky=tk.W, pady=3)
        ttk.Entry(cf, textvariable=v[k], width=55).grid(row=r, column=1, sticky=tk.EW, padx=5)
        ttk.Button(cf, text="Browse...", command=lambda k=k: v[k].set(
            filedialog.askopenfilename(filetypes=[("Excel files", "*.xlsx")]) or v[k].get())).grid(row=r, column=2)
        r += 1
    ttk.Label(cf, text="(leave any empty; a single old master workbook also works in any slot)",
              font=("", 8)).grid(row=r, column=1, sticky=tk.W)
    r += 1
    ttk.Label(cf, text="Output Folder:").grid(row=r, column=0, sticky=tk.W, pady=3)
    ttk.Entry(cf, textvariable=v["out"], width=55).grid(row=r, column=1, sticky=tk.EW, padx=5)
    ttk.Button(cf, text="Browse...", command=lambda: v["out"].set(filedialog.askdirectory() or v["out"].get())
               ).grid(row=r, column=2)
    r += 1
    for k, label in (("user", "GitHub Username:"), ("repo", "Repo Name:"), ("branch", "Branch:")):
        ttk.Label(cf, text=label).grid(row=r, column=0, sticky=tk.W, pady=3)
        ttk.Entry(cf, textvariable=v[k], width=30).grid(row=r, column=1, sticky=tk.W, padx=5)
        r += 1
    preview = ttk.Label(cf, text="", font=("", 8), foreground="#0066cc", wraplength=650)
    preview.grid(row=r, column=0, columnspan=3, sticky=tk.W)

    def upd(*_):
        u, rp, b = v["user"].get().strip(), v["repo"].get().strip(), v["branch"].get().strip() or "main"
        preview.config(text=f"Resulting URL prefix: {build_jsdelivr_url(u, rp, b)}" if u and rp
                       else "Enter username and repo to preview the resulting URL.")
    for k in ("user", "repo", "branch"):
        v[k].trace_add("write", upd)
    upd()
    cf.columnconfigure(1, weight=1)

    af = ttk.Frame(root)
    af.pack(fill=tk.X, padx=10)
    run_btn = ttk.Button(af, text="Run packager", style="Accent.TButton")
    run_btn.pack(side=tk.LEFT)

    def open_out():
        out = v["out"].get().strip()
        if out and os.path.isdir(out):
            import subprocess
            opener = "explorer" if sys.platform.startswith("win") else "open" if sys.platform == "darwin" else "xdg-open"
            subprocess.Popen([opener, out])
    ttk.Button(af, text="Open output folder", command=open_out).pack(side=tk.LEFT, padx=6)
    progress = ttk.Progressbar(af, mode="indeterminate")
    lf = ttk.LabelFrame(root, text="Log", padding=6)
    lf.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)
    log_text = ScrolledText(lf, state="disabled", bg="#151922", fg="#d7dce5", font=("Consolas", 9), wrap=tk.WORD)
    log_text.pack(fill=tk.BOTH, expand=True)
    sbar, set_status = tk_ui.status_bar(root)
    sbar.pack(fill=tk.X)
    q = queue.Queue()

    def log(msg):  # safe from any thread: drained on the UI thread
        q.put(str(msg))

    def pump():
        try:
            while True:
                line = q.get_nowait()
                log_text.configure(state="normal")
                log_text.insert(tk.END, line + "\n")
                log_text.see(tk.END)
                log_text.configure(state="disabled")
        except queue.Empty:
            pass
        root.after(100, pump)
    pump()

    def stop():
        progress.stop()
        progress.pack_forget()
        run_btn.config(state=tk.NORMAL)

    def start():
        for k in ("user", "repo", "branch"):
            err = validate_piece(k, v[k].get())
            if err:
                messagebox.showerror("Suspicious Input", err)
                return
        books = [v[k].get().strip() for k in ("parts", "products", "tcg") if v[k].get().strip()]
        if not (books and v["out"].get() and v["user"].get().strip() and v["repo"].get().strip()):
            messagebox.showerror("Missing Inputs", "Provide at least one workbook, the output folder, "
                                                   "GitHub username and repo name.")
            return
        base = build_jsdelivr_url(v["user"].get().strip(), v["repo"].get().strip(),
                                  v["branch"].get().strip() or "main")
        for k, var in v.items():
            prefs.set(k, var.get().strip())
        run_btn.config(state=tk.DISABLED)
        set_status(f"Packaging {len(books)} workbook(s) with {WORKERS} image threads ...", True)
        t0 = time.time()
        progress.pack(side=tk.LEFT, fill=tk.X, expand=True, padx=(10, 0))
        progress.start(15)
        log(f"Using base URL: {base}")

        result = {}

        def job():
            try:
                package(books, Path(v["out"].get()), base, log)
                log(f"\nSUCCESS: packaged in {time.time() - t0:.1f}s.")
                result["ok"] = True
            except Exception as e:
                import traceback
                log(f"\nERROR:\n{traceback.format_exc()}")
                result["err"] = e

        def wait(th):
            if th.is_alive():
                root.after(150, lambda: wait(th))
                return
            stop()
            if result.get("ok"):
                set_status(f"Done in {time.time() - t0:.1f}s - output in {v['out'].get()}", False)
            else:
                set_status("Failed - see the log", False)
                messagebox.showerror("Error", f"An error occurred:\n{result.get('err')}")
        th = threading.Thread(target=job, daemon=True)
        th.start()
        wait(th)

    run_btn.config(command=start)
    root.mainloop()


def run_cli(argv):
    ap = argparse.ArgumentParser(description="Package Beyblade workbooks into data/*.json + images")
    ap.add_argument("--parts")
    ap.add_argument("--products")
    ap.add_argument("--tcg")
    ap.add_argument("--workbook", action="append", default=[], help="any other / legacy master workbook")
    ap.add_argument("--out", required=True)
    ap.add_argument("--user", required=True)
    ap.add_argument("--repo", required=True)
    ap.add_argument("--branch", default="main")
    a = ap.parse_args(argv)
    for label in ("user", "repo", "branch"):
        err = validate_piece(label, getattr(a, label))
        if err:
            sys.exit(err)
    books = [b for b in (a.parts, a.products, a.tcg) if b] + a.workbook
    if not books:
        sys.exit("Give at least one workbook (--parts / --products / --tcg / --workbook).")
    package(books, Path(a.out), build_jsdelivr_url(a.user, a.repo, a.branch))


if __name__ == "__main__":
    if len(sys.argv) > 1:
        run_cli(sys.argv[1:])
    else:
        run_gui()
