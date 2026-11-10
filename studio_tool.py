#!/usr/bin/env python3
"""
Clasher Studio's workspace engine (JSON lines over stdin/stdout, like missing_data_tool.py serve):

  workspace     hobbies -> generations -> workbooks (studio_workspace.json, next to this file)
  packaging     packaging_profiles.json: which columns each JSON sheet carries and how critical they are
  publishing    data release (package -> commit + push data/ -> release files -> GitHub release) and translations
                release (upload changed lang_<code>.zip to the translations repo's release), release history
  scrapers      targets per hobby / generation, runs with live logs and a safe stop, scraper_config.json per
                target, and the per hobby / generation code files (scrapers/<hobby>/<generation>.py)

Long steps run as jobs in the background: {"event": "job", "id", "line"} streams their output and
{"event": "jobDone", "id", "ok", "result"|"error"} ends them; jobStop asks one to stop (scrapers finish the current
step and save their progress). Anything that reaches the internet or another repo (git push, gh release) is only
done when the app asks for it - and the app asks you first.

    python studio_tool.py serve
"""
from __future__ import annotations

import datetime as dt
import json
import os
import py_compile
import re
import shutil
import subprocess
import sys
import tempfile
import threading
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import beyblade_schema as S  # noqa: E402

WORKSPACE_FILE = HERE / "studio_workspace.json"
PYTHON = sys.executable or "python3"


def now_iso():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


# ════════════════════════════════════════════════════════════════════════════════════════════════════════════
# Workspace: hobbies, generations, workbooks
# ════════════════════════════════════════════════════════════════════════════════════════════════════════════

def default_workspace():
    return {
        "version": 1,
        "hobbies": [
            {"name": S.HOBBY_NAME, "kind": "parts", "generations": list(S.GENERATION_NAMES),
             "workbooks": [{"role": "parts", "file": S.BOOK_FILES["parts"]},
                           {"role": "products", "file": S.BOOK_FILES["products"]}],
             "packaged": True, "scraped": True},
            {"name": S.TCG_HOBBY_NAME, "kind": "cards", "generations": ["Original", "X"],
             "workbooks": [{"role": "tcg", "file": S.BOOK_FILES["tcg"]}],
             "packaged": True, "scraped": True},
        ],
    }


def load_workspace():
    try:
        data = json.loads(WORKSPACE_FILE.read_text("utf-8"))
        if isinstance(data.get("hobbies"), list):
            return data
    except (OSError, ValueError):
        pass
    return default_workspace()


def save_workspace(data):
    hobbies = data.get("hobbies")
    if not isinstance(hobbies, list) or not hobbies:
        raise ValueError("A workspace needs at least one hobby")
    seen = set()
    for h in hobbies:
        name = str(h.get("name") or "").strip()
        if not name:
            raise ValueError("Every hobby needs a name")
        if name.lower() in seen:
            raise ValueError(f"Two hobbies are called {name}")
        seen.add(name.lower())
        gens = [str(g).strip() for g in h.get("generations") or [] if str(g).strip()]
        if not gens:
            raise ValueError(f"{name} needs at least one generation (e.g. Burst, X - or a year for cards)")
        if len(set(g.lower() for g in gens)) != len(gens):
            raise ValueError(f"{name} lists a generation twice")
        for w in h.get("workbooks") or []:
            if not str(w.get("file") or "").lower().endswith(".xlsx"):
                raise ValueError(f"{name}: workbook {w.get('file')!r} must be an .xlsx file")
        h["name"], h["generations"] = name, gens
    data["version"] = 1
    tmp = WORKSPACE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(tmp, WORKSPACE_FILE)
    return describe_workspace(data)


def describe_workspace(data=None, data_root=None):
    """The workspace with each workbook's full path, whether it exists, and its tabs per generation."""
    data = data or load_workspace()
    root = Path(data_root) if data_root else HERE
    out = {"version": data.get("version", 1), "root": str(root), "hobbies": []}
    for h in data["hobbies"]:
        books = []
        for w in h.get("workbooks") or []:
            p = Path(w["file"]) if Path(w["file"]).is_absolute() else root / w["file"]
            books.append({**w, "path": str(p), "exists": p.exists()})
        out["hobbies"].append({**h, "workbooks": books})
    return out


