import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:missing_data_app/app.dart';
import 'package:missing_data_app/core/di/service_locator.dart';
import 'package:missing_data_app/core/services/data_change_notifier.dart';
import 'package:missing_data_app/features/missing_data/presentation/cubits/row_editor/row_editor_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repository.dart';
import '../support/fake_studio_repository.dart';

void main() {
  late FakeRepository repo;

  setUp(() async {
    await sl.reset();
    SharedPreferences.setMockInitialValues({});
    repo = FakeRepository();
    await initDependencies(prefs: await SharedPreferences.getInstance(), studioRepository: FakeStudioRepository(), repository: repo);
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

  testWidgets('delete a row from the editor, find it in Recently deleted, restore it', (tester) async {
    await openWorkbook(tester);
    await tester.tap(find.text('Hells Scythe'));
    await tester.pumpAndSettle();
    expect(find.text('#203  Hells Scythe'), findsOneWidget);

    await tester.tap(find.text('Delete row'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 1 row(s)?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repo.rowsData.containsKey('203'), isFalse);
    expect(find.text('Hells Scythe'), findsNothing, reason: 'gone from the list');
    expect(find.text('Click a row to edit it'), findsOneWidget, reason: 'the editor let go of the deleted row');
    expect(find.textContaining('in Recently deleted'), findsOneWidget);

    await tester.tap(find.byTooltip('Recently deleted'));
    await tester.pumpAndSettle();
    expect(find.text('#203  Hells Scythe'), findsOneWidget);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore 1'));
    await tester.pumpAndSettle();
    expect(repo.rowsData.containsKey('203'), isTrue, reason: 'back with its old id (still free)');
    expect(find.textContaining('Restored Parts_X_Blades #203'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Hells Scythe'), findsOneWidget, reason: 'listed again');
  });

  testWidgets('delete ticked rows; empty Recently deleted', (tester) async {
    repo.rowsData['204'] = {'name': 'Wizard Rod', 'code': 'BX-03', 'type': 'stamina', 'mass': 35.0};
    await openWorkbook(tester);
    await tester.tap(find.text('Tick all listed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete ticked'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 3 row(s)?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(repo.rowsData, isEmpty);
    expect(find.text('3 ticked'), findsNothing, reason: 'ticks dropped with the rows');

    await tester.tap(find.byTooltip('Recently deleted'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNWidgets(3));
    await tester.tap(find.text('Empty'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();
    expect(repo.deleted, isEmpty);
    expect(find.textContaining('Nothing deleted'), findsOneWidget);
  });

  testWidgets('ids that are not serial: asked on open; shift them, or not now until they change', (tester) async {
    repo.checkIds = true;
    repo.rowsData['203']!['parentPartId'] = 65;
    await openWorkbook(tester);
    expect(find.text("Ids aren't serial"), findsOneWidget, reason: 'asked as soon as the workbook opens');
    expect(find.textContaining('missing 201 id(s)'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text("Ids aren't serial"), findsNothing);
    expect(repo.rowsData.keys, ['65', '203'], reason: 'nothing changed');

    // a change to the ids (a new row) asks again
    repo.rowsData['204'] = {'name': 'Wizard Rod', 'code': 'BX-03', 'type': 'stamina', 'mass': 35.0};
    sl<DataChangeNotifier>().notify(DataChange.structureChanged);
    await tester.pumpAndSettle();
    expect(find.text("Ids aren't serial"), findsOneWidget);
    await tester.tap(find.text('Shift ids'));
    await tester.pumpAndSettle();
    expect(repo.rowsData.keys.toSet(), {'1', '2', '3'});
    expect(repo.rowsData['2']!['parentPartId'], 1, reason: 'parent ids follow');
    expect(find.textContaining('id(s) shifted'), findsOneWidget);
    expect(find.text("Ids aren't serial"), findsNothing, reason: 'serial now: not asked again');
  });

  testWidgets('the editor drops its row when ids change (renumber, delete, restore, undo of those)',
      (tester) async {
    await openWorkbook(tester);
    await tester.tap(find.text('Dran Sword'));
    await tester.pumpAndSettle();
    expect(sl<RowEditorCubit>().state.detail?.id, '65');
    sl<DataChangeNotifier>().notify(DataChange.idsChanged);
    await tester.pumpAndSettle();
    expect(sl<RowEditorCubit>().state.detail, isNull);
    expect(find.text('Click a row to edit it'), findsOneWidget);
  });
}
