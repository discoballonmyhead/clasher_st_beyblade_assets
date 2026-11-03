# Flutter integration (clasher_st app)

For how data gets from the workbooks to the app, and what goes in the assets folder, see
[../WORKFLOW.md](../WORKFLOW.md).

This folder plugs the new catalog data (ban/approve lists, stadiums, the card game) into the feature code you sent
(`beyblade/`, `presentation/` = `features/tournaments/presentation/`, `bey_testing/`). Its `lib/` mirrors the app's
`lib/`. Every file is either:

* **changed**: your file with a few edits. `patches/<file>.diff` shows exactly what changed, and each patch applies
  with `git apply` to the version you sent; or
* **new**: a file that doesn't exist in the app yet.

## Install

1. Copy `flutter_integration/lib/` over the app's `lib/`, or apply `patches/*.diff` and copy only the new files.
2. Run `sql/21_tournament_stadium.sql` in Supabase. First make the one marked `ADJUST` line use the same host check
   as `tournaments_set_part_rules`.
3. Run `flutter pub get`. No new packages are needed: it uses `hive_ce_flutter`, `supabase_flutter`, `go_router`
   and `get_it`, which the app already has.

## What changes for users, and where it lives

### 1. Ban & approve lists use the real parts catalog

**Before:** nothing registered a `PartCatalog`, so `resolvePartCatalog()` returned `ManualEntryPartCatalog`. In
Create tournament → Part rules → New list, "Add part" asked for a part type and a data id typed by hand. That is the
`//TODO Need to make it so that it selects the parts` in `create_tournament_page.dart`.

**Now:** "Add part" opens a picker over the local parts catalog:
* search by name or code;
* filter by part type;
* thumbnails, with recolors listed under their original;
* **Include all its variants** is on by default: banning Dran Sword also bans its Metal Coat recolors.

Chips show part names and images instead of `Blade #12`. Saved-list cards show the first few part names. The
Bey Station home has a **Ban & approve lists** tile for managing saved lists outside the create flow. The create
page links to it with **Manage lists** and reloads the lists when you come back.

| file | | what |
|---|---|---|
| `features/beyblade/parts_list.dart` | changed | `PartCatalog` gets `pickParts`, `isReady`/`ready()` and `thumbnail()`, all with defaults, so `ManualEntryPartCatalog` still compiles |
| `features/beyblade/presentation/part_lists/beyblade_part_catalog.dart` | new | `BeybladePartCatalog`: the real catalog plus the picker sheet, built on `BeybladeDataRepo` |
| `features/beyblade/presentation/widgets/part_list_editor.dart` | new | `PartListEditor` (ban/approve switch, parts by type, Add part) and `PartListPreview`, shared by both pages below |
| `features/beyblade/presentation/pages/part_lists_page.dart` | new | `PartListsPage` (your saved lists) and `PartListEditPage` (create/edit/delete one), using the existing `PartListsCubit` |
| `features/beyblade/di/beyblade_dependencies.dart` | changed | `sl.registerLazySingleton<PartCatalog>(() => BeybladePartCatalog(sl()))` |
| `features/beyblade/b_routes/beyblade_routes.dart` | changed | `BeybladeRoutes.partLists = '/beyblade/part-lists'` (provides `PartListsCubit`) |
| `features/beyblade/presentation/pages/beyblade_home.dart` | changed | "Ban & approve lists" tile in the Manage grid |
| `features/tournaments/presentation/pages/create_tournament_page.dart` | changed | `_NewListEditor` uses `PartListEditor`; `SavedListsPicker` gets "Manage lists"; `PartListCard` gets the preview |

The data shape is unchanged (`{"blade": ["12", "40"]}`), so existing saved lists, tournament snapshots and the
server-side deck check keep working.

### 2. One accessory picker for tournaments and bey_testing

bey_testing already had a stadium and launcher picker (`AccessoryPickerSheet`, `AccessoryName` and a private cache
in `test_setup_widgets.dart`). It now lives in the beyblade feature, so the tournament stadium uses the **same**
picker. bey_testing re-exports it, so `test_session_page.dart` and `matchup_score_page.dart` don't change.
Additions: thumbnails, a `noneLabel`, `AccessoryField` (a tappable card with clear) and `AccessoryThumb`. The cache
is cleared when a catalog update is applied.

| file | | what |
|---|---|---|
| `features/beyblade/presentation/widgets/accessory_picker.dart` | new | `AccessoryCache`, `AccessoryChoice`, `AccessoryPickerSheet`, `AccessoryName`, `AccessoryField`, `AccessoryThumb`, `accessoryTypeLabel` |
| `features/bey_testing/presentation/widgets/test_setup_widgets.dart` | changed | the moved classes replaced by `export '.../accessory_picker.dart'`; `SetupTile` and `TestBeyName` stay |
| `beyblade_sync_cubit.dart` | changed | `AccessoryCache.clear()` after an update |

