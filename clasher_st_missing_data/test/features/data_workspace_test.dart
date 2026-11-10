import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:missing_data_app/app.dart';
import 'package:missing_data_app/core/di/service_locator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repository.dart';
import '../support/fake_studio_repository.dart';

void main() {
  late FakeRepository repo;
  late FakeStudioRepository studio;

  setUp(() async {
    await sl.reset();
    SharedPreferences.setMockInitialValues({});
    repo = FakeRepository();
    studio = FakeStudioRepository();
    await initDependencies(prefs: await SharedPreferences.getInstance(), repository: repo, studioRepository: studio);
  });

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1700, 1160);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MissingDataApp());
    await tester.pumpAndSettle();
  }

  Finder doc(String file) => find.byKey(ValueKey('doc-/tmp/$file'));

  testWidgets('home lists the hobbies; a hobby opens its workbook', (tester) async {
    await start(tester);
    expect(find.text('Hobbies'), findsOneWidget);
    expect(find.text('Beyblade TCG'), findsOneWidget);
    expect(find.textContaining('Burst, X'), findsOneWidget);
  });

  testWidgets('workbooks open as tabs; each keeps its unsaved changes; closing a changed one asks', (tester) async {
    await start(tester);
    await tester.enterText(find.byType(TextField).first, '/tmp/beyblade_parts.xlsx');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(doc('beyblade_parts.xlsx'), findsOneWidget);

    // the hobby's other workbook is one click away
    await tester.tap(find.widgetWithText(ActionChip, 'beyblade_products.xlsx'));
    await tester.pumpAndSettle();
    expect(doc('beyblade_products.xlsx'), findsOneWidget);
    expect(repo.path, '/tmp/beyblade_products.xlsx');

    // change something in products
    await tester.tap(find.text('Hells Scythe'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'type'), 'attack');
    await tester.pump();
    await tester.tap(find.text('Apply 1'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: doc('beyblade_products.xlsx'), matching: find.text('● beyblade_products.xlsx')), findsOneWidget);

    // switch back: parts is clean, products still marked
    await tester.tap(doc('beyblade_parts.xlsx'));
    await tester.pumpAndSettle();
    expect(repo.path, '/tmp/beyblade_parts.xlsx');
    expect(find.descendant(of: doc('beyblade_products.xlsx'), matching: find.text('● beyblade_products.xlsx')), findsOneWidget);
    expect(find.descendant(of: doc('beyblade_parts.xlsx'), matching: find.text('beyblade_parts.xlsx')), findsOneWidget);
    expect(find.text('Hells Scythe'), findsOneWidget, reason: 'the rows of the workbook switched to');
    expect(
      [for (final c in tester.widgetList<InputChip>(find.byType(InputChip))) (c.key! as ValueKey<String>).value],
      ['doc-/tmp/beyblade_parts.xlsx', 'doc-/tmp/beyblade_products.xlsx'],
      reason: 'tabs keep their place when switching',
    );

    // close products: asks; Cancel keeps it
    final close = find.descendant(of: doc('beyblade_products.xlsx'), matching: find.byTooltip('Close'));
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(doc('beyblade_products.xlsx'), findsOneWidget);
    expect(repo.closed, isEmpty);

    // Save then close
    await tester.tap(close);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Save')));
    await tester.pumpAndSettle();
    expect(repo.closed, ['/tmp/beyblade_products.xlsx']);
    expect(doc('beyblade_products.xlsx'), findsNothing);
    expect(repo.path, '/tmp/beyblade_parts.xlsx', reason: 'back on the remaining workbook');
  });

  testWidgets('switching hobby opens its workbook', (tester) async {
    await start(tester);
    await tester.enterText(find.byType(TextField).first, '/tmp/beyblade_parts.xlsx');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beyblade').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beyblade TCG').last);
    await tester.pumpAndSettle();
    expect(repo.path, '/tmp/beyblade_tcg.xlsx');
    expect(doc('beyblade_tcg.xlsx'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Original'), findsOneWidget);
  });
}
