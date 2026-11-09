#!/usr/bin/env python3
"""
Translations for any Flutter app: finds every string, keeps the translation sheet in step with the app's
constants, checks the translations and builds the language packs.

Read-only on the Flutter project. It reads lib/ (the TrTokens constants, the default English map, the
language registry and every hard-coded UI string) and NEVER writes there: generated Dart goes to an export
folder, with a diff against the project's file, for you to copy (or for the Studio to copy, when you turn that
on and confirm). What it does write:
  * the translation sheet (.xlsx): new keys, translations, the Languages tab - with a timestamped backup before
    every save, a refusal when the file changed on disk since it was opened, and a recovery journal of unsaved
    edits (<sheet>.unsaved.jsonl);
  * the export folder: trc_constant_tokens.dart, default_english_tr.dart, app_language_constants.dart (merged:
    your file plus what's new, nothing removed or reordered), lang_<code>.zip packs, report.json.

The pack contract (same as the translations repo's langpack): lang_<code>.zip holds one translations.json of
{"key": "text"}, only non-empty translations, sorted, byte-for-byte reproducible. English is never packed (it
ships in the app as defaultEnglishTranslations). A column's code comes from, in order: the Languages tab, a
languages.json beside the sheet, a code in brackets ("Korean (ko)"), a header that is a code, the table of
language names below. A column that resolves to nothing stops the build: a made-up code ships a pack the app
can never match.

    python translation_tool.py serve                          JSON lines for the Studio app
    python translation_tool.py check  --project APP --sheet translations.xlsx
    python translation_tool.py export --project APP --sheet translations.xlsx --out dist
    python translation_tool.py packs  --sheet translations.xlsx --out dist [--strict]
"""
from __future__ import annotations

import argparse
import bisect
import datetime as dt
import difflib
import functools
import hashlib
import json
import os
import re
import shutil
import sys
import zipfile
from copy import copy
from pathlib import Path

try:
    import openpyxl
    from openpyxl.styles import Font, PatternFill
except ImportError:  # pragma: no cover
    sys.exit("This needs openpyxl:  pip install openpyxl")

# ── sheet layout ────────────────────────────────────────────────────────────────────────────────────────────
KEY_HEADER = "key"
ENGLISH_HEADER = "english"
LANGUAGES_TAB = "Languages"
LANGUAGES_COLUMNS = ["Column", "Code", "Name", "Country", "Status"]
# Grey columns: notes for people, never a language.
META_HEADERS = {"constant", "token", "section", "placeholders", "notes", "note", "comment", "comments", "context",
                "screen", "feature", "status", "source", "filepath", "file", "files", "added", "updated"}
BACKUPS_KEPT = 30
NEW_ROW_FILL = PatternFill("solid", fgColor="FFF4CC")

# Header -> (code, native name, country). The codes match the translations repo's langpack.
KNOWN_LANGUAGES = {
    "english": ("en", "English", "US"),
    "vietnamese": ("vi", "Tiếng Việt", "VN"),
    "vietnamese (north)": ("vi", "Tiếng Việt", "VN"),
    "vietnamese (south)": ("vi-south", "Tiếng Việt (Miền Nam)", "VN"),
    "japanese": ("ja", "日本語", "JP"),
    "malay": ("ms", "Bahasa Melayu", "MY"),
    "filipino": ("fil", "Filipino", "PH"),
    "tagalog": ("fil", "Filipino", "PH"),
    "indonesian": ("id", "Bahasa Indonesia", "ID"),
    "korean": ("ko", "한국어", "KR"),
    "chinese": ("zh-CN", "简体中文", "CN"),
    "chinese (simplified)": ("zh-CN", "简体中文", "CN"),
    "chinese (traditional)": ("zh-TW", "繁體中文 (台灣)", "TW"),
    "chinese (traditional, taiwan)": ("zh-TW", "繁體中文 (台灣)", "TW"),
    "chinese (traditional, hong kong)": ("zh-HK", "繁體中文 (香港)", "HK"),
    "thai": ("th", "ไทย", "TH"),
    "khmer": ("km", "ខ្មែរ", "KH"),
    "lao": ("lo", "ລາວ", "LA"),
    "burmese": ("my", "မြန်မာ", "MM"),
    "hindi": ("hi", "हिन्दी", "IN"),
    "bengali": ("bn", "বাংলা", "BD"),
    "tamil": ("ta", "தமிழ்", "IN"),
    "telugu": ("te", "తెలుగు", "IN"),
    "marathi": ("mr", "मराठी", "IN"),
    "urdu": ("ur", "اردو", "PK"),
    "nepali": ("ne", "नेपाली", "NP"),
    "sinhala": ("si", "සිංහල", "LK"),
    "arabic": ("ar", "العربية", "SA"),
    "persian": ("fa", "فارسی", "IR"),
    "hebrew": ("he", "עברית", "IL"),
    "turkish": ("tr", "Türkçe", "TR"),
    "russian": ("ru", "Русский", "RU"),
    "ukrainian": ("uk", "Українська", "UA"),
    "polish": ("pl", "Polski", "PL"),
    "czech": ("cs", "Čeština", "CZ"),
    "slovak": ("sk", "Slovenčina", "SK"),
    "hungarian": ("hu", "Magyar", "HU"),
    "romanian": ("ro", "Română", "RO"),
    "bulgarian": ("bg", "Български", "BG"),
    "greek": ("el", "Ελληνικά", "GR"),
    "german": ("de", "Deutsch", "DE"),
    "french": ("fr", "Français", "FR"),
    "spanish": ("es", "Español", "ES"),
    "spanish (latin america)": ("es-419", "Español (Latinoamérica)", "MX"),
    "portuguese": ("pt", "Português", "PT"),
    "portuguese (brazil)": ("pt-BR", "Português (Brasil)", "BR"),
    "italian": ("it", "Italiano", "IT"),
    "dutch": ("nl", "Nederlands", "NL"),
    "swedish": ("sv", "Svenska", "SE"),
    "norwegian": ("nb", "Norsk bokmål", "NO"),
    "danish": ("da", "Dansk", "DK"),
    "finnish": ("fi", "Suomi", "FI"),
    "croatian": ("hr", "Hrvatski", "HR"),
    "serbian": ("sr", "Српски", "RS"),
    "slovenian": ("sl", "Slovenščina", "SI"),
    "lithuanian": ("lt", "Lietuvių", "LT"),
    "latvian": ("lv", "Latviešu", "LV"),
    "estonian": ("et", "Eesti", "EE"),
    "catalan": ("ca", "Català", "ES"),
    "swahili": ("sw", "Kiswahili", "KE"),
    "afrikaans": ("af", "Afrikaans", "ZA"),
    "mongolian": ("mn", "Монгол", "MN"),
    "kazakh": ("kk", "Қазақ", "KZ"),
    "uzbek": ("uz", "Oʻzbek", "UZ"),
}
CODE_RE = re.compile(r"^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$")
KEY_RE = re.compile(r"^[a-z][a-z0-9]*(_[a-z0-9]+)*$")
PLACEHOLDER_RE = re.compile(r"\{([A-Za-z_][A-Za-z0-9_]*)\}")
PERCENT_RE = re.compile(r"%(?:\d+\$)?[sd]")


def now_iso():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="milliseconds")


def norm(s) -> str:
    return re.sub(r"\s+", " ", str(s or "")).strip()


def cell_text(v) -> str:
    """A sheet value as the app will see it ('' for empty)."""
    if v is None:
        return ""
    if isinstance(v, float) and v.is_integer():
        v = int(v)
    return str(v).strip()


def camel_case(key: str) -> str:
    parts = [p for p in re.split(r"[^A-Za-z0-9]+", key) if p]
    if not parts:
        return "emptyKey"
    out = parts[0].lower() + "".join(p[:1].upper() + p[1:].lower() for p in parts[1:])
    return ("k" + out) if out[0].isdigit() else out


# ════════════════════════════════════════════════════════════════════════════════════════════════════════════
# Dart source: read-only
# ════════════════════════════════════════════════════════════════════════════════════════════════════════════

class DartString:
    """One string literal: where it is, its value, and the $interpolations in it (as {placeholders})."""
    __slots__ = ("start", "end", "value", "line", "col", "placeholders", "raw")

    def __init__(self, start, end, value, line, col, placeholders, raw):
        self.start, self.end, self.value, self.line, self.col = start, end, value, line, col
        self.placeholders, self.raw = placeholders, raw


_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "b": "\b", "f": "\f", "v": "\v", "0": "\0",
            "'": "'", '"': '"', "\\": "\\", "$": "$"}


def _placeholder_name(expr: str) -> str:
    name = re.sub(r"[^A-Za-z0-9]+", "_", expr.strip()).strip("_")
    parts = [p for p in name.split("_") if p]
    if not parts:
        return "value"
    # widget.player.name -> playerName (the last two meaningful parts read best)
    keep = [p for p in parts if p not in ("widget", "this", "state", "context", "value", "length")] or parts
    keep = keep[-2:]
    return camel_case("_".join(keep))


