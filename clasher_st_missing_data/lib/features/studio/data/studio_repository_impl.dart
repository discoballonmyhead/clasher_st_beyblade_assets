import 'dart:async';

import '../../../core/bridge/engine_bridge.dart';
import '../../../core/error/failure.dart';
import '../../../core/settings/app_settings.dart';
import '../domain/entities/studio_models.dart';
import '../domain/repositories/studio_repository.dart';

typedef Json = Map<String, dynamic>;

String _s(Object? v) => v == null ? '' : '$v';
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
Json _j(Object? v) => Map<String, dynamic>.from(v as Map? ?? const {});
List<String> _list(Object? v) => [for (final x in (v as List? ?? const [])) '$x'];

Criticality criticalityFrom(Object? v) => switch ('$v') {
  'required' => Criticality.required,
  'optional' => Criticality.optional,
  _ => Criticality.recommended,
};

StudioWorkspace workspaceFromJson(Json j) => StudioWorkspace(
  root: _s(j['root']),
  hobbies: [
    for (final h in (j['hobbies'] as List? ?? const []))
      Hobby(
        name: _s(_j(h)['name']),
        kind: _s(_j(h)['kind']).isEmpty ? 'parts' : _s(_j(h)['kind']),
        generations: _list(_j(h)['generations']),
        packaged: _j(h)['packaged'] == true,
        scraped: _j(h)['scraped'] == true,
        workbooks: [
          for (final w in (_j(h)['workbooks'] as List? ?? const []))
            WorkbookRef(
              role: _s(_j(w)['role']),
              file: _s(_j(w)['file']),
              path: _s(_j(w)['path']),
              exists: _j(w)['exists'] == true,
            ),
        ],
      ),
  ],
);

SheetProfile profileFromJson(Json j) => SheetProfile(
  sheet: _s(j['sheet']),
  tab: _s(j['tab']),
  workbook: _s(j['workbook']),
  generation: j['generation'] == null ? null : _s(j['generation']),
  source: _s(j['source']),
  columns: [
    for (final c in (j['columns'] as List? ?? const []))
      ColumnRule(
        name: _s(_j(c)['name']),
        include: _j(c)['include'] != false,
        criticality: criticalityFrom(_j(c)['criticality']),
        defaultCriticality: criticalityFrom(_j(c)['default']),
        locked: _j(c)['locked'] == true,
        appRequired: _j(c)['appRequired'] == true,
      ),
  ],
);

GitStatus gitStatusFromJson(Json j) => GitStatus(
  isRepo: j['isRepo'] == true,
  branch: _s(j['branch']),
  remote: _s(j['remote']),
  changed: _i(j['changed']),
  changedImages: _i(j['changedImages']),
  sample: _list(j['sample']),
  ahead: j['ahead'] == null ? null : _i(j['ahead']),
  behind: j['behind'] == null ? null : _i(j['behind']),
  detail: _s(j['detail']),
  userName: _s(j['userName']),
  userEmail: _s(j['userEmail']),
);

/// studio_tool.py over its own bridge.
class StudioRepositoryImpl implements StudioRepository {
  StudioRepositoryImpl(this._bridge, this._settings);

  final EngineBridge _bridge;
  final AppSettings _settings;

  Future<Object?> _call(String cmd, [Map<String, Object?> args = const {}, Duration? timeout = const Duration(minutes: 2)]) async {
    if (!_bridge.isRunning) await _bridge.start(_settings.studioEngineConfig);
    return _bridge.call(cmd, args, timeout);
  }

  Future<Json> _map(String cmd, [Map<String, Object?> args = const {}]) async => _j(await _call(cmd, args));

  Future<Result<T>> _guard<T>(Future<T> Function() run) async {
    try {
      return Ok(await run());
    } on EngineException catch (e) {
      return Err(Failure(e.message));
    } on TypeError catch (e) {
      return Err(Failure('Unexpected answer from the studio engine: $e'));
    }
  }

