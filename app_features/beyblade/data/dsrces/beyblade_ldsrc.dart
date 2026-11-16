import 'dart:developer' as dev;
import 'package:clasher_st/core/constants/app_constants.dart';
import 'package:clasher_st/core/init_injection/injection.dart';
import 'package:clasher_st/core/utils/sheet_row_parsing.dart';
import 'package:clasher_st/features/beyblade/data/isolates/parsed_results.dart';
import 'package:clasher_st/features/beyblade/data/models/models.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:hive_ce/hive.dart';

abstract class BeybladeDataLocalDatasource {
//loads the sheets and the manifest to verify the existence of it. LOADS THE DAT OF THE BEYBLADE DATA THAT I PACKAGE AND FUND THE APP AS JSON
  Future<({Map<String, String> sheets, String manifestJson})>
      loadPartsDataBundle();

  //DeckSlots
  /// Retrieves all saved decks from local storage.
  List<DeckModel> getAllDecks();

  /// Saves or updates a deck in local storage.
  Future<void> saveDeck(DeckModel deck);

  /// Deletes a deck from local storage by its ID.
  Future<void> deleteDeck(String id);
  String? getDeckShareCode(int index);
  Future<void> saveDeckShareCode(int index, String shareCode);
  Future<void> clearDeckSlot(int index);

  // ── GETTERS: Parts & Accessories ───────────────────────────────────────────
  List<BladeModel> getAllBlades();
  BladeModel? getBlade(String dataId);

  List<RatchetModel> getAllRatchets();
  RatchetModel? getRatchet(String dataId);

  List<BitModel> getAllBits();
  BitModel? getBit(String dataId);

  List<LockChipModel> getAllLockChips();
  LockChipModel? getLockChip(String dataId);

  List<OverBladeModel> getAllOverBlades();
  OverBladeModel? getOverBlade(String dataId);

  List<MetalBladeModel> getAllMetalBlades();
  MetalBladeModel? getMetalBlade(String dataId);

  List<MainBladeModel> getAllMainBlades();
  MainBladeModel? getMainBlade(String dataId);

  List<AssistBladeModel> getAllAssistBlades();
  AssistBladeModel? getAssistBlade(String dataId);

  List<AccessoryModel> getAllAccessories();
  AccessoryModel? getAccessory(String dataId);

  // ── GETTERS: Products & Contents ───────────────────────────────────────────

  List<ProductModel> getAllProducts();
  ProductModel? getProduct(String productId);

  /// ProductContents has no dataId of its own -- rows are grouped and
  /// stored under their productId.
  List<ProductContentModel> getContentsForProduct(String productId);

  /// Every ProductContent row across every product.
  List<ProductContentModel> getAllProductContents();

  // ── SETTERS: Bulk Inserts ──────────────────────────────────────────────────

  Future<void> putBlades(Iterable<Map<String, dynamic>> rows);
  Future<void> putRatchets(Iterable<Map<String, dynamic>> rows);
  Future<void> putBits(Iterable<Map<String, dynamic>> rows);
  Future<void> putLockChips(Iterable<Map<String, dynamic>> rows);
  Future<void> putOverBlades(Iterable<Map<String, dynamic>> rows);
  Future<void> putMetalBlades(Iterable<Map<String, dynamic>> rows);
  Future<void> putMainBlades(Iterable<Map<String, dynamic>> rows);
  Future<void> putAssistBlades(Iterable<Map<String, dynamic>> rows);
  Future<void> putAccessories(Iterable<Map<String, dynamic>> rows);

  Future<void> putProducts(Iterable<Map<String, dynamic>> rows);

  /// Groups incoming rows by productId before storing.
  Future<void> putProductContents(Iterable<Map<String, dynamic>> rows);

  // ── UTILITIES & METADATA ───────────────────────────────────────────────────

  /// Updates just the two image fields on an already-stored row.
  Future<void> updateImagePaths(
    String sheetShortKey,
    String dataId, {
    String? imageUrl,
    String? minifiedImageUrl,
  });

