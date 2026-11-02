import 'package:equatable/equatable.dart';

/// How many rows of a tab miss one field.
class FieldGap extends Equatable {
  const FieldGap({required this.field, required this.missing, required this.ids, required this.never});

  final String field;
  final int missing;
  final List<String> ids;

  /// No row in the tab has it - probably not used by this game/series.
  final bool never;

  @override
  List<Object?> get props => [field, missing, ids, never];
}

class SheetAnalysis extends Equatable {
  const SheetAnalysis({required this.sheet, required this.total, required this.fields});

  final String sheet;
  final int total;
  final List<FieldGap> fields;

  List<FieldGap> get withGaps => fields.where((f) => f.missing > 0).toList()
    ..sort((a, b) => b.missing.compareTo(a.missing));

  @override
  List<Object?> get props => [sheet, total, fields];
}
