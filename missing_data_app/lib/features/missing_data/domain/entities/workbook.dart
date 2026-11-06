import 'package:equatable/equatable.dart';

/// One data tab of a workbook (Parts_X_Blades, Products, TCG_Cards ...).
class SheetInfo extends Equatable {
  const SheetInfo({required this.name, required this.rows, required this.rowsWithMissing, required this.hasImages});

  final String name;
  final int rows;
  final int rowsWithMissing;
  final bool hasImages;

  @override
  List<Object?> get props => [name, rows, rowsWithMissing, hasImages];
}

class WorkbookSummary extends Equatable {
  const WorkbookSummary({
    required this.path,
    required this.kind,
    required this.sheets,
    required this.dirty,
    required this.undoSteps,
    this.lastSaved,
    this.logEntries = 0,
    this.customColumns = 0,
    this.addedColumns = const [],
    this.unsavedEntries = 0,
    this.unsavedLast,
  });

  final String path;

  /// parts / products / tcg
  final String kind;
  final List<SheetInfo> sheets;

  /// Unsaved changes in memory.
  final bool dirty;
  final int undoSteps;
  final DateTime? lastSaved;

  /// Lines in the workbook's change log (_edit_log tab).
  final int logEntries;

  /// Columns added with the tool, over all tabs.
  final int customColumns;

  /// "Tab.column" the schema defines but the workbook didn't have yet (e.g. simpleRatchet): added, empty,
  /// when it was opened. Saved with the next save.
  final List<String> addedColumns;

  /// Edits from an earlier session that was closed (or crashed) without saving: kept in the recovery file and
  /// offered when the workbook opens.
  final int unsavedEntries;
  final DateTime? unsavedLast;

  String get fileName => path.split(RegExp(r'[\\/]')).last;

  @override
  List<Object?> get props =>
      [path, kind, sheets, dirty, undoSteps, lastSaved, logEntries, customColumns, addedColumns, unsavedEntries];
}

/// A row someone (or the scraper) changed, newest first.
class RecentEdit extends Equatable {
  const RecentEdit({required this.sheet, required this.id, required this.name, required this.updatedAt});

  final String sheet;
  final String id;
  final String name;
  final DateTime? updatedAt;

  @override
  List<Object?> get props => [sheet, id, name, updatedAt];
}