# ════════════════════════════════════════════════════════════════════════════════════════════════════════════
# Packaging profiles
# ════════════════════════════════════════════════════════════════════════════════════════════════════════════

ID_AND_IMAGE = {"dataID", "productID", "setID", "image", "minifiedImage", "boxImageUrl", "minifiedBoxImage",
                "imageUrl"}


def sheet_json_names():
    """JSON sheet -> (tab name, workbook role, generation or None)."""
    out = {}
    for gen, key, _ in S.all_part_targets():
        out[S.part_json_prefix(gen, key)] = (S.part_sheet(gen, key), "parts", gen)
    for name, cfg in S.SHEETS.items():
        out[cfg["json"]] = (name, cfg["book"], None)
    return out


def _headers(path: Path, tab: str):
    import openpyxl
    try:
        wb = openpyxl.load_workbook(path, read_only=True)
    except Exception:
        return None
    try:
        if tab not in wb.sheetnames:
            return None
        row = next(wb[tab].iter_rows(min_row=1, max_row=1, values_only=True), ())
        return [str(c).strip() for c in row if c not in (None, "")]
    finally:
        wb.close()


def profiles(data_root=None, only=None):
    """Every JSON sheet with its columns (from the workbook when it has the tab, else the schema) and their rules."""
    ws = describe_workspace(data_root=data_root)
    books = {w["role"]: Path(w["path"]) for h in ws["hobbies"] for w in h["workbooks"]}
    schema_cols = {S.part_json_prefix(g, k): p["columns"] + list(S.PART_IMAGE_COLS) for g, k, p in S.all_part_targets()}
    for name, cfg in S.SHEETS.items():
        schema_cols[cfg["json"]] = list(cfg["columns"]) + list(cfg["images"] or [])
    header_cache = {}
    out = []
    for js, (tab, role, gen) in sorted(sheet_json_names().items(), key=lambda kv: (kv[1][1], kv[1][2] or "", kv[0])):
        if only and js not in only:
            continue
        path = books.get(role)
        cols = None
        if path and path.exists():
            key = (str(path), tab)
            if key not in header_cache:
                header_cache[key] = _headers(path, tab)
            cols = header_cache[key]
        source = "workbook" if cols else "schema"
        cols = cols or schema_cols.get(js, [])
        rules = S.column_rules(js)
        req = set(S.app_required(js))
        columns = []
        for c in cols:
            r = rules.get(c, {})
            locked = c in req or c in ID_AND_IMAGE
            default = "required" if c in req else "optional" if c in OPTIONAL_DEFAULT else "recommended"
            crit = r.get("criticality") or default
            if c in req:
                crit = "required"
            columns.append({"name": c, "include": True if locked else r.get("include", True), "criticality": crit,
                            "default": default, "locked": locked, "appRequired": c in req,
                            "changed": bool(r) and not locked})
        out.append({"sheet": js, "tab": tab, "workbook": role, "generation": gen, "source": source,
                    "columns": columns})
    return {"file": S.PROFILES_FILE, "sheets": out}


OPTIONAL_DEFAULT = {"parentPartId", "variantLabel", "updated_at", "deleted", "incompleteData", "integratedRatchet",
                    "twoStat", "parentProductId", "parentCardId", "parentSetId", "linkedPartType",
                    "linkedPartDataID", "illustrator", "legality", "description", "subType", "simpleRatchet",
                    "requiresSimpleRatchet"}


def set_profile(sheet, columns):
    """columns: {name: {include, criticality}} - only differences from the defaults are stored."""
    if sheet not in sheet_json_names():
        raise ValueError(f"No JSON sheet called {sheet}")
    req = set(S.app_required(sheet))
    clean = {}
    for c, r in (columns or {}).items():
        crit = r.get("criticality")
        if crit is not None and crit not in S.CRITICALITY:
            raise ValueError(f"{c}: criticality must be one of {', '.join(S.CRITICALITY)}")
        if c in req or c in ID_AND_IMAGE:
            if r.get("include") is False or (crit and crit != "required" and c in req):
                raise ValueError(f"{c} is read by the app as required (or is an id / image) - it can't be left out "
                                 "or made optional")
            continue
        default = "optional" if c in OPTIONAL_DEFAULT else "recommended"
        entry = {}
        if r.get("include") is False:
            entry["include"] = False
        if crit and crit != default:
            entry["criticality"] = crit
        if entry:
            clean[c] = entry
    data = json.loads(json.dumps(S.load_profiles()))
    data.setdefault("sheets", {})
    if clean:
        data["sheets"][sheet] = {"columns": clean}
    else:
        data["sheets"].pop(sheet, None)
    data["version"] = 1
    S.save_profiles(data)
    return profiles(only={sheet})["sheets"][0]


