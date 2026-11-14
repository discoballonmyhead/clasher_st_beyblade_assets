# Clasher Studio (Flutter desktop)

One desktop app for the data behind clasher_st and for any app's translations. Windows, macOS and Linux.

Sections (left rail; each keeps its state while you're in another):

* **Data**: the missing data tool, by hobby (Beyblade, Beyblade TCG, and any you add) and generation, with every
  workbook you open as a tab. See *What the Data section does* below.
* **Translations**: the strings of any Flutter app and their translation sheet. See *Translations* below.
* **Publish**: everything that leaves the Studio. The data release (package -> commit + push -> release files ->
  GitHub release, in the data repo), the language packs (the translations repo's release), what the packager writes
  per JSON sheet, and the releases so far. See *Publish* below.
* **Scrapers**: the wiki scraper per hobby and generation: run targets with a live log and a safe stop, edit each
  target's settings and the generation's own scraper code. See *Scrapers* below.
* **Settings**: Python and the tools folder, the publishing names (repos, branch, release tags) and a settings backup
  file.

Closing the window with unsaved work in any section asks first (Save / Don't save / Cancel) and lists what's
unsaved. Every edit is also written to a recovery file next to its workbook, so even a crash loses nothing: the next
open offers it back.

## How it works

Flutter can't run Python code itself. This app starts `missing_data_tool.py serve` (data), `translation_tool.py serve`
(translations) and `studio_tool.py serve` (hobbies, packaging profiles, publishing, scrapers) when they're first needed
and keeps them running, each in its own process. Each open workbook gets its own data engine, which holds it in memory
(with its own recovery file), so switching tabs never reloads or loses anything. The app sends JSON lines over
stdin/stdout; long steps (packaging, git, releases, scraping) run as background jobs whose output streams into the
page's log and that can be stopped. If an engine stops (crash, killed), the next call starts it again. Only
`lib/core/bridge/engine_bridge.dart` and the data source know Python is involved. When the data moves to your admin
app's backend (Supabase, an API ...), you write a new `MissingDataRepository` implementation and register it in
`service_locator.dart`. The domain, the cubits and the UI stay as they are.

```
UI (pages/widgets) -> cubits -> use cases -> MissingDataRepository (domain interface)
                                                 |
                                MissingDataRepositoryImpl -> EngineDataSource -> EngineBridge -> python missing_data_tool.py serve
```

## Run

You need Flutter 3.x with desktop support, and Python 3 with the packages in `../requirements.txt`
(`pip install -r requirements.txt`).

```bash
cd clasher_st_missing_data
flutter pub get
flutter run -d windows      # or -d macos / -d linux
```

On first start, open **Settings** (left rail) and check:
* **Python**: the interpreter that has openpyxl and Pillow installed (`python`, `python3`, or a full path such as
  `C:\Python312\python.exe`).
* **Tools folder**: the folder that holds `missing_data_tool.py` (this repo). The app guesses it by looking in
  parent folders.

**Save and test** starts both engines and pings them. Under **Publishing**, set the names that stay the same
from release to release: GitHub owner, data repo and branch, the catalog release tag format, the image packs tag,
the translations repo and its release tag. They're kept with your user settings; **Export settings** writes them (and
everything else) to a JSON file you can keep or import on another computer.

## What the Data section does

* **Hobby and generation** (bar above the tabs): pick a hobby, then **All** or one generation; the tab list shows
  that generation's tabs (and shared tabs that have its rows). New columns can be added to just that generation's
  tabs. **Edit hobbies** (Data home page) adds hobbies (Yu-Gi-Oh!, Pokemon ... ) with their generations (series, or
  years for card games) and workbook files; Beyblade and Beyblade TCG are the ones the packager and scraper know.
* **Workbook tabs**: every workbook you open stays open as a tab (the hobby's other workbooks are one click away).
  A dot marks unsaved changes; closing a changed one asks to save first. Each keeps its own undo and recovery file.
* **Tabs**: shows the number of rows with gaps in each tab.
* **Missing per field**: shows how many rows miss each field. Click a field to list only those rows. **optional**
  also shows the optional columns.
* **Rows**: search with Ctrl+F. Sort by sheet order, most gaps, or **last edited**. Every edit stamps `updated_at`,
  which you can see in the *last edited* column. Tick rows for Fill from wiki.
* **Editor**: blank fields are highlighted. Press Enter in a field to apply. **Next gap** (Ctrl+Enter) jumps to the
  next row that still misses something. The image can come from a file, a URL or the parent row; it's trimmed, fitted in 600 px with a
  128 px minified copy, and stored as WebP.
* **More pictures and 3D models**: a tab with a second kind of picture (Bladers' full-body picture) gets a second
  picture box in the editor (optional, not counted as missing). The `model3d` field has a cube button that picks a
  `.glb` file and stores it relative to the workbook's folder.
* **Auto-fill** lets you preview each proposal, filter by source (derived, parent, same name) and tick what to apply.
* **Fill from wiki** runs the scraper's polite client on the ticked rows. Progress shows in the log panel and you
  can stop it.
* **Recently edited** lists the latest edits across all tabs.
* **New row** (rows panel) adds a row with the next free id and asks for its name. In the editor, **Duplicate as
  variant** creates a recolor of the open row (shared fields copied, parent id set), and **Copy row** copies every
  field. The new row opens in the editor.
* **Add column** (top bar) adds a field to this tab or to every tab. Choose whether variants copy it from their parent
  and whether it's optional. New columns are marked `+` in the field list and in the editor.
* **Change log** lists everything changed with the tool (this app, the Python GUI or the CLI): when, which tool, tab,
  row, field, and old → new. Search it, limit it to the open tab, and tap an entry to jump to its row. It's kept in the
  workbook's `_edit_log` tab, and the packager exports it.
* **Undo** (Ctrl+Z) undoes edits, auto-fills, images, new rows and new columns (and their change-log entries). **Save** (Ctrl+S) writes the workbook and keeps
  a `.bak` copy. Closing with unsaved changes asks first.

## Translations

Add an app (the **+** at the top): its Flutter project folder, its translation sheet (.xlsx) and an export folder.
You can add as many apps as you like and switch between them.

**The project is only read.** The Studio reads `lib/`: the `TrTokens` class, `defaultEnglishTranslations`, the
`LanguageRegistry` and every string still written in the code. It never edits your code. Generated Dart goes to the
export folder, with a diff against the project's file. An app's settings can turn on **Copy into the project**, which
copies only the three constants files after you confirm, each backed up first.

**What it writes:** the sheet (on **Save sheet**, Ctrl+S) and the export folder. Before every save it keeps a dated
copy in `backups/` next to the sheet. It refuses to save if the file changed on disk since it was opened (Excel or
another tool saved it), and offers to reopen or to overwrite. It also warns while Excel or LibreOffice has the sheet
open (their lock file).

Tabs:
* **Overview**: keys in the app, the sheet and both; errors and warnings; coverage per language; the files found.
* **Keys**: every key from the app or the sheet. Filter by *not in the sheet*, *not in the app*, *English differs*,
  *untranslated*, *problems*, *unused in code*, or *missing in a language*. The editor shows the app's and the
  sheet's English and every translation. Placeholders (`{name}`) and `%s` counts are checked while you type, and
  each status has its fix: add the key to the sheet, add it to the app on the next export, copy the app's English
  to the sheet, or use the sheet's English in the app. That last fix is refused when the placeholders differ,
  because the code fills them in.
* **In the code**: strings written in the code (`Text('...')`, `hintText:`, `tooltip:` ...), one row per text with
  where it's used. Each gets a suggested key from its context (`_hint`, `_label`, `_txt` ...), or the existing key
  when the sheet already has that English. Pick some and add them to the sheet and the app. Copy `TrTokens.x` to use
  in place of the text.
* **Languages**: the code each column is published under (`lang_<code>.zip`), its native name and flag, and whether
  it's published or removed. Saved to the sheet's **Languages** tab. Changing a code asks first, because it orphans
  packs people already downloaded. **Add a language** adds the column.
* **Issues**: everything, by severity and kind; tap one to open its key.
* **Export & packs**: the app constants (your files plus what's pending, nothing removed or reordered) and the
  language packs. Packs are deterministic (the same sheet gives the same zip); unchanged ones are marked so you only
  upload what changed. There's an optional strict mode, and the `gh release upload` command is filled in from
  Settings → Publishing.

The engine is `translation_tool.py` (repo root). It isn't tied to Beyblade and also runs on its own:
`translation_tool.py check|export|packs --project APP --sheet sheet.xlsx [--out dist]`.

## Publish

Names (owner, repos, branch, tag format) come from Settings -> Publishing. Every step that leaves your computer (git
push, creating or uploading to a release) shows exactly what it will do and waits for you to confirm.

**Data release** (the data repo), each step can be run on its own:
1. **Package**: the ticked workbooks -> `data/` (JSON per sheet + WebP images), checked against what the app accepts.
   Rows the app would reject are listed.
2. **Commit and push data/**: only `data/` is staged. If git doesn't know your name/email yet, the page asks for them
   and saves them for that repository only. A failed commit is unstaged again, and the error says why.
3. **Build the release files**: `catalog.zip`, `catalog_manifest.json` and the packs in `_release/<tag>/`; optionally
   leave out the rows the app can't read instead of stopping.
4. **Create the GitHub release** with `gh` (sign in once with `gh auth login`). Existing files with the same names
   are replaced. The page then shows the values for the Supabase manifest function, ready to copy.

**Translations release** (the translations repo): build the language packs from the Translations section's sheet
(strict mode leaves out packs with broken placeholders) and upload the ones that changed. Uploaded packs are marked
and aren't offered again until you build again.

**Packaging**: per JSON sheet, which columns go into the JSON and how critical each is: *required* (an empty cell
blocks the release), *recommended* (counted as missing in Data) or *optional* (never counted). Ids, images and the
fields the app reads as required are locked. Saved to `packaging_profiles.json`; the packager, the release check and
the Data section all follow it.

**History**: the releases on both repos and their files (refreshes each time you open it).

## Scrapers

* **Run**: pick a hobby and generation, tick targets (parts per type, products, cards) and run. Options: pages per
  target, request budget, delay, skip images, overwrite filled cells (asks first), relist, refetch, list only. The
  log is live; **Stop** finishes the current step and saves, and running again continues.
* **Target settings**: the wiki categories, title prefixes, exclusions, aliases and extra pages of a target, as JSON.
  Invalid JSON can't be saved; the previous file is kept in `scrapers/backups/`.
* **Code**: `scrapers/<hobby>/<generation>.py` with `adjust_row(target, title, fields, row)`, which runs after the
  built-in mapping for every page of that hobby and generation. Saving checks the syntax first (the error line is
  highlighted) and keeps the previous version; a file that fails to load is skipped by the scraper, so a mistake
  can't stop a run. **Scraper source (advanced)** opens `fandom_scraper.py` itself.
* **Scraper settings**: the user agent (put a way to contact you in it) and how polite the scraper is.

## Structure (clean architecture + service locator)

```
lib/
  main.dart                     initDependencies() then runApp
  app.dart                      MaterialApp.router + app-wide cubits
  core/
    bridge/engine_bridge.dart   Python process, JSON-line RPC (writes are queued)
    bridge/engine_pool.dart     one data engine per open workbook
    di/service_locator.dart     get_it: `sl` registers settings, bridge, data source, repository, use cases, cubits
    error/failure.dart          Failure + Result (Ok / Err)
    router/app_router.dart      go_router shell with one branch per section: / and /workbook, /translations, /settings
    router/studio_shell.dart    the left rail + the one "save before closing?" prompt for every section
    services/                   DataChangeNotifier (cubits tell each other what changed), file picker,
                                UnsavedWork (what the close prompt asks about)
    settings/app_settings.dart  shared_preferences: python, tools folder, recent workbooks, sort
    theme/app_theme.dart
  features/
    missing_data/
      domain/                   entities, repository interface, use cases (no Flutter imports)
      data/                     engine data source, JSON mappers, repository impl
      presentation/             cubits (workbook, sheet, row_editor, autofill, wiki), pages, widgets
    settings/                   settings cubit + page (engine, publishing names, backup)
    translations/               domain / data / presentation for the Translations section
    studio/                     studio_tool.py: workspace (hobbies), profiles, tools/git status, jobs (JobCenter)
    publish/                    the Publish section: data release, translations release, packaging, history
    scrapers/                   the Scrapers section and its code editor
test/
  core/engine_integration_test.dart   against the real Python engine (copy of samples/beyblade_parts.xlsx)
  core/translation_engine_test.dart   translation_tool.py on a throwaway app + sheet; the project must stay byte-identical
  core/engine_bridge_test.dart        engines started by several callers at once share one process
  features/                           bloc_test cubit tests + widget flows on fake repositories: open -> edit -> save,
                                      workbook tabs and hobbies, every Publish step (confirmations, failures, git
                                      identity), packaging profiles, scrapers (run, JSON settings, code check/save)
```

Run the tests with `flutter test`. The integration test uses `python3`, or the interpreter in `MDT_PYTHON`, and is
skipped when the tools folder isn't next to the app.

## Moving it into the admin app

1. Copy `lib/features/missing_data` (and `settings` if you keep the Python engine) into the admin app's
   `lib/features/`.
2. Merge the registrations from `core/di/service_locator.dart` into the admin app's locator, and add the routes
   from `app_router.dart`.
3. To drop Python, implement `MissingDataRepository` on top of your backend and register that one instead.
