# app_features

App features kept here so the data tools and the clasher_st app stay in step. This folder replaces the old
`flutter_integration/` folder. Each feature folder is a drop-in for `lib/features/`:

* `beyblade/`: the app's beyblade feature. It now reads 3D models, stock combos, bladers and credits; see below.
* `contributions/`: new. **Settings → Send pictures**: people send pictures with their username and an optional
  credit. See *Contributions* below.

```bash
cp -r app_features/beyblade app_features/contributions <app>/lib/features/
cp -r app_features/test/. <app>/test/        # optional: the tests and their fixtures
```

The beyblade feature needs nothing outside `lib/features/beyblade`. `AppConstants.trackedBeyBladeData`, the app's
Hive setup and the pubspec stay as they are. Contributions needs three small additions (below).

## What this version adds (all optional data)

| Data | Workbook | Packaged JSON | In the feature |
|---|---|---|---|
| 3D model of a part | `model3d` on every part tab | `model3dUrl`, `model3dHash` on every part row | `BeybladePart.model3dUrl`, `.model3dHash`, `.has3dModel` |
| Stock combos | `StockCombos` tab (products workbook) | `stockCombos.json` | `StockCombo` (with a `BeybladeLoadout`) |
| 3D model of a stock combo | `model3d` on `StockCombos` | `model3dUrl`, `model3dHash` | `StockCombo.model3dUrl` |
| Credits | `credits` on every data tab (parts, products, accessories, stock combos, bladers, TCG) | `credits` on every row | `credits` on parts, `Product`, `Accessory`, `StockCombo`, `Blader`; shown on detail pages |
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

### Credits
`credits` is free text (e.g. `@kai_photos; Wiki`) saying who contributed a row's data or pictures. A part, product
or accessory page shows it as a "Credits" row in the specs, and a blader's sheet shows it under the picture. Clasher
Studio adds a contributor's credit to the row when it applies a picture they sent. You can also type credits by hand
in any workbook.

## Contributions (Settings → Send pictures)

People pick what the picture is of: a part (searched by name or code), a blader (portrait or full body), a box, an
accessory, or "Other" with a note. Then they choose a picture from the gallery or camera (scaled to 1600 px and
compressed on the phone), add an optional credit and note, confirm they may share it, and send. The picture goes to
the Google Sheet / Drive web app in `submissions/` together with their **username** and user id. You review it in
Clasher Studio (Data → Submissions), and **Apply** puts it on the row with the credit. Setup: `submissions/README.md`.

**Add to the app:**
1. pubspec: `image_picker: ^1.1.2`. On iOS also add `NSPhotoLibraryUsageDescription` and `NSCameraUsageDescription`
   to Info.plist.
2. DI, after `BeybladeDependencies.init()`: `ContributionsDependencies.init(appVersion: '<version>');`
3. Router: add `...ContributionsRoutes.routes`. Settings page: add `const ContributeSettingsTile()` where it fits.

Build with `--dart-define=CONTRIBUTIONS_URL=<web app /exec URL> --dart-define=CONTRIBUTIONS_KEY=<SUBMIT_KEY>`.
Without them the page says sending isn't set up.

**Username:** `SupabaseContributorIdentity` sends the first of these set in the signed-in user's metadata:
`username`, `user_name`, `preferred_username`, `display_name`, `full_name`, `name`. If none is set, it sends the part
of the email before the @. Signed out, the page asks the person to sign in. If usernames live in a profiles table,
register your own `ContributorIdentity` before `ContributionsDependencies.init()`, or pass `lookup:`. Registered
`ContributionsConfig` / `ContributorIdentity` instances are kept.

**Credit:** optional and up to 120 characters. Empty means the username is the credit.

**How it's built:**
* `domain/`: entities, interfaces and `SubmitContributionUseCase`. The use case checks what the server checks, so
  problems show before uploading.
* `data/`:
  * `AppsScriptContributionsRepository` sends JSON as text/plain (no CORS preflight on web) and reads Apps Script's
    302 answer with a GET;
  * also the Supabase identity, the catalog search and the image_picker picker.
* `presentation/`: `ContributeCubit`, `ContributePage` and `ContributeSettingsTile`, built from plain Material
  widgets. Restyle them with the Holo components and TrTokens texts as you like.
* A route `extra` can be a `ContributionTarget`, to open the page on a specific part, e.g. from a "Send a picture of
  this" button.

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
* `test/contributions_test.dart` (10 tests) covers:
  * the client: the request body, the redirect, the username as the default credit, errors;
  * the checks before sending;
  * the page end to end with fakes: part, blader full body, signed out, a server refusal.
* `test/contributions_e2e_test.dart` sends over real HTTP to the web app; it ran against the local server.
* `test/catalog_extras_test.dart` runs the packager's real output for `samples/` (in `test/fixtures/`) through the
  parser, the models, the store and the repository. It ran against a stand-in package with stubs for the app parts
  that aren't in this folder.
* `domain/` and `data/` compile there without errors.
* The presentation files can't compile outside the app (other features, translations, Holo widgets). The analyzer
  reports no errors in them beyond the ones the original files already had there, and the new widget file compiles
  against stand-ins with the Holo widget signatures the feature already uses.
