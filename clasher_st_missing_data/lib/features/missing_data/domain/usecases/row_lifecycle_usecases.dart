import '../../../../core/error/failure.dart';
import '../entities/row_lifecycle.dart';
import '../repositories/missing_data_repository.dart';

class DeleteRows {
  const DeleteRows(this._repo);
  final MissingDataRepository _repo;
  Future<Result<DeleteResult>> call(String sheet, List<String> ids) =>
      _repo.deleteRows(sheet, ids);
}

class GetDeletedRows {
  const GetDeletedRows(this._repo);
  final MissingDataRepository _repo;
  Future<Result<List<DeletedRow>>> call() => _repo.deletedRows();
}

class RestoreDeletedRows {
  const RestoreDeletedRows(this._repo);
  final MissingDataRepository _repo;
  Future<Result<List<RestoredRow>>> call(List<String> keys) =>
      _repo.restoreDeleted(keys);
}

class PurgeDeletedRows {
  const PurgeDeletedRows(this._repo);
  final MissingDataRepository _repo;

  /// [keys] null empties everything -> how many were removed.
  Future<Result<int>> call({List<String>? keys}) =>
      _repo.purgeDeleted(keys: keys);
}

class CheckIds {
  const CheckIds(this._repo);
  final MissingDataRepository _repo;
  Future<Result<List<IdIssue>>> call() => _repo.idCheck();
}

class RenumberIds {
  const RenumberIds(this._repo);
  final MissingDataRepository _repo;
  Future<Result<RenumberResult>> call(String sheet) => _repo.renumber(sheet);
}
