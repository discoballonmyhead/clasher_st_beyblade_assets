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
  });

  final WorkbookStatus status;
  final WorkbookSummary? summary;
  final List<String> recent;
  final bool saving;

  /// One-off info for a snackbar ("Saved", "Undid: ...").
  final String? message;
  final String? error;

  bool get isOpen => summary != null;

  WorkbookState copyWith({
    WorkbookStatus? status,
    WorkbookSummary? summary,
    List<String>? recent,
    bool? saving,
    String? message,
    String? error,
  }) =>
      WorkbookState(
        status: status ?? this.status,
        summary: summary ?? this.summary,
        recent: recent ?? this.recent,
        saving: saving ?? this.saving,
        message: message,
        error: error,
      );

  @override
  List<Object?> get props => [status, summary, recent, saving, message, error];
}
