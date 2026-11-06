import 'package:equatable/equatable.dart';

/// A row deleted with the tool, kept (values + pictures) until it's restored or emptied.
class DeletedRow extends Equatable {
  const DeletedRow({
    required this.key,
    required this.sheet,
    required this.rowId,
    required this.name,
    this.deletedAt,
    this.source = '',
    this.hasImage = false,
  });

  /// Identifies the entry for restore / delete for good.
  final String key;
  final String sheet;

  /// The id it had when it was deleted (it gets it back if it's still free).
  final String rowId;
  final String name;
  final DateTime? deletedAt;
  final String source;
  final bool hasImage;

  @override
  List<Object?> get props => [key, sheet, rowId, name, deletedAt, source, hasImage];
}

class DeleteResult extends Equatable {
  const DeleteResult({required this.deleted, this.orphans = const []});

  final List<String> deleted;

  /// Variants whose parent id now points at a deleted row.
  final List<String> orphans;

  @override
  List<Object?> get props => [deleted, orphans];
}

class RestoredRow extends Equatable {
  const RestoredRow({required this.sheet, required this.id, required this.oldId});

  final String sheet;
  final String id;
  final String oldId;

  /// Its old id was taken in the meantime.
  bool get newId => id != oldId;

  @override
  List<Object?> get props => [sheet, id, oldId];
}

/// A tab whose ids don't run 1..N.
class IdIssue extends Equatable {
  const IdIssue({
    required this.sheet,
    required this.rows,
    required this.max,
    this.gaps = const [],
    this.gapCount = 0,
    this.duplicates = const [],
    this.nonNumeric = 0,
    this.released = 0,
    this.fingerprint = '',
  });

  final String sheet;
  final int rows;
  final int max;

  /// Missing ids as ranges ("2-64", "70").
  final List<String> gaps;
  final int gapCount;
  final List<String> duplicates;

  /// Ids that aren't numbers: the tab can't be renumbered until they're fixed.
  final int nonNumeric;

  /// Ids that would change and are already in the last package (released to the app).
  final int released;

  /// Changes whenever the tab's ids change, so "not now" lasts until then.
  final String fingerprint;

  bool get canRenumber => nonNumeric == 0;

  @override
  List<Object?> get props => [sheet, rows, max, gaps, gapCount, duplicates, nonNumeric, released, fingerprint];
}

class RenumberResult extends Equatable {
  const RenumberResult({
    required this.sheet,
    required this.changed,
    this.references = const {},
    this.cleared = const {},
    this.pendingFiles = const [],
  });

  final String sheet;
  final int changed;

  /// "Parts_X_Blades.parentPartId" -> how many were updated.
  final Map<String, int> references;

  /// Links to deleted rows that were cleared rather than left to hit another row.
  final Map<String, List<String>> cleared;

  /// Other workbooks updated when this one is saved.
  final List<String> pendingFiles;

  @override
  List<Object?> get props => [sheet, changed, references, cleared, pendingFiles];
}