# ════════════════════════════════════════════════════════════════════════════════════════════════════════════
# Jobs: long steps in the background, streamed
# ════════════════════════════════════════════════════════════════════════════════════════════════════════════

class Jobs:
    def __init__(self, send):
        self.send = send
        self.jobs = {}
        self.n = 0
        self.lock = threading.Lock()

    def start(self, kind, fn, *args):
        with self.lock:
            busy = [j for j in self.jobs.values() if j["running"] and j["kind"] == kind]
            if busy:
                raise ValueError(f"A {kind} job is already running")
            self.n += 1
            jid = f"{kind}-{self.n}"
            job = {"id": jid, "kind": kind, "running": True, "stop": threading.Event(), "proc": None,
                   "lines": [], "started": now_iso()}
            self.jobs[jid] = job

        def line(text):
            text = str(text).rstrip("\n")
            job["lines"].append(text)
            del job["lines"][:-2000]
            self.send({"event": "job", "id": jid, "line": text})

        def run():
            try:
                result = fn(job, line, *args)
                self.send({"event": "jobDone", "id": jid, "ok": True, "result": result})
            except Exception as e:  # reported to the app
                line(f"ERROR: {e}")
                self.send({"event": "jobDone", "id": jid, "ok": False, "error": str(e)})
            finally:
                job["running"] = False
        threading.Thread(target=run, daemon=True).start()
        return {"id": jid}

    def stop(self, jid):
        job = self.jobs.get(jid)
        if not job or not job["running"]:
            return {"stopped": False}
        job["stop"].set()
        stop_file = job.get("stopFile")
        if stop_file:
            Path(stop_file).write_text("stop", encoding="utf-8")  # the scraper saves and stops
        elif job.get("proc") is not None:
            job["proc"].terminate()
        return {"stopped": True}

    def status(self):
        return [{"id": j["id"], "kind": j["kind"], "running": j["running"], "started": j["started"],
                 "tail": j["lines"][-20:]} for j in self.jobs.values()]


def stream(job, line, cmd, cwd=None, env=None, ok_codes=(0,)):
    """Runs a command, streaming its output -> exit code. Raises on a code not in ok_codes."""
    line("$ " + " ".join(_show(c) for c in cmd))
    try:
        proc = subprocess.Popen(cmd, cwd=str(cwd or HERE), stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                stdin=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace",
                                env={**os.environ, "PYTHONIOENCODING": "utf-8", "PYTHONUNBUFFERED": "1",
                                     "GH_PROMPT_DISABLED": "1", "GIT_TERMINAL_PROMPT": "0", **(env or {})})
    except FileNotFoundError:
        raise RuntimeError(f"{cmd[0]} isn't installed (or not on PATH)")
    job["proc"] = proc
    for out in proc.stdout:
        line(out)
    code = proc.wait()
    job["proc"] = None
    if job["stop"].is_set() and code not in ok_codes:
        raise RuntimeError("Stopped")
    if code not in ok_codes:
        raise RuntimeError(f"{_show(cmd[0])} exited with code {code}")
    return code


def _show(arg):
    a = str(arg)
    return f'"{a}"' if " " in a else a


def run_quiet(cmd, cwd=None, timeout=60):
    try:
        p = subprocess.run(cmd, cwd=str(cwd or HERE), capture_output=True, text=True, encoding="utf-8",
                           errors="replace", timeout=timeout,
                           env={**os.environ, "GH_PROMPT_DISABLED": "1", "GIT_TERMINAL_PROMPT": "0"})
        return p.returncode, (p.stdout or "") + (p.stderr or "")
    except FileNotFoundError:
        return 127, f"{cmd[0]} isn't installed"
    except subprocess.TimeoutExpired:
        return 124, f"{cmd[0]} timed out"


