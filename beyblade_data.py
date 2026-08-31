#!/usr/bin/env python3
"""
Packages the Beyblade dataset (from your Apps Script fullchunk endpoint)
into a folder of plain JSON + real image files, ready to upload to R2.
No third-party packages needed — Python standard library only (uses Tkinter for GUI).
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
    """
    Fetches JSON by streaming the response in chunks.
    Includes exponential backoff retry logic if the connection drops or times out.
    """
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=TIMEOUT_SECONDS) as resp:
            raw_bytes = bytearray()
            last_kb = 0
            
            # Read in 64KB blocks so we can log live progress
            while True:
                chunk = resp.read(1024 * 64)
                if not chunk:
                    break
                
                raw_bytes.extend(chunk)
                current_kb = len(raw_bytes) // 1024
                
                # Update UI every ~250KB downloaded to show it isn't frozen
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
    """Fetches all chunks for a sheet, tracking network download size and progress."""
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

def extract_images(row, sheet, out_dir, log_func, stats):
    """Extracts base64 images, saves them to disk, updates the row, and tracks missing images."""
    has_image = False
    
    # Try multiple common ID fields so we have a reliable name for the log
    row_id = row.get("dataID") or row.get("dataId") or row.get("code") or row.get("name") or "unknown_id"
    
    for key, value in list(row.items()):
        if isinstance(value, str) and value.startswith("data:"):
            has_image = True
            header, _, b64data = value.partition(",")
            content_type = header.split(";")[0].replace("data:", "") or "image/png"
            ext = CONTENT_TYPE_EXT.get(content_type, "bin")
            
            filename = f"{sheet}-{row_id}.{ext}"
            img_bytes = base64.b64decode(b64data)
            
            (out_dir / filename).write_bytes(img_bytes)
            row[key] = filename
            
            # Track and log the image extraction
            stats["image_count"] += 1
            stats["image_bytes"] += len(img_bytes)
            log_func(f"    -> Extracted: {filename} ({len(img_bytes) / 1024:.1f} KB)")
            
    if not has_image:
        warning_msg = f"Sheet: {sheet} | ID: {row_id}"
        stats["missing_images"].append(warning_msg)
        log_func(f"    [WARNING] No image data found for row: {row_id}")
            
    return row

class BeybladePackagerGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("Beyblade Data Packager")
        self.root.geometry("750x650")
        self.root.resizable(False, False)

        # URL Input
        tk.Label(root, text="Apps Script Web App URL:", font=("Arial", 10, "bold")).pack(pady=(10, 0), padx=10, anchor="w")
        
        self.url_var = tk.StringVar()
        self.url_entry = tk.Entry(root, textvariable=self.url_var, width=90)
        self.url_entry.pack(pady=5, padx=10)
        
        # Action Button
        self.run_btn = tk.Button(root, text="Package Data", command=self.start_packaging, bg="#4CAF50", fg="white", font=("Arial", 10, "bold"))
        self.run_btn.pack(pady=10)
        
        # Log Output
        tk.Label(root, text="Console Output:", font=("Arial", 10, "bold")).pack(padx=10, anchor="w")
        self.log_area = scrolledtext.ScrolledText(root, height=27, width=90, state=tk.DISABLED, bg="#f4f4f4", font=("Consolas", 9))
        self.log_area.pack(padx=10, pady=5)

    def log(self, message):
        """Thread-safe logging to the text area."""
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

        # Disable button and clear log
        self.run_btn.config(state=tk.DISABLED, text="Packaging...")
        self.log_area.config(state=tk.NORMAL)
        self.log_area.delete(1.0, tk.END)
        self.log_area.config(state=tk.DISABLED)
        
        # Run process in a background thread to prevent UI freezing
        thread = threading.Thread(target=self.process_data, args=(url,), daemon=True)
        thread.start()

    def process_data(self, base_url):
        try:
            self.log("=== Starting Data Packaging ===")
            self.log(f"Config: Chunk Size = {CHUNK_SIZE}, Max Retries = {MAX_RETRIES}, Timeout = {TIMEOUT_SECONDS}s\n")
            
            out_dir = Path("dist")
            out_dir.mkdir(exist_ok=True)
            manifest = {"sheets": {}}
            
            stats = {
                "network_bytes": 0,
                "image_count": 0,
                "image_bytes": 0,
                "json_bytes": 0,
                "row_count": 0,
                "missing_images": []
            }
            
            for sheet in TRACKED_SHEETS:
                self.log(f"\n--- Fetching Data: {sheet.upper()} ---")
                raw_rows = fetch_all_rows(base_url, sheet, self.log, stats)
                
                self.log(f"\n  Processing {len(raw_rows)} rows and extracting images...")
                rows = [extract_images(row, sheet, out_dir, self.log, stats) for row in raw_rows]
                stats["row_count"] += len(rows)

                out_path = out_dir / f"{sheet}.json"
                json_data = json.dumps(rows, separators=(",", ":"), ensure_ascii=False).encode('utf-8')
                out_path.write_bytes(json_data)
                
                stats["json_bytes"] += len(json_data)
                manifest["sheets"][sheet] = {"rowCount": len(rows)}
                self.log(f"  -> Wrote JSON: {out_path.name} ({len(json_data) / 1024:.1f} KB)")

            # Write manifest
            manifest_path = out_dir / "manifest.json"
            manifest_data = json.dumps(manifest, indent=2).encode('utf-8')
            manifest_path.write_bytes(manifest_data)
            stats["json_bytes"] += len(manifest_data)
            
            self.log("\n--- Zipping Everything ---")
            zip_path = Path("beyblade-data.zip")
            with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
                for f in sorted(out_dir.iterdir()):
                    zf.write(f, arcname=f.name)

            final_zip_size = zip_path.stat().st_size
            
            # Print Summary
            self.log("\n==========================================")
            self.log("             FINAL SUMMARY                ")
            self.log("==========================================")
            self.log(f"Total Rows Processed:    {stats['row_count']}")
            self.log(f"Total Images Extracted:  {stats['image_count']}")
            self.log(f"Total Network Download:  {stats['network_bytes'] / (1024*1024):.2f} MB")
            self.log(f"Raw Image Disk Size:     {stats['image_bytes'] / (1024*1024):.2f} MB")
            self.log(f"Raw JSON Disk Size:      {stats['json_bytes'] / (1024*1024):.2f} MB")
            self.log(f"Uncompressed Total Size: {(stats['image_bytes'] + stats['json_bytes']) / (1024*1024):.2f} MB")
            self.log(f"FINAL ZIP FILE SIZE:     {final_zip_size / (1024*1024):.2f} MB")
            
            if stats["missing_images"]:
                self.log("\n!!! ROWS MISSING IMAGES !!!")
                for missing in stats["missing_images"]:
                    self.log(f"  - {missing}")
            else:
                self.log("\nRows Missing Images:     0 (Perfect extraction!)")
                
            self.log("==========================================")
            self.log(f"\nSUCCESS: Data saved to {zip_path.resolve()}")
            
            # Update popup message to mention missing images if any
            popup_msg = f"Data packaged successfully!\n\nExtracted {stats['image_count']} images.\nFinal Zip Size: {final_zip_size / (1024*1024):.2f} MB\n"
            if stats["missing_images"]:
                popup_msg += f"\nWarning: {len(stats['missing_images'])} rows were missing images (Check logs)."
            popup_msg += f"\n\nSaved to:\n{zip_path.resolve()}"
            
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