# Clasher ST – Beyblade data store

Humans manage three Excel workbooks → the packager turns them into `data/*.json` + `data/images/*.webp`

**How it all fits together, what each step creates, and what goes in the app's assets: [WORKFLOW.md](WORKFLOW.md)** (with flow graphs).
(served via jsDelivr) → the scraper can fill/update the workbooks from the Beyblade Fandom wiki.

| file | what it does |
|---|---|
| `beyblade_schema.py` | the layout: generations, part types, sheets, columns, release-code series |
| `make_sample_workbooks.py` | builds the 3 workbooks (`samples/` = with example rows; `--empty DIR` = blank store) |
| `fandom_scraper.py` | polite, resumable wiki scraper that fills the workbooks |
| `beyblade_data.py` | packager: workbooks → `data/` (PNG in the sheet → WebP) |
| `build_release.py` | release builder: `data/` → `catalog.zip` + manifest, image packs and data packs per hobby/generation |
| `catalog_check.py` | the release gate: checks `data/` against what the app accepts (required sheets and fields, duplicate ids, ProductContents keys) |
| `flutter_integration/` | drop-in changes for the clasher_st app: real parts picker for ban/approve lists, lists page, optional tournament stadium, card game (TCG) – changed files + `patches/` + SQL, see its README |
| `beyblade_store.py` | shared workbook read/write helper |
| `missing_data_tool.py` | finds empty fields / images per tab and fills them (auto, from the wiki, or by hand) |
| `missing_data_app/` | Flutter desktop version of the missing data tool (get_it, go_router, cubits, clean architecture) – see its README |
| `tk_ui.py` | shared look and helpers for the Python GUIs (theme, remembered settings, background jobs, status bar) |

**Speed and convenience (all tools):** image encoding uses every CPU core (the packager went from 23.6 s to 7.4 s on
a 4-core PC for a PNG workbook, with identical output), while wiki requests stay strictly one at a time so your IP
stays safe. Each GUI does slow work in the background so the window doesn't freeze, and remembers its last paths
and options in `~/.clasher_tools.json`. Every edit stamps the row's `updated_at` (*last edited*) column.

## The three workbooks
* **beyblade_parts.xlsx** – `Parts_<Series>_<PartType>` for the four series:
  **Original** (BitChips, AttackRings, WeightDisks, SpinGears, BladeBases, RunningCores – plastic and HMS),
  **Metal** (FaceBolts, EnergyRings, FusionWheels, SpinTracks, PerformanceTips – incl. Zero-G),
  **Burst** (Layers – with `layerComponent` for chip/ring/chassis/blade/armor…, Discs, Frames, Drivers),
  **X** (Blades, Ratchets, Bits, LockChips, Main/Assist/Metal/OverBlades). `system` says which system inside the series.
  Manufacturers: Takara-Tomy and Hasbro.
* **beyblade_products.xlsx** – `Products` (every release incl. launchers, stadiums, sets, TCG packs; both
  Takara-Tomy and Hasbro), `Accessories`, `ProductContents` (product → part/accessory/card links),
  `CodeSeries` (BX, UX, CX, B, BB, BBG, ... per manufacturer; drives the update mode).
* **beyblade_tcg.xlsx** – `TCG_Sets`, `TCG_Cards` (hobby `Beyblade TCG`). Today: the V-Force TCG (`hobbyGeneration`
  `Original`; Battle Edge / Spin Strength / Game Text / Lore). The Beyblade X TCG isn't released yet.

Same ID model everywhere: `dataID` (stable, never reused) + `parent…Id` / `variantLabel` for variants
(recolors, random-booster items `BX-50 06`, foil cards ...). Each workbook has a README and a Lists sheet
(dropdown values). Open `samples/` to see how filled rows look.

## Start a store
```bash
python make_sample_workbooks.py --empty .
```

