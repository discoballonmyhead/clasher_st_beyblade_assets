import '../../../../core/error/failure.dart';
import '../entities/workbook.dart';
import '../repositories/missing_data_repository.dart';

class OpenWorkbook {
  const OpenWorkbook(this._repo);
  final MissingDataRepository _repo;
  Future<Result<WorkbookSummary>> call(String path) => _repo.open(path);
}

class GetWorkbookSummary {
  const GetWorkbookSummary(this._repo);
  final MissingDataRepository _repo;
  Future<Result<WorkbookSummary>> call() => _repo.summary();
}

class SaveWorkbook {
  const SaveWorkbook(this._repo);
  final MissingDataRepository _repo;
  Future<Result<void>> call() => _repo.save();
}

class UndoLastChange {
  const UndoLastChange(this._repo);
  final MissingDataRepository _repo;

  /// The label of what was undone, or null when there was nothing to undo.
  Future<Result<String?>> call() => _repo.undo();
}

class RecoverUnsaved {
  const RecoverUnsaved(this._repo);
  final MissingDataRepository _repo;
  Future<Result<int>> call() => _repo.recoverUnsaved();
}

class DiscardUnsaved {
  const DiscardUnsaved(this._repo);
  final MissingDataRepository _repo;
  Future<Result<void>> call() => _repo.discardUnsaved();
}

class GetRecentEdits {
  const GetRecentEdits(this._repo);
  final MissingDataRepository _repo;
  Future<Result<List<RecentEdit>>> call({int limit = 50}) => _repo.recentEdits(limit: limit);
}
