import 'dart:convert';
import 'dart:typed_data';

import '../../domain/entities/fill_proposal.dart';
import '../../domain/entities/row.dart';
import '../../domain/entities/sheet_analysis.dart';
import '../../domain/entities/structure.dart';
import '../../domain/entities/workbook.dart';

/// Engine JSON -> domain entities. Tolerant: missing keys get safe defaults.
typedef Json = Map<String, dynamic>;

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
DateTime? _date(Object? v) {
  final s = _s(v);
  if (s.isEmpty) return null;
  return DateTime.tryParse(s.contains('T') || s.contains('+') ? s : s.replaceFirst(' ', 'T'));
}

WorkbookSummary workbookFromJson(Json j) => WorkbookSummary(
      path: _s(j['path']),
      kind: _s(j['kind']),
      sheets: [
        for (final s in (j['sheets'] as List? ?? const []))
          SheetInfo(
            name: _s((s as Json)['name']),
            rows: _i(s['rows']),
            rowsWithMissing: _i(s['rowsWithMissing']),
            hasImages: s['hasImages'] == true,
          ),
      ],
      dirty: j['dirty'] == true,
      undoSteps: _i(j['undo']),
      lastSaved: j['lastSaved'] is num
          ? DateTime.fromMillisecondsSinceEpoch(((j['lastSaved'] as num) * 1000).round())
          : null,
      logEntries: _i(j['logEntries']),
      customColumns: _i(j['customColumns']),
      addedColumns: [for (final c in (j['addedColumns'] as List? ?? const [])) _s(c)],
      unsavedEntries: _i((j['unsavedFromLastTime'] as Map?)?['entries']),
      unsavedLast: _date((j['unsavedFromLastTime'] as Map?)?['last']),
    );

SheetAnalysis analysisFromJson(Json j) => SheetAnalysis(
      sheet: _s(j['sheet']),
      total: _i(j['total']),
      fields: [
        for (final f in (j['fields'] as List? ?? const []))
          FieldGap(
            field: _s((f as Json)['field']),
            missing: _i(f['missing']),
            ids: [for (final id in (f['ids'] as List? ?? const [])) _s(id)],
            never: f['never'] == true,
            custom: f['custom'] == true,
          ),
      ],
    );

RowSummary rowSummaryFromJson(Json j) => RowSummary(
      row: _i(j['row']),
      id: _s(j['id']),
      name: _s(j['name']),
      code: _s(j['code']),
      edition: _s(j['edition']),
      updatedAt: _date(j['updatedAt']),
      missing: [for (final m in (j['missing'] as List? ?? const [])) _s(m)],
      hasImage: j['hasImage'] == true,
    );

RowsPage rowsPageFromJson(Json j) => RowsPage(
      total: _i(j['total']),
      rows: [for (final r in (j['rows'] as List? ?? const [])) rowSummaryFromJson(r as Json)],
    );

Uint8List? bytesFromBase64(Object? v) => v is String && v.isNotEmpty ? base64Decode(v) : null;

RowDetail rowDetailFromJson(Json j) => RowDetail(
      row: _i(j['row']),
      id: _s(j['id']),
      parentId: j['parentId'] == null ? null : _s(j['parentId']),
      updatedAt: _date(j['updatedAt']),
      fields: [for (final f in (j['fields'] as List? ?? const [])) _s(f)],
      values: Map<String, Object?>.from(j['values'] as Map? ?? const {}),
      missing: [for (final m in (j['missing'] as List? ?? const [])) _s(m)],
      image: bytesFromBase64(j['image']),
      customFields: [for (final f in (j['customFields'] as List? ?? const [])) _s(f)],
    );

FillProposal proposalFromJson(Json j) => FillProposal(
      row: _i(j['row']),
      id: _s(j['id']),
      field: _s(j['field']),
      value: j['value'],
      source: _s(j['source']),
    );

/// id and source go along so the change log says where each value came from.
Json proposalToJson(FillProposal p) =>
    {'row': p.row, 'id': p.id, 'field': p.field, 'value': p.value, 'source': p.source};

ColumnInfo columnFromJson(Json j) => ColumnInfo(
      name: _s(j['name']),
      custom: j['custom'] == true,
      optional: j['optional'] == true,
      inherit: j['inherit'] == true,
      note: _s(j['note']),
      isImage: j['image'] == true,
      isId: j['id'] == true,
    );

String? _opt(Object? v) => v == null || '$v'.isEmpty ? null : '$v';

EditLogEntry editLogEntryFromJson(Json j) => EditLogEntry(
      at: _date(j['at']),
      source: _s(j['source']),
      action: _s(j['action']),
      sheet: _s(j['sheet']),
      rowId: _opt(j['rowId']),
      field: _opt(j['field']),
      oldValue: _opt(j['oldValue']),
      newValue: _opt(j['newValue']),
      note: _opt(j['note']),
    );

EditLogPage editLogFromJson(Json j) => EditLogPage(
      total: _i(j['total']),
      entries: [for (final e in (j['entries'] as List? ?? const [])) editLogEntryFromJson(e as Json)],
    );

RecentEdit recentEditFromJson(Json j) => RecentEdit(
      sheet: _s(j['sheet']),
      id: _s(j['id']),
      name: _s(j['name']),
      updatedAt: _date(j['updatedAt']),
    );
