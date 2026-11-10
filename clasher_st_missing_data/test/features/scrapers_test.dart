import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:missing_data_app/app.dart';
import 'package:missing_data_app/core/di/service_locator.dart';
import 'package:missing_data_app/features/scrapers/presentation/widgets/code_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repository.dart';
import '../support/fake_studio_repository.dart';

void main() {
  late FakeStudioRepository studio;

  setUp(() async {
    await sl.reset();
    SharedPreferences.setMockInitialValues({});
    studio = FakeStudioRepository();
    await initDependencies(
      prefs: await SharedPreferences.getInstance(),
      repository: FakeRepository(),
      studioRepository: studio,
    );
  });

  Future<void> openScrapers(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MissingDataApp());
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text('Scrapers')));
    await tester.pumpAndSettle();
  }

  Finder editor() => find.descendant(of: find.byType(CodeEditor), matching: find.byType(TextField));

  testWidgets('run: targets by hobby and generation, picked ones are scraped', (tester) async {
    await openScrapers(tester);
    // Beyblade, latest generation (X): blades + products; the TCG target isn't listed
    expect(find.text('parts / blades'), findsOneWidget);
    expect(find.text('products'), findsOneWidget);
    expect(find.text('tcg / cards'), findsNothing);
    expect(find.textContaining('contact you in the user agent'), findsOneWidget);

    await tester.tap(find.text('parts / blades'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run 1 target(s)'));
    await tester.pumpAndSettle();
    expect(studio.calls['scrape']!.single['targets'], ['parts:X:blades']);
    expect(find.textContaining('scrape working'), findsOneWidget);
    expect(find.textContaining('Last run:'), findsOneWidget);
  });

  testWidgets('overwrite asks first', (tester) async {
    await openScrapers(tester);
    await tester.tap(find.text('parts / blades'));
    await tester.tap(find.text('Overwrite filled cells'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Run 1 target(s)'));
    await tester.pumpAndSettle();
    expect(find.text('Overwrite filled cells?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(studio.calls['scrape'], isNull);
  });

  testWidgets('target settings: broken JSON can not be saved, valid JSON is', (tester) async {
    await openScrapers(tester);
    await tester.tap(find.text('Target settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('parts / blades'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Category:Blades'), findsWidgets);

    await tester.enterText(editor(), '{"categories": [');
    await tester.pumpAndSettle();
    FilledButton save() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'));
    expect(save().onPressed, isNull);

    await tester.enterText(editor(), '{"categories": ["Category:Blades", "Category:X Blades"]}');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(studio.targetConfig['categories'], ['Category:Blades', 'Category:X Blades']);
  });

  testWidgets('code: a syntax error is shown and nothing is saved; good code is created', (tester) async {
    await openScrapers(tester);
    await tester.tap(find.text('Code'));
    await tester.pumpAndSettle();
    expect(find.textContaining('not created yet'), findsOneWidget);

    await tester.enterText(editor(), 'def adjust_row(target, title, fields, row):\n    return (((row\n');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(find.text('Line 1: invalid syntax'), findsOneWidget);
    expect(studio.saved, isEmpty);

    // switching generation with unsaved code is refused
    await tester.tap(find.widgetWithText(ChoiceChip, 'Burst'));
    await tester.pumpAndSettle();
    expect(find.text('Save or discard the code changes first'), findsOneWidget);

    await tester.enterText(editor(), 'def adjust_row(target, title, fields, row):\n    row["type"] = "attack"\n    return row\n');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(studio.saved.keys.single, '/tmp/scrapers/beyblade/x.py');
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget, reason: 'it exists now');
  });
}
