import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:missing_data_app/app.dart';
import 'package:missing_data_app/core/di/service_locator.dart';
import 'package:missing_data_app/features/studio/domain/entities/studio_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repository.dart';
import '../support/fake_studio_repository.dart';

void main() {
  late FakeStudioRepository studio;

  setUp(() async {
    await sl.reset();
    SharedPreferences.setMockInitialValues({'toolsDir': '/tmp/tools'});
    studio = FakeStudioRepository();
    await initDependencies(
      prefs: await SharedPreferences.getInstance(),
      repository: FakeRepository(),
      studioRepository: studio,
    );
  });

  Future<void> openPublish(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MissingDataApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Publish'));
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester, String action) async {
    expect(find.byType(AlertDialog), findsOneWidget, reason: 'outward actions ask first');
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(FilledButton, action)));
    await tester.pumpAndSettle();
  }

  testWidgets('data release: package, commit + push, build, create the release - each confirmed', (tester) async {
    await openPublish(tester);
    expect(find.text('Beyblade: beyblade_parts.xlsx'), findsOneWidget);
    expect(find.text('Beyblade TCG: beyblade_tcg.xlsx'), findsOneWidget);

    // 1 package: every existing workbook of a packaged hobby is ticked
    await tester.tap(find.widgetWithText(FilledButton, 'Package'));
    await tester.pumpAndSettle();
    final pkg = studio.calls['package']!.single;
    expect((pkg['books'] as List).length, 3);
    expect(pkg['out'], '/tmp/tools/data');
    expect(find.textContaining('Catalog check passed (1 warnings)'), findsOneWidget);
    expect(find.text('blades 12'), findsOneWidget);
    expect(find.textContaining('package working'), findsOneWidget, reason: 'job lines reach the log');

    // 2 commit + push: cancel first -> nothing happens
    await tester.tap(find.widgetWithText(FilledButton, 'Commit and push'));
    await tester.pumpAndSettle();
    expect(find.textContaining('3 changed file(s) under data/'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(studio.calls['commitPush'], isNull);
    await tester.tap(find.widgetWithText(FilledButton, 'Commit and push'));
    await tester.pumpAndSettle();
    await confirm(tester, 'Commit and push');
    expect(studio.calls['commitPush']!.single['push'], isTrue);
    expect(find.textContaining('committed abc1234'), findsOneWidget);

    // 3 build
    await tester.enterText(find.widgetWithText(TextField, 'Release tag'), 'v9');
    await tester.tap(find.widgetWithText(FilledButton, 'Build release files'));
    await tester.pumpAndSettle();
    expect(studio.calls['buildRelease']!.single['tag'], 'v9');
    expect(find.textContaining('2 file(s) in /tmp/_release/v9'), findsOneWidget);
    expect(find.textContaining('"releaseTag": "v9"'), findsOneWidget, reason: 'manifest values to copy');

    // 4 publish
    await tester.tap(find.widgetWithText(FilledButton, 'Create release'));
    await tester.pumpAndSettle();
    expect(find.textContaining('catalog.zip, catalog_manifest.json'), findsOneWidget);
    await confirm(tester, 'Create and upload');
    final pub = studio.calls['publishRelease']!.single;
    expect(pub['tag'], 'v9');
    expect((pub['files'] as List).length, 2);
    expect(find.text('https://example.invalid/r/v9'), findsOneWidget);
  });

  testWidgets('a failed step says why and the next one still waits', (tester) async {
    studio.failJobs.add('buildRelease');
    await openPublish(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Build release files'));
    await tester.pumpAndSettle();
    expect(find.text('buildRelease failed on purpose'), findsOneWidget, reason: 'snackbar');
    final create = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Create release'));
    expect(create.onPressed, isNull, reason: 'nothing to upload');
  });

  testWidgets('without gh signed in, creating a release is off and says how to fix it', (tester) async {
    studio.tools_ = const ToolsStatus(git: true, gh: true, ghSignedIn: false);
    await openPublish(tester);
    expect(find.textContaining('gh auth login'), findsOneWidget);
  });

  testWidgets('packaging: change a column, locked ones stay, save goes to the engine', (tester) async {
    await openPublish(tester);
    await tester.tap(find.text('Packaging'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('blades.json'));
    await tester.pumpAndSettle();

    Checkbox box(String column) => tester.widget<Checkbox>(
      find.descendant(of: find.widgetWithText(ListTile, column), matching: find.byType(Checkbox)),
    );
    expect(box('id').onChanged, isNull, reason: 'ids are locked');
    expect(box('name').onChanged, isNull, reason: 'the app needs name');

    await tester.tap(find.descendant(of: find.widgetWithText(ListTile, 'notes'), matching: find.byType(Checkbox)));
    await tester.pumpAndSettle();
    expect(box('notes').value, isFalse);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    final saved = studio.calls['saveProfile']!.single;
    expect(saved['sheet'], 'blades');
    final notes = (saved['columns'] as List<ColumnRule>).firstWhere((c) => c.name == 'notes');
    expect(notes.include, isFalse);
  });

  testWidgets('history lists the releases of the data repo', (tester) async {
    await openPublish(tester);
    await tester.tap(find.text('History'));
    await tester.pumpAndSettle();
    expect(find.textContaining('v8'), findsWidgets);
    expect(studio.calls['releases'], isNotEmpty);
  });

  testWidgets('git without a name/email: commit waits until it is set for the repository', (tester) async {
    studio.git_ = const GitStatus(isRepo: true, branch: 'main', remote: 'origin', changed: 2);
    await openPublish(tester);
    FilledButton commit() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Commit and push'));
    expect(find.textContaining("git doesn't know who you are"), findsOneWidget);
    expect(commit().onPressed, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Your name'), 'Sam');
    await tester.enterText(find.widgetWithText(TextField, 'Email (e.g. your GitHub email)'), 'sam@example.invalid');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Save'));
    await tester.pumpAndSettle();
    expect(studio.calls['setGitIdentity']!.single, {'name': 'Sam', 'email': 'sam@example.invalid'});
    expect(find.textContaining("git doesn't know who you are"), findsNothing);
    expect(commit().onPressed, isNotNull);
  });

  testWidgets('nothing changed and nothing to push: commit is off', (tester) async {
    studio.git_ = const GitStatus(isRepo: true, branch: 'main', changed: 0, ahead: 0, userName: 'a', userEmail: 'a@b.c');
    await openPublish(tester);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Commit and push')).onPressed, isNull);
  });
}