  SyncMetadataModel getSyncMeta();
  Future<void> putSyncMeta(SyncMetadataModel meta);

  /// Clears all local boxes.
  Future<void> clearAllBeyDataBoxes();

  //Decks and Combos
  /// Retrieves all saved combos from local storage.
  List<ComboModel> getAllSavedCombos();

  /// Saves or updates a combo in local storage.
  Future<void> saveCombo(ComboModel combo);

  /// Deletes a combo from local storage by its ID.
  Future<void> deleteCombo(String id);

  /// Empties the combos, decks and deck slots boxes (another account
  /// signed in on this phone). The catalog is untouched.
  Future<void> clearCombosDecksAndSlots();
}

class BeybladeDataLocalDatasourceImpl implements BeybladeDataLocalDatasource {
  final String assetBasePath = AppConstants.beyBladePartsAssetpaths;
  static const _logName = '[BeyBlade LocalDS]';
  static const trackedBeyBladeData = AppConstants.trackedBeyBladeData;

//LOAD BEYBLADE DATA LOCALLY FROM JSON not including images
  @override
  Future<({Map<String, String> sheets, String manifestJson})>
      loadPartsDataBundle() async {
    dev.log('Loading metadata bundle from $assetBasePath...', name: _logName);
    try {
      final sheetResults =
          await Future.wait(trackedBeyBladeData.map((sheet) async {
        try {
          final text =
              await rootBundle.loadString('$assetBasePath/$sheet.json');
          dev.log('Loaded $sheet.json successfully (${text.length} chars)',
              name: _logName);
          return MapEntry(sheet, text);
        } catch (e, st) {
          dev.log(
              'CRITICAL: Missing or unreadable asset file: $assetBasePath/$sheet.json',
              name: _logName,
              error: e,
              stackTrace: st);
          rethrow;
        }
      }));

      // Stock combos and bladers ship in the bundle when the catalog has them; an app bundled before they
      // existed simply has none.
      for (final sheet in kBeybladeExtraSheets) {
        try {
          final text = await rootBundle.loadString('$assetBasePath/$sheet.json');
          sheetResults.add(MapEntry(sheet, text));
        } catch (_) {
          dev.log('No bundled $sheet.json (optional)', name: _logName);
        }
      }

      dev.log('Loading manifest.json...', name: _logName);
      final manifestJson =
          await rootBundle.loadString('$assetBasePath/manifest.json');
      dev.log('Bundle loaded fully.', name: _logName);

      return (
        sheets: Map.fromEntries(sheetResults),
        manifestJson: manifestJson
      );
    } catch (e, st) {
      dev.log('Failed to load entire metadata bundle',
          name: _logName, error: e, stackTrace: st, level: 1000);
      rethrow;
    }
  }

  final Box _deckSlotBox = sl<Box>(instanceName: AppConstants.deckSlotsBoxName);
  final Box _decksBox = sl<Box>(instanceName: AppConstants.decksBoxName);

  @override
  List<DeckModel> getAllDecks() => _decksBox.values
      .map((raw) => DeckModel.fromJson(Map<String, dynamic>.from(raw as Map)))
      .toList(growable: false);

  @override
  Future<void> saveDeck(DeckModel deck) =>
      _decksBox.put(deck.id, deck.toJson());

  @override
  Future<void> deleteDeck(String id) => _decksBox.delete(id);

  @override
  String? getDeckShareCode(int index) {
    final raw = _deckSlotBox.get(index.toString());
    return raw is String ? raw : null;
  }

  @override
  Future<void> saveDeckShareCode(int index, String shareCode) async {
    dev.log('$_logName Saving slot $index (${shareCode.length} chars)',
        name: _logName);
    await _deckSlotBox.put(index.toString(), shareCode);
  }

  @override
  Future<void> clearDeckSlot(int index) async {
    dev.log('$_logName Clearing slot $index', name: _logName);
    await _deckSlotBox.delete(index.toString());
  }