def dart_strings(src: str):
    """Every string literal in Dart source, skipping comments. Adjacent literals stay separate."""
    i, n, line, line_start = 0, len(src), 1, 0
    out = []

    def nl_count(a, b):
        return src.count("\n", a, b)

    while i < n:
        c = src[i]
        if c == "\n":
            line += 1
            line_start = i + 1
            i += 1
            continue
        if src.startswith("//", i):
            j = src.find("\n", i)
            i = n if j < 0 else j
            continue
        if src.startswith("/*", i):
            depth, j = 1, i + 2
            while j < n and depth:
                if src.startswith("/*", j):
                    depth, j = depth + 1, j + 2
                elif src.startswith("*/", j):
                    depth, j = depth - 1, j + 2
                else:
                    j += 1
            line += nl_count(i, j)
            if "\n" in src[i:j]:
                line_start = src.rfind("\n", i, j) + 1
            i = j
            continue
        raw = False
        if c in "rR" and i + 1 < n and src[i + 1] in "'\"" and (i == 0 or not (src[i - 1].isalnum() or src[i - 1] == "_")):
            raw, c = True, src[i + 1]
            q_start = i + 1
        elif c in "'\"":
            q_start = i
        else:
            i += 1
            continue
        quote = src[q_start] * 3 if src.startswith(src[q_start] * 3, q_start) else src[q_start]
        j = q_start + len(quote)
        start, start_line, start_col = i, line, i - line_start + 1
        buf, phs = [], []
        while j < n:
            if src.startswith(quote, j):
                j += len(quote)
                break
            ch = src[j]
            if ch == "\n" and len(quote) == 1:  # unterminated single-line string: stop here
                break
            if not raw and ch == "\\" and j + 1 < n:
                e = src[j + 1]
                if e == "u":
                    if j + 2 < n and src[j + 2] == "{":
                        k = src.find("}", j + 3)
                        try:
                            buf.append(chr(int(src[j + 3:k], 16)))
                        except (ValueError, OverflowError):
                            pass
                        j = k + 1
                    else:
                        try:
                            buf.append(chr(int(src[j + 2:j + 6], 16)))
                        except ValueError:
                            pass
                        j += 6
                    continue
                if e == "x":
                    try:
                        buf.append(chr(int(src[j + 2:j + 4], 16)))
                    except ValueError:
                        pass
                    j += 4
                    continue
                buf.append(_ESCAPES.get(e, e))
                j += 2
                continue
            if not raw and ch == "$" and j + 1 < n:
                if src[j + 1] == "{":
                    depth, k = 1, j + 2
                    while k < n and depth:
                        if src[k] == "{":
                            depth += 1
                        elif src[k] == "}":
                            depth -= 1
                        elif src[k] in "'\"":  # nested string inside ${...}: skip it
                            q = src[k]
                            k += 1
                            while k < n and src[k] != q:
                                k += 2 if src[k] == "\\" else 1
                        k += 1
                    name = _placeholder_name(src[j + 2:k - 1])
                    phs.append(name)
                    buf.append("{" + name + "}")
                    j = k
                    continue
                m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", src[j + 1:])
                if m:
                    name = _placeholder_name(m.group(0))
                    phs.append(name)
                    buf.append("{" + name + "}")
                    j += 1 + len(m.group(0))
                    continue
            buf.append(ch)
            j += 1
        line += nl_count(start, j)
        if "\n" in src[start:j]:
            line_start = src.rfind("\n", start, j) + 1
        out.append(DartString(start, j, "".join(buf), start_line, start_col, phs, raw))
        i = j
    return out


def _literal_at(strings, pos):
    """The first literal starting at or after pos (strings are in source order)."""
    starts = getattr(_literal_at, "_cache", (None, None))
    if starts[0] is not strings:
        _literal_at._cache = starts = (strings, [x.start for x in strings])
    k = bisect.bisect_left(starts[1], pos)
    return strings[k] if k < len(strings) else None