# ════════════════════════════════════════════════════════════════════════════════════════════════════════════
# Publishing: data
# ════════════════════════════════════════════════════════════════════════════════════════════════════════════

def tools_check():
    """git / gh installed and signed in."""
    git_code, git_out = run_quiet(["git", "--version"])
    gh_code, gh_out = run_quiet(["gh", "--version"])
    auth = None
    if gh_code == 0:
        code, out = run_quiet(["gh", "auth", "status"])
        m = re.search(r"account (\S+)", out) or re.search(r"Logged in to \S+ as (\S+)", out)
        auth = {"ok": code == 0, "user": m.group(1) if m else None, "detail": out.strip()[-600:]}
    return {"git": git_code == 0, "gitVersion": git_out.strip().splitlines()[0] if git_code == 0 else None,
            "gh": gh_code == 0, "ghVersion": gh_out.strip().splitlines()[0] if gh_code == 0 else None,
            "ghAuth": auth}


def git_status(repo, paths=("data",)):
    repo = Path(repo)
    code, out = run_quiet(["git", "-C", str(repo), "rev-parse", "--abbrev-ref", "HEAD"])
    if code != 0:
        return {"isRepo": False, "detail": out.strip()}
    branch = out.strip()
    _, porcelain = run_quiet(["git", "-C", str(repo), "status", "--porcelain", "-uall", "--", *paths])
    changed = [ln[3:] for ln in porcelain.splitlines() if ln.strip()]
    _, remote = run_quiet(["git", "-C", str(repo), "remote", "get-url", "origin"])
    ahead = behind = None
    code, ab = run_quiet(["git", "-C", str(repo), "rev-list", "--left-right", "--count", "HEAD...@{u}"])
    if code == 0 and len(ab.split()) == 2:
        ahead, behind = (int(x) for x in ab.split())
    images = sum(1 for c in changed if "/images/" in c.replace("\\", "/"))
    return {"isRepo": True, "branch": branch, "remote": remote.strip(), "changed": len(changed),
            "changedImages": images, "sample": changed[:40], "ahead": ahead, "behind": behind}


def job_package(job, line, books, out_dir, owner, repo, branch):
    if not books:
        raise ValueError("No workbook to package")
    missing = [b for b in books if not Path(b).exists()]
    if missing:
        raise ValueError("Not found: " + ", ".join(missing))
    out = Path(out_dir)
    cmd = [PYTHON, str(HERE / "beyblade_data.py"), "--out", str(out), "--user", owner, "--repo", repo,
           "--branch", branch]
    for b in books:
        name = Path(b).name.lower()
        flag = "--tcg" if "tcg" in name else "--products" if "product" in name else "--parts" if "part" in name \
            else "--workbook"
        cmd += [flag, str(b)]
    stream(job, line, cmd)
    import catalog_check
    rep = catalog_check.check(catalog_check.load_sheets(out))
    diff = {}
    try:
        diff = json.loads((out / "_package_diff.json").read_text("utf-8"))
    except (OSError, ValueError):
        pass
    manifest = json.loads((out / "manifest.json").read_text("utf-8"))
    return {"out": str(out), "ok": rep.ok,
            "errors": [{"sheet": s, "id": None if i is None else str(i), "message": m} for s, i, m in rep.errors[:300]],
            "errorCount": len(rep.errors), "warningCount": len(rep.warnings),
            "warnings": [{"sheet": s, "id": None if i is None else str(i), "message": m} for s, i, m in rep.warnings[:100]],
            "sheets": {k: v for k, v in manifest.get("sheets", {}).items()},
            "changes": manifest.get("changes") or {}, "diff": diff.get("sheets") if isinstance(diff, dict) else {}}


def job_commit_push(job, line, repo, paths, message, push):
    repo = Path(repo)
    if not message.strip():
        raise ValueError("Write a commit message")
    stream(job, line, ["git", "-C", str(repo), "add", "--", *paths])
    code, out = run_quiet(["git", "-C", str(repo), "diff", "--cached", "--quiet", "--", *paths])
    committed = False
    if code == 1:
        stream(job, line, ["git", "-C", str(repo), "commit", "-m", message, "--", *paths])
        committed = True
    else:
        line("Nothing new to commit in " + ", ".join(paths))
    pushed = False
    if push:
        stream(job, line, ["git", "-C", str(repo), "push", "origin", "HEAD"])
        pushed = True
    _, head = run_quiet(["git", "-C", str(repo), "rev-parse", "--short", "HEAD"])
    return {"committed": committed, "pushed": pushed, "head": head.strip()}


