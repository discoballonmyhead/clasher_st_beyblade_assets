import 'dart:async';

import 'package:clasher_st/core/errors/exceptions.dart';
import 'package:clasher_st/core/services/wakelock_service/beyblade_wake_lock_service.dart';
import 'package:clasher_st/features/beyblade/data/dsrces/beyblade_cat_remdsrc.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/domain/usecases/usecases.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/accessory_picker.dart';
import 'package:clasher_st/features/beyblade_tcg/beyblade_tcg.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'dart:developer' as dev;
import 'beyblade_sync_state.dart';

/// Outcome of one catalog update check, for the settings button.
enum CatalogCheckResult { updated, upToDate, noRelease, failed, skipped }

/// Owns the part catalog: making sure one exists locally, and replacing
/// it when a newer release is published.
///
/// Two separate guarantees, deliberately kept apart:
///   * [ensureFreshOnFirstVisit] — a usable catalog exists. Local only,
///     works offline, never waits on the network. The app needs this
///     before it can show parts at all.
///   * [checkForUpdates] — the catalog is current. Network, runs in the
///     background once per launch, and failing is harmless: the app keeps
///     whatever catalog it already has.
class BeybladeSyncCubit extends Cubit<BeybladeSyncState> {
  BeybladeSyncCubit({
    required SyncBeybladeDataUseCase syncUseCase,
    required BeybladeCatalogRemoteDataSource catalogRemote,
    TcgCatalog? tcgCatalog,
  })  : _syncUseCase = syncUseCase,
        _catalogRemote = catalogRemote,
        _tcgCatalog = tcgCatalog,
        super(const SyncIdle()) {
    dev.log('Initialized', name: _logName);
  }

  static const _logName = 'BeybladeSyncCubit';

  final SyncBeybladeDataUseCase _syncUseCase;
  final BeybladeCatalogRemoteDataSource _catalogRemote;

  /// Card game catalog; filled from the same download when the release
  /// has TCG sheets.
  final TcgCatalog? _tcgCatalog;

  bool _hasCheckedThisSession = false;
  bool _updateCheckedThisSession = false;
  bool _checkingForUpdate = false;

  SyncMetadata? _metadata;
  DateTime? _lastCheckedAt;
  String? _lastCheckMessage;

  /// What's in the boxes right now. Null until the first check reads it.
  SyncMetadata? get metadata => _metadata;
  DateTime? get lastCheckedAt => _lastCheckedAt;

  /// Human-readable result of the last update check: "Up to date",
  /// "Updated to …", or why it couldn't check. Shown in settings.
  String? get lastCheckMessage => _lastCheckMessage;

  bool get isCheckingForUpdate => _checkingForUpdate;

  // ── STARTUP ────────────────────────────────────────────────────────────────

  /// Called once from the splash screen.
  ///
  /// Returns as soon as a usable local catalog exists — the splash waits
  /// on this, and on a first launch that means the bundled JSON has been
  /// loaded. The update check is then started without being awaited, so
  /// a slow or absent network never holds the app on the splash screen.
  Future<void> startup() async {
    await ensureFreshOnFirstVisit();
    unawaited(checkForUpdates());
  }

  /// Makes sure SOME catalog is loaded. Safe to call from anywhere, any
  /// number of times: after the first call it returns immediately.
  Future<void> ensureFreshOnFirstVisit() async {
    if (_hasCheckedThisSession) return;
    _hasCheckedThisSession = true;

    final meta = await _syncUseCase.getSyncMetadata();
    _metadata = meta;
    if (meta.hasMetadata) {
      emit(SyncReady(checkedAt: _lastCheckedAt));
    } else {
      dev.log('No local catalog; loading the bundled one', name: _logName);
      await loadBundledMetadata();
    }
  }

  /// Loads the catalog shipped inside the app. Also the recovery path
  /// whenever the local catalog ends up unusable.
  Future<void> loadBundledMetadata() async {
    if (state is SyncRunning) return;
    await _run(stream: _syncUseCase.executeSync());
    _metadata = await _syncUseCase.getSyncMetadata();
  }

  // ── UPDATES ────────────────────────────────────────────────────────────────

