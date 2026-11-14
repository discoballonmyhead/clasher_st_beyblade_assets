import 'dart:developer' as dev;

import 'package:clasher_st/core/constants/app_constants.dart';
import 'package:clasher_st/core/init_injection/injection.dart';
import 'package:clasher_st/features/beyblade/data/dsrces/beyblade_ldsrc.dart';
import 'package:clasher_st/features/beyblade/data/isolates/beyblade_bundle_parser.dart';
import 'package:clasher_st/features/beyblade/data/models/models.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/domain/repositories/beyblade_data_repo.dart';
import 'package:flutter/foundation.dart';

class BeyDataRepoImpl implements BeybladeDataRepo {
  BeyDataRepoImpl(this._ldsrc);

  final BeybladeDataLocalDatasource _ldsrc;

  /// Combos, decks and deck slots are saved on the phone first, then
  /// queued for the account. Looked up per call: the collection feature
  /// registers it after this repo exists.
  ComboSyncOutbox get _outbox => sl.isRegistered<ComboSyncOutbox>()
      ? sl<ComboSyncOutbox>()
      : const NoComboSyncOutbox();

  /// A failed queue never undoes the local save: the change stays on the
  /// phone and goes up with the next full upload.
  Future<void> _queue(Future<void> Function(ComboSyncOutbox o) send) async {
    try {
      await send(_outbox);
    } catch (e) {
      dev.log('Could not queue combo/deck change: $e', name: 'BeyDataRepo');
    }
  }

//Beyblade sync

  @override
  Future<bool> hasAvailData() async =>
      _ldsrc.getSyncMeta().toEntity().hasMetadata;

  @override
  Future<SyncMetadata> getSyncData() async => _ldsrc.getSyncMeta().toEntity();

  @override
  Stream<SyncProgress> loadMewBeyundle() async* {
    final Map<String, String> sheets;
    yield const SyncStarted(); // start the sync and show if its completed or failed
    try {
      sheets = (await _ldsrc.loadPartsDataBundle()).sheets;
    } catch (e) {
      yield SyncFailed(message: e.toString());

      return;
    }

    yield* applyCatalogSheets(sheets, version: 'bundled');
  }

  @override
  Stream<SyncProgress> applyCatalogSheets(
    Map<String, String> sheets, {
    String? version,
    String? sha256,
  }) async* {
    yield const SyncStarted();

    try {
      // Parse BEFORE touching the boxes. A malformed download then fails

      // here with the old catalog still fully intact, instead of halfway

      // through a replace.

      yield const SyncInProgress(fraction: 0.3, message: 'Reading part data…');

      final parsed = await compute(parseMetadataSheets, sheets);

      // An empty result is a broken release, not an empty catalog. Wiping

      // every part the user can see because of it would be far worse

      // than keeping yesterday's data.

      if (parsed.totalRecords == 0) {
        throw StateError(
            'The catalog contained no parts; keeping the current data.');
      }

      yield const SyncInProgress(fraction: 0.6, message: 'Saving part data…');

      // Full replace, not upsert: putAll alone would leave behind any part

      // a newer catalog removed or renumbered. The clear also wipes the

      // sync metadata, so if the app dies between here and putSyncMeta,

      // the next launch sees "not loaded" and reloads the bundled catalog

      // rather than trusting half-written boxes.

      await _ldsrc.clearAllBeyDataBoxes();

      await Future.wait([
        _ldsrc.putBlades(parsed.blades),
        _ldsrc.putRatchets(parsed.ratchets),
        _ldsrc.putBits(parsed.bits),
        _ldsrc.putLockChips(parsed.lockChips),
        _ldsrc.putOverBlades(parsed.overBlades),
        _ldsrc.putMetalBlades(parsed.metalBlades),
        _ldsrc.putMainBlades(parsed.mainBlades),
        _ldsrc.putAssistBlades(parsed.assistBlades),
        _ldsrc.putProducts(parsed.products),
        _ldsrc.putAccessories(parsed.accessories),
        _ldsrc.putProductContents(parsed.productContents),
      ]);

      await _ldsrc.putSyncMeta(
        SyncMetadataModel(
          lastMetadataSyncAtMillis: DateTime.now().millisecondsSinceEpoch,
          catalogVersion: version,
          catalogSha256: sha256,
        ),
      );

      yield SyncCompleted(
          summary: SyncSummary(
              totalRecords: parsed.totalRecords, syncedAt: DateTime.now()));
    } catch (e) {
      yield SyncFailed(message: e.toString());
    }
  }

//Combo REpo IML

