#!/usr/bin/env python3
"""
Image tool: put an image you found yourself onto an existing row of a workbook.

You pick the workbook, the tab (sheet) and the row's id (dataID / productID / setID); the image is
normalised (transparent borders trimmed, fitted inside 600 px, a 128 px minified copy made, both WebP)
and placed in that row's image + minified image cells, ready for the packager. Nothing else in the
workbook changes; a .bak copy is made before the first save.

    GUI:  the "Image tool..." button in the packager (python beyblade_data.py), or python image_tool.py
    CLI:  python beyblade_data.py image --workbook beyblade_parts.xlsx --sheet Parts_X_Blades --id 65 --file pic.png
          python beyblade_data.py image --workbook beyblade_parts.xlsx --sheet Parts_X_Blades --id 65 --url https://...
          python beyblade_data.py image --workbook beyblade_parts.xlsx --sheet Parts_X_Blades --missing
"""
import argparse
import base64
import io
import os
import sys

from PIL import Image

import beyblade_schema as S
from beyblade_store import Book

FULL_SIZE = 600
MIN_SIZE = 128
WEBP_QUALITY = 85


# ── core (no GUI) ─────────────────────────────────────────────────────────────

def normalize_image(data, full=FULL_SIZE, mini=MIN_SIZE):
    """Any image bytes -> (full_webp, min_webp). Trims fully transparent borders, keeps the aspect
    ratio, fits inside full x full (never upscales), white/opaque images are left as they are."""
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


def kind_of_workbook(path):
    name = os.path.basename(path).lower()
    return "tcg" if "tcg" in name else "products" if "product" in name else "parts"


def image_sheet_info(sheet_name):
    """-> (id column, full image column, minified image column) or None for sheets without images."""
    if S.parse_part_sheet(sheet_name):
        return ("dataID",) + tuple(S.PART_IMAGE_COLS)
    cfg = S.SHEETS.get(sheet_name)
    if cfg and cfg.get("images"):
        return (cfg["id"],) + tuple(cfg["images"])
    return None


def image_sheets(book):
    return [n for n in book.wb.sheetnames if image_sheet_info(n)]


def list_rows(book, sheet):
    """[(row_number, id, label, has_image, has_min)] for a sheet."""
    idc, full_c, min_c = image_sheet_info(sheet)
    ws = book.wb[sheet]
    hdr = book.headers(ws)
    with_full = {im.anchor._from.row + 1 for im in ws._images if im.anchor._from.col + 1 == hdr.get(full_c)}
    with_min = {im.anchor._from.row + 1 for im in ws._images if im.anchor._from.col + 1 == hdr.get(min_c)}
    out = []
    for r, x in book.rows(ws):
        name = x.get("name") or x.get("productName") or x.get("setName") or ""
        bits = [str(b) for b in (name, x.get("code") or x.get("sku") or x.get("cardNumber") or x.get("setCode"),
                                 x.get("variantLabel") or x.get("edition")) if b]
        out.append((r, x.get(idc), " | ".join(bits), r in with_full, r in with_min))
    return out


def find_row(book, sheet, row_id):
    idc = image_sheet_info(sheet)[0]
    r, _ = book.find(book.wb[sheet], lambda x: str(x.get(idc)).strip() == str(row_id).strip())
    return r


def set_row_image(book, sheet, row_id, data, save=True):
    """Normalise [data] and put it on the row whose id is [row_id]. Returns (row_number, full, mini)."""
    info = image_sheet_info(sheet)
    if not info:
        raise ValueError(f"{sheet} has no image columns")
    r = find_row(book, sheet, row_id)
    if r is None:
        raise ValueError(f"No row with {info[0]} = {row_id} in {sheet}")
    full, mini = normalize_image(data)
    ws = book.wb[sheet]
    book.set_image(ws, r, info[1], full, "full", replace=True)
    book.set_image(ws, r, info[2], mini, "min", replace=True)
    if save:
        book.save()
    return r, full, mini


def current_image(book, sheet, r):
    info = image_sheet_info(sheet)
    ws = book.wb[sheet]
    col = book.headers(ws).get(info[1])
    for im in ws._images:
        if im.anchor._from.row + 1 == r and im.anchor._from.col + 1 == col:
            return im._data()
    return None


def fetch_url(url):
    import requests
    r = requests.get(url, timeout=(10, 30), headers={"User-Agent": "ClasherImageTool/1.0"})
    r.raise_for_status()
    return r.content


# ── CLI ───────────────────────────────────────────────────────────────────────

