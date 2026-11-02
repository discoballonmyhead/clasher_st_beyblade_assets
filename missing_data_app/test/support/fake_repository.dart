import 'dart:async';
import 'dart:typed_data';

import 'package:missing_data_app/core/error/failure.dart';
import 'package:missing_data_app/features/missing_data/domain/entities/fill_proposal.dart';
import 'package:missing_data_app/features/missing_data/domain/entities/row.dart';
import 'package:missing_data_app/features/missing_data/domain/entities/sheet_analysis.dart';
import 'package:missing_data_app/features/missing_data/domain/entities/workbook.dart';
import 'package:missing_data_app/features/missing_data/domain/repositories/missing_data_repository.dart';

/// In-memory repository: two blade rows, one with gaps.
class FakeRepository implements MissingDataRepository {
  final rowsData = <String, Map<String, Object?>>{
    '65': {'name': 'Dran Sword', 'code': 'BX-01', 'type': 'attack', 'mass': 34.6},
    '203': {'name': 'Hells Scythe', 'code': 'BX-02', 'type': null, 'mass': null},
  };
  bool dirty = false;
  int undoSteps = 0;
  final _log = StreamController<String>.broadcast();

  List<String> _missing(String id) => [
        for (final f in ['type', 'mass'])
          if (rowsData[id]![f] == null) f,
      ];

  WorkbookSummary get _summary => WorkbookSummary(
        path: '/tmp/beyblade_parts.xlsx',
        kind: 'parts',
        sheets: [SheetInfo(name: 'Parts_X_Blades', rows: 2, rowsWithMissing: rowsData.keys.where((k) => _missing(k).isNotEmpty).length, hasImages: true)],
        dirty: dirty,
        undoSteps: undoSteps,
      );

  @override
  Future<Result<WorkbookSummary>> open(String path) async => Ok(_summary);
  @override
  Future<Result<WorkbookSummary>> summary() async => Ok(_summary);

  @override
  Future<Result<SheetAnalysis>> analyze(String sheet, {bool includeOptional = false}) async => Ok(SheetAnalysis(
        sheet: sheet,
        total: 2,
        fields: [
          for (final f in ['type', 'mass'])
            FieldGap(field: f, missing: rowsData.keys.where((k) => _missing(k).contains(f)).length, ids: const [], never: false),
        ],
      ));

  @override
  Future<Result<RowsPage>> rows(String sheet,
      {String? field, String query = '', RowSort sort = RowSort.sheet, bool includeOptional = false}) async {
    final list = [
      for (final e in rowsData.entries)
        if ((field == null || _missing(e.key).contains(field)) &&
            (query.isEmpty || '${e.key} ${e.value['name']}'.toLowerCase().contains(query.toLowerCase())))
          RowSummary(
            row: int.parse(e.key),
            id: e.key,
            name: '${e.value['name']}',
            code: '${e.value['code']}',
            edition: '',
            updatedAt: null,
            missing: _missing(e.key),
            hasImage: false,
          ),
    ];
    return Ok(RowsPage(total: list.length, rows: list));
  }

  @override
  Future<Result<RowDetail>> row(String sheet, String id) async => Ok(RowDetail(
        row: int.parse(id),
        id: id,
        parentId: null,
        updatedAt: null,
        fields: const ['name', 'code', 'type', 'mass'],
        values: rowsData[id]!,
        missing: _missing(id),
        image: null,
      ));

  @override
  Future<Result<int>> updateRow(String sheet, String id, Map<String, String> values) async {
    values.forEach((k, v) => rowsData[id]![k] = v);
    dirty = true;
    undoSteps++;
    return Ok(values.length);
  }

  @override
  Future<Result<List<FillProposal>>> proposals(String sheet, {bool parent = true, bool siblings = true, bool derive = true}) async =>
      const Ok([FillProposal(row: 203, id: '203', field: 'type', value: 'attack', source: 'parent #65')]);

  @override
  Future<Result<int>> applyProposals(String sheet, List<FillProposal> items) async {
    for (final p in items) {
      rowsData[p.id]![p.field] = p.value;
    }
    dirty = true;
    undoSteps++;
    return Ok(items.length);
  }

  @override
  Future<Result<void>> setImage(String sheet, String id, Uint8List bytes) async => const Ok(null);
  @override
  Future<Result<void>> setImageFromUrl(String sheet, String id, String url) async => const Ok(null);
  @override
  Future<Result<Uint8List?>> parentImage(String sheet, String id) async => const Ok(null);
  @override
  Future<Result<String?>> undo() async => const Ok(null);
  @override
  Future<Result<void>> save() async {
    dirty = false;
    return const Ok(null);
  }

  @override
  Future<Result<List<RecentEdit>>> recentEdits({int limit = 50}) async => const Ok([]);
  @override
  Future<Result<int>> fillFromWiki(String sheet, List<String> ids) async => const Ok(0);
  @override
  Future<Result<void>> stopWiki() async => const Ok(null);
  @override
  Stream<String> get logLines => _log.stream;
}
