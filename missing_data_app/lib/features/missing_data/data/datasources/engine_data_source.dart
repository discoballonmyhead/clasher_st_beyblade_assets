import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../../../core/bridge/engine_bridge.dart';
import '../../../../core/settings/app_settings.dart';
import '../../domain/entities/row.dart';
import '../models/mappers.dart';

/// Raw engine calls. Starts the engine on first use with the configured Python + tools folder.
class EngineDataSource {
  EngineDataSource(this._bridge, this._settings);

  final EngineBridge _bridge;
  final AppSettings _settings;

  Future<Object?> _call(String cmd, [Map<String, Object?> args = const {}, Duration? timeout = const Duration(minutes: 2)]) async {
    if (!_bridge.isRunning) await _bridge.start(_settings.engineConfig);
    return _bridge.call(cmd, args, timeout);
  }

  Future<Json> _map(String cmd, [Map<String, Object?> args = const {}, Duration? timeout = const Duration(minutes: 2)]) async =>
      Map<String, dynamic>.from(await _call(cmd, args, timeout) as Map);

  Future<Json> ping() => _map('ping');
  Future<Json> open(String path) => _map('open', {'path': path}, const Duration(minutes: 5));
  Future<Json> summary() => _map('summary');
  Future<Json> analyze(String sheet, bool includeOptional) =>
      _map('analyze', {'sheet': sheet, 'includeOptional': includeOptional});
  Future<Json> rows(String sheet, String? field, String query, RowSort sort, bool includeOptional) => _map('rows', {
        'sheet': sheet,
        'field': field,
        'query': query,
        'sort': sort.name,
        'includeOptional': includeOptional,
      });
  Future<Json> row(String sheet, String id) => _map('row', {'sheet': sheet, 'id': id});
  Future<Json> set(String sheet, String id, Map<String, String> values) =>
      _map('set', {'sheet': sheet, 'id': id, 'values': values});
  Future<List<Json>> proposals(String sheet, bool parent, bool siblings, bool derive) async => [
        for (final p in (await _call('proposals',
            {'sheet': sheet, 'parent': parent, 'siblings': siblings, 'derive': derive}) as List))
          Map<String, dynamic>.from(p as Map),
      ];
  Future<Json> apply(String sheet, List<Json> items) => _map('apply', {'sheet': sheet, 'items': items});
  Future<Json> image(String sheet, String id, Uint8List bytes) =>
      _map('image', {'sheet': sheet, 'id': id, 'base64': base64Encode(bytes)});
  Future<Json> imageUrl(String sheet, String id, String url) =>
      _map('image', {'sheet': sheet, 'id': id, 'url': url});
  Future<Json> parentImage(String sheet, String id) => _map('parentImage', {'sheet': sheet, 'id': id});
  Future<Json> undo() => _map('undo');
  Future<Json> save() => _map('save', const {}, const Duration(minutes: 5));
  Future<List<Json>> recent(int limit) async =>
      [for (final e in (await _call('recent', {'limit': limit}) as List)) Map<String, dynamic>.from(e as Map)];
  Future<Json> wiki(String sheet, List<String> ids) => _map('wiki', {'sheet': sheet, 'ids': ids}, null);
  Future<Json> stopWiki() => _map('stop');

  Future<Json> addColumn(List<String> sheets, String name, bool optional, bool inherit, String? defaultValue,
          String note) =>
      _map('addColumn', {
        'sheets': sheets,
        'name': name,
        'optional': optional,
        'inherit': inherit,
        'default': defaultValue,
        'note': note,
      });
  Future<Json> addRow(String sheet, Map<String, String>? values, String? copyFrom, String mode) =>
      _map('addRow', {'sheet': sheet, 'values': values, 'copyFrom': copyFrom, 'mode': mode});
  Future<Json> columns(String sheet) => _map('columns', {'sheet': sheet});
  Future<Json> editLog(int limit, String? sheet, String query) =>
      _map('log', {'limit': limit, 'sheet': sheet, 'query': query});

  /// Engine log lines (scraper progress during wiki fills, errors on stderr).
  Stream<String> get log => _bridge.events
      .where((e) => e['message'] != null)
      .map((e) => '${e['message']}');
}
