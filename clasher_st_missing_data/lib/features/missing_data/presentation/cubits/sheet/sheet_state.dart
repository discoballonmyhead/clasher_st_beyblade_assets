import 'package:equatable/equatable.dart';

import '../../../domain/entities/row.dart';
import '../../../domain/entities/sheet_analysis.dart';

class SheetState extends Equatable {
  const SheetState({
    this.sheet,
    this.analysis,
    this.rows = const [],
    this.total = 0,
    this.field,
    this.query = '',
    this.sort = RowSort.sheet,
    this.includeOptional = false,
    this.loading = false,
    this.selected = const {},
    this.focusedId,
    this.error,
    this.generation,
  });

  final String? sheet;
  final SheetAnalysis? analysis;
  final List<RowSummary> rows;
  final int total;

  /// Only rows missing this field (null = all rows).
  final String? field;
  final String query;
  final RowSort sort;
  final bool includeOptional;
  final bool loading;

  /// Row ids ticked for bulk actions (fill from wiki).
  final Set<String> selected;

  /// The row open in the editor.
  final String? focusedId;
  final String? error;

  /// Only this generation's rows in tabs that hold several (Products, Accessories ...); null = all.
  final String? generation;

  SheetState copyWith({
    String? sheet,
    SheetAnalysis? analysis,
    List<RowSummary>? rows,
    int? total,
    String? Function()? field,
    String? query,
    RowSort? sort,
    bool? includeOptional,
    bool? loading,
    Set<String>? selected,
    String? Function()? focusedId,
    String? error,
    String? Function()? generation,
  }) =>
      SheetState(
        sheet: sheet ?? this.sheet,
        analysis: analysis ?? this.analysis,
        rows: rows ?? this.rows,
        total: total ?? this.total,
        field: field != null ? field() : this.field,
        query: query ?? this.query,
        sort: sort ?? this.sort,
        includeOptional: includeOptional ?? this.includeOptional,
        loading: loading ?? this.loading,
        selected: selected ?? this.selected,
        focusedId: focusedId != null ? focusedId() : this.focusedId,
        error: error,
        generation: generation != null ? generation() : this.generation,
      );

  @override
  List<Object?> get props =>
      [sheet, analysis, rows, total, field, query, sort, includeOptional, loading, selected, focusedId, error, generation];
}