def job_build_release(job, line, data_dir, out_root, tag, owner, repo, drop_invalid, app_assets):
    if not re.fullmatch(r"[A-Za-z0-9._-]{1,100}", tag or ""):
        raise ValueError("A release tag is letters, digits, . _ - (e.g. 2026-11-10)")
    cmd = [PYTHON, str(HERE / "build_release.py"), "--data", str(data_dir), "--out", str(out_root), "--tag", tag,
           "--user", owner, "--repo", repo]
    if drop_invalid:
        cmd.append("--drop-invalid")
    if app_assets:
        cmd += ["--app-assets", str(app_assets)]
    stream(job, line, cmd)
    folder = Path(out_root) / tag
    manifest = json.loads((folder / "catalog_manifest.json").read_text("utf-8"))
    packs = json.loads((folder / "packs.json").read_text("utf-8")).get("packs", [])
    files = sorted(str(p) for p in folder.iterdir() if p.is_file())
    return {"folder": str(folder), "manifest": manifest, "files": files,
            "packs": [{k: p.get(k) for k in ("kind", "hobby", "generation", "file", "bytes")} for p in packs]}


def release_exists(slug, tag):
    code, _ = run_quiet(["gh", "release", "view", tag, "-R", slug, "--json", "tagName"])
    return code == 0


def job_publish_release(job, line, slug, tag, files, title, notes, latest):
    """Creates the GitHub release (or adds to it when it exists) and uploads files."""
    files = [f for f in files if Path(f).is_file()]
    if not files:
        raise ValueError("No files to upload")
    if release_exists(slug, tag):
        line(f"Release {tag} exists on {slug}: uploading (files with the same name are replaced)")
        stream(job, line, ["gh", "release", "upload", tag, *files, "--clobber", "-R", slug])
        created = False
    else:
        cmd = ["gh", "release", "create", tag, *files, "-R", slug, "--title", title or tag,
               "--notes", notes or f"Released with Clasher Studio on {now_iso()[:10]}"]
        if latest:
            cmd.append("--latest")
        stream(job, line, cmd)
        created = True
    code, out = run_quiet(["gh", "release", "view", tag, "-R", slug, "--json", "url,assets"])
    info = json.loads(out) if code == 0 else {}
    return {"created": created, "url": info.get("url"), "assets": [a.get("name") for a in info.get("assets", [])]}


def releases(slug, limit=30):
    code, out = run_quiet(["gh", "release", "list", "-R", slug, "--limit", str(limit), "--json",
                           "tagName,name,publishedAt,isLatest,isDraft,isPrerelease"])
    if code != 0:
        raise ValueError(out.strip()[-400:] or f"Couldn't list the releases of {slug}")
    return json.loads(out)


def release_assets(slug, tag):
    code, out = run_quiet(["gh", "release", "view", tag, "-R", slug, "--json", "assets,url,publishedAt"])
    if code != 0:
        raise ValueError(out.strip()[-400:])
    d = json.loads(out)
    return {"url": d.get("url"), "publishedAt": d.get("publishedAt"),
            "assets": [{"name": a.get("name"), "size": a.get("size"), "downloads": a.get("downloadCount")}
                       for a in d.get("assets", [])]}


# ════════════════════════════════════════════════════════════════════════════════════════════════════════════
# Scrapers
# ════════════════════════════════════════════════════════════════════════════════════════════════════════════

_EVENT_LOG = {"fn": lambda line: None}


def _scraper():
    import fandom_scraper as F
    F._LOG_SINK = lambda line: _EVENT_LOG["fn"](line)  # its log lines become log events, never stdout
    return F


