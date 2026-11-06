import '../../../../core/error/failure.dart';
import '../entities/fill_proposal.dart';
import '../repositories/missing_data_repository.dart';

class GetFillProposals {
  const GetFillProposals(this._repo);
  final MissingDataRepository _repo;
  Future<Result<List<FillProposal>>> call(String sheet) => _repo.proposals(sheet);
}

class ApplyFillProposals {
  const ApplyFillProposals(this._repo);
  final MissingDataRepository _repo;
  Future<Result<int>> call(String sheet, List<FillProposal> items) => _repo.applyProposals(sheet, items);
}

class FillFromWiki {
  const FillFromWiki(this._repo);
  final MissingDataRepository _repo;
  Future<Result<int>> call(String sheet, List<String> ids) => _repo.fillFromWiki(sheet, ids);
  Future<Result<void>> stop() => _repo.stopWiki();
  Stream<String> get log => _repo.logLines;
}
