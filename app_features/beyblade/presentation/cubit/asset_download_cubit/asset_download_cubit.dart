import 'dart:developer' as dev;

import 'package:clasher_st/core/services/wakelock_service/beyblade_wake_lock_service.dart';
import 'package:clasher_st/features/beyblade/domain/usecases/usecases.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'asset_download_state.dart';

class AssetDownloadCubit extends Cubit<AssetDownloadState> {
  AssetDownloadCubit({
    required DownloadGenerationAssetsUseCase downloadUseCase,
    required String githubReleaseTag,
  })  : _downloadUseCase = downloadUseCase,
        _releaseTag = githubReleaseTag,
        super(const AssetDownloadState()) {
    dev.log('Initialized for tag $_releaseTag', name: _logName);
  }

  // Notice how clean the dependencies are now! Just the Use Case.
  final DownloadGenerationAssetsUseCase _downloadUseCase;
  final String _releaseTag;

  static const _logName = 'AssetDownloadCubit';

  static const _activePhases = {
    AssetDownloadPhase.fetchingReleaseInfo,
    AssetDownloadPhase.downloading,
    AssetDownloadPhase.extracting,
    AssetDownloadPhase.updatingLocalData,
  };

  Future<void> downloadCompleteAssets(String generation) async {
    dev.log('downloadCompleteAssets started for generation: $generation',
        name: _logName);
    if (_activePhases.contains(state.phase)) {
      return; // ignore while one's already running
    }

    // 1. Reset state to get the UI ready for a new download
    emit(state.copyWith(
      generation: generation,
      progress: 0,
      clearError: true,
    ));

    try {
      // 2. Delegate ALL the complex logic to the Use Case.
      // The Cubit simply listens to the callbacks and updates the UI state.
      await BeybladeWakelockService.enable();
      await _downloadUseCase(
        generation: generation,
        releaseTag: _releaseTag,
        onPhaseChanged: (phase) {
          emit(state.copyWith(phase: phase));
        },
        onProgress: (progress) {
          emit(state.copyWith(progress: progress));
        },
      );

      // 3. If the Use Case finishes without throwing an error, we are 100% done!
      emit(state.copyWith(
          progress: 1.0)); // Just to ensure the progress bar finishes
    } catch (e) {
      // 4. If anything fails (network error, no zip found, extraction failed),
      // the Use Case throws it, and we catch it here to show the user.
      dev.log('Download caught error from Use Case', name: _logName, error: e);
      emit(state.copyWith(
        phase: AssetDownloadPhase.failed,
        errorMessage: e.toString(),
      ));
    } finally {
      await BeybladeWakelockService.disable();
    }
  }
}