  //create the beyblade and give it shape:

  //BOXES FOR PART DATA
  final Box _blades = sl<Box>(instanceName: AppConstants.bladesBoxName);
  final Box _ratchets = sl<Box>(instanceName: AppConstants.ratchetsBoxName);
  final Box _bits = sl<Box>(instanceName: AppConstants.bitsBoxName);
  final Box _lockChips = sl<Box>(instanceName: AppConstants.lockChipsBoxName);
  final Box _overBlades = sl<Box>(instanceName: AppConstants.overBladesBoxName);
  final Box _metalBlades =
      sl<Box>(instanceName: AppConstants.metalBladesBoxName);
  final Box _mainBlades = sl<Box>(instanceName: AppConstants.mainBladesBoxName);
  final Box _assistBlades =
      sl<Box>(instanceName: AppConstants.assistBladesBoxName);
  final Box _products = sl<Box>(instanceName: AppConstants.productsBoxName);
  final Box _productContents =
      sl<Box>(instanceName: AppConstants.productContentsBoxName);
  final Box _accessories =
      sl<Box>(instanceName: AppConstants.accessoriesBoxName);
  final Box _syncMeta = sl<Box>(instanceName: AppConstants.syncMetaBoxName);

  //KEYS
  final String _syncMetaKey = AppConstants.syncMetaKey;

  T _parseRowUtil<T>(
      dynamic raw, T Function(Map<String, dynamic>) parser, String modelName) {
    try {
      return parser(_asStringKeyedMapUtil(raw));
    } catch (e, st) {
      dev.log('Failed to parse $modelName',
          name: _logName, error: e, stackTrace: st, level: 1000);
      dev.log('CRASHING ROW DATA: $raw', name: _logName, level: 1000);
      rethrow;
    }
  }

  //standard part data getters:

  // --- GETTERS ---
  @override
  List<BladeModel> getAllBlades() => _blades.values
      .map((raw) => _parseRowUtil(raw, BladeModel.fromSheetJson, 'BladeModel'))
      .toList(growable: false);

  @override
  BladeModel? getBlade(String dataId) {
    final raw = _blades.get(dataId);
    return raw == null
        ? null
        : _parseRowUtil(raw, BladeModel.fromSheetJson, 'BladeModel');
  }

  @override
  List<RatchetModel> getAllRatchets() => _ratchets.values
      .map((raw) =>
          _parseRowUtil(raw, RatchetModel.fromSheetJson, 'RatchetModel'))
      .toList(growable: false);

  @override
  RatchetModel? getRatchet(String dataId) {
    final raw = _ratchets.get(dataId);
    return raw == null
        ? null
        : _parseRowUtil(raw, RatchetModel.fromSheetJson, 'RatchetModel');
  }

  @override
  List<BitModel> getAllBits() => _bits.values
      .map((raw) => _parseRowUtil(raw, BitModel.fromSheetJson, 'BitModel'))
      .toList(growable: false);

  @override
  BitModel? getBit(String dataId) {
    final raw = _bits.get(dataId);
    return raw == null
        ? null
        : _parseRowUtil(raw, BitModel.fromSheetJson, 'BitModel');
  }

  @override
  List<LockChipModel> getAllLockChips() => _lockChips.values
      .map((raw) =>
          _parseRowUtil(raw, LockChipModel.fromSheetJson, 'LockChipModel'))
      .toList(growable: false);

  @override
  LockChipModel? getLockChip(String dataId) {
    final raw = _lockChips.get(dataId);
    return raw == null
        ? null
        : _parseRowUtil(raw, LockChipModel.fromSheetJson, 'LockChipModel');
  }

  @override
  List<OverBladeModel> getAllOverBlades() => _overBlades.values
      .map((raw) =>
          _parseRowUtil(raw, OverBladeModel.fromSheetJson, 'OverBladeModel'))
      .toList(growable: false);

