import 'package:equatable/equatable.dart';

import '../../../domain/entities/structure.dart';

class EditLogState extends Equatable {
  const EditLogState({
    this.entries = const [],
    this.total = 0,
    this.loading = false,
    this.query = '',
    this.thisTabOnly = false,
    this.error,
  });

  final List<EditLogEntry> entries;
  final int total;
  final bool loading;
  final String query;
  final bool thisTabOnly;
  final String? error;

  EditLogState copyWith({
    List<EditLogEntry>? entries,
    int? total,
    bool? loading,
    String? query,
    bool? thisTabOnly,
    String? error,
  }) =>
      EditLogState(
        entries: entries ?? this.entries,
        total: total ?? this.total,
        loading: loading ?? this.loading,
        query: query ?? this.query,
        thisTabOnly: thisTabOnly ?? this.thisTabOnly,
        error: error,
      );

  @override
  List<Object?> get props => [entries, total, loading, query, thisTabOnly, error];
}
