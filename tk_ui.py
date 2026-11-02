#!/usr/bin/env python3
"""Shared look and conveniences for the desktop tools (scraper, packager, missing data tool).

    apply_theme(root)            consistent fonts/colours, striped tables, roomier rows
    Prefs                        remembers recent workbooks, last paths and options (~/.clasher_tools.json)
    BackgroundRunner(root)       runs slow work on a thread and delivers the result on the UI thread
    status_bar(root)             a status line + progress bar at the bottom of a window
"""
import json
import os
import queue
import threading

PREFS_PATH = os.path.join(os.path.expanduser("~"), ".clasher_tools.json")

COLORS = {"bg": "#f5f6f8", "panel": "#ffffff", "accent": "#2f6fed", "accent_dark": "#2457c5", "text": "#1d2330",
          "muted": "#6b7280", "warn_bg": "#fff1db", "ok": "#1f9d55", "danger": "#d64545", "stripe": "#f2f5fb",
          "select": "#dce7ff"}


def apply_theme(root):
    from tkinter import ttk
    import tkinter.font as tkfont
    style = ttk.Style(root)
    try:
        style.theme_use("clam")
    except Exception:
        pass
    base = tkfont.nametofont("TkDefaultFont")
    base.configure(size=10)
    root.configure(bg=COLORS["bg"])
    style.configure(".", background=COLORS["bg"], foreground=COLORS["text"])
    style.configure("TFrame", background=COLORS["bg"])
    style.configure("Card.TFrame", background=COLORS["panel"], relief="flat")
    style.configure("TLabel", background=COLORS["bg"])
    style.configure("Muted.TLabel", foreground=COLORS["muted"])
    style.configure("Title.TLabel", font=(base.actual("family"), 13, "bold"))
    style.configure("TButton", padding=(10, 5))
    style.configure("Accent.TButton", background=COLORS["accent"], foreground="white", padding=(12, 6))
    style.map("Accent.TButton", background=[("active", COLORS["accent_dark"]), ("disabled", "#9db6ef")])
    style.configure("Treeview", rowheight=24, background=COLORS["panel"], fieldbackground=COLORS["panel"])
    style.configure("Treeview.Heading", font=(base.actual("family"), 10, "bold"), padding=(6, 4))
    style.map("Treeview", background=[("selected", COLORS["select"])], foreground=[("selected", COLORS["text"])])
    style.configure("TNotebook.Tab", padding=(12, 5))
    style.configure("Horizontal.TProgressbar", background=COLORS["accent"])
    return style


def stripe(tree):
    """Alternate row colours on a Treeview (call after filling it)."""
    tree.tag_configure("odd", background=COLORS["stripe"])
    for i, iid in enumerate(tree.get_children()):
        tags = [t for t in tree.item(iid, "tags") if t != "odd"]
        if i % 2:
            tags.append("odd")
        tree.item(iid, tags=tags)


class Prefs:
    """Tiny JSON settings file shared by the tools."""

    def __init__(self, section):
        self.section = section
        self.data = {}
        try:
            with open(PREFS_PATH, encoding="utf-8") as f:
                self.data = json.load(f)
        except (OSError, ValueError):
            self.data = {}

    def get(self, key, default=None):
        return self.data.get(self.section, {}).get(key, default)

    def set(self, key, value):
        self.data.setdefault(self.section, {})[key] = value
        try:
            with open(PREFS_PATH, "w", encoding="utf-8") as f:
                json.dump(self.data, f, indent=1)
        except OSError:
            pass

    def add_recent(self, path, key="recent", keep=8):
        rec = [p for p in self.get(key, []) if p != path]
        self.set(key, [path] + rec[:keep - 1])


class BackgroundRunner:
    """run(fn, on_done, on_error): fn runs on a worker thread; callbacks run on the Tk thread.
    busy is True while something runs (one job at a time keeps the workbook consistent)."""

    def __init__(self, root, on_busy=None):
        self.root = root
        self.q = queue.Queue()
        self.busy = False
        self.on_busy = on_busy
        root.after(80, self._pump)

    def run(self, fn, on_done=None, on_error=None, label=""):
        if self.busy:
            return False
        self.busy = True
        if self.on_busy:
            self.on_busy(True, label)

        def work():
            try:
                res = fn()
                self.q.put((on_done, res, None))
            except Exception as e:  # delivered to on_error on the UI thread
                self.q.put((on_error, None, e))
        threading.Thread(target=work, daemon=True).start()
        return True

    def call_ui(self, fn, *args):
        """From a worker thread: run fn(*args) on the Tk thread."""
        self.q.put(("ui", fn, args))

    def _pump(self):
        try:
            while True:
                item = self.q.get_nowait()
                if item[0] == "ui":
                    item[1](*item[2])
                    continue
                cb, res, err = item
                self.busy = False
                if self.on_busy:
                    self.on_busy(False, "")
                if err is not None:
                    if cb:
                        cb(err)
                    else:
                        raise err
                elif cb:
                    cb(res)
        except queue.Empty:
            pass
        self.root.after(80, self._pump)


def status_bar(root):
    """-> (frame, set_status(text, busy=None)) with a status label and an indeterminate progress bar."""
    from tkinter import ttk
    bar = ttk.Frame(root, padding=(8, 4))
    label = ttk.Label(bar, text="Ready", style="Muted.TLabel")
    label.pack(side="left", fill="x", expand=True)
    prog = ttk.Progressbar(bar, mode="indeterminate", length=160)

    def set_status(text=None, busy=None):
        if text is not None:
            label.config(text=text)
        if busy is True:
            prog.pack(side="right")
            prog.start(12)
        elif busy is False:
            prog.stop()
            prog.pack_forget()
    return bar, set_status
