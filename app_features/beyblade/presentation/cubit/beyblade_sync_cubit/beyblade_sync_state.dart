import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:equatable/equatable.dart';

enum SyncTask { metadata }

sealed class BeybladeSyncState extends Equatable {
  const BeybladeSyncState();
  @override
  List<Object?> get props => [];
}

class SyncIdle extends BeybladeSyncState {
  const SyncIdle();
}

/// Steady state once a usable catalog is in the boxes.
///
/// [checkedAt] is the last time the app asked the server for a newer
/// catalog. It exists so a check that finds nothing new still produces
/// a distinct state and the settings tile's "last checked" line
/// refreshes; with no fields, re-emitting SyncReady would compare equal
/// and nothing would rebuild. Optional, so `const SyncReady()` and every
/// existing `SyncReady()` switch pattern are unaffected.
class SyncReady extends BeybladeSyncState {
  const SyncReady({this.checkedAt});
  final DateTime? checkedAt;
  @override
  List<Object?> get props => [checkedAt];
}

class SyncRunning extends BeybladeSyncState {
  const SyncRunning({required this.task, required this.progress});
  final SyncTask task;
  final SyncProgress progress;
  @override
  List<Object?> get props => [task, progress];
}

class SyncFinished extends BeybladeSyncState {
  const SyncFinished({required this.task, required this.summary});
  final SyncTask task;
  final SyncSummary summary;
  @override
  List<Object?> get props => [task, summary];
}

class SyncError extends BeybladeSyncState {
  const SyncError(
      {this.task, required this.message, required this.wasUserInitiated});
  final SyncTask? task;
  final String message;
  final bool wasUserInitiated;
  @override
  List<Object?> get props => [task, message, wasUserInitiated];
}
