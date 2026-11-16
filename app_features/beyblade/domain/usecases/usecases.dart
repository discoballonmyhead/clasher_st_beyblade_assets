import 'dart:developer' as dev;
import 'dart:io';

import 'package:background_downloader/background_downloader.dart';
import 'package:clasher_st/core/errors/exceptions.dart';
import 'package:clasher_st/core/services/asset_download_servoce/asset_download_service.dart';
import 'package:clasher_st/core/services/inflight_download_service/inflight_download_service.dart';
import 'package:clasher_st/features/beyblade/domain/engines/beyblade_stats_calculator.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/domain/repositories/beyblade_data_repo.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/asset_download_cubit/asset_download_state.dart';
import 'package:path_provider/path_provider.dart';

// ── RESOLVE BEYBLADE ─────────────────────────────────────────────

class ResolveBeybladeUseCase {
  const ResolveBeybladeUseCase(this._repository,
      [this._calculator = const BeybladeStatsCalculator()]);

  final BeybladeDataRepo _repository;

  final BeybladeStatsCalculator _calculator;

  Future<Beyblade?> call(BeybladeLoadout loadout) async {
    final bit = await _repository.getBitByDataId(loadout.bitDataId);

    if (bit == null) return null;

    final ratchet = loadout.ratchetDataId == null
        ? null
        : await _repository.getRatchetByDataId(loadout.ratchetDataId!);

    final assembly = await _resolveAssembly(loadout);

    if (assembly == null) return null;

    final allParts = [...assembly.parts, if (ratchet != null) ratchet, bit];

    return Beyblade(
      loadout: loadout,
      assembly: assembly,
      ratchet: ratchet,
      bit: bit,
      combinedStats: _calculator.combine(allParts),
      totalMass: _calculator.totalMass(allParts),
      archetype: bit.movementStyle,
      spinDirection: _spinDirectionOf(assembly),
      legality: _worstLegality(allParts.map((p) => p.legality)),
    );
  }

  Future<BladeAssembly?> _resolveAssembly(BeybladeLoadout loadout) async {
    if (loadout.bladeDataId != null) {
      final blade = await _repository.getBladeByDataId(loadout.bladeDataId!);

      return blade == null ? null : UnibodyAssembly(blade);
    }

    final lockChipId = loadout.lockChipDataId;

    final assistBladeId = loadout.assistBladeDataId;

    if (lockChipId == null || assistBladeId == null) return null;

    final lockChip = await _repository.getLockChipByDataId(lockChipId);

    final assistBlade = await _repository.getAssistBladeByDataId(assistBladeId);

    if (lockChip == null || assistBlade == null) return null;

    final core = await _resolveCore(loadout);

    if (core == null) return null;

    return SeparatedAssembly(
        lockChip: lockChip, core: core, assistBlade: assistBlade);
  }

  Future<BladeCore?> _resolveCore(BeybladeLoadout loadout) async {
    if (loadout.mainBladeDataId != null) {
      final mainBlade =
          await _repository.getMainBladeByDataId(loadout.mainBladeDataId!);

      return mainBlade == null ? null : MainCore(mainBlade);
    }

    if (loadout.overBladeDataId != null && loadout.metalBladeDataId != null) {
      final overBlade =
          await _repository.getOverBladeByDataId(loadout.overBladeDataId!);

      final metalBlade =
          await _repository.getMetalBladeByDataId(loadout.metalBladeDataId!);

      return (overBlade == null || metalBlade == null)
          ? null
          : OverMetalCore(overBlade: overBlade, metalBlade: metalBlade);
    }

    return null;
  }

  SpinDirection _spinDirectionOf(BladeAssembly assembly) => switch (assembly) {
        UnibodyAssembly(:final blade) => blade.spinDirection,
        SeparatedAssembly(:final core) => switch (core) {
            OverMetalCore(:final overBlade) => overBlade.spinDirection,
            MainCore(:final mainBlade) => mainBlade.spinDirection,
          },
      };

  WboLegality _worstLegality(Iterable<WboLegality> values) {
    if (values.any((v) => v == WboLegality.illegal)) return WboLegality.illegal;

    if (values.any((v) => v == WboLegality.unknown)) return WboLegality.unknown;

    return WboLegality.legal;
  }
}

// ── SEARCH BEYBLADE PARTS ────────────────────────────────────────

class SearchBeybladePartsUseCase {
  const SearchBeybladePartsUseCase(this._repository);

  final BeybladeDataRepo _repository;

  Future<List<BeybladePart>> call(String query) =>
      _repository.searchBeyParts(query);
}

// ── SYNC USE CASES ───────────────────────────────────────────────────────────

