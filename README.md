# Clasher ST – Beyblade data store

Humans manage three Excel workbooks → the packager turns them into `data/*.json` + `data/images/*.webp`
(served via jsDelivr) → the scraper can fill/update the workbooks from the Beyblade Fandom wiki.

| file | what it does |
|---|---|
| `beyblade_schema.py` | the layout: generations, part types, sheets, columns, release-code series |
| `make_sample_workbooks.py` | builds the 3 workbooks (`samples/` = with example rows; `--empty DIR` = blank store) |
| `fandom_scraper.py` | polite, resumable wiki scraper that fills the workbooks |
| `beyblade_data.py` | packager: workbooks → `data/` |
| `beyblade_store.py` | shared workbook read/write helper |

## The three workbooks
* **beyblade_parts.xlsx** – `Parts_<Generation>_<PartType>` per generation: X (Blades, Ratchets, Bits, LockChips,
  Main/Assist/Metal/OverBlades), Burst (Layers, Discs, Frames, Drivers), MetalFight (FaceBolts, EnergyRings,
  FusionWheels, SpinTracks, Tips), ZeroG, HMS, Plastic.
* **beyblade_products.xlsx** – `Products` (every release incl. launchers, stadiums, sets, TCG packs; both
  Takara-Tomy and Hasbro), `Accessories`, `ProductContents` (product → part/accessory/card links),
  `CodeSeries` (BX, UX, CX, B, BB, BBG, ... per manufacturer; drives the update mode).
* **beyblade_tcg.xlsx** – `TCG_Sets`, `TCG_Cards` for every Beyblade card game, told apart by `hobbyGeneration`
  (`Plastic` = the original 2000s TCG with Battle Edge / Spin Strength / Game Text / Lore, `X` = the X TCG).

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
python fandom_scraper.py --target tcg:Plastic:cards           # original 2000s TCG (Category:Cards)
python fandom_scraper.py --scope tcg --generation X           # Beyblade X TCG (set its category in the config)
python fandom_scraper.py --next      # next unfinished target
python fandom_scraper.py --status
```
* Parts and their variants: each part page's **Products** section lists every release the part came in
  (`CX-05 Random Booster Vol. 6 - 01: HellsReaper T4-70K`, `BX-00 Booster DranSword 3-60F (Metal Coat: Gold)`,
  Hasbro `G1678 Reaper Incendio T 4-70K`). The debut release (infobox product code) becomes the main row;
  every other release becomes a variant row with `parentPartId` = main row, its own `code` (BX/UX/CX/RX + item
  number, or the Hasbro item number), `edition`, `variantLabel` and `manufacturer`. Images come from the page
  gallery, matched by the codes in the captions (`Reaper (CX-05 02/G2746)`); recolors sharing a code (BX-00) are
  told apart by the caption text. A variant without a gallery image is written without one. Rows you already
  have (same name + code) are matched and only blank cells are filled, so your existing editions get their
  `parentPartId`. If the release is in the products workbook (sku = code) the part is added to its contents.
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
