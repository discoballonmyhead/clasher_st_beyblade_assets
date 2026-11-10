import 'dart:async';

import 'package:missing_data_app/core/error/failure.dart';
import 'package:missing_data_app/features/studio/domain/entities/studio_models.dart';
import 'package:missing_data_app/features/studio/domain/repositories/studio_repository.dart';

/// In-memory studio_tool.py: a workspace, profiles, and jobs that print a few lines and finish.
class FakeStudioRepository implements StudioRepository {
  FakeStudioRepository({StudioWorkspace? workspace, this.jobResults = const {}})
    : _ws = workspace ??
          const StudioWorkspace(root: '/tmp', hobbies: [
            Hobby(
              name: 'Beyblade',
              generations: ['Burst', 'X'],
              packaged: true,
              scraped: true,
              workbooks: [
                WorkbookRef(role: 'parts', file: 'beyblade_parts.xlsx', path: '/tmp/beyblade_parts.xlsx', exists: true),
                WorkbookRef(role: 'products', file: 'beyblade_products.xlsx', path: '/tmp/beyblade_products.xlsx', exists: true),
              ],
            ),
            Hobby(
              name: 'Beyblade TCG',
              generations: ['Original', 'X'],
              packaged: true,
              scraped: true,
              workbooks: [WorkbookRef(role: 'tcg', file: 'beyblade_tcg.xlsx', path: '/tmp/beyblade_tcg.xlsx', exists: true)],
            ),
          ]);

  StudioWorkspace _ws;

  /// What a job of a kind (package, commitPush, buildRelease, publishRelease, scrape) ends with.
  final Map<String, Object?> jobResults;

  /// Kinds that end with an error.
  final failJobs = <String>{};
  final calls = <String, List<Map<String, Object?>>>{};
  final stopped = <String>[];
  final saved = <String, String>{};
  final _events = StreamController<JobEvent>.broadcast();
  var _n = 0;

  ToolsStatus tools_ = const ToolsStatus(git: true, gh: true, ghSignedIn: true, ghUser: 'tester');
  GitStatus git_ = const GitStatus(isRepo: true, branch: 'main', remote: 'origin', changed: 3, sample: ['data/blades.json']);

  List<SheetProfile> profiles_ = [
    const SheetProfile(sheet: 'blades', tab: 'Parts_X_Blades', workbook: 'beyblade_parts.xlsx', generation: 'X', source: 'workbook', columns: [
      ColumnRule(name: 'id', locked: true, appRequired: true, criticality: Criticality.required, defaultCriticality: Criticality.required),
      ColumnRule(name: 'name', locked: true, appRequired: true, criticality: Criticality.required, defaultCriticality: Criticality.required),
      ColumnRule(name: 'attack'),
      ColumnRule(name: 'notes', criticality: Criticality.optional, defaultCriticality: Criticality.optional),
    ]),
  ];

  void _call(String name, [Map<String, Object?> args = const {}]) => (calls[name] ??= []).add(args);

  Future<Result<String>> _job(String kind, Map<String, Object?> args) async {
    _call(kind, args);
    final id = 'job${++_n}';
    // the engine prints asynchronously, after the id is returned
    scheduleMicrotask(() async {
      await Future<void>.delayed(Duration.zero);
      _events.add(JobEvent(id: id, line: '$kind started'));
      _events.add(JobEvent(id: id, line: '$kind working'));
      await Future<void>.delayed(Duration.zero);
      if (failJobs.contains(kind)) {
        _events.add(JobEvent(id: id, done: true, ok: false, error: '$kind failed on purpose'));
      } else {
        _events.add(JobEvent(id: id, done: true, ok: true, result: jobResults[kind] ?? defaultResult(kind)));
      }
    });
    return Ok(id);
  }

  static Object? defaultResult(String kind) => switch (kind) {
    'package' => {
      'out': '/tmp/data',
      'ok': true,
      'errors': [],
      'warnings': [
        {'sheet': 'blades', 'id': 'b1', 'message': 'no image'},
      ],
      'errorCount': 0,
      'warningCount': 1,
      'sheets': {
        'blades': {'rowCount': 12},
      },
      'changes': {},
    },
    'commitPush' => {'head': 'abc1234', 'pushed': true},
    'buildRelease' => {
      'folder': '/tmp/_release/v9',
      'manifest': {'releaseTag': 'v9'},
      'files': ['/tmp/_release/v9/catalog.zip', '/tmp/_release/v9/catalog_manifest.json'],
      'packs': [],
    },
    'publishRelease' => {'created': true, 'url': 'https://example.invalid/r/v9', 'assets': ['catalog.zip', 'catalog_manifest.json']},
    _ => {'ok': true},
  };

  @override
  Stream<JobEvent> get jobEvents => _events.stream;

  @override
  Future<Result<StudioWorkspace>> workspace() async => Ok(_ws);

  @override
  Future<Result<StudioWorkspace>> saveWorkspace(List<Hobby> hobbies) async {
    _call('saveWorkspace', {'hobbies': hobbies.map((h) => h.name).toList()});
    if (hobbies.map((h) => h.name).toSet().length != hobbies.length) return const Err(Failure('Two hobbies have the same name'));
    _ws = StudioWorkspace(root: _ws.root, hobbies: hobbies);
    return Ok(_ws);
  }

