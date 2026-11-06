import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:missing_data_app/app.dart';
import 'package:missing_data_app/core/di/service_locator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repository.dart';

void main() {
  late FakeRepository repo;

  setUp(() async {
    await sl.reset();
    SharedPreferences.setMockInitialValues({});
    repo = FakeRepository();
    await initDependencies(prefs: await SharedPreferences.getInstance(), repository: repo);
  });

  Future<void> openWorkbook(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1700, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MissingDataApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '/tmp/beyblade_parts.xlsx');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('edits from a session closed without saving are offered and recovered', (tester) async {
    repo.unsavedEntries = 34;
    await openWorkbook(tester);
    expect(find.text('Recover unsaved changes?'), findsOneWidget);
    expect(find.textContaining('34 change(s)'), findsOneWidget);
    await tester.tap(find.text('Recover'));
    await tester.pumpAndSettle();
    expect(repo.recovered, isTrue);
    expect(find.textContaining('Recovered 34 unsaved change(s)'), findsOneWidget);
    expect(find.textContaining('Unsaved changes'), findsOneWidget, reason: 'recovered, not yet saved');
  });

  testWidgets('closing the window with unsaved changes asks first', (tester) async {
    await openWorkbook(tester);
    // nothing changed: the window just closes
    expect(await tester.binding.handleRequestAppExit(), AppExitResponse.exit);

    await tester.tap(find.text('Hells Scythe'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'type'), 'attack');
    await tester.pump();
    await tester.tap(find.text('Apply 1'));
    await tester.pumpAndSettle();

    // Cancel keeps the app open
    var answer = tester.binding.handleRequestAppExit();
    await tester.pumpAndSettle();
    expect(find.text('Save before closing?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(await answer, AppExitResponse.cancel);

    // Save saves, then lets it close
    answer = tester.binding.handleRequestAppExit();
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save').last);
    await tester.pumpAndSettle();
    expect(await answer, AppExitResponse.exit);
    expect(repo.dirty, isFalse);
  });
}
