import '../../domain/entities/translation_models.dart';

typedef Json = Map<String, dynamic>;

String _s(Object? v) => v == null ? '' : '$v';
String? _o(Object? v) => v == null || '$v'.isEmpty ? null : '$v';
int _i(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
double _d(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
List<String> _list(Object? v) => [
  for (final x in (v as List? ?? const [])) '$x',
];
Json _j(Object? v) => Map<String, dynamic>.from(v as Map? ?? const {});

TrSeverity severityFrom(Object? v) => switch ('$v') {
  'error' => TrSeverity.error,
  'warning' => TrSeverity.warning,
  _ => TrSeverity.info,
};

TrLanguage languageFromJson(Json j) => TrLanguage(
  column: _s(j['column']),
  code: _o(j['code']),
  name: _s(j['name']),
  country: _s(j['country']),
  how: _o(j['how']),
  status: _o(j['status']) ?? 'active',
);

TrSummary summaryFromJson(Json j) {
  final p = j['project'] == null ? null : _j(j['project']);
  final s = j['sheet'] == null ? null : _j(j['sheet']);
  final files = p == null ? const <String, dynamic>{} : _j(p['files']);
  return TrSummary(
    project: p == null
        ? null
        : TrProjectInfo(
            root: _s(p['root']),
            tokensFile: _o(files['tokens']),
            defaultsFile: _o(files['defaults']),
            languagesFile: _o(files['languages']),
            tokens: _i(p['tokens']),
            sections: _list(p['sections']),
            className: _o(p['class']) ?? 'TrTokens',
            registry: p['registry'] == null
                ? null
                : [
                    for (final r in p['registry'] as List)
                      RegistryLanguage(
                        code: _s(_j(r)['code']),
                        name: _s(_j(r)['name']),
                        country: _s(_j(r)['country']),
                      ),
                  ],
            rejected: _list(p['rejected']),
          ),
    sheet: s == null
        ? null
        : TrSheetInfo(
            path: _s(s['path']),
            tabs: _list(s['tabs']),
            keys: _i(s['keys']),
            languages: [
              for (final l in (s['languages'] as List? ?? const []))
                languageFromJson(_j(l)),
            ],
            meta: _list(s['meta']),
            dirty: s['dirty'] == true,
            undo: _i(s['undo']),
            locks: [
              for (final l in (s['locks'] as List? ?? const []))
                LockInfo(
                  file: _s(_j(l)['file']),
                  user: _o(_j(l)['user']),
                  machine: _o(_j(l)['machine']),
                  modified: _o(_j(l)['modified']),
                  stale: _j(l)['stale'] == true,
                ),
            ],
            unsupported: _list(s['unsupported']),
            hasLanguagesTab: s['hasLanguagesTab'] == true,
            unsavedFromLastTime: _i(s['unsavedFromLastTime']),
          ),
  );
}

TrReport reportFromJson(Json j) {
  final keys = _j(j['keys']);
  return TrReport(
    issues: [
      for (final i in (j['issues'] as List? ?? const []))
        TrIssue(
          kind: _s(_j(i)['kind']),
          severity: severityFrom(_j(i)['severity']),
          message: _s(_j(i)['message']),
          key: _o(_j(i)['key']),
          language: _o(_j(i)['language']),
          where: _o(_j(i)['where']),
        ),
    ],
    coverage: [
      for (final c in (j['coverage'] as List? ?? const []))
        TrCoverage(
          language: languageFromJson(_j(c)),
          translated: _i(_j(c)['translated']),
          total: _i(_j(c)['total']),
          percent: _d(_j(c)['percent']),
          sameAsEnglish: _i(_j(c)['sameAsEnglish']),
        ),
    ],
    keysInApp: _i(keys['app']),
    keysInSheet: _i(keys['sheet']),
    keysInBoth: _i(keys['both']),
  );
}

TrProblem problemFromJson(Json j) => TrProblem(
  language: _s(j['language']),
  kind: _s(j['kind']),
  severity: severityFrom(j['severity']),
  message: _s(j['message']),
);

TrKeyRow keyRowFromJson(Json j) => TrKeyRow(
  key: _s(j['key']),
  token: _o(j['token']),
  section: _o(j['section']),
  subsection: _o(j['subsection']),
  comment: _s(j['comment']),
  appEnglish: j['appEnglish'] == null ? null : _s(j['appEnglish']),
  sheetEnglish: j['sheetEnglish'] == null ? null : _s(j['sheetEnglish']),
  where: _o(j['where']),
  translations: {
    for (final e in _j(j['translations']).entries) e.key: _s(e.value),
  },
  missingLanguages: _list(j['missingLanguages']),
  status: _list(j['status']),
  problems: [
    for (final p in (j['problems'] as List? ?? const []))
      problemFromJson(_j(p)),
  ],
  uses: _i(j['uses']),
);

TrKeysPage keysPageFromJson(Json j) => TrKeysPage(
  total: _i(j['total']),
  rows: [
    for (final r in (j['rows'] as List? ?? const [])) keyRowFromJson(_j(r)),
  ],
);

HardcodedString hardcodedFromJson(Json j) => HardcodedString(
  file: _s(j['file']),
  line: _i(j['line']),
  col: _i(j['col']),
  text: _s(j['text']),
  key: _s(j['key']),
  context: _s(j['context']),
  confidence: _o(j['confidence']) ?? 'high',
  placeholders: _list(j['placeholders']),
  existingKey: _o(j['existingKey']),
  snippet: _s(j['snippet']),
);

ExportResult exportFromJson(Json j) => ExportResult(
  out: _s(j['out']),
  problems: _list(j['problems']),
  files: [
    for (final f in (j['files'] as List? ?? const []))
      ExportFile(
        kind: _s(_j(f)['kind']),
        relative: _s(_j(f)['relative']),
        projectPath: _s(_j(f)['project']),
        exportPath: _s(_j(f)['export']),
        created: _j(f)['created'] == true,
        added: _i(_j(f)['added']),
        updated: _i(_j(f)['updated']),
        identical: _j(f)['identical'] == true,
        diff: _s(_j(f)['diff']),
      ),
  ],
);

PackReport packsFromJson(Json j, String out) => PackReport(
  out: out,
  totalKeys: _i(j['totalKeys']),
  packs: [
    for (final p in (j['packs'] as List? ?? const []))
      PackInfo(
        code: _s(_j(p)['code']),
        column: _s(_j(p)['column']),
        file: _s(_j(p)['file']),
        keys: _i(_j(p)['keys']),
        bytes: _i(_j(p)['bytes']),
        sha256: _s(_j(p)['sha256']),
        changed: _j(p)['changed'] != false,
        errors: _i(_j(p)['errors']),
      ),
  ],
  skipped: [
    for (final s in (j['skipped'] as List? ?? const []))
      PackSkip(
        code: _o(_j(s)['code']),
        column: _s(_j(s)['column']),
        reason: _s(_j(s)['reason']),
      ),
  ],
);
