import 'dart:typed_data';

import '../../../../core/bridge/engine_bridge.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entities/fill_proposal.dart';
import '../../domain/entities/row.dart';
import '../../domain/entities/sheet_analysis.dart';
import '../../domain/entities/workbook.dart';
import '../../domain/repositories/missing_data_repository.dart';
import '../datasources/engine_data_source.dart';
import '../models/mappers.dart';

class MissingDataRepositoryImpl implements MissingDataRepository {
  MissingDataRepositoryImpl(this._ds);

  final EngineDataSource _ds;

  /// Every call goes through here: engine/IO errors become a [Failure] with a readable message.
  Future<Result<T>> _guard<T>(Future<T> Function() body) async {
    try {
      return Ok(await body());
    } on EngineException catch (e) {
      return Err(Failure(_clean(e.message)));
    } catch (e) {
      return Err(Failure(_clean('$e')));
    }
  }

  static String _clean(String m) => m.replaceFirst(RegExp(r'^(ValueError|RuntimeError|KeyError): '), '');

  @override
  Future<Result<WorkbookSummary>> open(String path) => _guard(() async => workbookFromJson(await _ds.open(path)));

  @override
  Future<Result<WorkbookSummary>> summary() => _guard(() async => workbookFromJson(await _ds.summary()));

  @override
  Future<Result<SheetAnalysis>> analyze(String sheet, {bool includeOptional = false}) =>
      _guard(() async => analysisFromJson(await _ds.analyze(sheet, includeOptional)));

  @override
  Future<Result<RowsPage>> rows(String sheet,
          {String? field, String query = '', RowSort sort = RowSort.sheet, bool includeOptional = false}) =>
      _guard(() async => rowsPageFromJson(await _ds.rows(sheet, field, query, sort, includeOptional)));

  @override
  Future<Result<RowDetail>> row(String sheet, String id) => _guard(() async => rowDetailFromJson(await _ds.row(sheet, id)));

  @override
  Future<Result<int>> updateRow(String sheet, String id, Map<String, String> values) =>
      _guard(() async => ((await _ds.set(sheet, id, values))['changed'] as num? ?? 0).toInt());

  @override
  Future<Result<List<FillProposal>>> proposals(String sheet, {bool parent = true, bool siblings = true, bool derive = true}) =>
      _guard(() async => [for (final p in await _ds.proposals(sheet, parent, siblings, derive)) proposalFromJson(p)]);

  @override
  Future<Result<int>> applyProposals(String sheet, List<FillProposal> items) => _guard(
      () async => ((await _ds.apply(sheet, [for (final p in items) proposalToJson(p)]))['filled'] as num? ?? 0).toInt());

  @override
  Future<Result<void>> setImage(String sheet, String id, Uint8List bytes) => _guard(() => _ds.image(sheet, id, bytes));

  @override
  Future<Result<void>> setImageFromUrl(String sheet, String id, String url) => _guard(() => _ds.imageUrl(sheet, id, url));

  @override
  Future<Result<Uint8List?>> parentImage(String sheet, String id) =>
      _guard(() async => bytesFromBase64((await _ds.parentImage(sheet, id))['image']));

  @override
  Future<Result<String?>> undo() => _guard(() async => (await _ds.undo())['undone'] as String?);

  @override
  Future<Result<void>> save() => _guard(() => _ds.save());

  @override
  Future<Result<List<RecentEdit>>> recentEdits({int limit = 50}) =>
      _guard(() async => [for (final e in await _ds.recent(limit)) recentEditFromJson(e)]);

  @override
  Future<Result<int>> fillFromWiki(String sheet, List<String> ids) =>
      _guard(() async => ((await _ds.wiki(sheet, ids))['pages'] as num? ?? 0).toInt());

  @override
  Future<Result<void>> stopWiki() => _guard(() => _ds.stopWiki());

  @override
  Stream<String> get logLines => _ds.log;
}
