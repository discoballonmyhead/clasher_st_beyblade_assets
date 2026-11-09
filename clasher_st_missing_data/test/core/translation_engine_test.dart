import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:missing_data_app/core/bridge/engine_bridge.dart';
import 'package:missing_data_app/core/settings/app_settings.dart';
import 'package:missing_data_app/features/translations/data/datasources/translation_data_source.dart';
import 'package:missing_data_app/features/translations/data/repositories/translation_repository_impl.dart';
import 'package:missing_data_app/features/translations/domain/entities/translation_project.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// translation_tool.py through the real bridge, on a throwaway Flutter project and sheet.
/// Skipped when Python or the tools folder isn't there.
void main() {
  final toolsDir = Directory.current.parent.path;
  final python = Platform.environment['MDT_PYTHON'] ?? 'python3';
  final hasTools = File('$toolsDir/translation_tool.py').existsSync();

  late EngineBridge bridge;
  late TranslationRepositoryImpl repo;
  late Directory tmp;
  late TranslationProject project;

  const tokens = '''class TrTokens {
  TrTokens._();

  // ══ COMMON ═════════════════════════════
  static const String emailTxt = 'email_txt';
  static const String welcomeBackTxt = 'welcome_back_txt'; // {name}
}
''';
  const defaults = '''import 'trc_constant_tokens.dart';

const Map<String, String> defaultEnglishTranslations = {
  // ══ COMMON ═════════════════════════════
  TrTokens.emailTxt: 'Email',
  TrTokens.welcomeBackTxt: 'Welcome back, {name}',
};
''';

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'python': python,
      'toolsDir': toolsDir,
    });
    final settings = AppSettings(await SharedPreferences.getInstance());
    bridge = EngineBridge();
    repo = TranslationRepositoryImpl(TranslationDataSource(bridge, settings));
    tmp = await Directory.systemTemp.createTemp('trstudio');
    final consts = Directory('${tmp.path}/app/lib/core/constants')
      ..createSync(recursive: true);
    File('${consts.path}/trc_constant_tokens.dart').writeAsStringSync(tokens);
    File('${consts.path}/default_english_tr.dart').writeAsStringSync(defaults);
    File('${tmp.path}/app/lib/home.dart').writeAsStringSync(
      "import 'package:flutter/material.dart';\nWidget home() => Column(children: [Text('Save list'), "
      "TextField(decoration: InputDecoration(hintText: 'Search lists'))]);\n",
    );
    if (hasTools) {
      final r = await Process.run(python, [
        '-c',
        'import openpyxl,sys; wb=openpyxl.Workbook(); ws=wb.active; ws.title="Sheet1"; '
            'ws.append(["Key","English","Japanese","Korean (ko)"]); '
            'ws.append(["email_txt","Email","メール",""]); '
            'ws.append(["save_list_btn_txt","Save list","リストを保存","목록 저장"]); '
            'wb.save(sys.argv[1])',
        '${tmp.path}/tr.xlsx',
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
    }
    project = TranslationProject(
      id: 't',
      name: 'fixture',
      projectDir: '${tmp.path}/app',
      sheetPath: '${tmp.path}/tr.xlsx',
      exportDir: '${tmp.path}/out',
    );
  });

  tearDownAll(() async {
    await bridge.dispose();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('read the app and the sheet, fix both, export without touching the project, build packs', () async {
    final summary = (await repo.open(project)).valueOrNull!;
    expect(summary.project!.tokens, 2);
    expect(summary.sheet!.languages.map((l) => l.code), ['ja', 'ko']);
    expect((await repo.scan()).valueOrNull, 2);

    final report = (await repo.report()).valueOrNull!;
    expect(
      report.issues
          .where((i) => i.kind == 'missing_in_sheet')
          .map((i) => i.key),
      ['welcome_back_txt'],
    );
    expect(
      report.issues.where((i) => i.kind == 'missing_in_app').map((i) => i.key),
      ['save_list_btn_txt'],
    );

    final hard = (await repo.hardcoded()).valueOrNull!;
    expect(
      hard.firstWhere((h) => h.text == 'Save list').existingKey,
      'save_list_btn_txt',
    );
    expect(
      hard.firstWhere((h) => h.text == 'Search lists').key,
      'search_lists_hint',
    );

    final added = (await repo.addRows([
      (
        key: 'welcome_back_txt',
        english: 'Welcome back, {name}',
        meta: const {},
      ),
      (key: 'search_lists_hint', english: 'Search lists', meta: const {}),
    ])).valueOrNull!;
    expect(added.added, ['welcome_back_txt', 'search_lists_hint']);
    final problems = (await repo.setCells([
      (key: 'welcome_back_txt', column: 'Japanese', text: 'おかえり'),
    ])).valueOrNull!;
    expect(
      problems.single.kind,
      'placeholder_missing',
      reason: 'checked as it is written',
    );
    await repo.setCells([
      (key: 'welcome_back_txt', column: 'Japanese', text: 'おかえり、{name}'),
    ]);

    final before = {
      for (final f in Directory(
        '${tmp.path}/app',
      ).listSync(recursive: true).whereType<File>())
        f.path: f.readAsStringSync(),
    };
    final ex = (await repo.exportDart(
      project.exportDir,
      addKeys: ['save_list_btn_txt', 'search_lists_hint'],
    )).valueOrNull!;
    final tokensOut = ex.files.firstWhere((f) => f.kind == 'tokens');
    expect(tokensOut.added, 2);
    expect(
      File(tokensOut.exportPath).readAsStringSync(),
      contains("static const String saveListBtnTxt = 'save_list_btn_txt';"),
    );
    expect(tokensOut.diff, contains('+  static const String searchListsHint'));
    expect(
      ex.files.firstWhere((f) => f.kind == 'languages').created,
      isTrue,
      reason: 'no registry yet: created',
    );
    final after = {
      for (final f in Directory(
        '${tmp.path}/app',
      ).listSync(recursive: true).whereType<File>())
        f.path: f.readAsStringSync(),
    };
    expect(after, before, reason: 'the project is never written by an export');

    final packs = (await repo.buildPacks(
      project.exportDir,
      strict: true,
    )).valueOrNull!;
    expect(packs.packs.map((p) => p.file), ['lang_ja.zip', 'lang_ko.zip']);

    final backup = (await repo.save()).valueOrNull!;
    expect(
      File(backup).existsSync(),
      isTrue,
      reason: 'the previous sheet is kept',
    );
    expect(File('${project.sheetPath}.unsaved.jsonl').existsSync(), isFalse);
    final reopened = (await repo.open(project)).valueOrNull!;
    expect(reopened.sheet!.keys, 4);
  }, skip: hasTools ? false : 'translation_tool.py not found next to the app');
}
