import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';

abstract class BeybladeDataRepo {
  //remote synchronizationdownnloads and sync:

  Future<bool> hasAvailData();

  Future<SyncMetadata> getSyncData();

  /// Loads and stores the bundled metadata — every part's full data,

  /// image fields already plain URLs. This alone makes the app fully

  /// functional; nothing else needs to happen after it for the app to

  /// be usable. Near-instant (a local asset read, not a network call).

  Stream<SyncProgress> loadMewBeyundle();

  /// Replaces the whole local catalog with [sheets] (sheet name -> raw

  /// JSON text), the same shape the bundled loader reads. Used for both

  /// the bundled catalog and a downloaded release, so there is exactly

  /// one write path and the two can't drift apart.

  ///

  /// [version] and [sha256] are recorded so the next launch can tell

  /// whether a newer release exists.

  Stream<SyncProgress> applyCatalogSheets(
    Map<String, String> sheets, {
    String? version,
    String? sha256,
  });

  //COMBOS

  Future<List<Combo>> getAllCombos();

  Future<Combo> createCombo(String name, BeybladeLoadout loadout);

  Future<void> deleteCombo(String id);

//DECK AND DECKSLOTS

  Future<List<Deck>> getAllDecks();

  /// Throws ArgumentError if fewer than 3 UNIQUE combo ids are given --

  /// the reference app's own rule, enforced here so it can't be

  /// bypassed by calling this directly from anywhere else later.

  Future<Deck> createDeck(String name, List<String> comboIds);

  Future<void> deleteDeck(String id);

  /// Always returns exactly [DeckSlotsLocalDataSource.slotCount] entries,

  /// index 0 through slotCount-1, empty slots included — the UI renders

  /// a fixed 3-slot layout, not a variable-length list.

  Future<List<DeckSlot>> getAllDeckSlots();

  Future<void> saveDeckSlot(int index, BeybladeLoadout loadout);

  Future<void> clearDeckSlot(int index);

  /// Read access to locally-synced part data — Hive only, never the

  /// network (that's BeybladeSyncRepository's job). Every lookup is by

  /// `dataId`, not `code` (not unique per row).

  Future<List<Blade>> getAllBlades();

  Future<Blade?> getBladeByDataId(String dataId);

  Future<List<Ratchet>> getAllRatchets();

  Future<Ratchet?> getRatchetByDataId(String dataId);

  Future<List<Bit>> getAllBits();

  Future<Bit?> getBitByDataId(String dataId);

  Future<List<LockChip>> getAllLockChips();

  Future<LockChip?> getLockChipByDataId(String dataId);

  Future<List<OverBlade>> getAllOverBlades();

  Future<OverBlade?> getOverBladeByDataId(String dataId);

  Future<List<MetalBlade>> getAllMetalBlades();

  Future<MetalBlade?> getMetalBladeByDataId(String dataId);

  Future<List<MainBlade>> getAllMainBlades();

  Future<MainBlade?> getMainBladeByDataId(String dataId);

  Future<List<AssistBlade>> getAllAssistBlades();

  Future<AssistBlade?> getAssistBladeByDataId(String dataId);

  Future<List<Product>> getAllProducts();

  Future<Product?> getProductByProductId(String productId);

  Future<List<ProductContent>> getContentsForProduct(String productId);

  Future<List<Accessory>> getAllAccessories();

  Future<Accessory?> getAccessoryByDataId(String dataId);

  /// Rewrites imageUrl/minifiedImageUrl to local file paths for every

  /// part named in [pathsByKey] -- keys are "{sheetShortKey}-{dataId}"

  /// for the full image, "{sheetShortKey}-{dataId}-min" for the

  /// minified one (matching AssetDownloadService.extractAndMap's

  /// output). Used once a generation's image pack has been downloaded

  /// and extracted, so subsequent reads of that part use the local file

  /// instead of the remote CDN URL.

  Future<void> applyLocalBeyImagePaths(Map<String, String> pathsByKey);

  /// Unified search across every part type by code/name substring.

  Future<List<BeybladePart>> searchBeyParts(String query);

  /// The reverse of getContentsForProduct -- every ProductContent row

  /// referencing this exact part/accessory. partType is the sheet short

  /// key ("blades", "accessories", ...).

  Future<List<ProductContent>> getProductContentsForItem(
      String partType, String partDataId);

  /// Dispatches to the right getXByDataId by partTypeKey. Returns null

  /// for 'accessories' -- Accessory isn't a BeybladePart, call

  /// getAccessoryByDataId directly for that case.

  Future<BeybladePart?> getPartByTypeAndDataId(
      String partTypeKey, String dataId);

  /// Every part sharing the same "element" as [dataId] within

  /// [partTypeKey] -- the original plus every variant pointing at it,

  /// regardless of which one [dataId] itself refers to.

  Future<List<BeybladePart>> getVariantGroup(String partTypeKey, String dataId);

  // ── Stock combos & bladers (optional catalog sheets; empty when the catalog has none) ──

  Future<List<StockCombo>> getAllStockCombos();

  /// The combos that come out of this product's box (a set with several beys has several).
  Future<List<StockCombo>> getStockCombosForProduct(String productId);

  /// Every stock combo the part [dataId] of sheet [partTypeKey] ("blades", "bits" ...) is in.
  Future<List<StockCombo>> getStockCombosForPart(
      String partTypeKey, String dataId);

  Future<List<Blader>> getAllBladers();

  Future<Blader?> getBladerById(String bladerId);

  /// The bladers who use [part] in the show, in the order the data lists them. Unknown ids are skipped.
  Future<List<Blader>> getBladersForPart(BeybladePart part);

  /// Every part [bladerId] uses, as (part sheet key, part).
  Future<List<(String, BeybladePart)>> getPartsForBlader(String bladerId);
}