def run_cli(argv):
    ap = argparse.ArgumentParser(prog="beyblade_data.py image", description="Put an image on a workbook row")
    ap.add_argument("--workbook", required=True)
    ap.add_argument("--sheet", required=True, help="tab name, e.g. Parts_X_Blades, Products, TCG_Cards")
    ap.add_argument("--id", help="row id (dataID / productID / setID)")
    ap.add_argument("--file", help="image file (png, jpg, webp, gif ...)")
    ap.add_argument("--url", help="image URL")
    ap.add_argument("--missing", action="store_true", help="list rows that have no image yet")
    a = ap.parse_args(argv)
    book = Book(a.workbook, kind_of_workbook(a.workbook))
    if a.sheet not in book.wb.sheetnames or not image_sheet_info(a.sheet):
        sys.exit(f"'{a.sheet}' isn't an image tab of {a.workbook}. Tabs: {', '.join(image_sheets(book))}")
    if a.missing:
        rows = [x for x in list_rows(book, a.sheet) if not x[3]]
        print(f"{len(rows)} rows in {a.sheet} without an image:")
        for r, rid, label, _, _ in rows:
            print(f"  {rid!s:>6}  {label}")
        return
    if not a.id or not (a.file or a.url):
        sys.exit("Give --id and --file or --url (or --missing).")
    data = fetch_url(a.url) if a.url else open(a.file, "rb").read()
    try:
        r, full, mini = set_row_image(book, a.sheet, a.id, data)
    except ValueError as e:
        sys.exit(str(e))
    print(f"{a.sheet} row {r} (id {a.id}): image {len(full) // 1024} KB + minified {len(mini) // 1024} KB "
          f"saved to {a.workbook}")


# ── GUI ───────────────────────────────────────────────────────────────────────

