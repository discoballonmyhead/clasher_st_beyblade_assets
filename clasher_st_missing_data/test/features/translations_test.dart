import 'dart:convert';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:missing_data_app/app.dart';
import 'package:missing_data_app/core/di/service_locator.dart';
import 'package:missing_data_app/features/translations/domain/entities/translation_project.dart';
import 'package:missing_data_app/features/translations/presentation/cubits/translation_cubit.dart';
import 'package:missing_data_app/features/translations/presentation/widgets/project_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repository.dart';
import '../support/fake_studio_repository.dart';
import '../support/fake_translation_repository.dart';

const _project = TranslationProject(
  id: 'p1',
  name: 'clasher_st',
  projectDir: '/app',
  sheetPath: '/tr/ClasherSTTr.xlsx',
  exportDir: '/out',
);

void main() {
  late FakeTranslationRepository tr;

  Future<void> setUpWith({TranslationProject? project = _project}) async {
    await sl.reset();
    SharedPreferences.setMockInitialValues({
      if (project != null)
        'translationProjects': jsonEncode([project.toJson()]),
      if (project != null) 'activeTranslationProject': project.id,
    });
    tr = FakeTranslationRepository();
    await initDependencies(
      prefs: await SharedPreferences.getInstance(), studioRepository: FakeStudioRepository(),
      repository: FakeRepository(),
      translationRepository: tr,
    );
  }

  Future<void> openTranslations(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1700, 1050);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MissingDataApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Translations'));
    await tester.pumpAndSettle();
  }

  Future<void> openTab(WidgetTester tester, String name) async {
    await tester.tap(find.widgetWithText(Tab, name));
    await tester.pumpAndSettle();
  }

  group('project paths', () {
    bool yes(String _) => true;
    test('export inside the project lib/ is refused', () {
      final p = _project.copyWith(exportDir: '/app/lib/generated');
      expect(
        validateTranslationProject(p, dirExists: yes, fileExists: yes),
        contains(contains('lib/')),
      );
    });
    test('a project without lib/ and a non-xlsx sheet are refused', () {
      final p = _project.copyWith(sheetPath: '/tr/sheet.csv');
      final problems = validateTranslationProject(
        p,
        dirExists: (_) => false,
        fileExists: yes,
      );
      expect(problems, contains(contains('no lib/')));
      expect(problems, contains(contains('.xlsx')));
    });
    test('a good project passes', () {
      expect(
        validateTranslationProject(_project, dirExists: yes, fileExists: yes),
        isEmpty,
      );
    });
  });

  testWidgets('no app yet: the section explains and offers to add one', (
    tester,
  ) async {
    await setUpWith(project: null);
    await openTranslations(tester);
    expect(find.text('Add an app'), findsWidgets);
    expect(find.textContaining('never changes the project'), findsOneWidget);
  });

  testWidgets('opens the saved app: counts, coverage, what needs a look', (
    tester,
  ) async {
    await setUpWith();
    await openTranslations(tester);
    expect(find.text('Keys in the app'), findsOneWidget);
    expect(find.text('Japanese'), findsOneWidget);
    expect(find.textContaining('In the app, not in the sheet'), findsOneWidget);
  });

  testWidgets(
    'a key only in the app goes to the sheet; one only in the sheet goes to the app on export',
    (tester) async {
      await setUpWith();
      await openTranslations(tester);
      await openTab(tester, 'Keys');

      await tester.tap(find.widgetWithText(ChoiceChip, 'Not in the sheet'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('edit_list_txt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to the sheet'));
      await tester.pumpAndSettle();
      expect(tr.sheet['edit_list_txt']?['English'], 'Edit list');

      await tester.tap(find.widgetWithText(ChoiceChip, 'Not in the app'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('my_decks_txt').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to the app'));
      await tester.pumpAndSettle();
      expect(
        sl<TranslationCubit>().state.addToApp.keys,
        contains('my_decks_txt'),
      );

      await openTab(tester, 'Export & packs');
      expect(find.textContaining('TrTokens.myDecksTxt'), findsOneWidget);
      await tester.tap(find.text('Export to the export folder'));
      await tester.pumpAndSettle();
      expect(tr.lastExport!.addKeys, ['my_decks_txt']);
      expect(tr.lastExport!.out, '/out');
      expect(
        find.textContaining('The project wasn\'t changed'),
        findsOneWidget,
      );
      expect(
        find.text('Copy into the project ...'),
        findsNothing,
        reason: 'off unless the app allows it',
      );
    },
  );

  testWidgets('translations are checked while typing; Apply writes the sheet', (
    tester,
  ) async {
    await setUpWith();
    await openTranslations(tester);
    await openTab(tester, 'Keys');
    await tester.tap(find.text('welcome_back_txt'));
    await tester.pumpAndSettle();
    final korean = find.byKey(const ValueKey('welcome_back_txt-Korean'));
    await tester.enterText(korean, '다시 오신 것을 환영합니다');
    await tester.pumpAndSettle();
    expect(find.textContaining('missing {name}'), findsOneWidget);
    await tester.enterText(korean, '{name}님, 다시 오신 것을 환영합니다');
    await tester.pumpAndSettle();
    expect(find.textContaining('missing {name}'), findsNothing);
    await tester.tap(find.text('Apply 1'));
    await tester.pumpAndSettle();
    expect(tr.sheet['welcome_back_txt']!['Korean'], '{name}님, 다시 오신 것을 환영합니다');
    expect(find.text('Save sheet'), findsOneWidget);
  });

  testWidgets(
    'strings written in the code: add them to the sheet and the app',
    (tester) async {
      await setUpWith();
      await openTranslations(tester);
      await openTab(tester, 'In the code');
      expect(find.text('"Search lists"'), findsOneWidget);
      expect(
        find.text('already email_txt'),
        findsOneWidget,
        reason: 'only the code needs changing',
      );
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add 1 to the sheet and the app'));
      await tester.pumpAndSettle();
      expect(tr.sheet['search_lists_hint']?['English'], 'Search lists');
      expect(sl<TranslationCubit>().state.addToApp['search_lists_hint'], 'NEW');
    },
  );

  testWidgets(
    'copying into the project only when the app allows it, after confirming',
    (tester) async {
      await setUpWith(project: _project.copyWith(writeIntoProject: true));
      await openTranslations(tester);
      sl<TranslationCubit>().markForApp('my_decks_txt');
      await openTab(tester, 'Export & packs');
      await tester.tap(find.text('Export to the export folder'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy into the project ...'));
      await tester.pumpAndSettle();
      expect(find.text('Copy into the project?'), findsOneWidget);
      expect(find.textContaining('backed up first'), findsOneWidget);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(tr.appliedFrom, ['/out']);
      expect(
        sl<TranslationCubit>().state.addToApp,
        isEmpty,
        reason: 'the key reached the app',
      );
    },
  );

  testWidgets(
    'packs: built per language, with the release command from settings',
    (tester) async {
      await setUpWith();
      await openTranslations(tester);
      await openTab(tester, 'Export & packs');
      await tester.scrollUntilVisible(
        find.text('Build packs'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.text('Build packs'));
      await tester.pumpAndSettle();
      expect(find.textContaining('lang_ja.zip'), findsWidgets);
      expect(
        find.textContaining('-R discoballonmyhead/clasher_st_translations'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'changing a language code asks first (it orphans downloaded packs)',
    (tester) async {
      await setUpWith();
      await openTranslations(tester);
      await openTab(tester, 'Languages');
      await tester.enterText(find.byType(TextFormField).first, 'jp');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to the Languages tab'));
      await tester.pumpAndSettle();
      expect(find.text('Change language codes?'), findsOneWidget);
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      expect(tr.languages.first.code, 'jp');
    },
  );

  testWidgets('unsaved edits from last time are offered back', (tester) async {
    await setUpWith();
    tr.unsaved = 7;
    await openTranslations(tester);
    expect(find.text('Recover unsaved translations?'), findsOneWidget);
    await tester.tap(find.text('Recover'));
    await tester.pumpAndSettle();
    expect(tr.unsaved, 0);
    expect(find.textContaining('Recovered 7'), findsOneWidget);
  });

  testWidgets(
    'a sheet saved elsewhere meanwhile is not overwritten without asking',
    (tester) async {
      await setUpWith();
      tr.saveConflict = true;
      await openTranslations(tester);
      await openTab(tester, 'Keys');
      await tester.tap(find.text('email_txt'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('email_txt-Korean')),
        '이메일',
      );
      await tester.pump();
      await tester.tap(find.text('Apply 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save sheet'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('changed on disk after it was opened'),
        findsOneWidget,
      );
      expect(tr.dirty, isTrue);
      await tester.tap(find.text('Overwrite').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Overwrite'));
      await tester.pumpAndSettle();
      expect(tr.dirty, isFalse);
    },
  );

  testWidgets(
    'closing the window with an unsaved sheet asks, and Save saves it',
    (tester) async {
      await setUpWith();
      await openTranslations(tester);
      await openTab(tester, 'Keys');
      await tester.tap(find.text('email_txt'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('email_txt-Korean')),
        '이메일',
      );
      await tester.pump();
      await tester.tap(find.text('Apply 1'));
      await tester.pumpAndSettle();
      final answer = tester.binding.handleRequestAppExit();
      await tester.pumpAndSettle();
      expect(find.text('Save before closing?'), findsOneWidget);
      expect(
        find.textContaining('Translations: ClasherSTTr.xlsx'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(await answer, AppExitResponse.exit);
      expect(tr.dirty, isFalse);
    },
  );

  testWidgets(
    'the editor follows a fix applied to its key (English copied from the app)',
    (tester) async {
      await setUpWith();
      tr.sheet['welcome_back_txt']!['English'] = 'Welcome Back';
      await openTranslations(tester);
      await openTab(tester, 'Keys');
      await tester.tap(find.text('welcome_back_txt'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Welcome Back'), findsOneWidget);
      await tester.tap(find.text("Copy the app's English to the sheet"));
      await tester.pumpAndSettle();
      expect(tr.sheet['welcome_back_txt']!['English'], 'Welcome back, {name}');
      expect(
        find.widgetWithText(TextField, 'Welcome back, {name}'),
        findsOneWidget,
        reason: 'not the stale text',
      );
      expect(
        find.text('Apply'),
        findsOneWidget,
        reason: 'nothing left to apply',
      );
    },
  );
}
