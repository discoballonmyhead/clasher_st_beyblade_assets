import '../../../../core/bridge/engine_bridge.dart';
import '../../../../core/settings/app_settings.dart';

typedef Json = Map<String, dynamic>;

/// Raw calls to translation_tool.py serve (its own process, separate from the data engine).
class TranslationDataSource {
  TranslationDataSource(this._bridge, this._settings);

  final EngineBridge _bridge;
  final AppSettings _settings;

  Future<Object?> _call(
    String cmd, [
    Map<String, Object?> args = const {},
    Duration? timeout = const Duration(minutes: 3),
  ]) async {
    if (!_bridge.isRunning) {
      await _bridge.start(_settings.translationEngineConfig);
    }
    return _bridge.call(cmd, args, timeout);
  }

  Future<Json> _map(
    String cmd, [
    Map<String, Object?> args = const {},
    Duration? timeout = const Duration(minutes: 3),
  ]) async => Map<String, dynamic>.from(await _call(cmd, args, timeout) as Map);

  Future<Json> open(
    String project,
    String sheet,
    Map<String, String> overrides,
  ) => _map('open', {
    'project': project.trim().isEmpty ? null : project,
    'sheet': sheet.trim().isEmpty ? null : sheet,
    'overrides': overrides,
  }, const Duration(minutes: 5));
  Future<Json> summary() => _map('summary');
  Future<Json> scan() => _map('scan', const {}, const Duration(minutes: 5));
  Future<Json> report() => _map('report', const {}, const Duration(minutes: 5));
  Future<Json> keys(
    String query,
    String? status,
    String? missingIn,
    int limit,
  ) => _map('keys', {
    'query': query,
    'status': status,
    'language': missingIn,
    'limit': limit,
  });
  Future<List<Object?>> hardcoded() async =>
      (await _call('hardcoded') as List).cast<Object?>();
  Future<Json> set(List<Json> items) => _map('set', {'items': items});
  Future<Json> addRows(List<Json> items) => _map('addRows', {'items': items});
  Future<Json> addLanguage(Json args) => _map('addLanguage', args);
  Future<Json> setLanguages(List<Json> rows) =>
      _map('setLanguages', {'rows': rows});
  Future<Json> undo() => _map('undo');
  Future<Json> save(bool force) =>
      _map('save', {'force': force}, const Duration(minutes: 5));
  Future<Json> recover() =>
      _map('recover', const {}, const Duration(minutes: 5));
  Future<Json> discardUnsaved() => _map('discardUnsaved');
  Future<Json> exportDart(
    String out,
    List<String> addKeys,
    List<String> updateEnglish,
    Map<String, String> sections,
  ) => _map('exportDart', {
    'out': out,
    'addKeys': addKeys,
    'updateEnglish': updateEnglish,
    'sections': sections,
  });
  Future<Json> applyExport(String out) => _map('applyExport', {'out': out});
  Future<Json> buildPacks(String out, bool strict) => _map('buildPacks', {
    'out': out,
    'strict': strict,
  }, const Duration(minutes: 5));
}
