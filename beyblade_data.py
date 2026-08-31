#!/usr/bin/env python3
"""
Packages the Beyblade dataset from Apps Script into two separate zips:
1. Metadata Only (All data, but image fields are set to null)
2. Images Only (Only data IDs + image filenames, plus the actual image files)
"""

import base64
import json
import sys
import time
import urllib.parse
import urllib.request
import urllib.error
import zipfile
import threading
import tkinter as tk
from tkinter import scrolledtext, messagebox
from pathlib import Path
import shutil

TRACKED_SHEETS = ["blades", "ratchets", "bits", "lockChips", "mainBlades", "assistBlades"]
CHUNK_SIZE = 10  # Reduced chunk size for better stability
MAX_RETRIES = 3
TIMEOUT_SECONDS = 90  # Increased timeout for slow Apps Script generation

CONTENT_TYPE_EXT = {
    "image/png": "png",
    "image/jpeg": "jpg",
    "image/jpg": "jpg",
    "image/gif": "gif",
    "image/webp": "webp",
}

def fetch_json_stream(url, log_func, attempt=1):
    """Fetches JSON by streaming the response in chunks with retries."""
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=TIMEOUT_SECONDS) as resp:
            raw_bytes = bytearray()
            last_kb = 0
            
            while True:
                chunk = resp.read(1024 * 64)
                if not chunk:
                    break
                
                raw_bytes.extend(chunk)
                current_kb = len(raw_bytes) // 1024
                
                if current_kb - last_kb >= 250:
                    log_func(f"       ... receiving data: {current_kb} KB")
                    last_kb = current_kb
                    
            log_func(f"       -> Chunk download complete: {len(raw_bytes) / 1024:.1f} KB")
            return json.loads(raw_bytes.decode("utf-8")), len(raw_bytes)
            
    except (urllib.error.URLError, TimeoutError, ConnectionResetError) as e:
        if attempt <= MAX_RETRIES:
            wait_time = 2 ** attempt
            log_func(f"    [!] Network error ({str(e)}). Retrying {attempt}/{MAX_RETRIES} in {wait_time}s...")
            time.sleep(wait_time)
            return fetch_json_stream(url, log_func, attempt + 1)
        else:
            raise Exception(f"Failed after {MAX_RETRIES} attempts. Last error: {str(e)}")

def fetch_all_rows(base_url, sheet, log_func, stats):
    """Fetches all chunks for a sheet, tracking network download size."""
    rows = []
    offset = 0
    while True:
        log_func(f"\n  [{sheet}] Requesting rows {offset} to {offset + CHUNK_SIZE - 1}...")
        
        params = urllib.parse.urlencode(
            {"action": "fullchunk", "sheet": sheet, "offset": offset, "limit": CHUNK_SIZE}
        )
        url = f"{base_url}?{params}"
        
        data, byte_size = fetch_json_stream(url, log_func)
        stats["network_bytes"] += byte_size
        
        if "error" in data:
            raise RuntimeError(f"Apps Script error for {sheet}: {data['error']}")
            
        rows.extend(data["rows"])
        log_func(f"  [{sheet}] Total progress: {len(rows)}/{data['total']} rows processed")
        
        if not data["hasMore"] or not data["rows"]:
            break
        offset += len(data["rows"])
    return rows

