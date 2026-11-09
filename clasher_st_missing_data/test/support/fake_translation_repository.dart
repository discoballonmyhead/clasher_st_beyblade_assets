import 'package:missing_data_app/core/error/failure.dart';
import 'package:missing_data_app/features/translations/domain/entities/translation_models.dart';
import 'package:missing_data_app/features/translations/domain/entities/translation_project.dart';
import 'package:missing_data_app/features/translations/domain/repositories/translation_repository.dart';

/// In memory: an app with three constants, a sheet with three keys (one only in the sheet), two languages.
class FakeTranslationRepository implements TranslationRepository {
  final appEnglish = <String, String>{
    'email_txt': 'Email',
    'welcome_back_txt': 'Welcome back, {name}',
    'edit_list_txt': 'Edit list',
  };
  final sheet = <String, Map<String, String>>{
    'email_txt': {'English': 'Email', 'Japanese': 'メール', 'Korean': ''},
    'welcome_back_txt': {
      'English': 'Welcome back, {name}',
      'Japanese': 'おかえり {name}',
      'Korean': '',
    },
    'my_decks_txt': {'English': 'My Decks', 'Japanese': '', 'Korean': '내 덱'},
  };
  var languages = const [
    TrLanguage(
      column: 'Japanese',
      code: 'ja',
      name: '日本語',
      country: 'JP',
      how: 'known name',
    ),
    TrLanguage(
      column: 'Korean',
      code: 'ko',
      name: '한국어',
      country: 'KR',
      how: 'known name',
    ),
  ];
  final hardcodedList = <HardcodedString>[
    const HardcodedString(
      file: 'lib/a.dart',
      line: 3,
      text: 'Search lists',
      key: 'search_lists_hint',
      context: 'hintText',
    ),
    const HardcodedString(
      file: 'lib/a.dart',
      line: 9,
      text: 'Email',
      key: 'email_txt',
      existingKey: 'email_txt',
      context: 'Text',
    ),
  ];
  bool dirty = false;
  int undoSteps = 0;
  int unsaved = 0;
  ExportCall? lastExport;
  List<String> appliedFrom = [];
  bool saveConflict = false;

  List<String> get _cols => [for (final l in languages) l.column];

  TrSummary get _summary => TrSummary(
    project: const TrProjectInfo(
      root: '/app',
      tokensFile: '/app/lib/core/constants/trc_constant_tokens.dart',
      defaultsFile: '/app/lib/core/constants/default_english_tr.dart',
      languagesFile: '/app/lib/core/constants/app_language_constants.dart',
      tokens: 3,
      sections: ['COMMON', 'LISTS'],
      registry: [
        RegistryLanguage(code: 'en', name: 'English', country: 'US'),
        RegistryLanguage(code: 'ja', name: '日本語', country: 'JP'),
      ],
    ),
    sheet: TrSheetInfo(
      path: '/tr/ClasherSTTr.xlsx',
      tabs: const ['Sheet1'],
      keys: sheet.length,
      languages: languages,
      dirty: dirty,
      undo: undoSteps,
      hasLanguagesTab: true,
      unsavedFromLastTime: unsaved,
    ),
  );

  List<TrProblem> _problems(String english, String col, String text) {
    final pe = placeholdersOf(english), pt = placeholdersOf(text);
    return [
      if (text.isNotEmpty && pe.any((p) => !pt.contains(p)))
        TrProblem(
          language: col,
          kind: 'placeholder_missing',
          severity: TrSeverity.error,
          message: 'missing',
        ),
    ];
  }

  @override
  Future<Result<TrSummary>> open(TranslationProject project) async =>
      Ok(_summary);
  @override
  Future<Result<TrSummary>> summary() async => Ok(_summary);
  @override
  Future<Result<int>> scan() async => Ok(hardcodedList.length);

  @override
  Future<Result<TrReport>> report() async {
    final issues = <TrIssue>[
      for (final k in appEnglish.keys)
        if (!sheet.containsKey(k))
          TrIssue(
            kind: 'missing_in_sheet',
            severity: TrSeverity.warning,
            message: 'in the app, not in the sheet',
            key: k,
          ),
      for (final k in sheet.keys)
        if (!appEnglish.containsKey(k))
          TrIssue(
            kind: 'missing_in_app',
            severity: TrSeverity.info,
            message: 'in the sheet, not in TrTokens',
            key: k,
          ),
      for (final h in hardcodedList)
        TrIssue(
          kind: 'hardcoded',
          severity: TrSeverity.warning,
          message: '"${h.text}" is written in the code',
          key: h.key,
        ),
    ];
    return Ok(
      TrReport(
        issues: issues,
        keysInApp: appEnglish.length,
        keysInSheet: sheet.length,
        keysInBoth: appEnglish.keys.where(sheet.containsKey).length,
        coverage: [
          for (final l in languages)
            TrCoverage(
              language: l,
              translated: sheet.values
                  .where((v) => (v[l.column] ?? '').isNotEmpty)
                  .length,
              total: sheet.length,
              percent:
                  100 *
                  sheet.values
                      .where((v) => (v[l.column] ?? '').isNotEmpty)
                      .length /
                  sheet.length,
            ),
        ],
      ),
    );
  }