class SyncBeybladeDataUseCase {
  const SyncBeybladeDataUseCase(this._repository);

  final BeybladeDataRepo _repository;

  Future<bool> hasAvailableData() => _repository.hasAvailData();

  Future<SyncMetadata> getSyncMetadata() => _repository.getSyncData();

  Stream<SyncProgress> executeSync() => _repository.loadMewBeyundle();

  Stream<SyncProgress> applyCatalog(
    Map<String, String> sheets, {
    required String version,
    required String sha256,
  }) =>
      _repository.applyCatalogSheets(sheets, version: version, sha256: sha256);
}

// ── COMBOS USE CASES ─────────────────────────────────────────────────────────

class ManageCombosUseCase {
  const ManageCombosUseCase(this._repository);

  final BeybladeDataRepo _repository;

  Future<List<Combo>> getAllCombos() => _repository.getAllCombos();

  Future<Combo> createCombo(String name, BeybladeLoadout loadout) =>
      _repository.createCombo(name, loadout);

  Future<void> deleteCombo(String id) => _repository.deleteCombo(id);
}

// ── DECKS USE CASES ──────────────────────────────────────────────────────────

class ManageDecksUseCase {
  const ManageDecksUseCase(this._repository);

  final BeybladeDataRepo _repository;

  Future<List<Deck>> getAllDecks() => _repository.getAllDecks();

  Future<Deck> createDeck(String name, List<String> comboIds) =>
      _repository.createDeck(name, comboIds);

  Future<void> deleteDeck(String id) => _repository.deleteDeck(id);
}

// ── DECK SLOTS USE CASES ─────────────────────────────────────────────────────

class ManageDeckSlotsUseCase {
  const ManageDeckSlotsUseCase(this._repository);

  final BeybladeDataRepo _repository;

  Future<List<DeckSlot>> getAllDeckSlots() => _repository.getAllDeckSlots();

  Future<void> saveDeckSlot(int index, BeybladeLoadout loadout) =>
      _repository.saveDeckSlot(index, loadout);

  Future<void> clearDeckSlot(int index) => _repository.clearDeckSlot(index);
}

// ── PRODUCT & PART DETAILS USE CASES ─────────────────────────────────────────

class GetProductDetailsUseCase {
  const GetProductDetailsUseCase(this._repository);

  final BeybladeDataRepo _repository;

  Future<Product?> getProduct(String productId) =>
      _repository.getProductByProductId(productId);

  Future<List<ProductContent>> getProductContents(String productId) =>
      _repository.getContentsForProduct(productId);

  /// The combos that come out of the box.
  Future<List<StockCombo>> getStockCombos(String productId) =>
      _repository.getStockCombosForProduct(productId);
}

class GetPartDetailsUseCase {
  const GetPartDetailsUseCase(this._repository);

  final BeybladeDataRepo _repository;

  Future<BeybladePart?> getPart(String partTypeKey, String dataId) =>
      _repository.getPartByTypeAndDataId(partTypeKey, dataId);

  Future<List<BeybladePart>> getVariants(String partTypeKey, String dataId) =>
      _repository.getVariantGroup(partTypeKey, dataId);

  Future<List<ProductContent>> getIncludedInProducts(
          String partTypeKey, String dataId) =>
      _repository.getProductContentsForItem(partTypeKey, dataId);

  /// The out-of-the-box combos this part is in.
  Future<List<StockCombo>> getStockCombos(String partTypeKey, String dataId) =>
      _repository.getStockCombosForPart(partTypeKey, dataId);

  /// Who uses the part in the show.
  Future<List<Blader>> getBladers(BeybladePart part) =>
      _repository.getBladersForPart(part);
}

/// Bladers (characters) and the parts they use.
class GetBladersUseCase {
  const GetBladersUseCase(this._repository);

  final BeybladeDataRepo _repository;

  Future<List<Blader>> all() => _repository.getAllBladers();
  Future<Blader?> byId(String bladerId) => _repository.getBladerById(bladerId);
  Future<List<(String, BeybladePart)>> partsOf(String bladerId) =>
      _repository.getPartsForBlader(bladerId);
}

class DownloadGenerationAssetsUseCase {
  const DownloadGenerationAssetsUseCase({
    required this.downloadService,
    required this.dataRepository,
    required this.tracker,
  });

  final AssetDownloadService downloadService;

  final BeybladeDataRepo dataRepository;

  final InFlightDownloadsService tracker;

  static const _logName = 'DownloadAssetsUseCase';