  Future<Result<String>> _job(String cmd, Map<String, Object?> args) =>
      _guard(() async => _s((await _map(cmd, args))['id']));

  @override
  Stream<JobEvent> get jobEvents => _bridge.events
      .where((e) => e['event'] == 'job' || e['event'] == 'jobDone')
      .map((e) => e['event'] == 'job'
          ? JobEvent(id: _s(e['id']), line: _s(e['line']))
          : JobEvent(id: _s(e['id']), done: true, ok: e['ok'] == true, result: e['result'], error: e['error'] as String?));

  @override
  Future<Result<StudioWorkspace>> workspace() =>
      _guard(() async => workspaceFromJson(await _map('workspace', {'dataRoot': _settings.toolsDir})));

  @override
  Future<Result<StudioWorkspace>> saveWorkspace(List<Hobby> hobbies) => _guard(() async {
    await _map('setWorkspace', {
      'workspace': {'hobbies': [for (final h in hobbies) h.toJson()]},
    });
    return workspaceFromJson(await _map('workspace', {'dataRoot': _settings.toolsDir}));
  });

  @override
  Future<Result<List<SheetProfile>>> profiles() => _guard(() async => [
    for (final p in ((await _map('profiles', {'dataRoot': _settings.toolsDir}))['sheets'] as List? ?? const []))
      profileFromJson(_j(p)),
  ]);

  @override
  Future<Result<SheetProfile>> saveProfile(String sheet, List<ColumnRule> columns) => _guard(() async =>
      profileFromJson(await _map('setProfile', {
        'sheet': sheet,
        'columns': {
          for (final c in columns)
            if (!c.locked) c.name: {'include': c.include, 'criticality': c.criticality.name},
        },
      })));

  @override
  Future<Result<ToolsStatus>> tools() => _guard(() async {
    final j = await _map('tools');
    final auth = j['ghAuth'] == null ? null : _j(j['ghAuth']);
    return ToolsStatus(
      git: j['git'] == true,
      gh: j['gh'] == true,
      ghUser: auth?['user'] as String?,
      ghSignedIn: auth?['ok'] == true,
      ghDetail: _s(auth?['detail']),
    );
  });

  @override
  Future<Result<GitStatus>> gitStatus(String repo, {List<String> paths = const ['data']}) =>
      _guard(() async => gitStatusFromJson(await _map('gitStatus', {'repo': repo, 'paths': paths})));

  @override
  Future<Result<GitStatus>> setGitIdentity(String repo, {required String name, required String email}) =>
      _guard(() async => gitStatusFromJson(await _map('setGitIdentity', {'repo': repo, 'name': name, 'email': email})));

  @override
  Future<Result<List<ReleaseInfo>>> releases(String slug) => _guard(() async => [
    for (final r in (await _call('releases', {'slug': slug}) as List? ?? const []))
      ReleaseInfo(
        tag: _s(_j(r)['tagName']),
        name: _s(_j(r)['name']),
        publishedAt: DateTime.tryParse(_s(_j(r)['publishedAt'])),
        isLatest: _j(r)['isLatest'] == true,
        isDraft: _j(r)['isDraft'] == true,
      ),
  ]);

  @override
  Future<Result<List<ReleaseAsset>>> releaseAssets(String slug, String tag) => _guard(() async => [
    for (final a in ((await _map('releaseAssets', {'slug': slug, 'tag': tag}))['assets'] as List? ?? const []))
      ReleaseAsset(name: _s(_j(a)['name']), size: _i(_j(a)['size']), downloads: _i(_j(a)['downloads'])),
  ]);

  @override
  Future<Result<String>> package({
    required List<String> books,
    required String out,
    required String owner,
    required String repo,
    required String branch,
  }) => _job('package', {'books': books, 'out': out, 'owner': owner, 'repo': repo, 'branch': branch});

