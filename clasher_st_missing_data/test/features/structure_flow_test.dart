import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:missing_data_app/app.dart';
import 'package:missing_data_app/core/di/service_locator.dart';
import 'package:missing_data_app/features/missing_data/presentation/cubits/structure/structure_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repository.dart';
import '../support/fake_studio_repository.dart';

void main() {
  late FakeRepository repo;

  setUp(() async {
    await sl.reset();
    SharedPreferences.setMockInitialValues({});
    repo = FakeRepository();
    await initDependencies(
      prefs: await SharedPreferences.getInstance(), studioRepository: FakeStudioRepository(),
      repository: repo,
    );
  });

  Future<void> openWorkbook(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1700, 1160);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MissingDataApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '/tmp/beyblade_parts.xlsx');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  test('column names are checked before the engine is asked', () {
    expect(StructureCubit.validateName('tipShape'), isNull);
    expect(StructureCubit.validateName('tip_shape2'), isNull);
    expect(StructureCubit.validateName('2tip'), isNotNull);
    expect(StructureCubit.validateName('tip shape'), isNotNull);
  });

  testWidgets('add a column: it shows in the field list and the editor', (
    tester,
  ) async {
    await openWorkbook(tester);
    await tester.tap(find.text('Add column'));
    await tester.pumpAndSettle();

    // a bad name is refused in the dialog
    await tester.enterText(
      find.widgetWithText(TextField, 'Column name'),
      'tip shape',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add column'));
    await tester.pumpAndSettle();
    expect(find.textContaining('letters, digits and _ only'), findsOneWidget);
    expect(repo.customColumns, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextField, 'Column name'),
      'tipShape',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add column'));
    await tester.pumpAndSettle();
    expect(repo.customColumns, ['tipShape']);
    expect(
      find.text('tipShape  +'),
      findsOneWidget,
      reason: 'field list marks the new column',
    );

    await tester.tap(find.text('Dran Sword'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextFormField, 'tipShape  +'),
      findsOneWidget,
      reason: 'editor shows it',
    );
  });

  testWidgets(
    'duplicate as variant, copy and new row - each focused for editing',
    (tester) async {
      await openWorkbook(tester);
      await tester.tap(find.text('Dran Sword'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Duplicate as variant'));
      await tester.pumpAndSettle();
      expect(repo.rowsData['204'], isNotNull);
      expect(repo.rowsData['204']!['parentPartId'], '65');
      expect(
        repo.rowsData['204']!['type'],
        'attack',
        reason: 'shared fields carried over',
      );
      expect(
        repo.rowsData['204']!['code'],
        isNull,
        reason: 'release code is not shared',
      );
      expect(
        find.text('#204  Dran Sword'),
        findsOneWidget,
        reason: 'new row opens in the editor',
      );
      expect(find.textContaining('variant of #65'), findsWidgets);

      await tester.tap(find.text('New row'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Brand New Blade',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add row'));
      await tester.pumpAndSettle();
      expect(repo.rowsData['205']!['name'], 'Brand New Blade');
      expect(find.text('#205  Brand New Blade'), findsOneWidget);
      expect(find.textContaining('Unsaved changes'), findsOneWidget);
    },
  );

  testWidgets('columns the schema added on open are announced', (tester) async {
    repo.addedOnOpen = [
      'Parts_X_Ratchets.simpleRatchet',
      'Parts_X_Blades.requiresSimpleRatchet',
    ];
    await openWorkbook(tester);
    expect(
      find.textContaining(
        'New columns added to this workbook: Parts_X_Ratchets.simpleRatchet',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the change log lists what was done and jumps to the row', (
    tester,
  ) async {
    await openWorkbook(tester);
    await tester.tap(find.text('Hells Scythe'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'type'),
      'attack',
    );
    await tester.pump();
    await tester.tap(find.text('Apply 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate as variant'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dran Sword').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Change log'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('2 change(s) made with the missing data tool'),
      findsOneWidget,
    );
    expect(find.textContaining('#204  -  new row'), findsOneWidget);
    expect(
      find.textContaining('#203  -  type: (empty) → attack'),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Search tab, id, field, value'),
      'add_row',
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 change(s)'), findsOneWidget);

    await tester.tap(find.textContaining('#204  -  new row'));
    await tester.pumpAndSettle();
    expect(
      find.text('#204  Hells Scythe'),
      findsOneWidget,
      reason: 'jumped to the row',
    );
  });
}