  @override
  Future<List<Combo>> getAllCombos() async =>
      _ldsrc.getAllSavedCombos().map((m) => m.toEntity()).toList();

  @override
  Future<Combo> createCombo(String name, BeybladeLoadout loadout) async {
    final model = ComboModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      loadout: loadout,
      createdAtMillis: DateTime.now().millisecondsSinceEpoch,
    );

    await _ldsrc.saveCombo(model);
    await _queue((o) => o.upsertCombo(model.toJson()));

    return model.toEntity();
  }

  @override
  Future<void> deleteCombo(String id) async {
    await _ldsrc.deleteCombo(id);
    // Same as the server does on delete: decks drop the dead combo.
    for (final deck in _ldsrc.getAllDecks()) {
      if (!deck.comboIds.contains(id)) continue;
      await _ldsrc.saveDeck(DeckModel(
        id: deck.id,
        name: deck.name,
        comboIds: [
          for (final c in deck.comboIds)
            if (c != id) c
        ],
        createdAtMillis: deck.createdAtMillis,
      ));
    }
    await _queue((o) => o.delete('combos', id));
  }

  //decks

  @override
  Future<List<Deck>> getAllDecks() async =>
      _ldsrc.getAllDecks().map((m) => m.toEntity()).toList();

  @override
  Future<Deck> createDeck(String name, List<String> comboIds) async {
    final unique = comboIds.toSet();

    if (unique.length < 3) {
      throw ArgumentError(
          'A deck needs at least 3 unique combos (got ${unique.length}).');
    }

    final model = DeckModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      comboIds: comboIds,
      createdAtMillis: DateTime.now().millisecondsSinceEpoch,
    );

    await _ldsrc.saveDeck(model);
    await _queue((o) => o.upsertDeck(model.toJson()));

    return model.toEntity();
  }

  @override
  Future<void> deleteDeck(String id) async {
    await _ldsrc.deleteDeck(id);
    await _queue((o) => o.delete('decks', id));
  }

