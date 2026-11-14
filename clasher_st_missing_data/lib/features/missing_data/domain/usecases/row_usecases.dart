import 'dart:typed_data';

import '../../../../core/error/failure.dart';
import '../entities/row.dart';
import '../repositories/missing_data_repository.dart';

class GetRow {
  const GetRow(this._repo);
  final MissingDataRepository _repo;
  Future<Result<RowDetail>> call(String sheet, String id) => _repo.row(sheet, id);
}

class UpdateRow {
  const UpdateRow(this._repo);
  final MissingDataRepository _repo;

  /// Returns how many fields actually changed. Stamps the row's last-edited time.
  Future<Result<int>> call(String sheet, String id, Map<String, String> values) =>
      _repo.updateRow(sheet, id, values);
}

class SetRowImage {
  const SetRowImage(this._repo);
  final MissingDataRepository _repo;
  Future<Result<void>> call(String sheet, String id, Uint8List bytes, {String? field}) =>
      _repo.setImage(sheet, id, bytes, field: field);
  Future<Result<void>> fromUrl(String sheet, String id, String url, {String? field}) =>
      _repo.setImageFromUrl(sheet, id, url, field: field);
}

class GetParentImage {
  const GetParentImage(this._repo);
  final MissingDataRepository _repo;
  Future<Result<Uint8List?>> call(String sheet, String id) => _repo.parentImage(sheet, id);
}