### 3. Stadium (optional) on tournaments

The format step of Create tournament gets a **Stadium** block after Part rules. It lists the catalog's Accessories
with `accessoryType` Stadium; **No specific stadium** is the default. The tournament detail page shows the stadium
under "How it's played", and shows nothing when none was picked.

The create RPC and `CreateTournamentRequest` (data layer, not in the zip) are **not** touched. The page saves the
stadium right after the tournament is created, the same way it already saves prizes.

| file | | what |
|---|---|---|
| `features/tournaments/presentation/widgets/stadium_picker_field.dart` | new | `TournamentStadiumField` (create page; an `AccessoryField` for stadiums) and `TournamentStadiumPanel` (detail page) |
| `features/tournaments/data/tournament_stadium_repository.dart` | new | `setStadium` / `getStadium` (RPCs answer `{status, error}` like the rest of the app; reads are cached) |
| `sql/21_tournament_stadium.sql` | new | `tournaments.stadium_data_id`, `tournaments_set_stadium`, `tournaments_get_stadium` |
| `create_tournament_page.dart` | changed | `TournamentDraft.stadiumDataId`, the Stadium `FormBlock`, and `setStadium` in `_submit` after the tournament exists |
| `tournament_detail_page.dart` | changed | `TournamentStadiumPanel(tournamentId: t.id)` under the stages panel |
| `beyblade_dependencies.dart` | changed | registers `TournamentStadiumRepository` (move it to the tournaments DI if you prefer) |

### 4. Card game (Beyblade TCG, a separate hobby)

`catalog.zip` can carry `tcgCards.json` / `tcgSets.json`. The download now keeps them as **optional** sheets: they are
never required, so older releases still apply. After a successful update the sync cubit stores them in their own
Hive box. The Bey Station home gets a **Card game** tile: a page to search cards by name or number, filter by game
(V-Force / Beyblade X) and set, and open a card's details with its foils and parallels. With no card data yet, the
page offers "Check for updates".

| file | | what |
|---|---|---|
| `features/beyblade_tcg/beyblade_tcg.dart` | new | entities, row parser, `TcgCatalog`, and `HiveTcgStore` (its own box `beyblade_tcg_catalog`, opened lazily like `BeyTestsLocalDataSource`) |
| `features/beyblade_tcg/presentation/tcg_cards_page.dart` | new | `TcgCardsPage` |
| `features/beyblade/data/dsrces/beyblade_cat_remdsrc.dart` | changed | keeps `kOptionalCatalogSheets` (`tcgCards`, `tcgSets`, `codeSeries`) |
| `features/beyblade/presentation/cubit/beyblade_sync_cubit/beyblade_sync_cubit.dart` | changed | optional `tcgCatalog`; `ingestSheets(sheets)` after an update is applied (a bad TCG sheet only logs) |
| `beyblade_dependencies.dart`, `beyblade_routes.dart`, `beyblade_home.dart` | changed | `TcgCatalog` registration, `BeybladeRoutes.tcg = '/beyblade/tcg'`, and the "Card game" tile |

Card images use the CDN URLs in the rows, so they show without an image pack. TCG image packs
(`beyblade_tcg_images_<Gen>.zip`) are built by `build_release.py`, and `TcgCatalog.applyLocalImagePaths` is ready
for them. Offering them in the image-pack sheet needs `AssetDownloadService.findAssetForGeneration`, which wasn't in
the zip.

### 5. Scorekeeper: optimistic and fast, gradient selection borders

`features/tournaments/presentation/pages/score_keeper_page.dart` (changed, `patches/score_keeper_page.diff`). Only
this page changes: no cubit, entity or backend changes.