  /// Asks the server whether a newer catalog is published and applies it
  /// if so.
  ///
  /// Background calls run at most once per launch. [userInitiated]
  /// (the settings button) always runs.
  ///
  /// Never emits [SyncError] while the existing catalog is still valid:
  /// the part search page treats that state as "no parts database" and
  /// replaces its whole UI with an error, which would be wrong when the
  /// only thing that failed was checking for something newer.
  Future<CatalogCheckResult> checkForUpdates({
    bool userInitiated = false,
  }) async {
    if (!userInitiated && _updateCheckedThisSession) {
      return CatalogCheckResult.skipped;
    }
    if (_checkingForUpdate || state is SyncRunning) {
      return CatalogCheckResult.skipped;
    }
    _updateCheckedThisSession = true;
    _checkingForUpdate = true;

    try {
      final release = await _catalogRemote.fetchLatestRelease();
      _lastCheckedAt = DateTime.now();

      if (release == null) {
        _lastCheckMessage = 'No catalog update has been published yet.';
        _emitReady();
        return CatalogCheckResult.noRelease;
      }

      final meta = await _syncUseCase.getSyncMetadata();
      _metadata = meta;
      if (meta.catalogSha256 == release.dataSha256) {
        _lastCheckMessage = 'Up to date (${release.version}).';
        _emitReady();
        return CatalogCheckResult.upToDate;
      }

      dev.log(
          'Catalog update: ${meta.catalogVersion ?? 'none'} -> ${release.version}',
          name: _logName);

      // Download and verify first. Nothing local is touched until the
      // file has passed its checksum and contains every sheet.
      final sheets = await _catalogRemote.downloadCatalogSheets(release);

      await _run(
        stream: _syncUseCase.applyCatalog(
          sheets,
          version: release.version,
          sha256: release.dataSha256,
        ),
      );

      _metadata = await _syncUseCase.getSyncMetadata();

      if (state is SyncFinished) {
        AccessoryCache.clear(); // stadium / launcher names from the new data
        // Never blocks the parts update: a bad TCG sheet only logs.
        try {
          await _tcgCatalog?.ingestSheets(sheets);
        } catch (e) {
          dev.log('TCG sheets not applied', name: _logName, error: e);
        }
        _lastCheckMessage = 'Updated to ${release.version}.';
        return CatalogCheckResult.updated;
      }

      await _recoverAfterFailedApply();
      _lastCheckMessage = 'The update could not be applied; kept current data.';
      return CatalogCheckResult.failed;
    } catch (e) {
      dev.log('Update check failed', name: _logName, error: e);
      _lastCheckedAt = DateTime.now();
      _lastCheckMessage = _describe(e);
      _emitReady();
      return CatalogCheckResult.failed;
    } finally {
      _checkingForUpdate = false;
    }
  }

  /// A failed apply either failed before touching the boxes (bad parse,
  /// empty catalog), leaving the old catalog intact, or failed after the
  /// clear, leaving nothing. The sync metadata tells them apart, because
  /// the clear wipes it and only a completed apply writes it back.
  Future<void> _recoverAfterFailedApply() async {
    final meta = await _syncUseCase.getSyncMetadata();
    _metadata = meta;
    if (meta.hasMetadata) {
      emit(SyncReady(checkedAt: _lastCheckedAt));
    } else {
      dev.log('Apply left no catalog; restoring the bundled one',
          name: _logName);
      await loadBundledMetadata();
    }
  }

  /// Only replaces a steady state. If the local catalog itself is broken
  /// (SyncError from the bundled load) or still loading, that state is
  /// the more important thing to show and stays put.
  void _emitReady() {
    if (state is SyncReady || state is SyncFinished || state is SyncIdle) {
      emit(SyncReady(checkedAt: _lastCheckedAt));
    }
  }

  String _describe(Object e) {
    if (e is CatalogDownloadException) return e.message;
    if (e is TimeoutException || e is SocketException) {
      return "Couldn't reach the update server. Using the current catalog.";
    }
    return "Couldn't check for updates. Using the current catalog.";
  }

  // ── STREAM RUNNER ──────────────────────────────────────────────────────────

  Future<void> _run({required Stream<SyncProgress> stream}) async {
    await BeybladeWakelockService.enable();
    try {
      await for (final progress in stream) {
        switch (progress) {
          case SyncStarted():
            break;
          case SyncInProgress():
            emit(SyncRunning(task: SyncTask.metadata, progress: progress));
          case SyncCompleted(:final summary):
            dev.log('Catalog applied: ${summary.totalRecords} records',
                name: _logName);
            emit(SyncFinished(task: SyncTask.metadata, summary: summary));
          case SyncFailed(:final message):
            emit(SyncError(
                task: SyncTask.metadata,
                message: message,
                wasUserInitiated: true));
        }
      }
    } catch (e, st) {
      dev.log('Error during catalog run',
          name: _logName, error: e, stackTrace: st);
      emit(SyncError(
          task: SyncTask.metadata,
          message: e.toString(),
          wasUserInitiated: true));
    } finally {
      await BeybladeWakelockService.disable();
    }
  }
}