def scraper_targets():
    """Targets grouped by hobby and generation, with what the scraper remembers about each."""
    F = _scraper()
    cfg = F.load_config()
    state_dir = Path(cfg.get("state_dir") or "scrape_state")
    state_dir = state_dir if state_dir.is_absolute() else HERE / state_dir
    progress = {}
    for name in ("progress.json", "state.json"):
        p = state_dir / name
        if p.exists():
            try:
                d = json.loads(p.read_text("utf-8"))
                progress = d.get("progress", d) if isinstance(d, dict) else {}
                break
            except ValueError:
                pass
    out = []
    for t, src in cfg["sources"].items():
        kind = F.target_kind(t)
        gen, key = F.target_gen_key(t)
        hobby = S.TCG_HOBBY_NAME if kind == "tcg" else S.HOBBY_NAME
        pr = progress.get(t) if isinstance(progress, dict) else None
        out.append({"target": t, "kind": kind, "generation": gen, "key": key, "hobby": hobby,
                    "categories": src.get("categories", []), "listPages": src.get("list_pages", []),
                    "progress": pr if isinstance(pr, dict) else None,
                    "plugin": os.path.exists(F.plugin_path(hobby, gen))})
    return {"targets": out, "config": str(F.CONFIG_PATH), "userAgent": cfg.get("user_agent", ""),
            "politeness": cfg.get("politeness", {}), "stateDir": str(state_dir)}


def scraper_target_config(target):
    F = _scraper()
    cfg = F.load_config()
    if target not in cfg["sources"]:
        raise ValueError(f"No scraper target {target}")
    return {"target": target, "config": cfg["sources"][target]}


def set_scraper_target_config(target, config):
    """Replaces one target's settings in scraper_config.json (backup kept)."""
    F = _scraper()
    if not isinstance(config, dict):
        raise ValueError("The target's settings must be a JSON object")
    for k in ("categories", "title_prefixes", "extra_titles", "list_pages"):
        if k in config and not (isinstance(config[k], list) and all(isinstance(x, str) for x in config[k])):
            raise ValueError(f"{k} must be a list of texts")
    if "aliases" in config and not isinstance(config["aliases"], dict):
        raise ValueError("aliases must be an object: {\"wiki field\": \"our column\"}")
    if config.get("exclude_title_regex"):
        try:
            re.compile(config["exclude_title_regex"])
        except re.error as e:
            raise ValueError(f"exclude_title_regex isn't a valid pattern: {e}")
    path = Path(F.CONFIG_PATH)
    F.load_config()  # creates the file when missing
    data = json.loads(path.read_text("utf-8"))
    data.setdefault("sources", {})[target] = config
    _backup(path)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(tmp, path)
    return scraper_target_config(target)


def set_scraper_settings(user_agent=None, politeness=None):
    F = _scraper()
    path = Path(F.CONFIG_PATH)
    F.load_config()
    data = json.loads(path.read_text("utf-8"))
    if user_agent is not None:
        if not user_agent.strip():
            raise ValueError("The user agent can't be empty (Fandom asks bots to identify themselves)")
        data["user_agent"] = user_agent.strip()
    if politeness:
        p = data.setdefault("politeness", {})
        for k, v in politeness.items():
            if k == "delay_seconds" and float(v) < 0.5:
                raise ValueError("delay_seconds can't be below 0.5 - be kind to the wiki")
            p[k] = v
    _backup(path)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    os.replace(tmp, path)
    return {"saved": True}


PLUGIN_TEMPLATE = '''"""Scraper code for {hobby} - {gen}. Runs after the built-in mapping for every wiki page of this hobby and
generation (parts, products and cards alike). Edited in Clasher Studio -> Scrapers.

adjust_row(target, title, fields, row) -> row
    target  e.g. "parts:{gen}:blades", "products:{gen}", "tcg:{gen}:cards"
    title   the wiki page title
    fields  the page's infobox fields, as the wiki names them (lower case)
    row     what will be written to the workbook (column -> value); change it and return it.
            Only blank cells are filled unless the run overwrites, so you can't damage hand-made data.
"""


def adjust_row(target, title, fields, row):
    # Example: a field the built-in mapping doesn't know
    # if target.startswith("parts:") and fields.get("tip shape"):
    #     row["tipShape"] = fields["tip shape"]
    return row
'''


