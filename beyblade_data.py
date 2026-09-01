#!/usr/bin/env python3
import base64
import json
import time
import urllib.parse
import urllib.request
import urllib.error
import threading
import tkinter as tk
from tkinter import ttk, scrolledtext, messagebox
from datetime import datetime, timezone
from pathlib import Path

TRACKED_SHEETS = ["blades", "ratchets", "bits", "lockChips", "overBlades", "metalBlades", "mainBlades", "assistBlades"]
# Dropped from 9 — with some images sitting near/above Code.gs's ~1MB
# per-image cache ceiling (resolveCellImage_ silently skips caching
# anything bigger), each of those rows is a real, slow UrlFetchApp round
# trip to Drive on every request. Smaller chunks bound how much of that
# any single request can accumulate before running long enough to time
# out — this doesn't fix the root cause (oversized source images), just
# reduces how badly a slow chunk compounds.
CHUNK_SIZE = 4
MAX_RETRIES = 4
REQUEST_TIMEOUT = 120  # was 60 — some chunks are genuinely this slow, not stuck
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
        self.geometry("750x650")
        self.resizable(False, False)

        self.total_downloaded_bytes = 0
        self.process_start_time = 0

        self.create_widgets()

    def create_widgets(self):
        input_frame = ttk.LabelFrame(self, text="Configuration", padding=(10, 10))
        input_frame.pack(padx=10, pady=10, fill="x")

        ttk.Label(input_frame, text="Apps Script URL:").grid(row=0, column=0, sticky="w", pady=5)
        self.url_entry = ttk.Entry(input_frame, width=65)
        self.url_entry.grid(row=0, column=1, padx=5, pady=5)

        ttk.Label(input_frame, text="GitHub Owner:").grid(row=1, column=0, sticky="w", pady=5)
        self.owner_entry = ttk.Entry(input_frame, width=65)
        self.owner_entry.grid(row=1, column=1, padx=5, pady=5)

        ttk.Label(input_frame, text="GitHub Repo:").grid(row=2, column=0, sticky="w", pady=5)
        self.repo_entry = ttk.Entry(input_frame, width=65)
        self.repo_entry.grid(row=2, column=1, padx=5, pady=5)

        ttk.Label(input_frame, text="Branch (default 'main'):").grid(row=3, column=0, sticky="w", pady=5)
        self.branch_entry = ttk.Entry(input_frame, width=65)
        self.branch_entry.insert(0, "main")
        self.branch_entry.grid(row=3, column=1, padx=5, pady=5)

        self.run_btn = ttk.Button(self, text="Package Data", command=self.start_packaging)
        self.run_btn.pack(pady=5)

        log_frame = ttk.LabelFrame(self, text="Execution Logs", padding=(10, 10))
        log_frame.pack(padx=10, pady=5, fill="both", expand=True)

        self.log_area = scrolledtext.ScrolledText(log_frame, wrap=tk.WORD, height=18, state="disabled")
        self.log_area.pack(fill="both", expand=True)

    def log(self, message, level="INFO"):
        timestamp = datetime.now().strftime("%H:%M:%S")
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
        """Fetches JSON with retry+backoff — a slow/failed chunk no longer
        kills the whole run. Only retries network-level failures (timeout,
        connection reset); an actual {"error": ...} response from Apps
        Script is a real error, not a transient one, so that still
        propagates immediately without wasting retries on it."""
        last_err = None
        for attempt in range(1, MAX_RETRIES + 1):
            try:
                with urllib.request.urlopen(url, timeout=REQUEST_TIMEOUT) as resp:
                    raw_bytes = resp.read()
                    return json.loads(raw_bytes.decode("utf-8")), len(raw_bytes)
            except (urllib.error.URLError, TimeoutError, ConnectionResetError, OSError) as e:
                last_err = e
                if attempt >= MAX_RETRIES:
                    break
                wait = 2 ** attempt  # 2s, 4s, 8s, 16s
                self.log(f"    network error ({e}) — retry {attempt}/{MAX_RETRIES} in {wait}s", level="WARN")
                time.sleep(wait)
        raise RuntimeError(f"Failed after {MAX_RETRIES} attempts: {last_err}")

    def format_time(self, seconds):
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
            chunk_start_time = time.time()
            data, chunk_size_bytes = self.fetch_json(f"{base_url}?{params}")
            chunk_duration = time.time() - chunk_start_time

            self.total_downloaded_bytes += chunk_size_bytes
            elapsed_total = time.time() - self.process_start_time

            if "error" in data:
                raise RuntimeError(f"Apps Script error for {sheet}: {data['error']}")

            chunk_rows = data["rows"]
            rows.extend(chunk_rows)

            num_rows = len(chunk_rows)
            avg_row_size_kb = (chunk_size_bytes / num_rows / 1024) if num_rows > 0 else 0
            chunk_size_kb = chunk_size_bytes / 1024
            total_mb = self.total_downloaded_bytes / (1024 * 1024)

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
                img_bytes = base64.b64decode(b64data)
                (images_dir / filename).write_bytes(img_bytes)
                if len(img_bytes) > 300_000:
                    self.log(f"    {filename}: {len(img_bytes)/1024:.0f} KB — large; likely never cached server-side (see Code.gs's ~1MB ceiling)", level="WARN")
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

        raw_base_url = f"https://cdn.jsdelivr.net/gh/{owner}/{repo}@{branch}/data/"

        out_dir = Path("data")
        images_dir = out_dir / "images"
        images_dir.mkdir(parents=True, exist_ok=True)

        manifest = {"publishedAt": datetime.now(timezone.utc).isoformat(), "sheets": {}}

        self.total_downloaded_bytes = 0
        self.process_start_time = time.time()

        self.log(f"Starting packaging process. Output directory: {out_dir.resolve()}")

        try:
            for sheet in TRACKED_SHEETS:
                self.log(f"Fetching data for sheet: {sheet}...", level="START")
                raw_rows = self.fetch_all_rows(base_url, sheet)

                manifest["sheets"][sheet] = self.sheet_manifest_entry(raw_rows)

                rows = [self.extract_image(row, sheet, images_dir, raw_base_url) for row in raw_rows]

                out_path = out_dir / f"{sheet}.json"
                out_path.write_text(json.dumps(rows, separators=(",", ":"), ensure_ascii=False), encoding="utf-8")
                self.log(f"Saved {out_path.name} ({len(rows)} rows)", level="SUCCESS")

            manifest_path = out_dir / "manifest.json"
            manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
            self.log(f"Saved {manifest_path.name}", level="SUCCESS")

            total_elapsed = time.time() - self.process_start_time
            total_mb_final = self.total_downloaded_bytes / (1024 * 1024)

            self.log("=== MANIFEST SUMMARY ===", level="INFO")
            for sheet, info in manifest["sheets"].items():
                self.log(f"  {sheet}: {info['rowCount']} rows, latest edit: {info['latestUpdatedAt']}", level="INFO")

            self.log(f"Total Download Size: {total_mb_final:.2f} MB", level="INFO")
            self.log(f"Total Execution Time: {self.format_time(total_elapsed)}", level="INFO")

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
        self.log_area.config(state="normal")
        self.log_area.delete(1.0, tk.END)
        self.log_area.config(state="disabled")
        self.run_btn.config(state="disabled")
        threading.Thread(target=self.process_data, daemon=True).start()

if __name__ == "__main__":
    app = DataPackagerApp()
    app.mainloop()