**Why it felt slow:**
* Every bey tap waited for `selectBey` and then for `loadMatches` (a reload of **all** the tournament's matches)
  before the page counted the pick. The 4-second `_pending` timer could flip the pick back while the reload was
  still running.
* Logging a round put a full-screen scrim and spinner over the page until the same reload finished.
* Every selected button pulsed its glow on the shared animation, so all of them repainted 60 times a second.

**Now:**
* **Bey picks are optimistic.** The pick shows the moment you tap, and the step unlocks as soon as both players have
  one. When the save finishes, the server value takes over; if it failed, the picker falls back to the server's pick
  and the error snack says why. There's no timer.
* **Rounds are optimistic.** Score, pips, round number, flash and history update on tap. The history shows
  `· SAVING` until the server confirms. Rounds queue: you can log the next one while earlier ones save. They are sent
  in order, each waits for the bey saves, and numbering stays correct. If one fails, it and any later rounds are taken
  back off the board, and the snack shows the error. Undo and restart wait until nothing is saving.
* **No scrim.** A 2 px progress line at the top shows saving, and the page stays usable.
* **Selection look.** Every selectable control (finish buttons, compact chips, foul, player tags, bey rows, deck
  panels, compact player cards) has a neutral fill and a **theme-gradient border** (primary → tertiary → secondary,
  mirrored on player 2's side) when selected:
  * no inner tint, no glow and no pulse;
  * the foul button uses a warm foul → error gradient;
  * a deck panel with a picked bey uses success → player colour;
  * "Log round" fills with the theme gradient once a winner and finish are picked;
  * the border fades in over 110 ms, and the tap ripple is instant and faint.
* The pulse remains only on the round chip, the flip warning and the awaiting icon.

Checked in the stand-in package (with your original file as the baseline):
* `flutter analyze` shows only the two issues already in your original.
* 3 widget tests pass against a fake cubit whose server calls are held open:
  * picks and rounds show before the server answers, rounds wait for the bey saves, and the queue numbers rounds
    correctly;
  * a failed round save reverts that round and the ones after it;
  * a failed bey save falls back to the server's pick.
* The new look was rendered and compared with the old one.

## Data compatibility (checked against your parsers)

Checked by running a release through the app's own `downloadCatalogSheets`, `parseMetadataSheets` and `models.dart`
(`test/release_contract_test.dart`). `build_release.py` now refuses data the app would reject (see WORKFLOW.md).

* `data/*.json` from `beyblade_data.py` has every field `models.dart` reads (`dataID`, `parentPartId`,
  `variantLabel`, `wbolegality`, `type`, `spinDir`, `baseName`, `movementStyle`, `productID`, `partDataID`,
  `accessoryType` …).
* `accessoryType` values match `AccessoryType.parse`: `Stadium`, `Launcher`, `Grip`, `DeckBox`, `BattlePass`.
* Rows marked `deleted` in the workbooks are now left out by the packager. The app has no `deleted` filter, so before
  this they would have shown up.
* Ids are written as text, and `ProductContents.partType` uses the app's keys (`blades`, `accessories`), which
  `detail_page.dart` looks up. The old data used sheet names (`Parts_X_Blades`), so "in the box" couldn't resolve.
* Image packs keep the flat `<sheet>-<dataID>[-min].webp` layout that `applyLocalBeyImagePaths` expects.

## Strings

New text is plain English (`'Stadium'`, `'Manage lists'`, `'Ban & approve lists'`, `'Card game'`, the picker
labels). `FormBlock` calls `.tr` on its title and hint. If your translation helper doesn't return the key itself
when no translation exists, add `TrTokens` entries for `'Stadium'` and its hint. Move the rest into `TrTokens`
whenever you translate them. Existing tokens (`TrTokens.addPartBtn`, `banListTxt` …) are
reused where they already existed.

## What was verified, and how

The full app wasn't in the zip, so I couldn't build it. Instead:
* All **new** files and the changed `parts_list.dart`, `beyblade_cat_remdsrc.dart` and `beyblade_sync_cubit.dart` pass
  `flutter analyze`. The only warnings are two unused imports of `responsive_extras.dart`, and they come from the
  stubs: the files import it the same way `part_search_page.dart` does. The check used a stub `clasher_st` package with your real entities, `BeybladeDataRepo`,
  `PartListsCubit`, sync state and `arena_style.dart`. The core widgets that weren't in the zip (`holow_components`,
  `responsive`, `part_image_thumb`) were stubbed with the signatures your code uses.
* `test/part_lists_test.dart`, `test/tcg_catalog_test.dart`, `test/accessory_picker_test.dart` and
  `test/release_contract_test.dart` pass (9 tests) in that package. The release contract test needs
  `E2E_RELEASE=<_release/tag>` and `E2E_ASSETS=<--app-assets dir>`. The tests cover:
  * part names come from the catalog;
  * the editor rebuilds once the catalog loads;
  * opening the picker, searching "dran" and tapping Dran Sword adds it **and** its recolor;
  * the list preview;
  * TCG ingest, sorting, filters, variants and local image paths;
  * the tournament stadium field (pick, name, clear);
  * bey_testing's `SetupTile` with `AccessoryPickerSheet` through its own import;
  * a built release read by the app's real download, parse and model code.

  In the app, if `ResponsiveProvider.config` needs an ancestor widget, wrap the test widgets in it.
* The changed big files (`create_tournament_page.dart`, `tournament_detail_page.dart`, `beyblade_home.dart`, routes,
  DI) parse cleanly. Every `patches/*.diff` applies with `git apply --check` to the files you sent.
