# Missing data tool (Flutter desktop)

A Flutter version of `missing_data_tool.py` for Windows, macOS and Linux. It works on the same three workbooks
(`beyblade_parts.xlsx`, `beyblade_products.xlsx`, `beyblade_tcg.xlsx`).

## How it works

Flutter can't run Python code itself. This app starts `missing_data_tool.py serve` once and keeps it running. The
engine holds the workbook in memory, and the app sends it JSON lines over stdin/stdout. Only
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
cd missing_data_app
flutter pub get
flutter run -d windows      # or -d macos / -d linux
```

On first start, open **Settings** (gear icon) and check:
* **Python**: the interpreter that has openpyxl and Pillow installed (`python`, `python3`, or a full path such as
  `C:\Python312\python.exe`).
* **Tools folder**: the folder that holds `missing_data_tool.py` (this repo). The app guesses it by looking in
  parent folders.

**Save & test** starts the engine and pings it.

## What it does

* **Tabs**: shows the number of rows with gaps in each tab.
* **Missing per field**: shows how many rows miss each field. Click a field to list only those rows. **optional**
  also shows the optional columns.
* **Rows**: search with Ctrl+F. Sort by sheet order, most gaps, or **last edited**. Every edit stamps `updated_at`,
  which you can see in the *last edited* column. Tick rows for Fill from wiki.
* **Editor**: blank fields are highlighted. Press Enter in a field to apply. **Next gap** (Ctrl+Enter) jumps to the
  next row that still misses something. The image can come from a file, a URL or the parent row; it's trimmed, fitted in 600 px with a
  128 px minified copy, and stored as WebP.
* **Auto-fill** lets you preview each proposal, filter by source (derived, parent, same name) and tick what to apply.
* **Fill from wiki** runs the scraper's polite client on the ticked rows. Progress shows in the log panel and you
  can stop it.
* **Recently edited** lists the latest edits across all tabs.
* **New schema columns:** when a workbook opens without a column the schema now defines (e.g. `simpleRatchet` /
  `requiresSimpleRatchet`), it's added, empty, and a message says so. Save to keep it. Flag columns accept 1/0,
  yes/no or true/false.
* **New row** (rows panel) adds a row with the next free id and asks for its name. In the editor, **Duplicate as
  variant** creates a recolor of the open row (shared fields copied, parent id set), and **Copy row** copies every
  field. The new row opens in the editor.
* **Add column** (top bar) adds a field to this tab or to every tab. Choose whether variants copy it from their parent
  and whether it's optional. New columns are marked `+` in the field list and in the editor.
* **Change log** lists everything changed with the tool (this app, the Python GUI or the CLI): when, which tool, tab,
  row, field, and old → new. Search it, limit it to the open tab, and tap an entry to jump to its row. It's kept in the
  workbook's `_edit_log` tab, and the packager exports it.
* **Delete row** (editor) or **Delete ticked** (rows panel) removes rows; the rows below move up with their pictures.
  Deleted rows go to **Recently deleted** (bin icon in the top bar): restore them (old id when it's free) or remove
  them for good.
* **Ids aren't serial:** after opening and after rows are added, deleted or restored, the app checks that each tab's
  ids run 1..N. If not, it asks: **Shift ids** (order kept; parent ids, ProductContents and TCG links follow, links
  to deleted rows are cleared) or **Not now** (asked again once the ids change). It warns when changed ids are
  already in the last package, because the clasher_st app's saved builds store them.
* **Undo** (Ctrl+Z) undoes edits, auto-fills, images, new rows and new columns, deletes, restores and id shifts (and their change-log entries). **Save** (Ctrl+S) writes the workbook and keeps
  a `.bak` copy. Closing the window (or the workbook) with unsaved changes asks Save / Don't save / Cancel.
* **Recovery:** every edit is also written at once to `<workbook>.unsaved.jsonl`, so nothing is lost if the app is
  closed without saving, crashes or the engine stops. On the next open of that workbook the app offers **Recover**,
  **Discard them** (kept in `backups/`) or **Ask me next time**. Saving removes the file.

## Structure (clean architecture + service locator)

```
lib/
  main.dart                     initDependencies() then runApp
  app.dart                      MaterialApp.router + app-wide cubits
  core/
    bridge/engine_bridge.dart   Python process, JSON-line RPC (writes are queued)
    di/service_locator.dart     get_it: `sl` registers settings, bridge, data source, repository, use cases, cubits
    error/failure.dart          Failure + Result (Ok / Err)
    router/app_router.dart      go_router: / (home), /workbook, /settings
    services/                   DataChangeNotifier (cubits tell each other what changed), file picker
    settings/app_settings.dart  shared_preferences: python, tools folder, recent workbooks, sort
    theme/app_theme.dart
  features/
    missing_data/
      domain/                   entities, repository interface, use cases (no Flutter imports)
      data/                     engine data source, JSON mappers, repository impl
      presentation/             cubits (workbook, sheet, row_editor, autofill, wiki), pages, widgets
    settings/                   settings cubit + page
test/
  core/engine_integration_test.dart   against the real Python engine (copy of samples/beyblade_parts.xlsx)
  features/                           bloc_test cubit tests + an open -> edit -> save widget flow on a fake repository
```

Run the tests with `flutter test`. The integration test uses `python3`, or the interpreter in `MDT_PYTHON`, and is
skipped when the tools folder isn't next to the app.

## Moving it into the admin app

1. Copy `lib/features/missing_data` (and `settings` if you keep the Python engine) into the admin app's
   `lib/features/`.
2. Merge the registrations from `core/di/service_locator.dart` into the admin app's locator, and add the routes
   from `app_router.dart`.
3. To drop Python, implement `MissingDataRepository` on top of your backend and register that one instead.