  @override
  OverBladeModel? getOverBlade(String dataId) {
    final raw = _overBlades.get(dataId);
    return raw == null
        ? null
        : _parseRowUtil(raw, OverBladeModel.fromSheetJson, 'OverBladeModel');
  }

  @override
  List<MetalBladeModel> getAllMetalBlades() => _metalBlades.values
      .map((raw) =>
          _parseRowUtil(raw, MetalBladeModel.fromSheetJson, 'MetalBladeModel'))
      .toList(growable: false);

  @override
  MetalBladeModel? getMetalBlade(String dataId) {
    final raw = _metalBlades.get(dataId);
    return raw == null
        ? null
        : _parseRowUtil(raw, MetalBladeModel.fromSheetJson, 'MetalBladeModel');
  }

  @override
  List<MainBladeModel> getAllMainBlades() => _mainBlades.values
      .map((raw) =>
          _parseRowUtil(raw, MainBladeModel.fromSheetJson, 'MainBladeModel'))
      .toList(growable: false);

  @override
  MainBladeModel? getMainBlade(String dataId) {
    final raw = _mainBlades.get(dataId);
    return raw == null
        ? null
        : _parseRowUtil(raw, MainBladeModel.fromSheetJson, 'MainBladeModel');
  }

  @override
  List<AssistBladeModel> getAllAssistBlades() => _assistBlades.values
      .map((raw) => _parseRowUtil(
          raw, AssistBladeModel.fromSheetJson, 'AssistBladeModel'))
      .toList(growable: false);

  @override
  AssistBladeModel? getAssistBlade(String dataId) {
    final raw = _assistBlades.get(dataId);
    return raw == null
        ? null
        : _parseRowUtil(
            raw, AssistBladeModel.fromSheetJson, 'AssistBladeModel');
  }

  @override
  List<ProductModel> getAllProducts() => _products.values
      .map((raw) =>
          _parseRowUtil(raw, ProductModel.fromSheetJson, 'ProductModel'))
      .toList(growable: false);

  @override
  ProductModel? getProduct(String productId) {
    final raw = _products.get(productId);
    return raw == null
        ? null
        : _parseRowUtil(raw, ProductModel.fromSheetJson, 'ProductModel');
  }

  /// ProductContents has no dataId of its own -- rows are grouped and
  /// stored under their productId, so this reads the whole list for one
  /// product in a single box access rather than scanning every row.
  ///
  @override
  List<ProductContentModel> getContentsForProduct(String productId) {
    final raw = _productContents.get(productId);
    if (raw == null) return const [];
    final list = raw as List;
    return list
        .map((r) => _parseRowUtil(
            r, ProductContentModel.fromSheetJson, 'ProductContentModel'))
        .toList(growable: false);
  }

  /// Every ProductContent row across every product -- needed for the
  /// reverse lookup (given a part, which products contain it), since
  /// storage is grouped by productId with no per-part index. Fine to
  /// scan in full at this data scale.
  ///
  @override
  List<ProductContentModel> getAllProductContents() {
    final all = <ProductContentModel>[];
    for (final raw in _productContents.values) {
      final list = raw as List;
      all.addAll(list.map((r) => _parseRowUtil(
          r, ProductContentModel.fromSheetJson, 'ProductContentModel')));
    }
    return all;
  }

  @override
  List<AccessoryModel> getAllAccessories() => _accessories.values
      .map((raw) =>
          _parseRowUtil(raw, AccessoryModel.fromSheetJson, 'AccessoryModel'))
      .toList(growable: false);

  @override
  AccessoryModel? getAccessory(String dataId) {
    final raw = _accessories.get(dataId);
    return raw == null
        ? null
        : _parseRowUtil(raw, AccessoryModel.fromSheetJson, 'AccessoryModel');
  }