  @override
  Future<Result<List<SheetProfile>>> profiles() async => Ok(profiles_);

  @override
  Future<Result<SheetProfile>> saveProfile(String sheet, List<ColumnRule> columns) async {
    _call('saveProfile', {'sheet': sheet, 'columns': columns});
    final i = profiles_.indexWhere((p) => p.sheet == sheet);
    final p = profiles_[i].withColumns(columns);
    profiles_ = [...profiles_]..[i] = p;
    return Ok(p);
  }

  @override
  Future<Result<ToolsStatus>> tools() async => Ok(tools_);

  @override
  Future<Result<GitStatus>> gitStatus(String repo, {List<String> paths = const ['data']}) async => Ok(git_);

  @override
  Future<Result<List<ReleaseInfo>>> releases(String slug) async {
    _call('releases', {'slug': slug});
    return Ok([ReleaseInfo(tag: 'v8', name: 'Catalog v8', isLatest: true, publishedAt: DateTime(2026, 10, 1))]);
  }

  @override
  Future<Result<List<ReleaseAsset>>> releaseAssets(String slug, String tag) async =>
      const Ok([ReleaseAsset(name: 'catalog.zip', size: 2048, downloads: 5)]);

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
  }) => _job('commitPush', {'repo': repo, 'message': message, 'push': push});

  @override
  Future<Result<String>> buildRelease({
    required String data,
    required String out,
    required String tag,
    required String owner,
    required String repo,
    bool dropInvalid = false,
    String? appAssets,
  }) => _job('buildRelease', {'data': data, 'out': out, 'tag': tag, 'dropInvalid': dropInvalid});

  @override
  Future<Result<String>> publishRelease({
    required String slug,
    required String tag,
    required List<String> files,
    String? title,
    String? notes,
    bool latest = false,
  }) => _job('publishRelease', {'slug': slug, 'tag': tag, 'files': files, 'latest': latest});

  @override
  Future<Result<String>> scrape({required List<String> targets, Map<String, Object?> options = const {}}) =>
      _job('scrape', {'targets': targets, 'options': options});

  @override
  Future<Result<void>> stopJob(String id) async {
    stopped.add(id);
    return const Ok(null);
  }

  // ── scrapers ──
  Map<String, dynamic> targetConfig = {'categories': ['Category:Blades']};

  @override
  Future<Result<ScraperOverview>> scraperTargets() async => const Ok(ScraperOverview(
    configPath: '/tmp/scraper_targets.json',
    userAgent: 'Studio/1.0 (contact: CHANGE_ME)',
    politeness: {'delay': 1.0},
    targets: [
      ScraperTarget(target: 'parts:X:blades', kind: 'parts', generation: 'X', hobby: 'Beyblade', key: 'blades', categories: ['Category:Blades']),
      ScraperTarget(target: 'products:X', kind: 'products', generation: 'X', hobby: 'Beyblade'),
      ScraperTarget(target: 'tcg:Original:cards', kind: 'tcg', generation: 'Original', hobby: 'Beyblade TCG', key: 'cards'),
    ],
  ));

  @override
  Future<Result<Map<String, dynamic>>> scraperTargetConfig(String target) async => Ok(targetConfig);

  @override
  Future<Result<void>> saveScraperTargetConfig(String target, Map<String, dynamic> config) async {
    _call('saveScraperTargetConfig', {'target': target, 'config': config});
    targetConfig = config;
    return const Ok(null);
  }

  @override
  Future<Result<void>> saveScraperSettings({String? userAgent, Map<String, Object?>? politeness}) async {
    _call('saveScraperSettings', {'userAgent': userAgent, 'politeness': politeness});
    return const Ok(null);
  }

  @override
  Future<Result<({String path, String text, bool exists, String scraperPath})>> codeFiles(String hobby, String generation) async =>
      Ok((
        path: '/tmp/scrapers/${hobby.toLowerCase().replaceAll(' ', '_')}/${generation.toLowerCase()}.py',
        text: saved.values.lastOrNull ?? 'def adjust_row(target, title, fields, row):\n    return row\n',
        exists: saved.isNotEmpty,
        scraperPath: '/tmp/fandom_scraper.py',
      ));

  @override
  Future<Result<({String path, String text})>> readCode(String path) async => Ok((path: path, text: saved[path] ?? '# scraper\n'));

  @override
  Future<Result<CodeCheck>> checkCode(String path, String text) async {
    _call('checkCode', {'path': path});
    if (text.contains('def adjust_row(') && !text.contains('):\n')) {
      return const Ok(CodeCheck(ok: false, line: 1, message: 'invalid syntax'));
    }
    if (text.contains('(((')) return const Ok(CodeCheck(ok: false, line: 1, message: 'invalid syntax'));
    return const Ok(CodeCheck(ok: true));
  }

  @override
  Future<Result<void>> saveCode(String path, String text) async {
    final check = (await checkCode(path, text)).valueOrNull!;
    if (!check.ok) return Err(Failure('Line ${check.line}: ${check.message} - not saved'));
    saved[path] = text;
    return const Ok(null);
  }

  Future<void> dispose() => _events.close();
}
