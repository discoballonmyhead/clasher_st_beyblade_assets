import 'package:equatable/equatable.dart';

enum AssetDownloadPhase {
  idle,
  fetchingReleaseInfo,
  downloading,
  extracting,
  updatingLocalData,
  completed,
  failed,
}

class AssetDownloadState extends Equatable {
  const AssetDownloadState({
    this.phase = AssetDownloadPhase.idle,
    this.generation,
    this.progress = 0.0,
    this.errorMessage,
  });

  final AssetDownloadPhase phase;
  final String? generation;

  /// 0.0-1.0. Only meaningful during AssetDownloadPhase.downloading --
  /// the other phases (extracting, updatingLocalData) don't have a
  /// natural fractional progress the way a byte-count download does,
  /// so this just stays at whatever it last was through those.
  final double progress;
  final String? errorMessage;

  AssetDownloadState copyWith({
    AssetDownloadPhase? phase,
    String? generation,
    double? progress,
    String? errorMessage,
    bool clearError = false,
  }) =>
      AssetDownloadState(
        phase: phase ?? this.phase,
        generation: generation ?? this.generation,
        progress: progress ?? this.progress,
        errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      );

  @override
  List<Object?> get props => [phase, generation, progress, errorMessage];
}