  /// Updates just the two image fields on an already-stored row, by
  /// mutating the raw stored map directly -- there's no toJson() on any
  /// model to reconstruct a full row from, and adding one solely for a
  /// two-field update would be more machinery than this needs. Silently
  /// does nothing if the row doesn't exist.
  ///
  @override
  Future<void> updateImagePaths(
    String sheetShortKey,
    String dataId, {
    String? imageUrl,
    String? minifiedImageUrl,
  }) async {
    final box = _boxForShortKey(sheetShortKey);
    if (box == null) {
      dev.log('updateImagePaths: unknown sheet "$sheetShortKey"',
          name: _logName);
      return;
    }
    final raw = box.get(dataId);
    if (raw == null) return;
    final row = _asStringKeyedMapUtil(raw);
    if (imageUrl != null) row['imageUrl'] = imageUrl;
    if (minifiedImageUrl != null) row['minifiedImageUrl'] = minifiedImageUrl;
    await box.put(dataId, row);
  }

  Box? _boxForShortKey(String sheetShortKey) => switch (sheetShortKey) {
        'blades' => _blades,
        'ratchets' => _ratchets,
        'bits' => _bits,
        'lockChips' => _lockChips,
        'overBlades' => _overBlades,
        'metalBlades' => _metalBlades,
        'mainBlades' => _mainBlades,
        'assistBlades' => _assistBlades,
        'products' => _products,
        'accessories' => _accessories,
        _ => null,
      };

  // --- SETTERS ---