## Scrape (run on your own PC)
First run creates `scraper_config.json` – put contact info in `user_agent`. Category names / field names are
best guesses; check them per target before a full run:
```bash
python fandom_scraper.py --list-targets
python fandom_scraper.py --find-categories "ratchet"
python fandom_scraper.py --target parts:X:ratchets --list-only
python fandom_scraper.py --target parts:X:ratchets --inspect 5
```
Then:
```bash
python fandom_scraper.py --target parts:X:ratchets          # one sheet
python fandom_scraper.py --scope parts --generation X        # all X part sheets, one after another
python fandom_scraper.py --target products:X --inspect 5      # check how the product list pages are read
python fandom_scraper.py --target products:X                  # every X release (Takara Tomy + Hasbro lists)
python fandom_scraper.py --scope products --generation Burst  # another generation's product lists
python fandom_scraper.py --update                             # new releases since the last run
python fandom_scraper.py --update --series BX UX --manufacturer Takara-Tomy
python fandom_scraper.py --update --series B --from-code B-150
python fandom_scraper.py --update --no-probe                  # only re-read the list pages
python fandom_scraper.py --target tcg:Original:cards          # V-Force TCG cards (Category:Cards)
python fandom_scraper.py --next      # next unfinished target
python fandom_scraper.py --status
```
* Series detection: every part page is checked for the series it belongs to (Series / System fields, product-code
  prefix BX/UX/CX/RX → X, B → Burst, BB/BBG → Metal, A → Original, then categories). A page listed under X that is
  really Burst (e.g. `Blade - Guilty (Hasbro)`, QuadDrive) goes to that series' sheet (`Parts_Burst_Layers`,
  `layerComponent = blade`); rows an earlier run put in the wrong sheet are marked `deleted = true`. Anime / manga
  pages (episodes, chapters, volumes) are skipped everywhere.
* Parts and their variants: each part page's **Products** section lists every release the part came in
  (`CX-05 Random Booster Vol. 6 - 01: HellsReaper T4-70K`, `BX-00 Booster DranSword 3-60F (Metal Coat: Gold)`,
  Hasbro `G1678 Reaper Incendio T 4-70K`). The debut release (infobox product code) becomes the main row;
  every other release becomes a variant row with `parentPartId` = main row, its own `code` (BX/UX/CX/RX + item
  number, or the Hasbro item number), `edition`, `variantLabel` and `manufacturer`. Images come from the page
  gallery, matched by the codes in the captions (`Reaper (CX-05 02/G2746)`); recolors sharing a code (BX-00) are
  told apart by the caption text. A variant without a gallery image is written without one. Rows you already
  have (same name + code) are matched and only blank cells are filled, so your existing editions get their
  `parentPartId`. If the release is in the products workbook (sku = code) the part is added to its contents.
* Stats: type, spin direction, attack/defense/stamina, weight and WBO legality come from the page source; when
  the source doesn't have them (other field names, a stats sub-template) the rendered infobox is read instead –
  the same labels you see on the page ("Spin Direction", "Weight", "Attack"). Multi-mold values take the first
  ("34.6 grams (first mold)"). `rendered_infobox`: `auto` (default) / `always` / `never`.
* After each part sheet the log prints what's still blank, e.g.
  `Parts_X_Blades: 412 rows (278 variants), 390 with image; still blank: mass 12, attack 30`.
* Images inside the workbooks are **WebP** (`workbook_image_format`, default `webp`) – the packager copies them
  byte-for-byte into `data/images/` for the jsDelivr links and the release zips. Excel 365 and LibreOffice show
  WebP; set `png` if you edit in an old Excel that shows blank pictures.
* Anything already in the workbooks is skipped **before** downloading (wiki title, name+code, sku, card number).
  `--relist` finds newly added wiki pages; `--refresh-existing` fills blank cells of existing rows; hand edits
  are kept unless `--overwrite`.
* Products come from the wiki's product list pages (`List of Beyblade X products (Takara Tomy)` / `(Hasbro)`,
  others found in Category:Product Lists): one table row per release incl. launchers, stadiums, cases and
  BX-00/UX-00/CX-00 limited releases – the whole line in a couple of requests. A limited re-release of an
  existing product (e.g. BX-01 at CoroCoro Spirit Festival) becomes a variant of it. Each *new* product's page
  is then opened for the box image, random-booster items (`CX-05 01: HellsReaper T4-70K` → variant products
  with `parentProductId`) and contents (Blade/Ratchet/Bit; CX: Lock Chip + Main Blade + Ratchet + Bit).
  Launchers, grips, stadiums and cases also get an `Accessories` row.
* Update mode: 1) re-reads the list pages and adds only rows not in the store, 2) per sequential series in
  `CodeSeries` searches for codes after the highest one in `Products` (e.g. BX-57 → BX-58, BX-59 …) until 3
  in a row are missing – catches releases the lists don't have yet (the lists also skip numbers, e.g. BX-55).
* Live progress: every request (`-> #57 image Foo.png` / `<- #57 HTTP 200, 48 KB in 1.2s`) and every step is
  printed with a timestamp and also saved to `scrape_state/scrape.log`. If nothing is printed for 15 s a
  heartbeat line says exactly what it is waiting on (`... still busy: request #57: image Foo.png - 12 KB
  received (34s)`). Each download has a hard 90 s limit; an image that keeps failing is skipped (row written
  without image) instead of stalling the run. `--quiet` hides the per-request lines on screen only.