  Future<void> call({
    required String generation,
    required String releaseTag,
    required void Function(AssetDownloadPhase phase) onPhaseChanged,
    required void Function(double progress) onProgress,
  }) async {
    final taskId =
        'beyblade_images_${generation}_${DateTime.now().millisecondsSinceEpoch}';

    try {
      dev.log('Fetching release assets for $releaseTag...', name: _logName);

      onPhaseChanged(AssetDownloadPhase.fetchingReleaseInfo);

      // 1. Check Github

      final assets = await downloadService.fetchReleaseAssets(releaseTag);

      final asset = downloadService.findAssetForGeneration(assets, generation);

      if (asset == null) {
        throw AssetDownloadException(
            'No image pack found for "$generation" on release "$releaseTag".');
      }

      // 2. Register Sticky Note

      dev.log('Marking task $taskId as started in tracker', name: _logName);

      await tracker.markStarted(taskId, generation);

      // 3. Download

      onPhaseChanged(AssetDownloadPhase.downloading);

      final zipFile = await downloadService.downloadAsset(
        asset: asset,
        taskId: taskId,
        onProgress: onProgress,
        onStatus: (s) => dev.log('Download status: $s', name: _logName),
      );

      // 4. Unzip & Map

      onPhaseChanged(AssetDownloadPhase.extracting);

      final pathsByKey =
          await downloadService.extractAndMap(zipFile, generation);

      // 5. Save to Local Database

      onPhaseChanged(AssetDownloadPhase.updatingLocalData);

      await dataRepository.applyLocalBeyImagePaths(pathsByKey);

      // 6. Clean up sticky note

      await tracker.markDone(taskId);

      onPhaseChanged(AssetDownloadPhase.completed);

      dev.log('Successfully completed entire asset pipeline for $generation',
          name: _logName);
    } catch (e, st) {
      dev.log('Pipeline failed', name: _logName, error: e, stackTrace: st);

      // Clean up the sticky note so we don't end up with a zombie task

      await tracker.markDone(taskId);

      rethrow;
    }
  }
}

// Import your services and repos here...

/// Call ONCE at app startup via [ResumeInFlightDownloadsUseCase.call()].

/// This is what actually makes InFlightDownloadsTracker mean

/// something, rather than just being a record nothing ever reads.

class ResumeInFlightDownloadsUseCase {
  const ResumeInFlightDownloadsUseCase({
    required this.downloadService,
    required this.dataRepository,
    required this.tracker,
  });

  final AssetDownloadService downloadService;

  final BeybladeDataRepo dataRepository;

  final InFlightDownloadsService tracker;

  static const _logName = 'ResumeDownloadsUseCase';

  void call() {
    // Note: We are calling this on the injected instance, not statically!

    downloadService.registerForAppRestart(
      onStatusUpdate: (taskId, status) async {
        final generation = tracker.generationFor(taskId);

        if (generation == null) return; // not one of ours, or already handled

        dev.log(
            'Resumed task $taskId (generation "$generation") reported status: $status',
            name: _logName);

        if (status != TaskStatus.complete) {
          // Still running, or ended in a state that isn't "done" (failed,

          // canceled) -- leave the tracker entry as-is either way. A

          // still-running task will report again later; a failed one is

          // deliberately left recorded rather than silently cleared, so

          // it's at least visible (via allInFlight()) that something

          // didn't finish, instead of disappearing with no trace.

          return;
        }

        try {
          // The file should already be on disk at the same path it would

          // have been if the download had finished normally -- background_

          // downloader's own guarantee, not something reconstructed here.

          final safeName = generation.replaceAll(' ', '_').replaceAll('/', '_');

          final appSupportDir = await getApplicationSupportDirectory();

          // Must match the subDirectory defined in AssetDownloadServiceImpl.downloadAsset

          final expectedPath =
              '${appSupportDir.path}/beyblade_downloads/beyblade_images_$safeName.zip';

          final zipFile = File(expectedPath);

          if (!await zipFile.exists()) {
            dev.log(
                'Resumed task $taskId completed but expected file not found at $expectedPath',
                name: _logName);

            return;
          }

          // Finish the processing pipeline

          final pathsByKey =
              await downloadService.extractAndMap(zipFile, generation);

          await dataRepository.applyLocalBeyImagePaths(pathsByKey);

          // Clean up the sticky note

          await tracker.markDone(taskId);

          dev.log(
              'Resumed task $taskId (generation "$generation") finished processing successfully',
              name: _logName);
        } catch (e, st) {
          dev.log('Failed to finish processing resumed task $taskId',
              name: _logName, error: e, stackTrace: st);

          // Deliberately not marking done -- leaves it recorded as still

          // unresolved rather than silently dropping a failure.
        }
      },

      onProgressUpdate: (_, __) {}, // no UI to report progress to at this point
    );
  }
}