  @override
  Future<Result<TrKeysPage>> keys({
    String query = '',
    String? status,
    String? missingIn,
    int limit = 5000,
  }) async {
    final all = {...appEnglish.keys, ...sheet.keys};
    final rows = <TrKeyRow>[];
    for (final k in all) {
      final s = sheet[k];
      final st = [
        if (!sheet.containsKey(k)) TrStatus.missingInSheet,
        if (!appEnglish.containsKey(k)) TrStatus.missingInApp,
        if (s != null &&
            appEnglish.containsKey(k) &&
            appEnglish[k] != s['English'])
          TrStatus.englishMismatch,
        if (s != null && _cols.any((c) => (s[c] ?? '').isEmpty))
          TrStatus.untranslated,
      ];
      if (status != null && !st.contains(status)) continue;
      if (query.isNotEmpty && !k.contains(query)) continue;
      rows.add(
        TrKeyRow(
          key: k,
          token: appEnglish.containsKey(k) ? tokenNameFor(k) : null,
          section: appEnglish.containsKey(k) ? 'COMMON' : null,
          appEnglish: appEnglish[k],
          sheetEnglish: s?['English'],
          where: s == null ? null : 'Sheet1!2',
          translations: {for (final c in _cols) c: s?[c] ?? ''},
          missingLanguages: [
            for (final c in _cols)
              if ((s?[c] ?? '').isEmpty) c,
          ],
          status: st,
        ),
      );
    }
    return Ok(TrKeysPage(total: rows.length, rows: rows));
  }

  @override
  Future<Result<List<HardcodedString>>> hardcoded() async => Ok(hardcodedList);

  @override
  Future<Result<List<TrProblem>>> setCells(
    List<({String key, String column, String text})> items,
  ) async {
    final problems = <TrProblem>[];
    for (final i in items) {
      sheet[i.key]![i.column] = i.text;
      if (i.column != 'English') {
        problems.addAll(_problems(sheet[i.key]!['English']!, i.column, i.text));
      }
    }
    dirty = true;
    undoSteps++;
    return Ok(problems);
  }

  @override
  Future<Result<({List<String> added, List<String> skipped})>> addRows(
    List<({String key, String english, Map<String, String> meta})> items,
  ) async {
    final added = <String>[], skipped = <String>[];
    for (final i in items) {
      if (sheet.containsKey(i.key)) {
        skipped.add('${i.key} is already in the sheet');
        continue;
      }
      sheet[i.key] = {'English': i.english, for (final c in _cols) c: ''};
      added.add(i.key);
    }
    hardcodedList.removeWhere((h) => added.contains(h.key));
    dirty = true;
    undoSteps++;
    return Ok((added: added, skipped: skipped));
  }

  @override
  Future<Result<void>> addLanguage({
    required String column,
    String? code,
    String? name,
    String? country,
  }) async {
    languages = [
      ...languages,
      TrLanguage(
        column: column,
        code: code,
        name: name ?? '',
        country: country ?? '',
      ),
    ];
    for (final v in sheet.values) {
      v[column] = '';
    }
    dirty = true;
    return const Ok(null);
  }

  @override
  Future<Result<void>> setLanguages(List<TrLanguage> l) async {
    languages = l;
    dirty = true;
    return const Ok(null);
  }

  @override
  Future<Result<String?>> undo() async => Ok(undoSteps-- > 0 ? 'edit' : null);

  @override
  Future<Result<String>> save({bool force = false}) async {
    if (saveConflict && !force) {
      return const Err(
        Failure('ClasherSTTr.xlsx changed on disk since it was opened'),
      );
    }
    dirty = false;
    return const Ok('/tr/backups/ClasherSTTr-1.xlsx');
  }

  @override
  Future<Result<int>> recoverUnsaved() async {
    final n = unsaved;
    unsaved = 0;
    dirty = true;
    return Ok(n);
  }

  @override
  Future<Result<void>> discardUnsaved() async {
    unsaved = 0;
    return const Ok(null);
  }

  @override
  Future<Result<ExportResult>> exportDart(
    String outDir, {
    List<String> addKeys = const [],
    List<String> updateEnglish = const [],
    Map<String, String> sections = const {},
  }) async {
    lastExport = ExportCall(outDir, addKeys, updateEnglish, sections);
    return Ok(
      ExportResult(
        out: outDir,
        files: [
          ExportFile(
            kind: 'tokens',
            relative: 'lib/core/constants/trc_constant_tokens.dart',
            projectPath: '/app/lib/core/constants/trc_constant_tokens.dart',
            exportPath: '$outDir/lib/core/constants/trc_constant_tokens.dart',
            added: addKeys.length,
            diff: '+  static const String myDecksTxt = \'my_decks_txt\';',
          ),
        ],
      ),
    );
  }

  @override
  Future<Result<List<String>>> applyExport(String outDir) async {
    appliedFrom.add(outDir);
    for (final k in lastExport?.addKeys ?? const <String>[]) {
      appEnglish[k] = sheet[k]?['English'] ?? '';
    }
    return const Ok(['lib/core/constants/trc_constant_tokens.dart']);
  }

  @override
  Future<Result<PackReport>> buildPacks(
    String outDir, {
    bool strict = false,
  }) async => Ok(
    PackReport(
      out: outDir,
      totalKeys: sheet.length,
      packs: [
        for (final l in languages)
          PackInfo(
            code: l.code!,
            column: l.column,
            file: 'lang_${l.code}.zip',
            keys: 2,
            bytes: 900,
            sha256: 'x',
          ),
      ],
    ),
  );
}

class ExportCall {
  ExportCall(this.out, this.addKeys, this.updateEnglish, this.sections);
  final String out;
  final List<String> addKeys;
  final List<String> updateEnglish;
  final Map<String, String> sections;
}
