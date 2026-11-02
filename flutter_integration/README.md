# Flutter integration (clasher_st app)

New Flutter files for the app, laid out like the app's `lib/` so each one drops into the same path.
Nothing here replaces an existing file; every change to an existing file is a few lines and is listed below.

## How data reaches the app

```
fandom_scraper.py   wiki -> beyblade_parts.xlsx / beyblade_products.xlsx / beyblade_tcg.xlsx   (humans edit these)
beyblade_data.py    workbooks -> data/*.json + data/images/*.webp (PNG in the sheet -> WebP)   (packager)
build_release.py    data/ -> _release/<tag>/                                                    (release builder)
                      catalog.zip + catalog_manifest.json  -> beyblade_catalog_manifest RPC (dataUrl, dataSha256, version)
                      beyblade_images_<Gen>.zip             -> AssetDownloadCubit / image pack sheet (unchanged format)
                      beyblade_tcg_images_<Gen>.zip         -> TCG image packs (hobby "Beyblade TCG")
                      beyblade_*_data_<Gen>.zip + packs.json -> optional per hobby/generation data packs (future)
```

* Image packs keep the exact layout of the current `beyblade_images_X.zip` (flat
  `<sheet>-<dataID>.webp` / `-min.webp`), so `applyLocalBeyImagePaths` keeps working. Checked: a rebuilt
  X pack has the same 1026 file names as the one on release `9526Update`.
* `catalog.zip` contains every sheet. The app only reads `trackedBeyBladeData`, so extra sheets
  (other generations, `codeSeries`, `tcgCards`, `tcgSets`) are ignored until you opt in.
* Rows keep the app's columns. New optional columns (`parentProductId`, `variantLabel`, `currency`,
  `region` on products; variant rows for parts) are read with `ciGet` or ignored.
* `accessoryType` values now match `AccessoryType.parse`: `Stadium`, `Launcher`, `Grip`, `DeckBox`,
  `BattlePass`.
* TCG rows use `hobbyName = "Beyblade TCG"`, a separate hobby from `Beyblade`.

## 1. Ban / allow lists (the broken "meta")

**Why it was broken:** nothing registered a `PartCatalog`, so `resolvePartCatalog()` used
`ManualEntryPartCatalog` ("type a part type and data id").

**Files**
* `lib/features/beyblade/presentation/part_lists/beyblade_part_catalog.dart`: the real catalog plus a
  part picker sheet (search by name or code, filter by type, images, variants under their original,
  "include all its variants").
* `lib/features/beyblade/presentation/pages/part_lists_page.dart`:
  * `PartListsPage`: manage saved lists in the Beyblade feature;
  * `PartListEditPage`: create or edit one list;
  * `PartListEditor`: reusable editor widget.

**Edits**
1. `features/beyblade/di/beyblade_dependencies.dart`, end of `init()`:
   ```dart
   sl.registerLazySingleton<PartCatalog>(() => BeybladePartCatalog(sl()));
   ```
   This alone fixes the create-tournament page, which already calls `resolvePartCatalog()`.
2. `features/beyblade/b_routes/beyblade_routes.dart`:
   ```dart
   static const String partLists = '/beyblade/part-lists';
   GoRoute(
     path: partLists,
     builder: (_, __) => BlocProvider(
       create: (_) => sl<PartListsCubit>()..load(),
       child: const PartListsPage(),
     ),
   ),
   ```
   Then add a tile on the Beyblade home that calls `context.push(BeybladeRoutes.partLists)`.
3. Optional, create page: replace the body of `_NewListEditor` with
   `PartListEditor(list: draft.newList, onChanged: (l) => draft.update(() => draft.newList = l))`. Keep the
   name field and the "save to my lists" button below it. You get images and "add with variants" in the
   create flow too.