def extract_images(row, sheet, img_dir, log_func, stats):
    """
    Splits the row into two dictionaries:
    1. row_meta: All data, but image fields are set to null.
    2. row_images: Only the ID fields and the generated image filenames.
    """
    has_image = False
    
    # Identify the primary ID for naming the file
    row_id = row.get("dataID") or row.get("dataId") or row.get("code") or row.get("name") or "unknown_id"
    
    row_meta = dict(row)
    row_images = {}
    
    # Ensure the images package keeps the identifier keys so users can join the data later
    for id_key in ["dataID", "dataId", "code", "name"]:
        if id_key in row:
            row_images[id_key] = row[id_key]
    
    for key, value in list(row.items()):
        if isinstance(value, str) and value.startswith("data:"):
            has_image = True
            header, _, b64data = value.partition(",")
            content_type = header.split(";")[0].replace("data:", "") or "image/png"
            ext = CONTENT_TYPE_EXT.get(content_type, "bin")
            
            filename = f"{sheet}-{row_id}.{ext}"
            img_bytes = base64.b64decode(b64data)
            
            # Save the physical image to the images directory
            (img_dir / filename).write_bytes(img_bytes)
            
            # SPLIT THE DATA
            row_meta[key] = None          # Metadata gets null instead of base64
            row_images[key] = filename    # Images package gets the filename
            
            stats["image_count"] += 1
            stats["image_bytes"] += len(img_bytes)
            log_func(f"    -> Extracted: {filename} ({len(img_bytes) / 1024:.1f} KB)")
            
    if not has_image:
        warning_msg = f"Sheet: {sheet} | ID: {row_id}"
        stats["missing_images"].append(warning_msg)
        log_func(f"    [WARNING] No image data found for row: {row_id}")
            
    return row_meta, row_images

class BeybladePackagerGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("Beyblade Data Packager")
        self.root.geometry("750x650")
        self.root.resizable(False, False)

        tk.Label(root, text="Apps Script Web App URL:", font=("Arial", 10, "bold")).pack(pady=(10, 0), padx=10, anchor="w")
        
        self.url_var = tk.StringVar()
        self.url_entry = tk.Entry(root, textvariable=self.url_var, width=90)
        self.url_entry.pack(pady=5, padx=10)
        
        self.run_btn = tk.Button(root, text="Package Data", command=self.start_packaging, bg="#4CAF50", fg="white", font=("Arial", 10, "bold"))
        self.run_btn.pack(pady=10)
        
        tk.Label(root, text="Console Output:", font=("Arial", 10, "bold")).pack(padx=10, anchor="w")
        self.log_area = scrolledtext.ScrolledText(root, height=27, width=90, state=tk.DISABLED, bg="#f4f4f4", font=("Consolas", 9))
        self.log_area.pack(padx=10, pady=5)

    def log(self, message):
        self.root.after(0, self._append_log, message)

    def _append_log(self, message):
        self.log_area.config(state=tk.NORMAL)
        self.log_area.insert(tk.END, message + "\n")
        self.log_area.see(tk.END)
        self.log_area.config(state=tk.DISABLED)

    def start_packaging(self):
        url = self.url_var.get().strip()
        if not url.startswith("http"):
            messagebox.showwarning("Invalid URL", "Please enter a valid HTTP/HTTPS URL.")
            return

        self.run_btn.config(state=tk.DISABLED, text="Packaging...")
        self.log_area.config(state=tk.NORMAL)
        self.log_area.delete(1.0, tk.END)
        self.log_area.config(state=tk.DISABLED)
        
        thread = threading.Thread(target=self.process_data, args=(url,), daemon=True)
        thread.start()

    def process_data(self, base_url):
        try:
            self.log("=== Starting Data Split Packaging ===")
            
            # Setup separate directories for Meta and Images
            out_dir = Path("dist")
            if out_dir.exists():
                shutil.rmtree(out_dir)
                
            meta_dir = out_dir / "meta"
            img_dir = out_dir / "images"
            meta_dir.mkdir(parents=True, exist_ok=True)
            img_dir.mkdir(parents=True, exist_ok=True)
            
            manifest_meta = {"sheets": {}}
            manifest_img = {"sheets": {}}
            
            stats = {
                "network_bytes": 0, "image_count": 0, "image_bytes": 0,
                "meta_json_bytes": 0, "img_json_bytes": 0, "row_count": 0,
                "missing_images": []
            }
            
            for sheet in TRACKED_SHEETS:
                self.log(f"\n--- Fetching Data: {sheet.upper()} ---")
                raw_rows = fetch_all_rows(base_url, sheet, self.log, stats)
                
                self.log(f"\n  Splitting {len(raw_rows)} rows...")
                meta_rows = []
                image_rows = []
                
                for row in raw_rows:
                    r_meta, r_img = extract_images(row, sheet, img_dir, self.log, stats)
                    meta_rows.append(r_meta)
                    image_rows.append(r_img)
                    
                stats["row_count"] += len(raw_rows)

                # Write Meta JSON
                meta_path = meta_dir / f"{sheet}.json"
                meta_json_data = json.dumps(meta_rows, separators=(",", ":"), ensure_ascii=False).encode('utf-8')
                meta_path.write_bytes(meta_json_data)
                stats["meta_json_bytes"] += len(meta_json_data)
                
                # Write Images JSON
                img_path = img_dir / f"{sheet}.json"
                img_json_data = json.dumps(image_rows, separators=(",", ":"), ensure_ascii=False).encode('utf-8')
                img_path.write_bytes(img_json_data)
                stats["img_json_bytes"] += len(img_json_data)

                manifest_meta["sheets"][sheet] = {"rowCount": len(meta_rows)}
                manifest_img["sheets"][sheet] = {"rowCount": len(image_rows)}
                
                self.log(f"  -> Wrote split JSONs for {sheet}")

            # Write manifests
            (meta_dir / "manifest.json").write_bytes(json.dumps(manifest_meta, indent=2).encode('utf-8'))
            (img_dir / "manifest.json").write_bytes(json.dumps(manifest_img, indent=2).encode('utf-8'))
            
            self.log("\n--- Zipping Packages ---")
            meta_zip_path = Path("beyblade-metadata-only.zip")
            img_zip_path = Path("beyblade-images-only.zip")
            
            # Zip Metadata
            with zipfile.ZipFile(meta_zip_path, "w", zipfile.ZIP_DEFLATED) as zf_meta:
                for f in sorted(meta_dir.iterdir()):
                    zf_meta.write(f, arcname=f.name)
                    
            # Zip Images
            with zipfile.ZipFile(img_zip_path, "w", zipfile.ZIP_DEFLATED) as zf_img:
                for f in sorted(img_dir.iterdir()):
                    zf_img.write(f, arcname=f.name)

            meta_zip_size = meta_zip_path.stat().st_size
            img_zip_size = img_zip_path.stat().st_size
            
            # Print Summary
            self.log("\n==========================================")
            self.log("             FINAL SUMMARY                ")
            self.log("==========================================")
            self.log(f"Total Rows Processed:    {stats['row_count']}")
            self.log(f"Total Images Extracted:  {stats['image_count']}")
            self.log(f"Total Network Download:  {stats['network_bytes'] / (1024*1024):.2f} MB")
            self.log("------------------------------------------")
            self.log(f"META ZIP (Text Only):    {meta_zip_size / (1024*1024):.3f} MB")
            self.log(f"IMAGES ZIP (Media+IDs):  {img_zip_size / (1024*1024):.2f} MB")
            
            if stats["missing_images"]:
                self.log("\n!!! ROWS MISSING IMAGES !!!")
                for missing in stats["missing_images"]:
                    self.log(f"  - {missing}")
            else:
                self.log("\nRows Missing Images:     0 (Perfect extraction!)")
                
            self.log("==========================================")
            self.log(f"\nSUCCESS: Data saved locally.")
            
            popup_msg = f"Data packaged successfully!\n\n"
            popup_msg += f"Metadata Package: {meta_zip_size / 1024:.1f} KB\n"
            popup_msg += f"Images Package: {img_zip_size / (1024*1024):.2f} MB\n"
            
            if stats["missing_images"]:
                popup_msg += f"\nWarning: {len(stats['missing_images'])} rows were missing images (Check logs)."
            
            self.root.after(0, lambda: messagebox.showinfo("Finished", popup_msg))
            
        except Exception as e:
            self.log(f"\nFATAL ERROR: {str(e)}")
            self.root.after(0, lambda: messagebox.showerror("Error", f"An error occurred:\n{str(e)}"))
            
        finally:
            self.root.after(0, lambda: self.run_btn.config(state=tk.NORMAL, text="Package Data"))

if __name__ == "__main__":
    root = tk.Tk()
    app = BeybladePackagerGUI(root)
    if len(sys.argv) > 1:
        app.url_var.set(sys.argv[1])
    root.mainloop()