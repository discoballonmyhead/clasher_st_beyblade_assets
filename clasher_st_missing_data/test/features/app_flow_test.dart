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

  testWidgets('open a workbook, see what is missing, fix a row', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MissingDataApp());
    await tester.pumpAndSettle();
    expect(find.text('Find and fill what is missing'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '/tmp/beyblade_parts.xlsx');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // workbook page: tab, field gaps, rows
    expect(find.text('X_Blades'), findsOneWidget);
    expect(find.text('Hells Scythe'), findsOneWidget);
    expect(find.text('type, mass'), findsOneWidget);

    // open the row with gaps and fill one field
    await tester.tap(find.text('Hells Scythe'));
    await tester.pumpAndSettle();
    expect(find.text('#203  Hells Scythe'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextFormField, 'type'), 'attack');
    await tester.pump();
    await tester.tap(find.text('Apply 1'));
    await tester.pumpAndSettle();

    expect(repo.rowsData['203']!['type'], 'attack');
    expect(find.text('mass'), findsWidgets); // still missing mass
    expect(find.textContaining('Unsaved changes'), findsOneWidget);

    // save
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(repo.dirty, isFalse);
    expect(find.textContaining('All changes saved'), findsOneWidget);
  });
}
