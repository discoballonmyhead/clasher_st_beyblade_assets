import 'dart:typed_data';

import '../../../../core/error/failure.dart';
import '../entities/fill_proposal.dart';
import '../entities/row.dart';
import '../entities/row_lifecycle.dart';
import '../entities/sheet_analysis.dart';
import '../entities/structure.dart';
import '../entities/workbook.dart';

/// Everything the missing-data screens need. Implemented today by the Python engine
/// (data/repositories); an admin app can implement it against its own backend.
abstract class MissingDataRepository {
  /// Opens a workbook - or switches to it when it's already open (its unsaved edits kept).
  Future<Result<WorkbookSummary>> open(String path);

  /// Closes an open workbook (unsaved edits stay in its recovery file).
  Future<Result<void>> close(String path);
  Future<Result<WorkbookSummary>> summary();
  Future<Result<SheetAnalysis>> analyze(
    String sheet, {
    bool includeOptional = false,
  });
  Future<Result<RowsPage>> rows(
    String sheet, {
    String? field,
    String query = '',
    RowSort sort = RowSort.sheet,
    bool includeOptional = false, String? generation,
  });
  Future<Result<RowDetail>> row(String sheet, String id);
  Future<Result<int>> updateRow(
    String sheet,
    String id,
    Map<String, String> values,
  );
  Future<Result<List<FillProposal>>> proposals(
    String sheet, {
    bool parent = true,
    bool siblings = true,
    bool derive = true,
  });
  Future<Result<int>> applyProposals(String sheet, List<FillProposal> items);
  Future<Result<void>> setImage(String sheet, String id, Uint8List bytes);
  Future<Result<void>> setImageFromUrl(String sheet, String id, String url);
  Future<Result<Uint8List?>> parentImage(String sheet, String id);
  Future<Result<String?>> undo();
  Future<Result<void>> save();
  Future<Result<List<RecentEdit>>> recentEdits({int limit = 50});
  Future<Result<int>> fillFromWiki(String sheet, List<String> ids);
  Future<Result<void>> stopWiki();

  // ── recovery of unsaved edits from a closed / crashed session ──
  /// Replays them -> how many were recovered.
  Future<Result<int>> recoverUnsaved();

  /// Drops them (the engine moves the file to backups/).
  Future<Result<void>> discardUnsaved();

  // ── structure + change log ──
  /// Appends a column to each tab (after the last column) and registers it.
  Future<Result<void>> addColumn({
    required List<String> sheets,
    required String name,
    bool optional = false,
    bool inherit = false,
    String? defaultValue,
    String note = '',
  });

  /// A new row with the next id -> its id.
  Future<Result<String>> addRow(
    String sheet, {
    Map<String, String>? values,
    String? copyFrom,
    NewRowMode mode,
  });
  Future<Result<List<ColumnInfo>>> columns(String sheet);

  // ── deleting rows, recently deleted, ids ──
  /// Removes rows (the rows below move up with their pictures); they go to recently deleted.
  Future<Result<DeleteResult>> deleteRows(String sheet, List<String> ids);

  /// Recently deleted, newest first.
  Future<Result<List<DeletedRow>>> deletedRows();

  /// Puts them back at the end of their tab (old id when it's free).
  Future<Result<List<RestoredRow>>> restoreDeleted(List<String> keys);

  /// Removes them for good ([keys] null = all) -> how many.
  Future<Result<int>> purgeDeleted({List<String>? keys});

  /// Tabs whose ids don't run 1..N.
  Future<Result<List<IdIssue>>> idCheck();

  /// Shifts a tab's ids to 1..N and updates what points at them.
  Future<Result<RenumberResult>> renumber(String sheet);

  /// Changes made with the tool, newest first.
  Future<Result<EditLogPage>> editLog({
    int limit = 500,
    String? sheet,
    String query = '',
  });
  Stream<String> get logLines;
}