def code_files(hobby, gen):
    """The editable code for a hobby + generation: its plugin file, plus the scraper itself (advanced)."""
    F = _scraper()
    plugin = Path(F.plugin_path(hobby, gen))
    return {"plugin": {"path": str(plugin), "exists": plugin.exists(),
                       "text": plugin.read_text("utf-8") if plugin.exists() else PLUGIN_TEMPLATE.format(hobby=hobby, gen=gen)},
            "scraper": {"path": str(HERE / "fandom_scraper.py")}}


def read_code(path):
    p = _allowed_code_path(path)
    return {"path": str(p), "text": p.read_text("utf-8") if p.exists() else "", "exists": p.exists()}


def _allowed_code_path(path):
    """Only the scraper and files under scrapers/ can be edited from the app."""
    p = Path(path).resolve()
    allowed = [(HERE / "fandom_scraper.py").resolve(), (HERE / "scraper_config.json").resolve()]
    if p in allowed or (HERE / "scrapers").resolve() in p.parents:
        if p.suffix not in (".py", ".json"):
            raise ValueError("Only .py and .json files")
        return p
    raise ValueError(f"{path} isn't a scraper file the Studio edits")


def check_code(path, text):
    """Syntax check without saving -> {ok, line, message}."""
    p = _allowed_code_path(path)
    if p.suffix == ".json":
        try:
            json.loads(text)
            return {"ok": True}
        except ValueError as e:
            return {"ok": False, "line": getattr(e, "lineno", None), "message": str(e)}
    with tempfile.TemporaryDirectory() as d:
        f = Path(d) / p.name
        f.write_text(text, encoding="utf-8")
        try:
            py_compile.compile(str(f), doraise=True)
            return {"ok": True}
        except py_compile.PyCompileError as e:
            err = e.exc_value
            return {"ok": False, "line": getattr(err, "lineno", None), "message": f"{type(err).__name__}: {getattr(err, 'msg', err)}"}


def save_code(path, text):
    """Saves after a syntax check (refused when it fails); the previous version goes to scrapers/backups/."""
    p = _allowed_code_path(path)
    chk = check_code(path, text)
    if not chk["ok"]:
        raise ValueError(f"Not saved - line {chk.get('line')}: {chk['message']}")
    p.parent.mkdir(parents=True, exist_ok=True)
    bk = _backup(p) if p.exists() else None
    tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, p)
    return {"saved": True, "backup": bk}


def _backup(p: Path):
    folder = HERE / "scrapers" / "backups"
    folder.mkdir(parents=True, exist_ok=True)
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    dest = folder / f"{p.stem}-{stamp}{p.suffix}"
    n = 1
    while dest.exists():
        dest, n = folder / f"{p.stem}-{stamp}-{n}{p.suffix}", n + 1
    shutil.copy2(p, dest)
    for old in sorted(folder.glob(f"{p.stem}-*{p.suffix}"))[:-30]:
        old.unlink()
    return str(dest)


def job_scrape(job, line, targets, options):
    """fandom_scraper.py for these targets; stop = finish the current step, save, stop."""
    if not targets and not options.get("update"):
        raise ValueError("Pick at least one target")
    stop_file = Path(tempfile.gettempdir()) / f"clasher_scrape_stop_{os.getpid()}_{job['id']}"
    stop_file.unlink(missing_ok=True)
    job["stopFile"] = str(stop_file)
    cmd = [PYTHON, str(HERE / "fandom_scraper.py"), "--stop-file", str(stop_file)]
    if options.get("update"):
        cmd.append("--update")
        if options.get("generation"):
            cmd += ["--generation", options["generation"]]
    for t in targets:
        cmd += ["--target", t]
    for flag, key in (("--limit", "limit"), ("--max-requests", "maxRequests"), ("--delay", "delay")):
        if options.get(key) not in (None, ""):
            cmd += [flag, str(options[key])]
    for flag, key in (("--no-images", "noImages"), ("--overwrite", "overwrite"), ("--relist", "relist"),
                      ("--refresh-existing", "refreshExisting"), ("--list-only", "listOnly")):
        if options.get(key):
            cmd.append(flag)
    try:
        code = stream(job, line, cmd, ok_codes=(0, 2, 130))
    finally:
        stop_file.unlink(missing_ok=True)
    return {"exitCode": code, "stoppedSafely": code in (2, 130),
            "message": "stopped safely - run again to continue" if code in (2, 130) else "finished"}