Lists keep their exact shape (`{"blade": ["12", "40"]}`), so saved lists and tournament snapshots
stay compatible. Server-side checks compare loadout ids directly. If a ban on an original should also
cover its recolors, either tick "include all its variants" when adding the part, or treat
`parentPartId` as the same part in the deck check.

## 2. Stadium (optional) for tournaments

**File:** `lib/features/tournaments/presentation/widgets/stadium_picker_field.dart`
(`TournamentStadiumField`). It picks from catalog Accessories of type Stadium, and "No specific stadium"
is the default.

**Edits** (the first two are in `create_tournament_page.dart`; I couldn't finish the last two without
the tournaments data layer):
1. `TournamentDraft`: `String? stadiumDataId;`
2. A `FormBlock` next to the part rules:
   ```dart
   FormBlock(
     title: 'Stadium',
     child: _DraftSelect(
       draft: draft,
       select: (x) => x.stadiumDataId,
       builder: (context, _) => TournamentStadiumField(
         value: draft.stadiumDataId,
         onChanged: (id) => draft.update(() => draft.stadiumDataId = id),
       ),
     ),
   ),
   ```
3. `CreateTournamentRequest`: add `String? stadiumDataId`, pass it in `toRequest()`, and send it in
   the create RPC.
4. Database: `tournaments.stadium_data_id text null` and the create RPC parameter. Show it on the
   tournament detail page with `getAccessoryByDataId`.

To finish 3 and 4 I need `features/tournaments/data/*` and `features/tournaments/domain/*`, plus the
SQL of the create-tournament RPC.

## 3. Beyblade TCG (separate hobby)

**File:** `lib/features/beyblade_tcg/beyblade_tcg.dart`. It holds:
* entities `TcgCard` and `TcgSet`, with the same original/variant model as parts;
* a tolerant row parser;
* `TcgCatalog`, which ingests the sheets map, stores it, overlays downloaded images, and offers
  filters and variant groups.

It has no Flutter or Hive imports: `dart analyze` is clean and its unit test passes.

**Edits**
1. `beyblade_cat_remdsrc.dart` → `downloadCatalogSheets()`: also keep `kOptionalCatalogSheets`. Don't
   add them to `trackedBeyBladeData`, which is the required list and would reject older releases.
   ```dart
   final optional = kOptionalCatalogSheets.toSet();
   // in the loop:
   if (!tracked.contains(sheet) && !optional.contains(sheet)) continue;
   ```
2. `beyblade_sync_cubit.dart`, after `downloadCatalogSheets(release)`:
   `await sl<TcgCatalog>().ingestSheets(sheets);`
3. DI: `sl.registerLazySingleton<TcgCatalog>(() => TcgCatalog(HiveKeyValueStore(<any Box>)));`
   The 6-line adapter is at the bottom of the file.
4. TCG image packs are named `beyblade_tcg_images_<Gen>.zip`. `AssetDownloadService.findAssetForGeneration`
   isn't in the zip I received. If it matches on `beyblade_images_<gen>`, the TCG packs need a
   hobby-aware lookup (`<hobby-slug>_images_<gen>.zip`). Send me that service and I'll add it without
   changing the parts flow.

A TCG browse screen is the next step once the data is flowing.

## 4. Per hobby / generation data downloads (future)

`build_release.py` already writes `beyblade_data_<Gen>.zip` / `beyblade_tcg_data_<Gen>.zip` and
`packs.json` (hobby, generation, url, sha256, size, row counts). When the catalog gets big, the app can
offer these exactly like the image packs (same sheet, `ImagePacks` pattern) instead of one catalog.zip.
Nothing in the app needs to change for that today.

## Still needed from you
* `features/tournaments/data/*`, `features/tournaments/domain/*` and the create-tournament RPC SQL, to
  finish the stadium.
* `core/services/.../asset_download_service.dart` (`findAssetForGeneration`, `extractAndMap`), for TCG
  image packs.
* `core/constants/app_constants.dart` and the Hive box setup in `core/init_injection`, to wire the TCG
  catalog without guessing box names.
