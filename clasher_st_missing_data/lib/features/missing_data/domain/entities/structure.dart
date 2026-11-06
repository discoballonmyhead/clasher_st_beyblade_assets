import 'package:equatable/equatable.dart';

/// One column of a tab, and whether it was added with the tool.
class ColumnInfo extends Equatable {
  const ColumnInfo({
    required this.name,
    this.custom = false,
    this.optional = false,
    this.inherit = false,
    this.note = '',
    this.isImage = false,
    this.isId = false,
  });

  final String name;

  /// Added with the missing data tool (purple header, listed in the _columns tab).
  final bool custom;

  /// Not reported as missing.
  final bool optional;

  /// Variants copy it from their parent row during auto-fill.
  final bool inherit;
  final String note;
  final bool isImage;
  final bool isId;

  @override
  List<Object?> get props => [name, custom, optional, inherit, note, isImage, isId];
}

/// How a new row starts.
enum NewRowMode {
  /// Only the next id and what follows from the tab (series, hobby).
  empty,

  /// The fields a variant shares with its base part, parent id set (recolors, coatings ...).
  variant,

  /// Every field of the source row.
  copy,
}

/// One change made with the missing data tool (Python GUI, this app or the CLI).
class EditLogEntry extends Equatable {
  const EditLogEntry({
    required this.at,
    required this.source,
    required this.action,
    required this.sheet,
    this.rowId,
    this.field,
    this.oldValue,
    this.newValue,
    this.note,
  });

  final DateTime? at;

  /// missing_data_tool / missing_data_app / cli
  final String source;

  /// set, auto-fill, image, add_row, add_column, wiki
  final String action;
  final String sheet;
  final String? rowId;
  final String? field;
  final String? oldValue;
  final String? newValue;
  final String? note;

  @override
  List<Object?> get props => [at, source, action, sheet, rowId, field, oldValue, newValue, note];
}

class EditLogPage extends Equatable {
  const EditLogPage({required this.total, required this.entries});

  final int total;
  final List<EditLogEntry> entries;

  @override
  List<Object?> get props => [total, entries];
}
