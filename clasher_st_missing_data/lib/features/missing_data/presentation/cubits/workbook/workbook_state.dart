import 'package:equatable/equatable.dart';

import '../../../domain/entities/workbook.dart';

enum WorkbookStatus { idle, opening, ready, failed }

class WorkbookState extends Equatable {
  const WorkbookState({
    this.status = WorkbookStatus.idle,
    this.summary,
    this.recent = const [],
    this.saving = false,
    this.message,
    this.error,
    this.docs = const [],
    this.dirtyDocs = const {},
  });

  final WorkbookStatus status;
  final WorkbookSummary? summary;
  final List<String> recent;
  final bool saving;

  /// One-off info for a snackbar ("Saved", "Undid: ...").
  final String? message;
  final String? error;

  /// Workbooks open as tabs (paths), in opening order; [summary] is the current one.
  final List<String> docs;

  /// Open workbooks with unsaved changes.
  final Set<String> dirtyDocs;

  bool get isOpen => summary != null;
  bool get anyDirty => dirtyDocs.isNotEmpty || (summary?.dirty ?? false);

  WorkbookState copyWith({
    WorkbookStatus? status,
    WorkbookSummary? summary,
    List<String>? recent,
    bool? saving,
    String? message,
    String? error,
    List<String>? docs,
    Set<String>? dirtyDocs,
    bool clearSummary = false,
  }) =>
      WorkbookState(
        status: status ?? this.status,
        summary: clearSummary ? null : summary ?? this.summary,
        recent: recent ?? this.recent,
        saving: saving ?? this.saving,
        message: message,
        error: error,
        docs: docs ?? this.docs,
        dirtyDocs: dirtyDocs ?? this.dirtyDocs,
      );

  @override
  List<Object?> get props => [status, summary, recent, saving, message, error, docs, dirtyDocs];
}