# ════════════════════════════════════════════════════════════════════════════════════════════════════════════
# serve
# ════════════════════════════════════════════════════════════════════════════════════════════════════════════

def serve(stdin=None, stdout=None):
    stdin, stdout = stdin or sys.stdin, stdout or sys.stdout
    if stdout is sys.stdout:
        sys.stdout = sys.stderr  # a stray print() anywhere must never corrupt the JSON lines
    out_lock = threading.Lock()

    def send(obj):
        with out_lock:
            stdout.write(json.dumps(obj, ensure_ascii=False, default=str) + "\n")
            stdout.flush()

    _EVENT_LOG["fn"] = lambda line: send({"event": "log", "message": str(line)})

    jobs = Jobs(send)
    root = {"dir": str(HERE)}

    def a_root(a):
        return a.get("dataRoot") or root["dir"]

    cmds = {
        "ping": lambda a: {"pong": True, "engine": "studio", "version": 1},
        "workspace": lambda a: describe_workspace(data_root=a_root(a)),
        "setWorkspace": lambda a: save_workspace(a["workspace"]),
        "profiles": lambda a: profiles(a_root(a), set(a["only"]) if a.get("only") else None),
        "setProfile": lambda a: set_profile(a["sheet"], a["columns"]),
        "tools": lambda a: tools_check(),
        "gitStatus": lambda a: git_status(a["repo"], a.get("paths") or ["data"]),
        "releases": lambda a: releases(a["slug"], a.get("limit", 30)),
        "releaseAssets": lambda a: release_assets(a["slug"], a["tag"]),
        "releaseExists": lambda a: {"exists": release_exists(a["slug"], a["tag"])},
        "package": lambda a: jobs.start("package", job_package, a["books"], a["out"], a["owner"], a["repo"],
                                        a.get("branch", "main")),
        "commitPush": lambda a: jobs.start("git", job_commit_push, a["repo"], a.get("paths") or ["data"],
                                           a.get("message", ""), a.get("push", True)),
        "buildRelease": lambda a: jobs.start("release", job_build_release, a["data"], a["out"], a["tag"], a["owner"],
                                             a["repo"], a.get("dropInvalid", False), a.get("appAssets")),
        "publishRelease": lambda a: jobs.start("publish", job_publish_release, a["slug"], a["tag"], a["files"],
                                               a.get("title"), a.get("notes"), a.get("latest", False)),
        "scraperTargets": lambda a: scraper_targets(),
        "scraperTarget": lambda a: scraper_target_config(a["target"]),
        "setScraperTarget": lambda a: set_scraper_target_config(a["target"], a["config"]),
        "setScraperSettings": lambda a: set_scraper_settings(a.get("userAgent"), a.get("politeness")),
        "codeFiles": lambda a: code_files(a["hobby"], a["generation"]),
        "readCode": lambda a: read_code(a["path"]),
        "checkCode": lambda a: check_code(a["path"], a["text"]),
        "saveCode": lambda a: save_code(a["path"], a["text"]),
        "scrape": lambda a: jobs.start("scrape", job_scrape, a.get("targets") or [], a.get("options") or {}),
        "jobStop": lambda a: jobs.stop(a["id"]),
        "jobs": lambda a: jobs.status(),
    }
    send({"event": "ready", "version": 1, "engine": "studio"})
    for raw in stdin:
        raw = raw.strip()
        if not raw:
            continue
        try:
            req = json.loads(raw)
        except ValueError:
            send({"ok": False, "error": "bad JSON"})
            continue
        rid, cmd = req.get("id"), req.get("cmd")
        if cmd == "quit":
            break
        try:
            if cmd not in cmds:
                raise ValueError(f"unknown command {cmd}")
            send({"id": rid, "ok": True, "result": cmds[cmd](req.get("args") or {})})
        except Exception as e:
            send({"id": rid, "ok": False, "error": str(e) if isinstance(e, (ValueError, RuntimeError, OSError))
                  else f"{type(e).__name__}: {e}"})
    for j in list(jobs.jobs):
        jobs.stop(j)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "serve":
        serve()
    else:
        print(__doc__)