  @override
  Future<Result<String>> commitPush({
    required String repo,
    required String message,
    List<String> paths = const ['data'],
    bool push = true,
  }) => _job('commitPush', {'repo': repo, 'message': message, 'paths': paths, 'push': push});

  @override
  Future<Result<String>> buildRelease({
    required String data,
    required String out,
    required String tag,
    required String owner,
    required String repo,
    bool dropInvalid = false,
    String? appAssets,
  }) => _job('buildRelease', {
    'data': data,
    'out': out,
    'tag': tag,
    'owner': owner,
    'repo': repo,
    'dropInvalid': dropInvalid,
    if (appAssets != null && appAssets.trim().isNotEmpty) 'appAssets': appAssets.trim(),
  });

  @override
  Future<Result<String>> publishRelease({
    required String slug,
    required String tag,
    required List<String> files,
    String? title,
    String? notes,
    bool latest = false,
  }) => _job('publishRelease', {
    'slug': slug,
    'tag': tag,
    'files': files,
    'title': title,
    'notes': notes,
    'latest': latest,
  });

  @override
  Future<Result<String>> scrape({required List<String> targets, Map<String, Object?> options = const {}}) =>
      _job('scrape', {'targets': targets, 'options': options});

  @override
  Future<Result<void>> stopJob(String id) => _guard(() => _call('jobStop', {'id': id}));

  @override
  Future<Result<ScraperOverview>> scraperTargets() => _guard(() async {
    final j = await _map('scraperTargets');
    return ScraperOverview(
      configPath: _s(j['config']),
      userAgent: _s(j['userAgent']),
      politeness: _j(j['politeness']),
      stateDir: _s(j['stateDir']),
      targets: [
        for (final t in (j['targets'] as List? ?? const []))
          ScraperTarget(
            target: _s(_j(t)['target']),
            kind: _s(_j(t)['kind']),
            generation: _s(_j(t)['generation']),
            hobby: _s(_j(t)['hobby']),
            key: _j(t)['key'] == null ? null : _s(_j(t)['key']),
            categories: _list(_j(t)['categories']),
            progress: _j(t)['progress'] == null ? null : _j(_j(t)['progress']),
            hasPlugin: _j(t)['plugin'] == true,
          ),
      ],
    );
  });

  @override
  Future<Result<Map<String, dynamic>>> scraperTargetConfig(String target) =>
      _guard(() async => _j((await _map('scraperTarget', {'target': target}))['config']));

  @override
  Future<Result<void>> saveScraperTargetConfig(String target, Map<String, dynamic> config) =>
      _guard(() => _map('setScraperTarget', {'target': target, 'config': config}));

  @override
  Future<Result<void>> saveScraperSettings({String? userAgent, Map<String, Object?>? politeness}) =>
      _guard(() => _map('setScraperSettings', {'userAgent': userAgent, 'politeness': politeness}));

  @override
  Future<Result<({String path, String text, bool exists, String scraperPath})>> codeFiles(String hobby, String generation) =>
      _guard(() async {
        final j = await _map('codeFiles', {'hobby': hobby, 'generation': generation});
        final p = _j(j['plugin']);
        return (path: _s(p['path']), text: _s(p['text']), exists: p['exists'] == true, scraperPath: _s(_j(j['scraper'])['path']));
      });

  @override
  Future<Result<({String path, String text})>> readCode(String path) => _guard(() async {
    final j = await _map('readCode', {'path': path});
    return (path: _s(j['path']), text: _s(j['text']));
  });

  @override
  Future<Result<CodeCheck>> checkCode(String path, String text) => _guard(() async {
    final j = await _map('checkCode', {'path': path, 'text': text});
    return CodeCheck(ok: j['ok'] == true, line: j['line'] == null ? null : _i(j['line']), message: _s(j['message']));
  });

  @override
  Future<Result<void>> saveCode(String path, String text) => _guard(() => _map('saveCode', {'path': path, 'text': text}));
}
