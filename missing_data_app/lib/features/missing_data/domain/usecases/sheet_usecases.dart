import '../../../../core/error/failure.dart';
import '../entities/row.dart';
import '../entities/sheet_analysis.dart';
import '../repositories/missing_data_repository.dart';

class AnalyzeSheet {
  const AnalyzeSheet(this._repo);
  final MissingDataRepository _repo;
  Future<Result<SheetAnalysis>> call(String sheet, {bool includeOptional = false}) =>
      _repo.analyze(sheet, includeOptional: includeOptional);
}

class ListRows {
  const ListRows(this._repo);
  final MissingDataRepository _repo;
  Future<Result<RowsPage>> call(String sheet,
          {String? field, String query = '', RowSort sort = RowSort.sheet, bool includeOptional = false}) =>
      _repo.rows(sheet, field: field, query: query, sort: sort, includeOptional: includeOptional);
}
