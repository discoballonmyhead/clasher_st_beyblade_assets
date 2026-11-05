import 'dart:async';
import 'dart:typed_data';

import 'package:missing_data_app/core/error/failure.dart';
import 'package:missing_data_app/features/missing_data/domain/entities/fill_proposal.dart';
import 'package:missing_data_app/features/missing_data/domain/entities/row.dart';
import 'package:missing_data_app/features/missing_data/domain/entities/sheet_analysis.dart';
import 'package:missing_data_app/features/missing_data/domain/entities/structure.dart';
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

  /// Columns added through [addColumn] (counted as missing like the others).
  final customColumns = <String>[];

  /// What the engine reports as added from the schema when the workbook opens.
  List<String> addedOnOpen = const [];
  final editLogEntries = <EditLogEntry>[];

  List<String> get _checked => ['type', 'mass', ...customColumns];

  List<String> _missing(String id) => [
        for (final f in _checked)
          if (rowsData[id]![f] == null) f,
      ];

  void _logEntry(String action, {String? rowId, String? field, String? oldValue, String? newValue, String? note}) =>
      editLogEntries.insert(
          0,
          EditLogEntry(
              at: DateTime.now().toUtc(),
              source: 'missing_data_app',
              action: action,
              sheet: 'Parts_X_Blades',
              rowId: rowId,
              field: field,
              oldValue: oldValue,
              newValue: newValue,
              note: note));

  WorkbookSummary get _summary => WorkbookSummary(
        path: '/tmp/beyblade_parts.xlsx',
        kind: 'parts',
        sheets: [SheetInfo(name: 'Parts_X_Blades', rows: rowsData.length, rowsWithMissing: rowsData.keys.where((k) => _missing(k).isNotEmpty).length, hasImages: true)],
        dirty: dirty,
        undoSteps: undoSteps,
        logEntries: editLogEntries.length,
        customColumns: customColumns.length,
        addedColumns: addedOnOpen,
      );

  @override
  Future<Result<WorkbookSummary>> open(String path) async => Ok(_summary);
  @override
  Future<Result<WorkbookSummary>> summary() async => Ok(_summary);

  @override
  Future<Result<SheetAnalysis>> analyze(String sheet, {bool includeOptional = false}) async => Ok(SheetAnalysis(
        sheet: sheet,
        total: rowsData.length,
        fields: [
          for (final f in _checked)
            FieldGap(
                field: f,
                missing: rowsData.keys.where((k) => _missing(k).contains(f)).length,
                ids: const [],
                never: false,
                custom: customColumns.contains(f)),
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
        updatedAt: null,
        fields: ['name', 'code', 'parentPartId', 'type', 'mass', ...customColumns],
        values: rowsData[id]!,
        missing: _missing(id),
        image: null,
        parentId: rowsData[id]!['parentPartId'] == null ? null : '${rowsData[id]!['parentPartId']}',
        customFields: customColumns,
      ));

  @override
  Future<Result<int>> updateRow(String sheet, String id, Map<String, String> values) async {
    values.forEach((k, v) {
      _logEntry('set', rowId: id, field: k, oldValue: rowsData[id]![k]?.toString(), newValue: v);
      rowsData[id]![k] = v;
    });
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
  Future<Result<void>> addColumn({
    required List<String> sheets,
    required String name,
    bool optional = false,
    bool inherit = false,
    String? defaultValue,
    String note = '',
  }) async {
    if (customColumns.contains(name) || _checked.contains(name)) {
      return Err(Failure('Parts_X_Blades already has a column \'$name\''));
    }
    customColumns.add(name);
    for (final r in rowsData.values) {
      r[name] = (defaultValue == null || defaultValue.isEmpty) ? null : defaultValue;
    }
    _logEntry('add_column', field: name, note: note.isEmpty ? null : note);
    dirty = true;
    undoSteps++;
    return const Ok(null);
  }

  @override
  Future<Result<String>> addRow(String sheet,
      {Map<String, String>? values, String? copyFrom, NewRowMode mode = NewRowMode.empty}) async {
    final id = '${rowsData.keys.map(int.parse).reduce((a, b) => a > b ? a : b) + 1}';
    final src = copyFrom == null ? null : rowsData[copyFrom];
    rowsData[id] = {
      'name': null, 'code': null, 'parentPartId': null, 'type': null, 'mass': null,
      for (final c in customColumns) c: null,
      if (src != null && mode == NewRowMode.copy) ...src,
      if (src != null && mode == NewRowMode.variant) ...{
        'name': src['name'], 'type': src['type'], 'mass': src['mass'], 'parentPartId': copyFrom,
      },
      ...?values,
    };
    _logEntry('add_row', rowId: id, note: src == null ? 'new' : '${mode.name} of #$copyFrom');
    dirty = true;
    undoSteps++;
    return Ok(id);
  }

  @override
  Future<Result<List<ColumnInfo>>> columns(String sheet) async => Ok([
        for (final c in ['dataID', 'name', 'code', 'type', 'mass', ...customColumns])
          ColumnInfo(name: c, custom: customColumns.contains(c), isId: c == 'dataID'),
      ]);

  @override
  Future<Result<EditLogPage>> editLog({int limit = 500, String? sheet, String query = ''}) async {
    final q = query.toLowerCase();
    final list = [
      for (final e in editLogEntries)
        if (q.isEmpty || '${e.action} ${e.rowId} ${e.field} ${e.newValue}'.toLowerCase().contains(q)) e,
    ];
    return Ok(EditLogPage(total: list.length, entries: list.take(limit).toList()));
  }

  @override
  Stream<String> get logLines => _log.stream;
}