def dart_quote(text: str) -> str:
    """A Dart single-quoted literal for text ($ and \\ escaped, so it's never interpolated)."""
    return "'" + (text.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$")
                  .replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")) + "'"


SECTION_RE = re.compile(r"^\s*//\s*══+\s*(.*?)\s*═*\s*$")
SUBSECTION_RE = re.compile(r"^\s*//\s*──+\s*(.*?)\s*─*\s*$")
TOKEN_RE = re.compile(r"static\s+const\s+(?:String\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*")
DEFAULT_ENTRY_RE = re.compile(r"(?:TrTokens\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)|(['\"])([^'\"]+)\2)\s*:\s*")


def _line_of(src, pos):
    return src.count("\n", 0, pos) + 1


def parse_tokens_file(path: Path):
    """class TrTokens { static const String emailTxt = 'email_txt'; // {placeholders} ... } in file order,
    with the ══ section / ── subsection each one sits under."""
    src = path.read_text("utf-8")
    strings = dart_strings(src)
    m = re.search(r"class\s+(\w+)\s*\{", src)
    cls = m.group(1) if m else "TrTokens"
    body_end = src.rfind("}")
    entries, section, sub = [], "", ""
    lines = src.split("\n")
    by_line = {}
    for t in TOKEN_RE.finditer(src):
        lit = _literal_at(strings, t.end())
        if lit is None or lit.start != t.end():
            continue
        by_line[_line_of(src, t.start())] = (t.group(1), lit)
    for no, text in enumerate(lines, 1):
        sm, ss = SECTION_RE.match(text), SUBSECTION_RE.match(text)
        if sm and sm.group(1):
            section, sub = sm.group(1).strip(), ""
            continue
        if ss and ss.group(1):
            sub = ss.group(1).strip()
            continue
        if no in by_line:
            name, lit = by_line[no]
            eol = src.find("\n", lit.end)
            cm = re.search(r";\s*//\s*(.*)$", src[lit.end:len(src) if eol < 0 else eol])
            entries.append({"token": name, "key": lit.value, "section": section, "subsection": sub,
                            "comment": cm.group(1).strip() if cm else "", "line": no})
    return {"path": str(path), "class": cls, "entries": entries, "end": body_end, "source": src}


def parse_defaults_file(path: Path):
    """const Map<String, String> defaultEnglishTranslations = { TrTokens.emailTxt: 'Email', ... } - values may
    be adjacent literals ('a' 'b'), raw, triple-quoted; keys may be TrTokens.x or a plain 'key'."""
    src = path.read_text("utf-8")
    strings = dart_strings(src)
    starts = [x.start for x in strings]
    m = re.search(r"(\w+)\s*=\s*(?:const\s*)?(?:<[^>]*>\s*)?\{", src)
    name = m.group(1) if m else "defaultEnglishTranslations"
    start = m.end() if m else 0
    entries, seen = [], set()
    pos = start
    for e in DEFAULT_ENTRY_RE.finditer(src, start):
        if e.start() < pos:
            continue
        # skip matches inside a string (a value containing "x: ")
        k = bisect.bisect_right(starts, e.start()) - 1
        if k >= 0 and strings[k].start < e.start() < strings[k].end:
            continue
        j = e.end()
        parts, last_end = [], j
        while True:
            k = j
            while k < len(src) and src[k] in " \t\r\n":
                k += 1
            if src.startswith("//", k):
                j = src.find("\n", k)
                continue
            lit = _literal_at(strings, k)
            if lit is not None and lit.start == k:
                parts.append(lit.value)
                j = last_end = lit.end
                continue
            break
        if not parts:
            continue
        token, key = (e.group(1), None) if e.group(1) else (None, e.group(3))
        first = _literal_at(strings, e.end())
        entries.append({"token": token, "key": key, "value": "".join(parts), "line": _line_of(src, e.start()),
                        "vstart": first.start if first else e.end(), "end": last_end,
                        "duplicate": (token or key) in seen})
        seen.add(token or key)
        pos = last_end
    return {"path": str(path), "name": name, "entries": entries, "source": src}


LANG_ENTRY_RE = re.compile(r"\bAppLanguage\s*\(")


def _call_args(src, open_paren, strings):
    """Text between ( and its matching ), skipping parentheses inside strings and comments."""
    depth, k = 1, open_paren + 1
    starts = [x.start for x in strings]
    while k < len(src) and depth:
        i = bisect.bisect_left(starts, k)
        if i < len(strings) and strings[i].start == k:
            k = strings[i].end
            continue
        if src.startswith("//", k):
            k = src.find("\n", k) if src.find("\n", k) > 0 else len(src)
            continue
        if src[k] == "(":
            depth += 1
        elif src[k] == ")":
            depth -= 1
        k += 1
    return src[open_paren + 1:k - 1], open_paren + 1


def parse_languages_file(path: Path):
    """LanguageRegistry.registeredLanguages (AppLanguage(code:, name:, countryCode:)) and the codes find()
    rejects (if (searchCode == 'vi-south') return null;)."""
    src = path.read_text("utf-8")
    strings = dart_strings(src)
    langs = []
    for m in LANG_ENTRY_RE.finditer(src):
        k = bisect.bisect_left([x.start for x in strings], m.start())
        if k > 0 and strings[k - 1].start < m.start() < strings[k - 1].end:
            continue  # inside a string
        body, _ = _call_args(src, m.end() - 1, strings)
        args = {}
        for s in dart_strings(body):
            nm = re.search(r"(\w+)\s*:\s*$", body[:s.start])
            if nm:
                args[nm.group(1)] = s.value
        if "code" in args and "name" in args:
            langs.append({"code": args["code"], "name": args["name"], "country": args.get("countryCode", ""),
                          "line": _line_of(src, m.start())})
    rejected = re.findall(r"searchCode\s*==\s*['\"]([^'\"]+)['\"]\s*\)\s*return\s+null", src)
    return {"path": str(path), "languages": langs, "rejected": rejected, "source": src}


# ── finding things in a project ──────────────────────────────────────────────────────────────────────────────
GENERATED_SUFFIXES = (".g.dart", ".freezed.dart", ".gr.dart", ".config.dart", ".mocks.dart", ".pb.dart",
                      ".pbenum.dart", ".pbjson.dart")
SKIP_DIRS = {"generated", "l10n", ".dart_tool", "build"}


def dart_files(lib: Path):
    for f in sorted(lib.rglob("*.dart")):
        if f.name.endswith(GENERATED_SUFFIXES) or any(p in SKIP_DIRS for p in f.relative_to(lib).parts[:-1]):
            continue
        yield f


def find_project_files(project: Path, overrides=None):
    """Where the TrTokens class, the default English map and the language registry are (None when absent)."""
    overrides = overrides or {}
    lib = project / "lib"
    if not lib.is_dir():
        raise ValueError(f"{project} has no lib/ folder - pick the Flutter project's root")
    found = {"tokens": None, "defaults": None, "languages": None}
    for kind in found:
        if overrides.get(kind):
            p = Path(overrides[kind])
            found[kind] = p if p.is_absolute() else project / p
    want = {k for k, v in found.items() if v is None}
    if want:
        for f in dart_files(lib):
            try:
                head = f.read_text("utf-8", errors="replace")
            except OSError:
                continue
            if "tokens" in want and re.search(r"class\s+TrTokens\b", head):
                found["tokens"], _ = f, want.discard("tokens")
            if "defaults" in want and re.search(r"\bdefaultEnglishTranslations\s*=", head):
                found["defaults"], _ = f, want.discard("defaults")
            if "languages" in want and re.search(r"class\s+LanguageRegistry\b", head):
                found["languages"], _ = f, want.discard("languages")
            if not want:
                break
    return found


# UI arguments whose string value people read.
UI_ARGS = {"hintText": "hint", "labelText": "label", "helperText": "help", "errorText": "error",
           "tooltip": "tooltip", "title": "title", "subtitle": "subtitle", "label": "label",
           "semanticLabel": "label", "semanticsLabel": "label", "message": "msg", "placeholder": "hint",
           "counterText": "txt", "prefixText": "txt", "suffixText": "txt", "buttonText": "btn_txt",
           "confirmText": "btn_txt", "cancelText": "btn_txt", "okText": "btn_txt", "description": "desc",
           "emptyText": "txt", "barrierLabel": "label", "text": "txt", "content": "txt", "subtitleText": "txt",
           "titleText": "title", "actionLabel": "btn_txt", "header": "title", "heading": "title"}
UI_CALLS = {"Text": "txt", "SelectableText": "txt", "TextSpan": "txt", "Tooltip": "tooltip",
            "SnackBar": "txt", "Tab": "txt", "AutoSizeText": "txt"}
NOT_UI_CALLS = {"Key", "ValueKey", "ObjectKey", "GlobalKey", "PageStorageKey", "print", "debugPrint", "log",
                "RegExp", "DateFormat", "NumberFormat", "Uri", "parse", "tryParse", "AssetImage", "Image",
                "SvgPicture", "Exception", "StateError", "ArgumentError", "FormatException", "assert",
                "UnimplementedError", "UnsupportedError", "Logger", "MethodChannel", "EventChannel", "Hive",
                "openBox", "box", "get", "put", "getString", "setString", "jsonDecode", "fromJson", "tr",
                "translate", "Color", "Icon", "Icons", "FontWeight", "TextStyle", "Duration", "Offset"}
LOOKS_TECHNICAL = re.compile(r"^(?:[a-z0-9_.\-/:]+|[A-Z0-9_]+|#?[0-9a-fA-F]{3,8}|\W*)$")


def _call_context(src: str, pos: int):
    """('Text', None) when the literal is Text('...')'s first argument, (None, 'hintText') for hintText: '...',
    (fn, None) for other calls - from the code just before the literal."""
    k = pos - 1
    while k >= 0 and src[k] in " \t\r\n":
        k -= 1
    if k >= 0 and src[k] == ":":
        m = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*$", src[max(0, k - 60):k])
        return None, m.group(1) if m else None
    if k >= 0 and src[k] == "(":
        m = re.search(r"([A-Za-z_][A-Za-z0-9_.]*)\s*$", src[max(0, k - 80):k])
        fn = m.group(1).split(".")[-1] if m else None
        if m and m.group(1).split(".")[0] in ("Text", "SelectableText") and fn in ("rich", "Text", "SelectableText"):
            fn = m.group(1).split(".")[0]
        return fn, None
    if k >= 0 and src[k] == "?":
        return "?", None
    return None, None


def is_ui_text(value: str) -> bool:
    t = value.strip()
    if len(t) < 2 or not re.search(r"[^\W\d_]", t):
        return False
    stripped = PLACEHOLDER_RE.sub("", t).strip()
    if not stripped or LOOKS_TECHNICAL.match(stripped):
        return False
    if re.match(r"^(https?:|mailto:|assets/|packages/|lib/)", t) or re.search(r"\.(png|jpe?g|svg|webp|json|gif|ttf)$", t):
        return False
    return True


def suggest_key(text: str, kind: str, taken) -> str:
    flat = re.sub(r"['’‘`]", "", PLACEHOLDER_RE.sub(lambda m: m.group(1), text.lower()))
    words = re.findall(r"[a-z0-9]+", flat)
    base = "_".join(words[:5])[:40].strip("_") or "text"
    if base[0].isdigit():
        base = "n_" + base
    suffix = UI_ARGS.get(kind) or UI_CALLS.get(kind) or "txt"
    key = f"{base}_{suffix}" if not base.endswith("_" + suffix) else base
    n, cand = 2, key
    while cand in taken:
        cand, n = f"{key}_{n}", n + 1
    return cand


def scan_hardcoded(project: Path, skip_files=(), english_index=None, taken_keys=()):
    """Hard-coded strings people would read, with file/line, how sure we are, a suggested key - or the existing
    key whose English is exactly this text (then nothing new is needed, only the code change)."""
    lib = project / "lib"
    skip = {Path(p).resolve() for p in skip_files if p}
    english_index = english_index or {}
    taken = set(taken_keys)
    found, by_text = [], {}
    for f in dart_files(lib):
        if f.resolve() in skip:
            continue
        try:
            src = f.read_text("utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        rel = f.relative_to(project).as_posix()
        for s in dart_strings(src):
            line_text = src[src.rfind("\n", 0, s.start) + 1:src.find("\n", s.start)]
            if re.match(r"\s*(import|export|part|library)\b", line_text) or line_text.lstrip().startswith("@"):
                continue
            fn, arg = _call_context(src, s.start)
            if fn in NOT_UI_CALLS or (arg and arg in ("key", "fontFamily", "package", "semanticsIdentifier",
                                                       "restorationId", "heroTag", "routeName", "name", "path",
                                                       "id", "type", "url", "image", "asset", "icon")):
                continue
            if not is_ui_text(s.value):
                continue
            if fn in UI_CALLS:
                kind, sure = fn, "high"
            elif arg in UI_ARGS:
                kind, sure = arg, "high"
            elif fn == "?" or re.search(r"[A-Z]", s.value[:1]) and " " in s.value.strip():
                kind, sure = (arg or fn or "txt"), "maybe"
            else:
                continue
            text = s.value
            existing = english_index.get(text) or english_index.get(norm(text))
            item = {"file": rel, "line": s.line, "col": s.col, "text": text, "context": kind or "",
                    "confidence": sure, "placeholders": s.placeholders, "existingKey": existing,
                    "snippet": line_text.strip()[:160]}
            if existing:
                item["key"] = existing
            elif text in by_text:
                item["key"] = by_text[text]
            else:
                item["key"] = suggest_key(text, kind or "txt", taken)
                taken.add(item["key"])
                by_text[text] = item["key"]
            found.append(item)
    return found


def token_usage(project: Path, cls="TrTokens", skip_files=()):
    """{token name: number of uses} in lib/, outside the constants files."""
    skip = {Path(p).resolve() for p in skip_files if p}
    use = {}
    pat = re.compile(rf"\b{re.escape(cls)}\s*\.\s*([A-Za-z_][A-Za-z0-9_]*)")
    for f in dart_files(project / "lib"):
        if f.resolve() in skip:
            continue
        try:
            src = f.read_text("utf-8", errors="replace")
        except OSError:
            continue
        for m in pat.finditer(src):
            use[m.group(1)] = use.get(m.group(1), 0) + 1
    return use


# ════════════════════════════════════════════════════════════════════════════════════════════════════════════
# The translation sheet
# ════════════════════════════════════════════════════════════════════════════════════════════════════════════

def lock_files(path: Path):
    """Excel (~$name.xlsx) / LibreOffice (.~lock.name#) lock files: the sheet may be open elsewhere."""
    out = []
    for cand in (path.with_name("~$" + path.name), path.with_name(".~lock." + path.name + "#")):
        if cand.exists():
            info = {"file": cand.name, "modified": dt.datetime.fromtimestamp(cand.stat().st_mtime).isoformat(timespec="minutes")}
            try:
                parts = cand.read_text("utf-8", errors="replace").split(",")
                if cand.name.startswith(".~lock") and len(parts) >= 3:
                    info.update(user=parts[1].strip(), machine=parts[2].strip())
            except OSError:
                pass
            info["stale"] = cand.stat().st_mtime < path.stat().st_mtime - 60 if path.exists() else False
            out.append(info)
    return out


def unkeepable(path: Path):
    """Parts of an .xlsx openpyxl drops on save: charts, pivot tables, in-cell pictures, macros."""
    out = []
    try:
        names = zipfile.ZipFile(path).namelist()
    except (zipfile.BadZipFile, OSError):
        return ["not a readable .xlsx file"]
    if any(n.startswith("xl/charts/") for n in names):
        out.append("charts")
    if any(n.startswith("xl/pivotTables/") or n.startswith("xl/pivotCache/") for n in names):
        out.append("pivot tables")
    if any(n.startswith("xl/richData/") for n in names):
        out.append("pictures placed in cells")
    if any(n.endswith("vbaProject.bin") for n in names):
        out.append("macros")
    return out


def backup(path: Path):
    folder = path.parent / "backups"
    folder.mkdir(exist_ok=True)
    stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    dest = folder / f"{path.stem}-{stamp}{path.suffix}"
    n = 1
    while dest.exists():
        dest, n = folder / f"{path.stem}-{stamp}-{n}{path.suffix}", n + 1
    shutil.copy2(path, dest)
    for old in sorted(folder.glob(f"{path.stem}-*{path.suffix}"))[:-BACKUPS_KEPT]:
        old.unlink()
    return dest


def resolve_code(header: str, tab_map: dict, json_map: dict):
    """-> (code, name, country, how) or None. Order: Languages tab, languages.json, (code) in brackets, a header
    that is a code, the table of names."""
    h = norm(header)
    if h in tab_map:
        return (*tab_map[h], "Languages tab")
    if h in json_map:
        v = json_map[h]
        return (v[0], v[1] if len(v) > 1 else v[0], v[2] if len(v) > 2 else "", "languages.json")
    m = re.search(r"\(([A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*)\)\s*$", h)
    if m and CODE_RE.match(m.group(1)[:2].lower() + m.group(1)[2:]):
        code = m.group(1)
        base = KNOWN_LANGUAGES.get(norm(h[:m.start()]).lower())
        return (code, base[1] if base else code, base[2] if base else "", "brackets")
    if CODE_RE.match(h):
        k = next((v for v in KNOWN_LANGUAGES.values() if v[0] == h), None)
        return (h, k[1] if k else h, k[2] if k else "", "header is a code")
    k = KNOWN_LANGUAGES.get(h.lower())
    if k:
        return (*k, "known name")
    return None


class Sheet:
    """The translation workbook in memory: every tab whose first header is Key, merged; the Languages tab."""

    def __init__(self, path: Path):
        self.path = Path(path)
        if not self.path.exists():
            raise ValueError(f"{self.path} doesn't exist")
        self.wb = openpyxl.load_workbook(self.path)
        self.mtime = self.path.stat().st_mtime
        self.dirty = False
        self.unsupported = unkeepable(self.path)
        self._read()

    # ---- reading ------------------------------------------------------------------------------------------
    def _read(self):
        self.tabs, self.rows, self.duplicates = [], {}, []
        self.columns = []       # language columns in sheet order (headers)
        self.meta = []          # grey columns seen
        for ws in self.wb.worksheets:
            if ws.title == LANGUAGES_TAB or ws.max_row < 1:
                continue
            hdr = [norm(c.value) for c in ws[1]]
            if not hdr or hdr[0].lower() != KEY_HEADER:
                continue
            cols = {h: i + 1 for i, h in enumerate(hdr) if h}
            eng = next((i for h, i in cols.items() if h.lower() == ENGLISH_HEADER), None)
            if eng is None:
                continue
            langs = [h for h in cols if h.lower() not in (KEY_HEADER, ENGLISH_HEADER) and h.lower() not in META_HEADERS]
            for h in langs:
                if h not in self.columns:
                    self.columns.append(h)
            self.meta += [h for h in cols if h.lower() in META_HEADERS and h not in self.meta]
            self.tabs.append({"name": ws.title, "cols": cols, "english": eng})
            for r in range(2, ws.max_row + 1):
                key = cell_text(ws.cell(r, 1).value)
                if not key:
                    continue
                if key in self.rows:
                    self.duplicates.append({"key": key, "tab": ws.title, "row": r,
                                            "first": f"{self.rows[key]['tab']}!{self.rows[key]['row']}"})
                    continue
                vals = {h: cell_text(ws.cell(r, i).value) for h, i in cols.items() if i > 1}
                self.rows[key] = {"tab": ws.title, "row": r, "english": vals.get(next(h for h in cols if cols[h] == eng), ""),
                                  "values": {h: vals.get(h, "") for h in langs},
                                  "meta": {h: vals.get(h, "") for h in cols if h.lower() in META_HEADERS}}
        if not self.tabs:
            raise ValueError(f"{self.path.name} has no tab whose first column header is 'Key' (and an 'English' column)")
        self._read_languages()

    def _read_languages(self):
        self.tab_langs = {}
        self.statuses = {}
        if LANGUAGES_TAB in self.wb.sheetnames:
            ws = self.wb[LANGUAGES_TAB]
            hdr = [norm(c.value).lower() for c in ws[1]]
            ix = {h: i for i, h in enumerate(hdr)}
            for row in ws.iter_rows(min_row=2, values_only=True):
                get = lambda name: cell_text(row[ix[name]]) if name in ix and ix[name] < len(row) else ""  # noqa: E731
                col = norm(get("column"))
                if col and get("code"):
                    self.tab_langs[col] = (get("code"), get("name") or get("code"), get("country"))
                    if get("status"):
                        self.statuses[get("code")] = get("status").lower()
        self.json_langs = {}
        jp = self.path.with_name("languages.json")
        if jp.exists():
            try:
                self.json_langs = {norm(k): v for k, v in json.loads(jp.read_text("utf-8")).items()}
            except (ValueError, OSError):
                pass

    def languages(self):
        """[{column, code, name, country, how, status}] - code None when it can't be resolved."""
        out = []
        for h in self.columns:
            r = resolve_code(h, self.tab_langs, self.json_langs)
            if r is None:
                out.append({"column": h, "code": None, "name": "", "country": "", "how": None, "status": "unresolved"})
            else:
                code, name, country, how = r
                out.append({"column": h, "code": code, "name": name, "country": country, "how": how,
                            "status": self.statuses.get(code, "active")})
        return out

    # ---- writing ------------------------------------------------------------------------------------------
    def _tab(self, name=None):
        t = next((t for t in self.tabs if t["name"] == name), None) if name else None
        return t or self.tabs[0]

    def _style_like(self, ws, r, src_row):
        if src_row < 2:
            return
        for c in range(1, ws.max_column + 1):
            ws.cell(r, c)._style = copy(ws.cell(src_row, c)._style)

    def set_cell(self, key, column, text):
        """-> old value. column is 'English', a language header or a meta header."""
        row = self.rows.get(key)
        if row is None:
            raise ValueError(f"No key {key!r} in the sheet")
        tab = self._tab(row["tab"])
        col = tab["english"] if column.lower() == ENGLISH_HEADER else tab["cols"].get(column)
        if col is None:
            raise ValueError(f"Tab {tab['name']} has no column {column!r}")
        ws = self.wb[tab["name"]]
        old = cell_text(ws.cell(row["row"], col).value)
        text = "" if text is None else str(text)
        if old == text.strip() and old == text:
            return old
        ws.cell(row["row"], col).value = text if text != "" else None
        if column.lower() == ENGLISH_HEADER:
            row["english"] = text.strip()
        elif column in row["values"]:
            row["values"][column] = text.strip()
        else:
            row["meta"][column] = text.strip()
        self.dirty = True
        return old

    def add_row(self, key, english, tab=None, meta=None, mark=True):
        """Appends a key (refuses a duplicate). -> (tab, row)."""
        if key in self.rows:
            raise ValueError(f"Key {key!r} is already in the sheet ({self.rows[key]['tab']} row {self.rows[key]['row']})")
        if not KEY_RE.match(key):
            raise ValueError(f"{key!r} isn't a valid key: lower case words joined by _ (e.g. save_list_btn_txt)")
        t = self._tab(tab)
        ws = self.wb[t["name"]]
        r = ws.max_row + 1
        while r > 2 and not any(ws.cell(r - 1, c).value not in (None, "") for c in range(1, ws.max_column + 1)):
            r -= 1
        self._style_like(ws, r, r - 1)
        ws.cell(r, 1).value = key
        ws.cell(r, t["english"]).value = english
        for h, v in (meta or {}).items():
            c = next((i for name, i in t["cols"].items() if name.lower() == h.lower()), None)
            if c and v:
                ws.cell(r, c).value = v
        if mark:
            ws.cell(r, 1).fill = NEW_ROW_FILL
        self.rows[key] = {"tab": t["name"], "row": r, "english": english,
                          "values": {h: "" for h in self.columns if h in t["cols"]},
                          "meta": {h: (meta or {}).get(h, "") for h in t["cols"] if h.lower() in META_HEADERS}}
        self.dirty = True
        return t["name"], r

    def remove_row(self, key):
        """Undo of add_row only (clears the cells of the last-added row)."""
        row = self.rows.pop(key, None)
        if not row:
            return
        ws = self.wb[row["tab"]]
        for c in range(1, ws.max_column + 1):
            ws.cell(row["row"], c).value = None
            ws.cell(row["row"], c).fill = PatternFill(fill_type=None)
        self.dirty = True

    def add_language_column(self, header, tab=None):
        """A new language column at the end of every Key tab (or one). -> tabs changed"""
        header = norm(header)
        if not header or header.lower() in (KEY_HEADER, ENGLISH_HEADER) or header.lower() in META_HEADERS:
            raise ValueError(f"{header!r} can't be a language column")
        changed = []
        for t in (self.tabs if tab is None else [self._tab(tab)]):
            if header in t["cols"]:
                continue
            ws = self.wb[t["name"]]
            c = max(t["cols"].values()) + 1
            ws.cell(1, c).value = header
            ws.cell(1, c)._style = copy(ws.cell(1, c - 1)._style)
            ws.column_dimensions[ws.cell(1, c).column_letter].width = \
                ws.column_dimensions[ws.cell(1, c - 1).column_letter].width or 24
            t["cols"][header] = c
            changed.append(t["name"])
        if header not in self.columns:
            self.columns.append(header)
            for row in self.rows.values():
                row["values"].setdefault(header, "")
        self.dirty = True
        return changed

    def remove_language_column(self, header):
        """Undo of add_language_column (only an empty, last column)."""
        for t in self.tabs:
            c = t["cols"].get(header)
            if c and c == max(t["cols"].values()):
                ws = self.wb[t["name"]]
                for r in range(1, ws.max_row + 1):
                    ws.cell(r, c).value = None
                del t["cols"][header]
        if header in self.columns:
            self.columns.remove(header)
        for row in self.rows.values():
            row["values"].pop(header, None)
        self.dirty = True

    def write_languages(self, langs):
        """The Languages tab, from [{column, code, name, country, status}]."""
        if LANGUAGES_TAB in self.wb.sheetnames:
            ws = self.wb[LANGUAGES_TAB]
            ws.delete_rows(1, ws.max_row)
        else:
            ws = self.wb.create_sheet(LANGUAGES_TAB)
        ws.append(LANGUAGES_COLUMNS)
        for c in ws[1]:
            c.font = Font(bold=True)
        for col, w in zip("ABCDE", (28, 12, 26, 10, 12)):
            ws.column_dimensions[col].width = w
        for lang in langs:
            ws.append([lang.get("column"), lang.get("code"), lang.get("name"), lang.get("country"),
                       lang.get("status") or "active"])
        self.dirty = True
        self._read_languages()

    def languages_rows(self):
        if LANGUAGES_TAB not in self.wb.sheetnames:
            return None
        ws = self.wb[LANGUAGES_TAB]
        hdr = [norm(c.value).lower() for c in ws[1]]
        out = []
        for row in ws.iter_rows(min_row=2, values_only=True):
            d = {h: cell_text(row[i]) if i < len(row) else "" for i, h in enumerate(hdr) if h}
            if d.get("column"):
                out.append({"column": d.get("column"), "code": d.get("code"), "name": d.get("name"),
                            "country": d.get("country"), "status": d.get("status") or "active"})
        return out

    def save(self, force=False):
        if self.unsupported:
            raise RuntimeError("Not saved - saving would lose part of this workbook: " + ", ".join(self.unsupported))
        if not force and self.path.exists() and self.path.stat().st_mtime > self.mtime + 1:
            raise RuntimeError(f"{self.path.name} changed on disk since it was opened (someone saved it in Excel, "
                               "or another tool). Not saved, so neither version is lost: reopen it to pick up "
                               "those changes, or save with force to overwrite them.")
        tmp = self.path.with_name(self.path.stem + ".tmp" + self.path.suffix)
        self.wb.save(tmp)
        check = openpyxl.load_workbook(tmp, read_only=True)
        n = sum(1 for t in self.tabs for _ in check[t["name"]].iter_rows(min_row=2, max_col=1, values_only=True))
        check.close()
        if n < len(self.rows):
            tmp.unlink()
            raise RuntimeError(f"Not saved - the written file had {n} key rows instead of {len(self.rows)}")
        bk = backup(self.path)
        os.replace(tmp, self.path)
        self.mtime = self.path.stat().st_mtime
        self.dirty = False
        return str(bk)


# ════════════════════════════════════════════════════════════════════════════════════════════════════════════
# The project (read-only) and the report that compares it with the sheet
# ════════════════════════════════════════════════════════════════════════════════════════════════════════════

class Project:
    def __init__(self, root: Path, overrides=None):
        self.root = Path(root)
        self.files = find_project_files(self.root, overrides)
        self.tokens = parse_tokens_file(self.files["tokens"]) if self.files["tokens"] else None
        self.defaults = parse_defaults_file(self.files["defaults"]) if self.files["defaults"] else None
        self.registry = parse_languages_file(self.files["languages"]) if self.files["languages"] else None

    @property
    def constants_files(self):
        return [p for p in self.files.values() if p]

    def key_of_token(self):
        return {e["token"]: e["key"] for e in (self.tokens or {}).get("entries", [])}

    def english(self):
        """{key: default English} (via the token names)."""
        k = self.key_of_token()
        out = {}
        for e in (self.defaults or {}).get("entries", []):
            key = k.get(e["token"]) if e["token"] else e["key"]
            if key and key not in out:
                out[key] = e["value"]
        return out


def placeholders(text):
    return sorted(set(PLACEHOLDER_RE.findall(text or "")))


def stray_braces(text):
    t = PLACEHOLDER_RE.sub("", text or "")
    return t.count("{") + t.count("}")


def check_translation(english, text):
    """Problems a translation would cause in the app (empty list = fine)."""
    out = []
    if not text:
        return out
    pe, pt = placeholders(english), placeholders(text)
    missing, extra = [p for p in pe if p not in pt], [p for p in pt if p not in pe]
    if missing:
        out.append(("placeholder_missing", "error", f"missing {', '.join('{' + p + '}' for p in missing)}"))
    if extra:
        out.append(("placeholder_unknown", "error",
                    f"{', '.join('{' + p + '}' for p in extra)} isn't in the English - the app prints it as is"))
    if len(PERCENT_RE.findall(english or "")) != len(PERCENT_RE.findall(text)):
        out.append(("percent_mismatch", "error", "%s / %d count differs from the English"))
    if stray_braces(text) and not stray_braces(english):
        out.append(("stray_brace", "warning", "a { or } that isn't a placeholder"))
    if text != text.strip() and english == (english or "").strip():
        out.append(("whitespace", "info", "starts or ends with a space the English doesn't have"))
    return out


def build_report(project: Project | None, sheet: Sheet | None, hardcoded=None, usage=None):
    """Everything that's out of step, per key and per language, plus coverage. Read-only."""
    issues = []

    def add(kind, severity, message, key=None, language=None, where=None):
        issues.append({"kind": kind, "severity": severity, "message": message, "key": key,
                       "language": language, "where": where})

    tokens = (project.tokens or {}).get("entries", []) if project else []
    dart_keys = [e["key"] for e in tokens]
    dart_english = project.english() if project else {}
    sheet_rows = sheet.rows if sheet else {}
    langs = sheet.languages() if sheet else []

    # ── the Dart side ──
    if project:
        if not project.tokens:
            add("no_tokens_file", "warning", "No TrTokens class found in lib/ - export creates trc_constant_tokens.dart")
        if not project.defaults:
            add("no_defaults_file", "warning", "No defaultEnglishTranslations map found - export creates default_english_tr.dart")
        seen_tok, seen_key = {}, {}
        for e in tokens:
            if e["token"] in seen_tok:
                add("duplicate_token", "error", f"TrTokens.{e['token']} is declared twice (lines {seen_tok[e['token']]} "
                    f"and {e['line']}) - the app won't compile", e["key"], where=f"line {e['line']}")
            seen_tok.setdefault(e["token"], e["line"])
            if e["key"] in seen_key:
                add("duplicate_key_value", "error", f"{seen_key[e['key']]} and {e['token']} both hold '{e['key']}'",
                    e["key"], where=f"line {e['line']}")
            seen_key.setdefault(e["key"], e["token"])
            if not KEY_RE.match(e["key"]):
                add("bad_key", "warning", f"'{e['key']}' isn't lower_snake_case", e["key"])
            if e["key"] not in dart_english:
                add("no_default_english", "error", f"TrTokens.{e['token']} has no entry in defaultEnglishTranslations "
                    "- people see the raw key until a pack has it", e["key"])
        names = set(seen_tok)
        for d in (project.defaults or {}).get("entries", []):
            if d["token"] and d["token"] not in names:
                add("default_without_token", "error", f"defaultEnglishTranslations uses TrTokens.{d['token']}, "
                    "which doesn't exist - the app won't compile", where=f"line {d['line']}")
            if d.get("duplicate"):
                add("duplicate_default", "error", f"{d['token'] or d['key']} appears twice in defaultEnglishTranslations",
                    where=f"line {d['line']}")
        if usage is not None:
            for e in tokens:
                if not usage.get(e["token"]):
                    add("unused_token", "info", f"TrTokens.{e['token']} isn't used anywhere in lib/", e["key"])

    # ── Dart <-> sheet ──
    if project and sheet:
        dk = set(dart_keys)
        for key in dart_keys:
            if key not in sheet_rows:
                add("missing_in_sheet", "warning", "in the app, not in the sheet - nobody can translate it", key)
            elif dart_english.get(key) is not None and norm(dart_english[key]) != norm(sheet_rows[key]["english"]):
                add("english_mismatch", "warning", f"app: \"{dart_english[key]}\"  /  sheet: \"{sheet_rows[key]['english']}\"",
                    key)
        for key, row in sheet_rows.items():
            if key not in dk:
                add("missing_in_app", "info", "in the sheet, not in TrTokens - unused by the app, or not added yet",
                    key, where=f"{row['tab']}!{row['row']}")

    # ── the sheet ──
    cover = []
    if sheet:
        for d in sheet.duplicates:
            add("duplicate_key", "error", f"appears again at {d['tab']} row {d['row']} (first at {d['first']}); "
                "the first one is used", d["key"])
        live = [k for k in sheet_rows if not project or not project.tokens or k in set(dart_keys)] or list(sheet_rows)
        for lang in langs:
            if lang["code"] is None:
                add("language_unresolved", "error", f"column '{lang['column']}' has no language code - add it to the "
                    "Languages tab, or write the code in brackets: 'Korean (ko)'", language=lang["column"])
        codes = {}
        for lang in langs:
            if lang["code"]:
                if lang["code"] in codes and lang["status"] != "deprecated":
                    add("duplicate_code", "error", f"'{lang['column']}' and '{codes[lang['code']]}' both resolve to "
                        f"{lang['code']} - one pack would replace the other", language=lang["column"])
                codes.setdefault(lang["code"], lang["column"])
        for key, row in sheet_rows.items():
            if not row["english"]:
                add("empty_english", "error", "no English - export and packs skip it", key, where=f"{row['tab']}!{row['row']}")
            elif not KEY_RE.match(key):
                add("bad_key", "warning", f"'{key}' isn't lower_snake_case", key)
        for lang in langs:
            col = lang["column"]
            done = same = 0
            for key in live:
                row = sheet_rows[key]
                text = row["values"].get(col, "")
                if not text:
                    continue
                done += 1
                if text == row["english"] and re.search(r"[A-Za-z]{4,}", text):
                    same += 1
                for kind, sev, msg in check_translation(row["english"], text):
                    add(kind, sev, msg, key, col)
            # keys the app uses that the sheet lacks can't be translated: they count against coverage
            total = len(live) + (len([k for k in dart_keys if k not in sheet_rows]) if project and project.tokens else 0)
            cover.append({**lang, "translated": done, "total": total, "sameAsEnglish": same,
                          "percent": round(100 * done / total, 1) if total else 100.0})
            if total - done:
                add("untranslated", "info", f"{total - done} of {total} keys not translated (they show in English)",
                    language=col)

    # ── the registry ──
    if project and project.registry and sheet:
        reg = {x["code"]: x for x in project.registry["languages"]}
        for lang in langs:
            if lang["code"] and lang["status"] != "deprecated" and lang["code"] not in reg \
                    and lang["code"] not in project.registry["rejected"]:
                add("registry_missing", "warning", f"{lang['code']} ({lang['column']}) isn't in the language registry "
                    "- the app shows it as its code until the exported registry ships", language=lang["column"])
            elif lang["code"] in reg and lang["name"] and lang["how"] == "Languages tab" \
                    and reg[lang["code"]]["name"] != lang["name"]:
                add("registry_name", "info", f"registry calls {lang['code']} \"{reg[lang['code']]['name']}\", the "
                    f"Languages tab \"{lang['name']}\"", language=lang["column"])

    for h in hardcoded or []:
        add("hardcoded", "warning" if h["confidence"] == "high" else "info",
            f"\"{h['text']}\" is written in the code" + (f" (already in the sheet as {h['existingKey']})"
                                                       if h.get("existingKey") else ""),
            h.get("existingKey") or h.get("key"), where=f"{h['file']}:{h['line']}")

    counts = {}
    for i in issues:
        counts[i["severity"]] = counts.get(i["severity"], 0) + 1
    return {"issues": issues, "counts": counts, "coverage": cover,
            "keys": {"app": len(dart_keys), "sheet": len(sheet_rows),
                     "both": len(set(dart_keys) & set(sheet_rows)) if sheet else 0}}


# ════════════════════════════════════════════════════════════════════════════════════════════════════════════
# Exports: generated Dart (merged into your files' text), language packs
# ════════════════════════════════════════════════════════════════════════════════════════════════════════════

SECTION_LINE = "  // ══ {name} " + "═" * 60
NEW_SECTION = "NEW"


def _apply_edits(src: str, edits):
    """edits: [(offset, delete_len, insert_text)] on the original text, applied from the end."""
    for off, dlen, text in sorted(edits, key=lambda e: (e[0], e[1]), reverse=True):
        src = src[:off] + text + src[off + dlen:]
    return src


def _line_offsets(src):
    offs = [0]
    for i, ch in enumerate(src):
        if ch == "\n":
            offs.append(i + 1)
    return offs


def _section_insert_points(src, entry_lines, close_offset):
    """{section name: offset just after the last entry line of that section}, from the ══ headers."""
    offs = _line_offsets(src)
    lines = src.split("\n")
    points, current, last_line = {}, "", {}
    entry_lines = set(entry_lines)
    for no, text in enumerate(lines, 1):
        m = SECTION_RE.match(text)
        if m and m.group(1):
            current = m.group(1).strip()
        if no in entry_lines:
            last_line[current] = no
    for sec, no in last_line.items():
        points[sec] = offs[no] if no < len(offs) else close_offset
    return points


def _close_of(src, pattern):
    """Offset of the line holding the closing brace (class '}' / map '};')."""
    pos = src.rfind(pattern)
    if pos < 0:
        return len(src)
    return src.rfind("\n", 0, pos) + 1


def merge_tokens(project_tokens, new_entries):
    """Your trc_constant_tokens.dart text plus new_entries [{token, key, section, comment}]."""
    src = project_tokens["source"]
    close = _close_of(src, "}")
    points = _section_insert_points(src, [e["line"] for e in project_tokens["entries"]], close)
    edits, groups = [], {}
    for e in new_entries:
        sec = e.get("section") if e.get("section") in points else NEW_SECTION
        groups.setdefault(sec, []).append(e)
    for sec, items in groups.items():
        body = "".join(f"  static const String {e['token']} = {dart_quote(e['key'])};"
                       + (f" // {e['comment']}" if e.get("comment") else "") + "\n" for e in items)
        if sec in points:
            edits.append((points[sec], 0, body))
        else:
            edits.append((close, 0, "\n" + SECTION_LINE.format(name=sec) + "\n" + body))
    return _apply_edits(src, edits)


def merge_defaults(project_defaults, cls, new_entries, english_updates):
    """Your default_english_tr.dart text plus new entries [{token, english, section}], and English replaced in
    place for english_updates {token: text}."""
    src = project_defaults["source"]
    close = _close_of(src, "};")
    points = _section_insert_points(src, [e["line"] for e in project_defaults["entries"]], close)
    edits, groups = [], {}
    for e in project_defaults["entries"]:
        if e["token"] in english_updates:
            edits.append((e["vstart"], e["end"] - e["vstart"], dart_quote(english_updates[e["token"]])))
    for e in new_entries:
        sec = e.get("section") if e.get("section") in points else NEW_SECTION
        groups.setdefault(sec, []).append(e)
    for sec, items in groups.items():
        body = "".join(f"  {cls}.{e['token']}: {dart_quote(e['english'])},\n" for e in items)
        edits.append((points[sec], 0, body) if sec in points
                     else (close, 0, "  // ══ " + sec + " " + "═" * 60 + "\n" + body))
    return _apply_edits(src, edits)


def new_tokens_file(entries, cls="TrTokens"):
    out = ["// Translation keys for the app. Created by Clasher Studio; safe to edit by hand -",
           "// the Studio only ever adds lines here, under the section a key belongs to.",
           "//", "// A comment after a constant lists its placeholders.",
           f"class {cls} {{", f"  {cls}._();", ""]
    sec = None
    for e in entries:
        if e.get("section", "COMMON") != sec:
            sec = e.get("section") or "COMMON"
            out += ["", SECTION_LINE.format(name=sec)]
        out.append(f"  static const String {e['token']} = {dart_quote(e['key'])};"
                   + (f" // {e['comment']}" if e.get("comment") else ""))
    out += ["}", ""]
    return "\n".join(out)


def new_defaults_file(entries, tokens_import, cls="TrTokens"):
    out = [f"import '{tokens_import}';", "",
           f"/// English for every {cls} key, in the same order and sections as {cls}.",
           "const Map<String, String> defaultEnglishTranslations = {"]
    sec = None
    for e in entries:
        if e.get("section", "COMMON") != sec:
            sec = e.get("section") or "COMMON"
            out.append("  // ══ " + sec + " " + "═" * 60)
        out.append(f"  {cls}.{e['token']}: {dart_quote(e['english'])},")
    out += ["};", ""]
    return "\n".join(out)


REGISTRY_TEMPLATE = """// GENERATED by Clasher Studio from the translation sheet's Languages. Edit the sheet, not this file:
// add the language to the sheet (and to its Languages tab) and export again.
//
// `code` is the language pack's name on the release: lang_<code>.zip. It is also
// what TranslationService stores, so changing a code here orphans what people
// already downloaded under the old one.

class AppLanguage {{
  final String code; // matches lang_<code>.zip on the translations release
  final String name; // native language name, for the picker
  final String countryCode; // for the GeoConstants flag lookup

  const AppLanguage({{
    required this.code,
    required this.name,
    required this.countryCode,
  }});
}}

class LanguageRegistry {{
  LanguageRegistry._();

  /// English first, then every language published as a pack.
  static const List<AppLanguage> registeredLanguages = [
{entries}  ];

  /// Languages that come from the release, i.e. everything except English.
  static List<AppLanguage> get downloadable =>
      registeredLanguages.where((l) => l.code != 'en').toList();

  static AppLanguage? find(String code) {{
    final searchCode = code.trim().toLowerCase();

    // Removed languages: their packs are no longer published.
{rejects}
    for (final lang in registeredLanguages) {{
      if (lang.code.toLowerCase() == searchCode) return lang;
    }}

    // Fallback for legitimately new packs
    return AppLanguage(
      code: code,
      name: code.toUpperCase(),
      countryCode: code.contains('-')
          ? code.split('-').last.toUpperCase()
          : code.toUpperCase(),
    );
  }}
}}
"""


def _lang_line(lang):
    return (f"    AppLanguage(code: {dart_quote(lang['code'])}, name: {dart_quote(lang['name'] or lang['code'])}, "
            f"countryCode: {dart_quote(lang['country'] or '')}),\n")


def registry_text(project_registry, langs):
    """Your app_language_constants.dart plus the languages it doesn't list yet (and find() rejecting the
    deprecated ones) - or a new one when the project has none."""
    active = [l for l in langs if l.get("code") and l.get("status") != "deprecated"]
    deprecated = sorted({l["code"].lower() for l in langs if l.get("code") and l.get("status") == "deprecated"})
    if project_registry is None:
        entries = _lang_line({"code": "en", "name": "English", "country": "US"}) + "".join(
            _lang_line(l) for l in active if l["code"] != "en")
        rejects = "".join(f"    if (searchCode == {dart_quote(c)}) return null;\n" for c in deprecated)
        return REGISTRY_TEMPLATE.format(entries=entries, rejects=rejects)
    src = project_registry["source"]
    have = {x["code"] for x in project_registry["languages"]}
    edits = []
    add = [l for l in active if l["code"] not in have and l["code"].lower() not in project_registry["rejected"]]
    if add:
        m = re.search(r"registeredLanguages\s*=\s*\[", src)
        close = src.find("];", m.end()) if m else -1
        if close > 0:
            edits.append((src.rfind("\n", 0, close) + 1, 0, "".join(_lang_line(l) for l in add)))
    rej = [c for c in deprecated if c not in [r.lower() for r in project_registry["rejected"]]]
    if rej:
        m = re.search(r"final\s+searchCode\s*=.*?;\n", src)
        if m:
            edits.append((m.end(), 0, "".join(f"    if (searchCode == {dart_quote(c)}) return null;\n" for c in rej)))
    return _apply_edits(src, edits)


def unified_diff(old, new, name):
    lines = list(difflib.unified_diff(old.splitlines(keepends=True), new.splitlines(keepends=True),
                                      fromfile=f"project/{name}", tofile=f"export/{name}", n=2))
    return "".join(lines[:4000])


def write_zip(path: Path, payload: bytes, entry="translations.json"):
    """Byte-for-byte reproducible: fixed timestamp and permissions."""
    tmp = path.with_suffix(".tmp")
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED) as zf:
        info = zipfile.ZipInfo(entry, date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        zf.writestr(info, payload)
    os.replace(tmp, path)


def sha256(path: Path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


# ════════════════════════════════════════════════════════════════════════════════════════════════════════════
# Engine: what the Studio talks to
# ════════════════════════════════════════════════════════════════════════════════════════════════════════════

JOURNALED = ("set_cells", "add_rows", "add_language", "set_languages", "undo")


def journal_path(sheet_path):
    return Path(str(sheet_path) + ".unsaved.jsonl")


def _journaled(fn):
    @functools.wraps(fn)
    def run(self, *a, **k):
        out = fn(self, *a, **k)
        self._journal(fn.__name__, a, k)
        return out
    return run


class Engine:
    def __init__(self, log=print, source="clasher_studio"):
        self.log, self.source = log, source
        self.project = self.sheet = None
        self.overrides = {}
        self._hardcoded = None
        self._usage = None
        self._undo = []
        self.journaling = True
        self._pending_journal = None

    # ---- opening ------------------------------------------------------------------------------------------
    def open(self, project=None, sheet=None, overrides=None):
        self.overrides = overrides or {}
        self.project = Project(Path(project), self.overrides) if project else None
        self._hardcoded = self._usage = None
        self._undo = []
        self.sheet = None
        if sheet:
            sp = Path(sheet)
            jp = journal_path(sp)
            if jp.exists():  # a session that never saved: keep it aside and offer it
                pending = sp.with_name(f"{sp.name}.unsaved-pending-{dt.datetime.now():%Y%m%d-%H%M%S}.jsonl")
                os.replace(jp, pending)
            self.sheet = Sheet(sp)
        return self.summary()

    def _pending_files(self):
        if not self.sheet:
            return []
        return sorted(self.sheet.path.parent.glob(self.sheet.path.name + ".unsaved-pending-*.jsonl"))

    def summary(self):
        p, sh = self.project, self.sheet
        out = {"project": None, "sheet": None}
        if p:
            out["project"] = {"root": str(p.root), "files": {k: str(v) if v else None for k, v in p.files.items()},
                              "tokens": len(p.tokens["entries"]) if p.tokens else 0,
                              "sections": list(dict.fromkeys(e["section"] for e in p.tokens["entries"]))
                              if p.tokens else [],
                              "class": p.tokens["class"] if p.tokens else "TrTokens",
                              "registry": [{"code": x["code"], "name": x["name"], "country": x["country"]}
                                           for x in p.registry["languages"]] if p.registry else None,
                              "rejected": p.registry["rejected"] if p.registry else []}
        if sh:
            entries = 0
            for f in self._pending_files():
                entries += sum(1 for line in f.read_text("utf-8").splitlines() if '"op"' in line)
            out["sheet"] = {"path": str(sh.path), "tabs": [t["name"] for t in sh.tabs], "keys": len(sh.rows),
                            "languages": sh.languages(), "meta": sh.meta, "dirty": sh.dirty, "undo": len(self._undo),
                            "locks": lock_files(sh.path), "unsupported": sh.unsupported,
                            "hasLanguagesTab": LANGUAGES_TAB in sh.wb.sheetnames, "unsavedFromLastTime": entries}
        return out

    def _need_sheet(self):
        if not self.sheet:
            raise ValueError("Open a translation sheet first")
        return self.sheet

    # ---- analysis -----------------------------------------------------------------------------------------
    def scan(self):
        """Re-reads the project (constants + hard-coded strings + usage). The project is never written."""
        if not self.project:
            return []
        self.project = Project(self.project.root, self.overrides)
        english_index = {}
        for key, text in self.project.english().items():
            english_index.setdefault(text, key)
            english_index.setdefault(norm(text), key)
        if self.sheet:
            for key, row in self.sheet.rows.items():
                if row["english"]:
                    english_index.setdefault(row["english"], key)
                    english_index.setdefault(norm(row["english"]), key)
        taken = set(self.project.key_of_token().values()) | set(self.sheet.rows if self.sheet else ())
        self._hardcoded = scan_hardcoded(self.project.root, self.project.constants_files, english_index, taken)
        cls = self.project.tokens["class"] if self.project.tokens else "TrTokens"
        self._usage = token_usage(self.project.root, cls, self.project.constants_files)
        return self._hardcoded

    def report(self):
        if self.project and self._hardcoded is None:
            self.scan()
        return build_report(self.project, self.sheet, self._hardcoded, self._usage)

    def hardcoded(self):
        if self.project and self._hardcoded is None:
            self.scan()
        return self._hardcoded or []

    def keys(self, query="", status=None, language=None, offset=0, limit=200):
        """Rows for the keys table: every key in the app or the sheet, with where it stands."""
        p, sh = self.project, self.sheet
        tokens = {e["key"]: e for e in (p.tokens["entries"] if p and p.tokens else [])}
        app_en = p.english() if p else {}
        rows = sh.rows if sh else {}
        usage = self._usage or {}
        langs = [l["column"] for l in (sh.languages() if sh else [])]
        order = list(tokens) + [k for k in rows if k not in tokens]
        q = (query or "").strip().lower()
        out = []
        for key in order:
            t, r = tokens.get(key), rows.get(key)
            st = []
            if p and p.tokens and t and not r and sh:
                st.append("missing_in_sheet")
            if r and p and p.tokens and not t:
                st.append("missing_in_app")
            if t and r and key in app_en and norm(app_en[key]) != norm(r["english"]):
                st.append("english_mismatch")
            if t and self._usage is not None and not usage.get(t["token"]):
                st.append("unused")
            problems = []
            if r:
                for col in langs:
                    for kind, sev, msg in check_translation(r["english"], r["values"].get(col, "")):
                        if sev != "info":
                            problems.append({"language": col, "kind": kind, "severity": sev, "message": msg})
            if problems:
                st.append("problem")
            missing_langs = [c for c in langs if r and not r["values"].get(c)]
            if r and missing_langs:
                st.append("untranslated")
            if status and status not in st:
                continue
            if language and r and r["values"].get(language):
                continue
            text = " ".join([key, t["token"] if t else "", app_en.get(key, ""), r["english"] if r else "",
                             " ".join(r["values"].values()) if r else ""]).lower()
            if q and q not in text:
                continue
            out.append({"key": key, "token": t["token"] if t else None, "section": t["section"] if t else None,
                        "subsection": t["subsection"] if t else None, "comment": t["comment"] if t else "",
                        "appEnglish": app_en.get(key), "sheetEnglish": r["english"] if r else None,
                        "where": f"{r['tab']}!{r['row']}" if r else None,
                        "translations": r["values"] if r else {}, "missingLanguages": missing_langs,
                        "status": st, "problems": problems, "uses": usage.get(t["token"], 0) if t else 0})
        return {"total": len(out), "rows": out[offset:offset + limit]}

    # ---- edits (journaled, undoable) ---------------------------------------------------------------------
    @_journaled
    def set_cells(self, items):
        """[{key, column, text}] -> {changed, problems}. Writes the sheet in memory (save to keep)."""
        sh = self._need_sheet()
        changes, problems = [], []
        for it in items:
            old = sh.set_cell(it["key"], it["column"], it.get("text") or "")
            if old != (it.get("text") or ""):
                changes.append(("cell", it["key"], it["column"], old))
            col = it["column"]
            if col.lower() != ENGLISH_HEADER and col in sh.columns:
                for kind, sev, msg in check_translation(sh.rows[it["key"]]["english"], it.get("text") or ""):
                    problems.append({"key": it["key"], "language": col, "kind": kind, "severity": sev, "message": msg})
        if changes:
            self._undo.append(("set", changes))
        return {"changed": len(changes), "problems": problems}

    @_journaled
    def add_rows(self, items):
        """[{key, english, tab?, meta?}] -> {added: [keys], skipped: [{key, reason}]}"""
        sh = self._need_sheet()
        added, skipped, changes = [], [], []
        for it in items:
            try:
                sh.add_row(it["key"], it["english"], it.get("tab"), it.get("meta"))
                added.append(it["key"])
                changes.append(("row", it["key"]))
            except ValueError as e:
                skipped.append({"key": it["key"], "reason": str(e)})
        if changes:
            self._undo.append(("add", changes))
        self._hardcoded = None
        return {"added": added, "skipped": skipped}

    @_journaled
    def add_language(self, column, code=None, name=None, country=None):
        """A new language column (+ its Languages tab row when a code is given)."""
        sh = self._need_sheet()
        before = sh.languages_rows()
        changed = sh.add_language_column(column)
        if code:
            rows = before if before is not None else [
                {"column": l["column"], "code": l["code"], "name": l["name"], "country": l["country"],
                 "status": l["status"]} for l in sh.languages() if l["code"] and l["column"] != norm(column)]
            rows = [r for r in rows if norm(r["column"]) != norm(column)] + [
                {"column": norm(column), "code": code, "name": name or code, "country": country or "", "status": "active"}]
            sh.write_languages(rows)
        self._undo.append(("language", [("column", norm(column), before)]))
        return {"tabs": changed, "languages": sh.languages()}

    @_journaled
    def set_languages(self, rows):
        """Writes the Languages tab: [{column, code, name, country, status}]."""
        sh = self._need_sheet()
        for r in rows:
            if r.get("code") and not CODE_RE.match(r["code"][:2].lower() + r["code"][2:]):
                raise ValueError(f"{r['code']!r} doesn't look like a language code (e.g. ko, zh-TW, vi-south)")
        before = sh.languages_rows()
        sh.write_languages(rows)
        self._undo.append(("languages", [("tab", None, before)]))
        return {"languages": sh.languages()}

    @_journaled
    def undo(self):
        sh = self._need_sheet()
        if not self._undo:
            return {"undone": None, "undo": 0}
        label, changes = self._undo.pop()
        for ch in reversed(changes):
            if ch[0] == "cell":
                sh.set_cell(ch[1], ch[2], ch[3])
            elif ch[0] == "row":
                sh.remove_row(ch[1])
            elif ch[0] == "column":
                sh.remove_language_column(ch[1])
                if ch[2] is not None:
                    sh.write_languages(ch[2])
            elif ch[0] == "tab":
                if ch[2] is None:
                    if LANGUAGES_TAB in sh.wb.sheetnames:
                        del sh.wb[LANGUAGES_TAB]
                    sh._read_languages()
                else:
                    sh.write_languages(ch[2])
        self._hardcoded = None
        return {"undone": label, "undo": len(self._undo)}

    def save(self, force=False):
        sh = self._need_sheet()
        bk = sh.save(force=force)
        jp = journal_path(sh.path)
        if jp.exists():
            jp.unlink()
        return {"saved": True, "backup": bk}

    # ---- recovery journal ----------------------------------------------------------------------------------
    def _journal(self, op, args, kwargs):
        if not self.journaling or not self.sheet or op not in JOURNALED:
            return
        jp = journal_path(self.sheet.path)
        new = not jp.exists()
        with open(jp, "a", encoding="utf-8") as f:
            if new:
                f.write(json.dumps({"journal": 1, "sheet": self.sheet.path.name, "started": now_iso()}) + "\n")
            f.write(json.dumps({"at": now_iso(), "op": op, "args": list(args), "kwargs": kwargs},
                               ensure_ascii=False) + "\n")
            f.flush()
            os.fsync(f.fileno())

    def recover(self):
        done, failed = 0, []
        for f in self._pending_files():
            for line in f.read_text("utf-8").splitlines():
                try:
                    e = json.loads(line)
                except ValueError:
                    continue
                if e.get("op") in JOURNALED:
                    try:
                        getattr(self, e["op"])(*e.get("args", []), **e.get("kwargs", {}))
                        done += 1
                    except Exception as x:  # keep going: one bad entry must not lose the rest
                        failed.append(f"{e['op']}: {x}")
            f.unlink()
        return {"recovered": done, "failed": failed}

    def discard_unsaved(self):
        files = self._pending_files()
        for f in files:
            folder = f.parent / "backups"
            folder.mkdir(exist_ok=True)
            os.replace(f, folder / ("discarded-" + f.name))
        return {"discarded": len(files)}

    # ---- exports (never into the project) -----------------------------------------------------------------
    def export_dart(self, out_dir, add_keys=None, update_english=None, sections=None):
        """Writes trc_constant_tokens.dart / default_english_tr.dart / app_language_constants.dart to out_dir
        (project-relative paths), merged with the project's files. add_keys: sheet keys to add to the app
        (with their sheet English); update_english: keys whose app English becomes the sheet's; sections:
        {key: section}. -> [{kind, project, export, created, added, updated, identical, diff}]"""
        p, sh = self.project, self.sheet
        if not p:
            raise ValueError("Pick the Flutter project first")
        out = Path(out_dir)
        if p.root.resolve() == out.resolve() or (p.root / "lib").resolve() in [out.resolve(), *out.resolve().parents]:
            raise ValueError("The export folder can't be inside the project's lib/ - the project is never written")
        add_keys, update_english, sections = add_keys or [], update_english or [], sections or {}
        rows = sh.rows if sh else {}
        cls = p.tokens["class"] if p.tokens else "TrTokens"
        existing_names = {e["token"] for e in (p.tokens or {}).get("entries", [])}
        existing_keys = set(p.key_of_token().values())
        new_entries, problems = [], []
        for key in dict.fromkeys(add_keys):
            if key in existing_keys:
                continue
            row = rows.get(key)
            if row is None or not row["english"]:
                problems.append(f"{key}: not in the sheet with an English text - add it to the sheet first")
                continue
            if not KEY_RE.match(key):
                problems.append(f"{key}: isn't lower_snake_case - rename it in the sheet first")
                continue
            name, n = camel_case(key), 2
            while name in existing_names:
                name, n = f"{camel_case(key)}{n}", n + 1
            existing_names.add(name)
            ph = placeholders(row["english"])
            new_entries.append({"token": name, "key": key, "english": row["english"],
                                "section": sections.get(key) or NEW_SECTION,
                                "comment": " ".join("{" + x + "}" for x in ph)})
        token_of = {v: k for k, v in p.key_of_token().items()}
        app_en = p.english()
        english_updates = {}
        for k in update_english:
            if k not in token_of or k not in rows or not rows[k]["english"]:
                continue
            if placeholders(app_en.get(k, "")) != placeholders(rows[k]["english"]):
                problems.append(f"{k}: not updated - the app's English has "
                                f"{' '.join('{' + x + '}' for x in placeholders(app_en.get(k, ''))) or 'no placeholders'}, "
                                f"the sheet's {' '.join('{' + x + '}' for x in placeholders(rows[k]['english'])) or 'none'}; "
                                "the code fills those in, so fix the sheet's English first")
                continue
            english_updates[token_of[k]] = rows[k]["english"]
        results = []

        def emit(kind, project_path: Path | None, default_rel, text, added, updated):
            rel = project_path.relative_to(p.root) if project_path else Path(default_rel)
            dest = out / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            old = project_path.read_text("utf-8") if project_path and project_path.exists() else ""
            dest.write_text(text, encoding="utf-8")
            results.append({"kind": kind, "project": str(project_path or p.root / rel), "export": str(dest),
                            "relative": rel.as_posix(), "created": project_path is None, "added": added,
                            "updated": updated, "identical": old == text,
                            "diff": unified_diff(old, text, rel.as_posix())})

        consts = Path("lib/core/constants")
        if p.tokens:
            emit("tokens", p.files["tokens"], None, merge_tokens(p.tokens, new_entries), len(new_entries), 0)
        else:
            emit("tokens", None, consts / "trc_constant_tokens.dart", new_tokens_file(new_entries, cls),
                 len(new_entries), 0)
        tokens_rel = (p.files["tokens"].relative_to(p.root) if p.files["tokens"] else consts / "trc_constant_tokens.dart")
        if p.defaults:
            emit("defaults", p.files["defaults"], None,
                 merge_defaults(p.defaults, cls, new_entries, english_updates), len(new_entries), len(english_updates))
        else:
            dflt_rel = tokens_rel.parent / "default_english_tr.dart"
            imp = os.path.relpath(tokens_rel, dflt_rel.parent).replace(os.sep, "/")
            emit("defaults", None, dflt_rel, new_defaults_file(new_entries, imp, cls), len(new_entries), 0)
        if sh:
            langs = sh.languages()
            if any(l["code"] is None for l in langs):
                problems.append("some language columns have no code - the registry skips them")
            text = registry_text(p.registry, langs)
            have = {x["code"] for x in p.registry["languages"]} if p.registry else set()
            rejected = {r.lower() for r in p.registry["rejected"]} if p.registry else set()
            emit("languages", p.files["languages"], tokens_rel.parent / "app_language_constants.dart", text,
                 sum(1 for l in langs if l.get("code") and l["status"] != "deprecated" and l["code"] not in have
                     and l["code"].lower() not in rejected), 0)
        manifest = {"exportedAt": now_iso(), "project": str(p.root), "files": [
            {k: r[k] for k in ("kind", "relative", "created", "added", "updated", "identical")} for r in results],
            "problems": problems}
        (out / "export.json").write_text(json.dumps(manifest, indent=1, ensure_ascii=False), encoding="utf-8")
        return {"files": results, "problems": problems, "out": str(out)}

    def apply_export(self, out_dir, kinds=None):
        """Copies exported constants files into the project (only those three files; a backup of each first,
        under out_dir/project-backups/<time>/). The Studio calls this only when you turned it on and confirmed."""
        p = self.project
        if not p:
            raise ValueError("Pick the Flutter project first")
        out = Path(out_dir)
        man = json.loads((out / "export.json").read_text("utf-8"))
        stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
        done = []
        for f in man["files"]:
            if kinds and f["kind"] not in kinds:
                continue
            if f["kind"] not in ("tokens", "defaults", "languages"):
                continue
            src, dest = out / f["relative"], p.root / f["relative"]
            if not str(dest.resolve()).startswith(str((p.root / "lib").resolve())):
                raise ValueError(f"{f['relative']} isn't under lib/ - refusing to write it")
            if dest.exists():
                bk = out / "project-backups" / stamp / f["relative"]
                bk.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(dest, bk)
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dest)
            done.append(f["relative"])
        self.project = Project(p.root, self.overrides)
        self._hardcoded = None
        return {"written": done, "backups": str(out / "project-backups" / stamp)}

    def build_packs(self, out_dir, strict=False, only=None):
        """lang_<code>.zip per language (non-empty translations, sorted, reproducible) + report.json.
        strict: a language with errors (placeholders, %s) isn't written."""
        sh = self._need_sheet()
        out = Path(out_dir)
        out.mkdir(parents=True, exist_ok=True)
        langs = sh.languages()
        bad = [l["column"] for l in langs if l["code"] is None]
        if bad:
            raise ValueError("No language code for " + ", ".join(bad) + " - add them to the Languages tab, or write "
                             "the code in brackets ('Korean (ko)'). Nothing written.")
        prev = {}
        if (out / "report.json").exists():
            try:
                prev = {x["code"]: x.get("sha256") for x in json.loads((out / "report.json").read_text("utf-8"))["packs"]}
            except (ValueError, KeyError):
                prev = {}
        packs, skipped = [], []
        for l in langs:
            if l["status"] == "deprecated" or l["code"] == "en":
                skipped.append({"code": l["code"], "column": l["column"], "reason": l["status"] if l["status"] == "deprecated"
                                else "English ships inside the app"})
                continue
            if only and l["code"] not in only:
                continue
            data, errors = {}, []
            for key, row in sh.rows.items():
                text = row["values"].get(l["column"], "")
                if not text or not row["english"]:
                    continue
                errs = [m for k, sev, m in check_translation(row["english"], text) if sev == "error"]
                if errs:
                    errors.append({"key": key, "problems": errs})
                data[key] = text
            if strict and errors:
                skipped.append({"code": l["code"], "column": l["column"],
                                "reason": f"{len(errors)} key(s) with errors (strict)", "errors": errors[:50]})
                continue
            if not data:
                skipped.append({"code": l["code"], "column": l["column"], "reason": "nothing translated"})
                continue
            payload = json.dumps(data, ensure_ascii=False, indent=1, sort_keys=True).encode("utf-8")
            zp = out / f"lang_{l['code']}.zip"
            write_zip(zp, payload)
            digest = sha256(zp)
            packs.append({"code": l["code"], "column": l["column"], "file": zp.name, "keys": len(data),
                          "bytes": zp.stat().st_size, "sha256": digest, "changed": prev.get(l["code"]) != digest,
                          "errors": len(errors), "errorSamples": errors[:20]})
        if self.project or sh:
            reg = registry_text(self.project.registry if self.project else None, langs)
            (out / "app_language_constants.dart").write_text(reg, encoding="utf-8")
        report = {"builtAt": now_iso(), "sheet": str(sh.path), "packs": packs, "skipped": skipped,
                  "totalKeys": len(sh.rows)}
        (out / "report.json").write_text(json.dumps(report, indent=1, ensure_ascii=False), encoding="utf-8")
        return report


# ── serve: JSON lines over stdin/stdout ───────────────────────────────────────────────────────────────────────

def serve(stdin=None, stdout=None):
    stdin, stdout = stdin or sys.stdin, stdout or sys.stdout

    def send(obj):
        stdout.write(json.dumps(obj, ensure_ascii=False, default=str) + "\n")
        stdout.flush()

    eng = Engine(log=lambda m: send({"event": "log", "message": str(m)}))
    cmds = {
        "ping": lambda a: {"pong": True, "version": 1},
        "open": lambda a: eng.open(a.get("project"), a.get("sheet"), a.get("overrides")),
        "summary": lambda a: eng.summary(),
        "scan": lambda a: {"hardcoded": len(eng.scan())},
        "report": lambda a: eng.report(),
        "keys": lambda a: eng.keys(a.get("query", ""), a.get("status"), a.get("language"), a.get("offset", 0),
                                   a.get("limit", 200)),
        "hardcoded": lambda a: eng.hardcoded(),
        "set": lambda a: eng.set_cells(a["items"]),
        "addRows": lambda a: eng.add_rows(a["items"]),
        "addLanguage": lambda a: eng.add_language(a["column"], a.get("code"), a.get("name"), a.get("country")),
        "setLanguages": lambda a: eng.set_languages(a["rows"]),
        "undo": lambda a: eng.undo(),
        "save": lambda a: eng.save(a.get("force", False)),
        "recover": lambda a: eng.recover(),
        "discardUnsaved": lambda a: eng.discard_unsaved(),
        "exportDart": lambda a: eng.export_dart(a["out"], a.get("addKeys"), a.get("updateEnglish"), a.get("sections")),
        "applyExport": lambda a: eng.apply_export(a["out"], a.get("kinds")),
        "buildPacks": lambda a: eng.build_packs(a["out"], a.get("strict", False), a.get("only")),
    }
    send({"event": "ready", "version": 1, "engine": "translations"})
    for line in stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except ValueError:
            send({"ok": False, "error": "bad JSON"})
            continue
        rid, cmd = req.get("id"), req.get("cmd")
        try:
            if cmd not in cmds:
                raise ValueError(f"unknown command {cmd}")
            send({"id": rid, "ok": True, "result": cmds[cmd](req.get("args") or {})})
        except Exception as e:  # reported to the app, the engine keeps running
            send({"id": rid, "ok": False, "error": f"{type(e).__name__}: {e}" if not isinstance(e, (ValueError, RuntimeError)) else str(e)})


# ── command line ──────────────────────────────────────────────────────────────────────────────────────────────

def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if argv and argv[0] == "serve":
        return serve()
    ap = argparse.ArgumentParser(description="Translations for a Flutter app (read-only on the project)")
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("check", "export", "packs"):
        p = sub.add_parser(name)
        p.add_argument("--project", required=name == "export")
        p.add_argument("--sheet", required=name == "packs")
        if name in ("export", "packs"):
            p.add_argument("--out", required=True)
        if name == "packs":
            p.add_argument("--strict", action="store_true")
            p.add_argument("--only", action="append")
        if name == "export":
            p.add_argument("--add-sheet-keys", action="store_true", help="add every sheet key the app lacks")
    a = ap.parse_args(argv)
    eng = Engine(source="cli")
    eng.journaling = False
    eng.open(a.project, a.sheet)
    if a.cmd == "check":
        rep = eng.report()
        for c in rep["coverage"]:
            print(f"  {c['column']:<32} {c['code'] or '?':<9} {c['percent']:>5}%  ({c['translated']}/{c['total']})")
        by = {}
        for i in rep["issues"]:
            by.setdefault((i["severity"], i["kind"]), []).append(i)
        for (sev, kind), items in sorted(by.items()):
            print(f"{sev:<8} {kind:<22} {len(items)}")
            for i in items[:5]:
                print(f"           {i.get('key') or i.get('language') or ''}: {i['message']}"
                      + (f"  [{i['where']}]" if i.get("where") else ""))
        return 1 if rep["counts"].get("error") else 0
    if a.cmd == "export":
        keys = [k for k in (eng.sheet.rows if eng.sheet else {}) if k not in set(eng.project.key_of_token().values())] \
            if a.add_sheet_keys else []
        res = eng.export_dart(a.out, keys)
        for f in res["files"]:
            print(f"  {f['relative']}: {'new' if f['created'] else 'merged'}, +{f['added']} keys, "
                  f"{f['updated']} English updated{' (unchanged)' if f['identical'] else ''}")
        for pr in res["problems"]:
            print("  !", pr)
        print(f"Written to {res['out']} - the project wasn't touched.")
        return 0
    rep = eng.build_packs(a.out, a.strict, a.only)
    for pk in rep["packs"]:
        print(f"  {pk['file']:<22} {pk['keys']:>5} keys  {'changed' if pk['changed'] else 'unchanged'}"
              + (f"  ({pk['errors']} with errors)" if pk["errors"] else ""))
    for sk in rep["skipped"]:
        print(f"  skipped {sk['column']} ({sk['code']}): {sk['reason']}")
    return 0


if __name__ == "__main__":
    sys.exit(main() or 0)