  Map<String, Map<String, dynamic>> _mapByDataId(
      Iterable<Map<String, dynamic>> rows, String sheetName) {
    final mapped = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      try {
        mapped[requiredString(r, 'dataID')] = r;
      } catch (e, st) {
        dev.log('Missing dataID during putAll for $sheetName! Row: $r',
            name: _logName, error: e, stackTrace: st);
        rethrow;
      }
    }
    return mapped;
  }

  @override
  Future<void> putBlades(Iterable<Map<String, dynamic>> rows) async {
    dev.log('Writing ${rows.length} rows to Blades box', name: _logName);
    await _blades.putAll(_mapByDataId(rows, 'blades'));
  }

  @override
  Future<void> putRatchets(Iterable<Map<String, dynamic>> rows) async {
    dev.log('Writing ${rows.length} rows to Ratchets box', name: _logName);
    await _ratchets.putAll(_mapByDataId(rows, 'ratchets'));
  }

  @override
  Future<void> putBits(Iterable<Map<String, dynamic>> rows) async {
    dev.log('Writing ${rows.length} rows to Bits box', name: _logName);
    await _bits.putAll(_mapByDataId(rows, 'bits'));
  }

  @override
  Future<void> putLockChips(Iterable<Map<String, dynamic>> rows) async {
    dev.log('Writing ${rows.length} rows to LockChips box', name: _logName);
    await _lockChips.putAll(_mapByDataId(rows, 'lockChips'));
  }

  @override
  Future<void> putOverBlades(Iterable<Map<String, dynamic>> rows) async {
    dev.log('Writing ${rows.length} rows to OverBlades box', name: _logName);
    await _overBlades.putAll(_mapByDataId(rows, 'overBlades'));
  }

  @override
  Future<void> putMetalBlades(Iterable<Map<String, dynamic>> rows) async {
    dev.log('Writing ${rows.length} rows to MetalBlades box', name: _logName);
    await _metalBlades.putAll(_mapByDataId(rows, 'metalBlades'));
  }

  @override
  Future<void> putMainBlades(Iterable<Map<String, dynamic>> rows) async {
    dev.log('Writing ${rows.length} rows to MainBlades box', name: _logName);
    await _mainBlades.putAll(_mapByDataId(rows, 'mainBlades'));
  }

  @override
  Future<void> putAssistBlades(Iterable<Map<String, dynamic>> rows) async {
    dev.log('Writing ${rows.length} rows to AssistBlades box', name: _logName);
    await _assistBlades.putAll(_mapByDataId(rows, 'assistBlades'));
  }

  @override
  Future<void> putProducts(Iterable<Map<String, dynamic>> rows) async {
    dev.log('Writing ${rows.length} rows to Products box', name: _logName);
    await _products.putAll(_mapByProductId(rows, 'products'));
  }

  Map<String, Map<String, dynamic>> _mapByProductId(
      Iterable<Map<String, dynamic>> rows, String sheetName) {
    final mapped = <String, Map<String, dynamic>>{};
    for (final r in rows) {
      try {
        mapped[requiredString(r, 'productID')] = r;
      } catch (e, st) {
        dev.log('Missing productID during putAll for $sheetName! Row: $r',
            name: _logName, error: e, stackTrace: st);
        rethrow;
      }
    }
    return mapped;
  }

  /// Groups incoming rows by productId before storing -- ProductContents
  /// has no dataId of its own, and every real lookup is "give me this
  /// product's contents", never "give me one content row by its own id".
  ///
  @override
  Future<void> putProductContents(Iterable<Map<String, dynamic>> rows) async {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final r in rows) {
      try {
        grouped.putIfAbsent(requiredString(r, 'productID'), () => []).add(r);
      } catch (e, st) {
        dev.log('Missing productID during putAll for productContents! Row: $r',
            name: _logName, error: e, stackTrace: st);
        rethrow;
      }
    }
    dev.log(
        'Writing ${grouped.length} product(s) worth of contents to ProductContents box',
        name: _logName);
    await _productContents.putAll(grouped);
  }

  @override
  Future<void> putAccessories(Iterable<Map<String, dynamic>> rows) async {
    dev.log('Writing ${rows.length} rows to Accessories box', name: _logName);
    await _accessories.putAll(_mapByDataId(rows, 'accessories'));
  }

  @override
  SyncMetadataModel getSyncMeta() {
    final raw = _syncMeta.get(_syncMetaKey);
    if (raw == null) {
      dev.log('getSyncMeta: No existing metadata found, returning initial',
          name: _logName);
      return SyncMetadataModel.initial();
    }
    return _parseRowUtil(raw, SyncMetadataModel.fromJson, 'SyncMetadataModel');
  }

  @override
  Future<void> putSyncMeta(SyncMetadataModel meta) async {
    dev.log('putSyncMeta: Saving updated metadata', name: _logName);
    await _syncMeta.put(_syncMetaKey, meta.toJson());
  }

  @override
  Future<void> clearAllBeyDataBoxes() async {
    dev.log('clearAll: Emptying all local boxes', name: _logName);
    await Future.wait([
      _blades.clear(),
      _ratchets.clear(),
      _bits.clear(),
      _lockChips.clear(),
      _overBlades.clear(),
      _metalBlades.clear(),
      _assistBlades.clear(),
      _mainBlades.clear(),
      _products.clear(),
      _productContents.clear(),
      _accessories.clear(),
      _syncMeta.clear(),
    ]);
  }

  //Combos
  //combo box
  final Box _comboBox = sl<Box>(instanceName: AppConstants.combosBoxName);

  @override
  List<ComboModel> getAllSavedCombos() => _comboBox.values
      .map((raw) => ComboModel.fromJson(Map<String, dynamic>.from(raw as Map)))
      .toList(growable: false);

  @override
  Future<void> saveCombo(ComboModel combo) =>
      _comboBox.put(combo.id, combo.toJson());

  @override
  Future<void> deleteCombo(String id) => _comboBox.delete(id);

  @override
  Future<void> clearCombosDecksAndSlots() async {
    await Future.wait([
      _comboBox.clear(),
      _decksBox.clear(),
      _deckSlotBox.clear(),
    ]);
  }
}

Map<String, dynamic> _asStringKeyedMapUtil(dynamic raw) {
  try {
    return Map<String, dynamic>.from(raw as Map);
  } catch (e, st) {
    dev.log('Type cast failed: Expected Map but got ${raw.runtimeType}',
        name: 'Beyblade.Local', error: e, stackTrace: st);
    rethrow;
  }
}
