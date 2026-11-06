import 'package:equatable/equatable.dart';

/// A value the engine can fill automatically, and why.
class FillProposal extends Equatable {
  const FillProposal({required this.row, required this.id, required this.field, required this.value, required this.source});

  final int row;
  final String id;
  final String field;
  final Object? value;

  /// "parent #65", "same name: 2 other row(s) say so ...", "derive: ..."
  final String source;

  /// parent / same name / derive - for filtering in the preview.
  String get sourceKind => source.split(':').first.split(' #').first;

  @override
  List<Object?> get props => [row, id, field, value, source];
}
