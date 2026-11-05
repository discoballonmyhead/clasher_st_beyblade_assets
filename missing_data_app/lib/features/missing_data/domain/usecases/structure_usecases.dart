import '../../../../core/error/failure.dart';
import '../entities/structure.dart';
import '../repositories/missing_data_repository.dart';

class AddColumn {
  const AddColumn(this._repo);
  final MissingDataRepository _repo;
  Future<Result<void>> call({
    required List<String> sheets,
    required String name,
    bool optional = false,
    bool inherit = false,
    String? defaultValue,
    String note = '',
  }) =>
      _repo.addColumn(
          sheets: sheets, name: name, optional: optional, inherit: inherit, defaultValue: defaultValue, note: note);
}

class AddRow {
  const AddRow(this._repo);
  final MissingDataRepository _repo;

  /// The new row's id.
  Future<Result<String>> call(String sheet,
          {Map<String, String>? values, String? copyFrom, NewRowMode mode = NewRowMode.empty}) =>
      _repo.addRow(sheet, values: values, copyFrom: copyFrom, mode: mode);
}

class GetColumns {
  const GetColumns(this._repo);
  final MissingDataRepository _repo;
  Future<Result<List<ColumnInfo>>> call(String sheet) => _repo.columns(sheet);
}

class GetEditLog {
  const GetEditLog(this._repo);
  final MissingDataRepository _repo;
  Future<Result<EditLogPage>> call({int limit = 500, String? sheet, String query = ''}) =>
      _repo.editLog(limit: limit, sheet: sheet, query: query);
}
