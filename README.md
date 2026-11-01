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
* **beyblade_tcg.xlsx** – `TCG_Sets`, `TCG_Cards`.

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
python fandom_scraper.py --scope products --generation Burst # products of a generation (category listing)
python fandom_scraper.py --update                            # new releases after the last code in the store
python fandom_scraper.py --update --series BX UX --manufacturer Takara-Tomy
python fandom_scraper.py --update --series B --from-code B-150
python fandom_scraper.py --scope tcg
python fandom_scraper.py --next      # next unfinished target
python fandom_scraper.py --status
```
* Anything already in the workbooks is skipped **before** downloading (wiki title, name+code, sku, card number).
  `--relist` finds newly added wiki pages; `--refresh-existing` fills blank cells of existing rows; hand edits
  are kept unless `--overwrite`.
* Update mode: per sequential series in `CodeSeries`, finds the highest code for that manufacturer in
  `Products` (e.g. BX-54) and searches the wiki for BX-55, BX-56 … until 3 in a row are missing.
  Non-sequential codes (BX-00 limited releases, Hasbro item numbers) come from `--scope products`.
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