* Safe: one request at a time with a 2–3 s gap, Retry-After/maxlag honoured, stops itself on repeated
  throttling or HTTP 403, 1500-request budget per run, everything checkpointed – just run again to continue.

## Package
```bash
python beyblade_data.py --parts beyblade_parts.xlsx --products beyblade_products.xlsx --tcg beyblade_tcg.xlsx \
  --out data --user discoballonmyhead --repo clasher_st_beyblade_assets
```
(or run without arguments for the GUI). X parts keep their old file names (`blades.json` ...); other
generations are prefixed (`burstLayers.json`, `metalFightFusionWheels.json`); plus `products.json`,
`accessories.json`, `productContents.json`, `codeSeries.json`, `tcgSets.json`, `tcgCards.json`.

## Release (GitHub release + app)
```bash
python build_release.py --tag 2026-11-02 --user discoballonmyhead --repo clasher_st_beyblade_assets
```
Writes `_release/<tag>/`:
* `catalog.zip` + `catalog_manifest.json` – the values the `beyblade_catalog_manifest` RPC returns
  (`version`, `dataUrl`, `dataSha256`, `publishedAtMillis`);
* `beyblade_images_<Gen>.zip` (hobby Beyblade) and `beyblade_tcg_images_<Gen>.zip` (hobby Beyblade TCG) – same
  flat `<sheet>-<dataID>.webp` / `-min.webp` layout as the existing `beyblade_images_X.zip`;
* `beyblade_data_<Gen>.zip` / `beyblade_tcg_data_<Gen>.zip` + `packs.json` – optional per hobby/generation data
  packs for when one catalog gets too big (`--no-data-packs` to skip).
Before writing anything it checks the data against what the app accepts (`catalog_check.py`) and stops with a
list of rows if the app would reject or fail to read them. `--drop-invalid` releases without those rows;
`--app-assets DIR` also writes the bundled catalog for the app's assets folder (see [WORKFLOW.md](WORKFLOW.md)).
Zips are deterministic: unchanged data gives the same SHA-256, so apps don't re-download it. Upload the folder's
files to the release `<tag>`.

Hobbies: parts and products are hobby `Beyblade`; the card game is its own hobby `Beyblade TCG` (own packs).
Accessory types use the app's values: `Stadium`, `Launcher`, `Grip`, `DeckBox`, `BattlePass`.

## Missing data tool (`missing_data_tool.py`)
A separate tool to see what's empty, field by field, and fill it. Run it without arguments for the GUI, or use the
Flutter app in `missing_data_app/`. Both work the same way. Pick a workbook and a tab, and the left list shows how
many rows miss each field (click one to list those rows). Pick a row to edit its values (blank fields are
highlighted) or give it an image.

* **Edits stay in memory until you save** (Ctrl+S, or autosave every 2 min). Every change can be undone with Ctrl+Z,
  including auto-fills, images and wiki fills. Closing with unsaved changes asks first.
* **Last edited:** each row shows when it was last changed. Sort by it, or open *Recently edited* to jump back.
* **Quick keys:** Enter applies the field, Ctrl+Enter applies and jumps to the next row with a gap, Ctrl+F searches.
  A *Recent* menu reopens your last workbooks.

* **Auto-fill (preview first):** variants copy shared fields from their parent row (type, spin, stats, weight,
  system…, never code/edition/manufacturer); rows with the same name fill a stable field when the others all agree;
  derived values (series from the tab, ratchet `3-60` → protrusions/height, currency/region from the manufacturer).
* **Fill from wiki:** re-reads the chosen rows' wiki pages with the scraper (polite client, rendered infobox, gallery
  images) and fills blank cells only. Pages come from `_scrape_log`, or are guessed from the name (`Blade - DranSword`).
* **Manual:** type values; images from a file, URL, the clipboard or the parent row – trimmed, fitted in 600 px,
  128 px minified copy, both WebP.
* Every save keeps a `.bak`. Rows marked `deleted` are ignored.

```bash
python missing_data_tool.py report --workbook beyblade_parts.xlsx --csv missing.csv
python missing_data_tool.py fill   --workbook beyblade_parts.xlsx --dry-run
python missing_data_tool.py fill   --workbook beyblade_parts.xlsx --parent --derive
python missing_data_tool.py set    --workbook beyblade_parts.xlsx --sheet Parts_X_Blades --id 65 --field mass --value 34.6
python missing_data_tool.py image  --workbook beyblade_parts.xlsx --sheet Parts_X_Blades --id 65 --file found.png
python missing_data_tool.py wiki   --workbook beyblade_parts.xlsx --sheet Parts_X_Blades --limit 20
python missing_data_tool.py serve  # JSON lines over stdin/stdout; used by the Flutter app
```
