#!/usr/bin/env python3
import base64
import json
import time
import urllib.parse
import urllib.request
import threading
import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox
from datetime import datetime, timezone
from pathlib import Path

TRACKED_SHEETS = ["blades", "ratchets", "bits", "lockChips", "mainBlades", "assistBlades"]
CHUNK_SIZE = 9  # Locked to 9 for optimal performance
CONTENT_TYPE_EXT = {
    "image/png": "png",
    "image/jpeg": "jpg",
    "image/jpg": "jpg",
    "image/gif": "gif",
    "image/webp": "webp",
}

class DataPackagerApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("Beyblade Data Packager")
        self.geometry("750x650") # Made slightly wider to fit the new detailed logs
        self.resizable(False, False)

        # Tracking variables
        self.total_downloaded_bytes = 0
        self.process_start_time = 0

        # Setup UI Elements
        self.create_widgets()

    def create_widgets(self):
        # Input Frame
        input_frame = ttk.LabelFrame(self, text="Configuration", padding=(10, 10))
        input_frame.pack(padx=10, pady=10, fill="x")

        # Apps Script URL
        ttk.Label(input_frame, text="Apps Script URL:").grid(row=0, column=0, sticky="w", pady=5)
        self.url_entry = ttk.Entry(input_frame, width=65)
        self.url_entry.grid(row=0, column=1, padx=5, pady=5)

        # GitHub Owner
        ttk.Label(input_frame, text="GitHub Owner:").grid(row=1, column=0, sticky="w", pady=5)
        self.owner_entry = ttk.Entry(input_frame, width=65)
        self.owner_entry.grid(row=1, column=1, padx=5, pady=5)

        # GitHub Repo
        ttk.Label(input_frame, text="GitHub Repo:").grid(row=2, column=0, sticky="w", pady=5)
        self.repo_entry = ttk.Entry(input_frame, width=65)
        self.repo_entry.grid(row=2, column=1, padx=5, pady=5)

        # Branch
        ttk.Label(input_frame, text="Branch (default 'main'):").grid(row=3, column=0, sticky="w", pady=5)
        self.branch_entry = ttk.Entry(input_frame, width=65)
        self.branch_entry.insert(0, "main")
        self.branch_entry.grid(row=3, column=1, padx=5, pady=5)

        # Run Button
        self.run_btn = ttk.Button(self, text="Package Data", command=self.start_packaging)
        self.run_btn.pack(pady=5)

        # Log Output
        log_frame = ttk.LabelFrame(self, text="Execution Logs", padding=(10, 10))
        log_frame.pack(padx=10, pady=5, fill="both", expand=True)

        self.log_area = scrolledtext.ScrolledText(log_frame, wrap=tk.WORD, height=18, state="disabled")
        self.log_area.pack(fill="both", expand=True)

    def log(self, message, level="INFO"):
        """Appends a formatted, timestamped message to the log area safely."""
        timestamp = datetime.now().strftime("%H:%M:%S")
        
        # Add visual spacing for final instructions
        if level == "PROMPT":
            log_entry = f"\n[{timestamp}] [ACTION REQUIRED]\n{message}\n"
        else:
            log_entry = f"[{timestamp}] [{level}] {message}\n"
            
        self.log_area.config(state="normal")
        self.log_area.insert(tk.END, log_entry)
        self.log_area.see(tk.END)
        self.log_area.config(state="disabled")
        self.update_idletasks()

    def fetch_json(self, url):
        """Fetches the JSON and returns a tuple of (parsed_data, real_byte_size)."""
        with urllib.request.urlopen(url, timeout=60) as resp:
            raw_bytes = resp.read()
            size_in_bytes = len(raw_bytes)
            data = json.loads(raw_bytes.decode("utf-8"))
            return data, size_in_bytes

    def format_time(self, seconds):
        """Converts seconds into HH:MM:SS format."""
        m, s = divmod(int(seconds), 60)
        h, m = divmod(m, 60)
        return f"{h:02d}:{m:02d}:{s:02d}"

    def fetch_all_rows(self, base_url, sheet):
        rows = []
        offset = 0
        while True:
            params = urllib.parse.urlencode(
                {"action": "fullchunk", "sheet": sheet, "offset": offset, "limit": CHUNK_SIZE}
            )
            
            # Start timer for chunk
            chunk_start_time = time.time()
            data, chunk_size_bytes = self.fetch_json(f"{base_url}?{params}")
            chunk_duration = time.time() - chunk_start_time
            
            # Update cumulative stats
            self.total_downloaded_bytes += chunk_size_bytes
            elapsed_total = time.time() - self.process_start_time
            
            if "error" in data:
                raise RuntimeError(f"Apps Script error for {sheet}: {data['error']}")
            
            chunk_rows = data["rows"]
            rows.extend(chunk_rows)
            
            # Calculate metrics
            num_rows = len(chunk_rows)
            avg_row_size_kb = (chunk_size_bytes / num_rows / 1024) if num_rows > 0 else 0
            chunk_size_kb = chunk_size_bytes / 1024
            total_mb = self.total_downloaded_bytes / (1024 * 1024)
            
            # Format the log message
            log_msg = (
                f"{sheet}: {len(rows)}/{data['total']} rows "
                f"| Chunk: {chunk_duration:.2f}s, {chunk_size_kb:.1f} KB (Avg: {avg_row_size_kb:.1f} KB/row) "
                f"| Total: {total_mb:.2f} MB, Lapsed: {self.format_time(elapsed_total)}"
            )
            self.log(log_msg)
            
            if not data["hasMore"] or not chunk_rows:
                break
            offset += num_rows
        return rows

    def extract_image(self, row, sheet, images_dir, raw_base_url):
        for key, value in list(row.items()):
            if isinstance(value, str) and value.startswith("data:"):
                header, _, b64data = value.partition(",")
                content_type = header.split(";")[0].replace("data:", "") or "image/png"
                ext = CONTENT_TYPE_EXT.get(content_type, "bin")
                data_id = row.get("dataID") or row.get("dataId") or row.get("code") or "unknown"
                filename = f"{sheet}-{data_id}.{ext}"
                
                # Write the image file physically
                (images_dir / filename).write_bytes(base64.b64decode(b64data))
                
                # Replace the data URI in the JSON with the future GitHub Raw URL
                row[key] = f"{raw_base_url}images/{filename}"
        return row

    def sheet_manifest_entry(self, rows):
        timestamps = [r.get("updated_at") or r.get("updatedAt") for r in rows]
        timestamps = [t for t in timestamps if t]
        return {
            "latestUpdatedAt": max(timestamps) if timestamps else None,
            "rowCount": len(rows),
        }

    def process_data(self):
        base_url = self.url_entry.get().strip()
        owner = self.owner_entry.get().strip()
        repo = self.repo_entry.get().strip()
        branch = self.branch_entry.get().strip() or "main"

        if not all([base_url, owner, repo]):
            messagebox.showerror("Error", "URL, Owner, and Repo are required fields.")
            self.run_btn.config(state="normal")
            return

        raw_base_url = f"https://raw.githubusercontent.com/{owner}/{repo}/{branch}/data/"

        out_dir = Path("data")
        images_dir = out_dir / "images"
        images_dir.mkdir(parents=True, exist_ok=True)

        manifest = {"publishedAt": datetime.now(timezone.utc).isoformat(), "sheets": {}}
        
        # Reset trackers
        self.total_downloaded_bytes = 0
        self.process_start_time = time.time()
        
        self.log(f"Starting packaging process. Output directory: {out_dir.resolve()}")

        try:
            for sheet in TRACKED_SHEETS:
                self.log(f"Fetching data for sheet: {sheet}...", level="START")
                raw_rows = self.fetch_all_rows(base_url, sheet)
                
                manifest["sheets"][sheet] = self.sheet_manifest_entry(raw_rows)
                
                # Process images and rows
                rows = [self.extract_image(row, sheet, images_dir, raw_base_url) for row in raw_rows]
                
                # Save sheet JSON with explicit UTF-8 encoding
                out_path = out_dir / f"{sheet}.json"
                out_path.write_text(json.dumps(rows, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
                self.log(f"Saved {out_path.name} ({len(rows)} rows)", level="SUCCESS")

            # Save Manifest with explicit UTF-8 encoding
            manifest_path = out_dir / "manifest.json"
            manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
            self.log(f"Saved {manifest_path.name}", level="SUCCESS")
            
            # Print Summary
            total_elapsed = time.time() - self.process_start_time
            total_mb_final = self.total_downloaded_bytes / (1024 * 1024)
            
            self.log("=== MANIFEST SUMMARY ===", level="INFO")
            for sheet, info in manifest["sheets"].items():
                self.log(f"  {sheet}: {info['rowCount']} rows, latest edit: {info['latestUpdatedAt']}", level="INFO")
            
            self.log(f"Total Download Size: {total_mb_final:.2f} MB", level="INFO")
            self.log(f"Total Execution Time: {self.format_time(total_elapsed)}", level="INFO")

            # Final steps prompt for the user
            final_instructions = (
                f"Data successfully packaged to {out_dir.resolve()}/\n"
                "To upload to GitHub, run these commands in your terminal:\n\n"
                "  git add data/\n"
                "  git commit -m 'update data'\n"
                "  git push\n\n"
                f"Your AppConstants.metadataBaseUrl should be exactly:\n  {raw_base_url}"
            )
            self.log(final_instructions, level="PROMPT")
            
        except Exception as e:
            self.log(str(e), level="ERROR")
        finally:
            self.run_btn.config(state="normal")
            self.log("Process finished.", level="INFO")

    def start_packaging(self):
        # Clear log area
        self.log_area.config(state="normal")
        self.log_area.delete(1.0, tk.END)
        self.log_area.config(state="disabled")
        
        # Disable button to prevent multiple clicks
        self.run_btn.config(state="disabled")
        
        # Run in a separate thread to keep UI responsive
        threading.Thread(target=self.process_data, daemon=True).start()

if __name__ == "__main__":
    app = DataPackagerApp()
    app.mainloop()