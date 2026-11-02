import 'dart:typed_data';

import 'package:equatable/equatable.dart';

enum RowSort { sheet, updated, missing }

/// A row as listed in the table.
class RowSummary extends Equatable {
  const RowSummary({
    required this.row,
    required this.id,
    required this.name,
    required this.code,
    required this.edition,
    required this.updatedAt,
    required this.missing,
    required this.hasImage,
  });

  /// Spreadsheet row number (stable while the workbook is open).
  final int row;
  final String id;
  final String name;
  final String code;
  final String edition;

  /// Last edited (UTC), null when never edited.
  final DateTime? updatedAt;
  final List<String> missing;
  final bool hasImage;

  @override
  List<Object?> get props => [row, id, name, code, edition, updatedAt, missing, hasImage];
}

class RowsPage extends Equatable {
  const RowsPage({required this.total, required this.rows});

  final int total;
  final List<RowSummary> rows;

  @override
  List<Object?> get props => [total, rows];
}

/// Everything about one row, for the editor.
class RowDetail extends Equatable {
  const RowDetail({
    required this.row,
    required this.id,
    required this.parentId,
    required this.updatedAt,
    required this.fields,
    required this.values,
    required this.missing,
    required this.image,
  });

  final int row;
  final String id;
  final String? parentId;
  final DateTime? updatedAt;

  /// Editable columns in sheet order.
  final List<String> fields;
  final Map<String, Object?> values;
  final List<String> missing;

  /// Current image (WebP/PNG bytes), null when the row has none.
  final Uint8List? image;

  String display(String field) {
    final v = values[field];
    return v == null ? '' : '$v';
  }

  @override
  List<Object?> get props => [row, id, parentId, updatedAt, fields, values, missing, image?.length];
}