//DECK SLOTs

  @override
  Future<List<DeckSlot>> getAllDeckSlots() async => [
        for (var i = 0; i < AppConstants.slotCount; i++)
          DeckSlot(index: i, loadout: _decode(i, _ldsrc.getDeckShareCode(i))),
      ];

  BeybladeLoadout? _decode(int index, String? shareCode) {
    if (shareCode == null) return null;

    try {
      return BeybladeLoadout.fromShareCode(shareCode);
    } catch (e) {
      // Corrupted or otherwise unreadable stored code — treated as an

      // empty slot rather than crashing the whole slots screen over one

      // bad entry. Logged so it's not silently invisible either.

      dev.log('Slot $index has an unreadable share code, treating as empty');

      return null;
    }
  }

  @override
  Future<void> saveDeckSlot(int index, BeybladeLoadout loadout) async {
    final code = loadout.toShareCode();
    await _ldsrc.saveDeckShareCode(index, code);
    await _queue((o) => o.upsertDeckSlot(index, code));
  }

  @override
  Future<void> clearDeckSlot(int index) async {
    await _ldsrc.clearDeckSlot(index);
    await _queue((o) => o.delete('deckSlots', '$index'));
  }

  //Beybalde PArts

  @override
  Future<List<Blade>> getAllBlades() async =>
      _ldsrc.getAllBlades().map((m) => m.toEntity()).toList();

  @override
  Future<Blade?> getBladeByDataId(String dataId) async =>
      _ldsrc.getBlade(dataId)?.toEntity();

  @override
  Future<List<Ratchet>> getAllRatchets() async =>
      _ldsrc.getAllRatchets().map((m) => m.toEntity()).toList();

  @override
  Future<Ratchet?> getRatchetByDataId(String dataId) async =>
      _ldsrc.getRatchet(dataId)?.toEntity();

  @override
  Future<List<Bit>> getAllBits() async =>
      _ldsrc.getAllBits().map((m) => m.toEntity()).toList();

  @override
  Future<Bit?> getBitByDataId(String dataId) async =>
      _ldsrc.getBit(dataId)?.toEntity();

  @override
  Future<List<LockChip>> getAllLockChips() async =>
      _ldsrc.getAllLockChips().map((m) => m.toEntity()).toList();

  @override
  Future<LockChip?> getLockChipByDataId(String dataId) async =>
      _ldsrc.getLockChip(dataId)?.toEntity();

  @override
  Future<List<OverBlade>> getAllOverBlades() async =>
      _ldsrc.getAllOverBlades().map((m) => m.toEntity()).toList();

  @override
  Future<OverBlade?> getOverBladeByDataId(String dataId) async =>
      _ldsrc.getOverBlade(dataId)?.toEntity();

  @override
  Future<List<MetalBlade>> getAllMetalBlades() async =>
      _ldsrc.getAllMetalBlades().map((m) => m.toEntity()).toList();

  @override
  Future<MetalBlade?> getMetalBladeByDataId(String dataId) async =>
      _ldsrc.getMetalBlade(dataId)?.toEntity();

  @override
  Future<List<MainBlade>> getAllMainBlades() async =>
      _ldsrc.getAllMainBlades().map((m) => m.toEntity()).toList();

  @override
  Future<MainBlade?> getMainBladeByDataId(String dataId) async =>
      _ldsrc.getMainBlade(dataId)?.toEntity();

  @override
  Future<List<AssistBlade>> getAllAssistBlades() async =>
      _ldsrc.getAllAssistBlades().map((m) => m.toEntity()).toList();

  @override
  Future<AssistBlade?> getAssistBladeByDataId(String dataId) async =>
      _ldsrc.getAssistBlade(dataId)?.toEntity();

  @override
  Future<List<Product>> getAllProducts() async =>
      _ldsrc.getAllProducts().map((m) => m.toEntity()).toList();

  @override
  Future<Product?> getProductByProductId(String productId) async =>
      _ldsrc.getProduct(productId)?.toEntity();

  @override
  Future<List<ProductContent>> getContentsForProduct(String productId) async =>
      _ldsrc.getContentsForProduct(productId).map((m) => m.toEntity()).toList();

  @override
  Future<List<Accessory>> getAllAccessories() async =>
      _ldsrc.getAllAccessories().map((m) => m.toEntity()).toList();

  @override
  Future<Accessory?> getAccessoryByDataId(String dataId) async =>
      _ldsrc.getAccessory(dataId)?.toEntity();

  @override
  Future<void> applyLocalBeyImagePaths(Map<String, String> pathsByKey) async {
    for (final entry in pathsByKey.entries) {
      final (sheetShortKey, dataId, isMinified) = _parseImageKey(entry.key);

      if (sheetShortKey == null || dataId == null) continue;

      await _ldsrc.updateImagePaths(
        sheetShortKey,
        dataId,
        imageUrl: isMinified ? null : entry.value,
        minifiedImageUrl: isMinified ? entry.value : null,
      );
    }
  }

  /// Parses "blades-1" -> (sheetShortKey: "blades", dataId: "1", isMinified: false)

  /// and "blades-1-min" -> (sheetShortKey: "blades", dataId: "1", isMinified: true).

  /// Checks the "-min" suffix first, then splits on the FIRST remaining

  /// hyphen -- safe as long as sheet short keys themselves never contain

  /// a hyphen, which is true for every one in use today (blades,

  /// ratchets, overBlades, etc.).

  (String?, String?, bool) _parseImageKey(String key) {
    final isMinified = key.endsWith('-min');

    final base = isMinified ? key.substring(0, key.length - 4) : key;

    final firstHyphen = base.indexOf('-');

    if (firstHyphen == -1) return (null, null, false);

    return (
      base.substring(0, firstHyphen),
      base.substring(firstHyphen + 1),
      isMinified
    );
  }

  @override
  Future<List<BeybladePart>> searchBeyParts(String query) async {
    final q = query.trim().toLowerCase();

    if (q.isEmpty) return const [];

    final all = <BeybladePart>[
      ...await getAllBlades(),
      ...await getAllRatchets(),
      ...await getAllBits(),
      ...await getAllLockChips(),
      ...await getAllOverBlades(),
      ...await getAllMetalBlades(),
      ...await getAllMainBlades(),
      ...await getAllAssistBlades(),
    ];

    bool matches(BeybladePart p) =>
        p.code.toLowerCase().contains(q) || p.name.toLowerCase().contains(q);

    final results = all.where(matches).toList()
      ..sort((a, b) {
        final aStarts = a.name.toLowerCase().startsWith(q) ? 0 : 1;

        final bStarts = b.name.toLowerCase().startsWith(q) ? 0 : 1;

        final byStart = aStarts.compareTo(bStarts);

        return byStart != 0 ? byStart : a.name.compareTo(b.name);
      });

    return results;
  }

  @override
  Future<List<ProductContent>> getProductContentsForItem(
          String partType, String partDataId) async =>
      _ldsrc
          .getAllProductContents()
          .where((m) => m.partType == partType && m.partDataId == partDataId)
          .map((m) => m.toEntity())
          .toList();

  @override
  Future<BeybladePart?> getPartByTypeAndDataId(
      String partTypeKey, String dataId) async {
    switch (partTypeKey) {
      case 'blades':
        return getBladeByDataId(dataId);

      case 'ratchets':
        return getRatchetByDataId(dataId);

      case 'bits':
        return getBitByDataId(dataId);

      case 'lockChips':
        return getLockChipByDataId(dataId);

      case 'overBlades':
        return getOverBladeByDataId(dataId);

      case 'metalBlades':
        return getMetalBladeByDataId(dataId);

      case 'mainBlades':
        return getMainBladeByDataId(dataId);

      case 'assistBlades':
        return getAssistBladeByDataId(dataId);

      default:
        return null;
    }
  }

  Future<List<BeybladePart>> _getAllForType(String partTypeKey) async {
    switch (partTypeKey) {
      case 'blades':
        return getAllBlades();

      case 'ratchets':
        return getAllRatchets();

      case 'bits':
        return getAllBits();

      case 'lockChips':
        return getAllLockChips();

      case 'overBlades':
        return getAllOverBlades();

      case 'metalBlades':
        return getAllMetalBlades();

      case 'mainBlades':
        return getAllMainBlades();

      case 'assistBlades':
        return getAllAssistBlades();

      default:
        return <BeybladePart>[];
    }
  }

  @override
  Future<List<BeybladePart>> getVariantGroup(
      String partTypeKey, String dataId) async {
    final all = await _getAllForType(partTypeKey);

    final target = all.firstWhere((p) => p.dataId == dataId,
        orElse: () =>
            throw ArgumentError('No $partTypeKey with dataId $dataId'));

    final rootId = target.parentPartId ?? target.dataId;

    return all
        .where((p) => p.dataId == rootId || p.parentPartId == rootId)
        .toList();
  }
}
