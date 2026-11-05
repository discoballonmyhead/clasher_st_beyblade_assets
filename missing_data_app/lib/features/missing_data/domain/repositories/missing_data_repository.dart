import 'dart:typed_data';

import '../../../../core/error/failure.dart';
import '../entities/fill_proposal.dart';
import '../entities/row.dart';
import '../entities/sheet_analysis.dart';
import '../entities/structure.dart';
import '../entities/workbook.dart';

/// Everything the missing-data screens need. Implemented today by the Python engine
/// (data/repositories); an admin app can implement it against its own backend.
abstract class MissingDataRepository {
  Future<Result<WorkbookSummary>> open(String path);
  Future<Result<WorkbookSummary>> summary();
  Future<Result<SheetAnalysis>> analyze(String sheet, {bool includeOptional = false});
  Future<Result<RowsPage>> rows(String sheet,
      {String? field, String query = '', RowSort sort = RowSort.sheet, bool includeOptional = false});
  Future<Result<RowDetail>> row(String sheet, String id);
  Future<Result<int>> updateRow(String sheet, String id, Map<String, String> values);
  Future<Result<List<FillProposal>>> proposals(String sheet, {bool parent = true, bool siblings = true, bool derive = true});
  Future<Result<int>> applyProposals(String sheet, List<FillProposal> items);
  Future<Result<void>> setImage(String sheet, String id, Uint8List bytes);
  Future<Result<void>> setImageFromUrl(String sheet, String id, String url);
  Future<Result<Uint8List?>> parentImage(String sheet, String id);
  Future<Result<String?>> undo();
  Future<Result<void>> save();
  Future<Result<List<RecentEdit>>> recentEdits({int limit = 50});
  Future<Result<int>> fillFromWiki(String sheet, List<String> ids);
  Future<Result<void>> stopWiki();

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
  Future<Result<String>> addRow(String sheet, {Map<String, String>? values, String? copyFrom, NewRowMode mode});
  Future<Result<List<ColumnInfo>>> columns(String sheet);

  /// Changes made with the tool, newest first.
  Future<Result<EditLogPage>> editLog({int limit = 500, String? sheet, String query = ''});
  Stream<String> get logLines;
}