def open_window(master=None, workbook=""):
    """Image tool window. As a Toplevel of the packager, or standalone."""
    import tkinter as tk
    from tkinter import ttk, filedialog, messagebox

    win = tk.Toplevel(master) if master else tk.Tk()
    win.title("Image tool - put an image on a row")
    win.geometry("980x640")
    state = {"book": None, "rows": [], "new": None}

    top = ttk.Frame(win, padding=8)
    top.pack(fill=tk.X)
    wb_var, sheet_var, filt_var = tk.StringVar(value=workbook), tk.StringVar(), tk.StringVar()
    only_missing = tk.BooleanVar(value=True)
    ttk.Label(top, text="Workbook:").grid(row=0, column=0, sticky="w")
    ttk.Entry(top, textvariable=wb_var, width=60).grid(row=0, column=1, sticky="we", padx=4)
    ttk.Button(top, text="Browse...", command=lambda: (wb_var.set(
        filedialog.askopenfilename(filetypes=[("Excel files", "*.xlsx")]) or wb_var.get()), load_book())
               ).grid(row=0, column=2)
    ttk.Button(top, text="Open", command=lambda: load_book()).grid(row=0, column=3, padx=4)
    ttk.Label(top, text="Tab:").grid(row=1, column=0, sticky="w", pady=4)
    sheet_box = ttk.Combobox(top, textvariable=sheet_var, width=40, state="readonly")
    sheet_box.grid(row=1, column=1, sticky="w", padx=4)
    ttk.Label(top, text="Filter:").grid(row=2, column=0, sticky="w")
    ttk.Entry(top, textvariable=filt_var, width=40).grid(row=2, column=1, sticky="w", padx=4)
    ttk.Checkbutton(top, text="Only rows without an image", variable=only_missing,
                    command=lambda: fill_list()).grid(row=2, column=2, columnspan=2, sticky="w")
    top.columnconfigure(1, weight=1)

    body = ttk.Frame(win, padding=8)
    body.pack(fill=tk.BOTH, expand=True)
    lst = tk.Listbox(body, font=("Consolas", 10), activestyle="dotbox")
    lst.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
    sb = ttk.Scrollbar(body, command=lst.yview)
    sb.pack(side=tk.LEFT, fill=tk.Y)
    lst.config(yscrollcommand=sb.set)

    side = ttk.Frame(body, padding=(10, 0))
    side.pack(side=tk.LEFT, fill=tk.Y)
    sel_lbl = ttk.Label(side, text="Pick a row", wraplength=300)
    sel_lbl.pack(anchor="w")
    ttk.Label(side, text="Current image:").pack(anchor="w", pady=(8, 0))
    cur_img = ttk.Label(side)
    cur_img.pack(anchor="w")
    ttk.Label(side, text="New image:").pack(anchor="w", pady=(8, 0))
    new_img = ttk.Label(side)
    new_img.pack(anchor="w")
    url_var = tk.StringVar()
    src = ttk.Frame(side)
    src.pack(anchor="w", pady=6, fill=tk.X)
    ttk.Button(src, text="Choose file...", command=lambda: load_new("file")).pack(fill=tk.X)
    ttk.Button(src, text="Paste from clipboard", command=lambda: load_new("clipboard")).pack(fill=tk.X, pady=2)
    ttk.Entry(src, textvariable=url_var).pack(fill=tk.X, pady=(6, 0))
    ttk.Button(src, text="Load from URL", command=lambda: load_new("url")).pack(fill=tk.X)
    save_btn = ttk.Button(side, text="Save image to this row", state="disabled", command=lambda: save())
    save_btn.pack(fill=tk.X, pady=(10, 0))
    status = ttk.Label(win, text="", padding=6, foreground="#0066cc")
    status.pack(fill=tk.X)

    def preview(widget, data, size=220):
        if not data:
            widget.config(image="", text="(none)")
            widget.image = None
            return
        im = Image.open(io.BytesIO(data)).convert("RGBA")
        im.thumbnail((size, size))
        buf = io.BytesIO()
        im.save(buf, "PNG")
        photo = tk.PhotoImage(data=base64.b64encode(buf.getvalue()))
        widget.config(image=photo, text="")
        widget.image = photo

    def load_book():
        path = wb_var.get().strip()
        if not path or not os.path.exists(path):
            status.config(text="Choose an existing workbook.")
            return
        status.config(text=f"Opening {os.path.basename(path)} ...")
        win.update_idletasks()
        state["book"] = Book(path, kind_of_workbook(path))
        sheets = image_sheets(state["book"])
        sheet_box.config(values=sheets)
        if sheets:
            with_rows = [s for s in sheets if state["book"].rows(state["book"].wb[s])]
            sheet_var.set((with_rows or sheets)[0])
        fill_list()
        status.config(text=f"Opened {os.path.basename(path)}: {len(sheets)} tabs with images.")

    def fill_list(*_):
        lst.delete(0, tk.END)
        state["rows"] = []
        if not state["book"] or not sheet_var.get():
            return
        f = filt_var.get().strip().lower()
        for row in list_rows(state["book"], sheet_var.get()):
            r, rid, label, has_full, _ = row
            if only_missing.get() and has_full:
                continue
            if f and f not in f"{rid} {label}".lower():
                continue
            state["rows"].append(row)
            lst.insert(tk.END, f"{rid!s:>6}  {'img ' if has_full else '--- '} {label}")
        status.config(text=f"{len(state['rows'])} rows shown in {sheet_var.get()}")

    def selected():
        i = lst.curselection()
        return state["rows"][i[0]] if i else None

    def on_select(_=None):
        row = selected()
        if not row:
            return
        r, rid, label, _, _ = row
        sel_lbl.config(text=f"{sheet_var.get()}  id {rid}\n{label}")
        preview(cur_img, current_image(state["book"], sheet_var.get(), r))
        save_btn.config(state="normal" if state["new"] else "disabled")

    def load_new(how):
        try:
            if how == "file":
                p = filedialog.askopenfilename(filetypes=[("Images", "*.png *.jpg *.jpeg *.webp *.gif *.bmp"),
                                                          ("All files", "*.*")])
                if not p:
                    return
                data = open(p, "rb").read()
            elif how == "url":
                if not url_var.get().strip():
                    return
                data = fetch_url(url_var.get().strip())
            else:
                from PIL import ImageGrab
                clip = ImageGrab.grabclipboard()
                if clip is None:
                    status.config(text="No image on the clipboard (copy the image itself, not the page).")
                    return
                if isinstance(clip, list):  # copied files
                    data = open(clip[0], "rb").read()
                else:
                    buf = io.BytesIO()
                    clip.save(buf, "PNG")
                    data = buf.getvalue()
            full, mini = normalize_image(data)
        except Exception as e:
            messagebox.showerror("Image", f"Couldn't load that image:\n{e}")
            return
        state["new"] = data
        preview(new_img, full)
        status.config(text=f"New image ready: {len(full) // 1024} KB WebP + {len(mini) // 1024} KB minified. "
                           "Pick the row and press Save.")
        save_btn.config(state="normal" if selected() else "disabled")

    def save():
        row = selected()
        if not row or not state["new"]:
            return
        r, rid, label, _, _ = row
        try:
            set_row_image(state["book"], sheet_var.get(), rid, state["new"])
        except Exception as e:
            messagebox.showerror("Image", str(e))
            return
        status.config(text=f"Saved image on {sheet_var.get()} id {rid} ({label}). Workbook saved (.bak kept).")
        state["new"] = None
        preview(new_img, None)
        save_btn.config(state="disabled")
        fill_list()

    lst.bind("<<ListboxSelect>>", on_select)
    sheet_box.bind("<<ComboboxSelected>>", fill_list)
    filt_var.trace_add("write", fill_list)
    if workbook:
        win.after(100, load_book)
    if not master:
        win.mainloop()
    return win


if __name__ == "__main__":
    if len(sys.argv) > 1:
        run_cli(sys.argv[1:])
    else:
        open_window()
