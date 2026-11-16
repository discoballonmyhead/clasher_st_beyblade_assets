# beyblade_feature

The clasher_st app's beyblade feature (`lib/features/beyblade`), kept here so the data tools and the app stay in
step. It replaces the old `flutter_integration/` folder. `beyblade/` is a drop-in copy of the feature folder:

```bash
cp -r beyblade_feature/beyblade <app>/lib/features/
cp -r beyblade_feature/test/. <app>/test/        # optional: the parsing test and its fixtures
```

Nothing outside `lib/features/beyblade` has to change. `AppConstants.trackedBeyBladeData` stays as it is, and so do
the app's Hive setup and pubspec.

## What this version adds (all optional data)

| Data | Workbook | Packaged JSON | In the feature |
|---|---|---|---|
| 3D model of a part | `model3d` on every part tab | `model3dUrl`, `model3dHash` on every part row | `BeybladePart.model3dUrl`, `.model3dHash`, `.has3dModel` |
| Stock combos | `StockCombos` tab (products workbook) | `stockCombos.json` | `StockCombo` (with a `BeybladeLoadout`) |
| 3D model of a stock combo | `model3d` on `StockCombos` | `model3dUrl`, `model3dHash` | `StockCombo.model3dUrl` |
| Bladers (who uses a part in the show) | `Bladers` tab (parts workbook) + `bladerIDs` on blades / lock chips | `bladers.json`; `bladerIDs: ["BL1", ...]` on part rows | `Blader`; `BeybladePart.bladerIds` |

### 3D models
Each model is a `.glb` file (glTF binary: one self-contained file) of up to 20 MB, served from the same CDN as the
pictures (`.../data/models/<sheet>-<id>.glb`), or any https link the data team enters. `model3dHash` changes when the
file does, so it can be used as a cache key.

"View in 3D" (`presentation/widgets/catalog_extras.dart`) opens the model in Google's Scene Viewer on Android, and the
file link elsewhere. That needs no new package; iOS Quick Look needs USDZ files, so on iOS the link just opens the
file. To show models inside the app instead, replace `open3dModel` with a viewer widget (e.g. `model_viewer_plus`)
fed with the same URL.

### Stock combos
Until now the detail page guessed a part's "stock combo" as *everything else in each box it came in*, which is wrong
for sets with more than one bey. Now:
* `stockCombos.json` has one row per bey in a product. Its part ids are a `BeybladeLoadout`, so a stock combo
  resolves (`ResolveBeybladeUseCase`), saves and shares (`toShareCode()`) like any build.
* On a **part** page, each box the part shipped in shows the declared combo it belongs to ("Assembled with" + the
  combo's other parts). Boxes without a declared combo still use the old guess ("Packed with").
* A **product** page lists its stock combos.
* Each combo has **Open in builder** (the builder route now accepts a `BeybladeLoadout` as `extra`) and **View in 3D**
  when it has a model.

Repository: `getAllStockCombos()`, `getStockCombosForProduct(productId)` and
`getStockCombosForPart(partTypeKey, dataId)`. Use cases: `GetProductDetailsUseCase.getStockCombos`,
`GetPartDetailsUseCase.getStockCombos`.

### Bladers
`Blader` has a name, an optional description and two optional pictures, each with a small copy for lists:
* the portrait: `imageUrl`, plus `minifiedImageUrl`;
* the full-body picture: `fullBodyImageUrl`, plus `minifiedFullBodyImageUrl`.

Use `avatarUrl` for a small avatar. Parts point at bladers with `bladerIds`; the data fills them on blades and lock
chips, but the field is on every part.
* Repository: `getBladersForPart(part)`, `getPartsForBlader(bladerId)` (as `(sheetKey, part)`), `getAllBladers()`,
  `getBladerById(id)`. Use cases: `GetBladersUseCase`, `GetPartDetailsUseCase.getBladers`.
* A part page shows "Used in the show by" (`BladersSection`); tapping a blader opens its full-body picture.
* Blader pictures aren't in the image packs: they load from their CDN URLs, like any network image.

## How the data gets in
* `catalog.zip` (download) and the bundled assets carry `stockCombos.json` and `bladers.json` when the catalog has
  them. They're listed in `kBeybladeExtraSheets` (`data/isolates/parsed_results.dart`) and are never required, so an
  older release or bundle still applies (with no combos or bladers).
* `parseMetadataSheets` puts them in `ParsedFullBundle.stockCombos` / `.bladers`.
* `applyCatalogSheets` stores them with each catalog apply, replacing the previous ones.
* They're stored in the feature's own Hive box, `beyblade_catalog_extras` (`HiveBeybladeExtrasLocalDataSource`, opened
  on first use), so no new box has to be registered in the app.
* A row the model can't read is skipped and logged; it never blocks a catalog.
* Bundled catalog: `build_release.py --app-assets <dir>` writes `stockCombos.json` and `bladers.json` next to the other
  sheets. Make sure the app's pubspec asset entry covers them: a folder entry does, an entry per file needs two more
  lines.

## Changed files
* `domain/entities/entities.dart`: the 3D model and `bladerIds` on `BeybladePart`; new `StockCombo` and `Blader`.
* `data/models/models.dart`: parse them (`parseIdList` takes a JSON list or a comma-separated string);
  `StockComboModel`, `BladerModel`.
* `data/isolates/parsed_results.dart`, `beyblade_bundle_parser.dart`: the optional sheets.
* `data/dsrces/beyblade_cat_remdsrc.dart`: keeps the optional sheets when it downloads `catalog.zip`.
* `data/dsrces/beyblade_ldsrc.dart`: loads them from the bundle when present.
* `data/dsrces/beyblade_extras_ldsrc.dart` (new): their store.
* `data/repositories/bey_data_repo_impl.dart`, `domain/repositories/beyblade_data_repo.dart`: store and look them up.
  Any other `BeybladeDataRepo` implementation (e.g. a test fake) needs the 7 new methods.
* `domain/usecases/usecases.dart`, `di/beyblade_dependencies.dart`: use cases and registrations.
* `presentation/widgets/catalog_extras.dart` (new): View in 3D, stock combo actions, bladers.
* `presentation/pages/detail_page.dart`: the sections above. The page's own `StockCombo` class became `ShippedIn`,
  since `StockCombo` is now the domain entity.
* `b_routes/beyblade_routes.dart`: the builder accepts a starting loadout.

## Checked
* `test/catalog_extras_test.dart` runs the packager's real output for `samples/` (in `test/fixtures/`) through the
  parser, the models, the store and the repository. It ran against a stand-in package with stubs for the app parts
  that aren't in this folder.
* `domain/` and `data/` compile there without errors.
* The presentation files can't compile outside the app (other features, translations, Holo widgets). The analyzer
  reports no errors in them beyond the ones the original files already had there, and the new widget file compiles
  against stand-ins with the Holo widget signatures the feature already uses.
