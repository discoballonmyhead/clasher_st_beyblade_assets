import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:missing_data_app/app.dart';
import 'package:missing_data_app/core/di/service_locator.dart';
import 'package:missing_data_app/core/services/file_picker_service.dart';
import 'package:missing_data_app/features/missing_data/presentation/cubits/row_editor/row_editor_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repository.dart';
import '../support/fake_studio_repository.dart';

class _Picker implements FilePickerService {
  String? file;
  final images = Uint8List.fromList(
      [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]); // "a picture"
  @override
  Future<String?> pickWorkbook() async => null;
  @override
  Future<Uint8List?> pickImage() async => images;
  @override
  Future<String?> pickFolder({String title = ''}) async => null;
  @override
  Future<String?> pickFile({required List<String> extensions, String title = ''}) async => file;
}

void main() {
  test('3D model paths are kept relative to the workbook folder when inside it', () {
    expect(relativeToWorkbook('/data/store/models/dran.glb', '/data/store/beyblade_parts.xlsx'), 'models/dran.glb');
    expect(relativeToWorkbook(r'C:\Store\models\dran.glb', r'C:\store\beyblade_parts.xlsx'), 'models/dran.glb');
    expect(relativeToWorkbook('/elsewhere/dran.glb', '/data/store/beyblade_parts.xlsx'), '/elsewhere/dran.glb');
    expect(relativeToWorkbook('/x/dran.glb', null), '/x/dran.glb');
  });

  testWidgets('a second picture kind and a .glb picker in the row editor', (tester) async {
    await sl.reset();
    SharedPreferences.setMockInitialValues({});
    final repo = FakeRepository()
      ..extraFields = ['model3d']
      ..extraImageFields = ['fullBodyImage'];
    final picker = _Picker()..file = '/tmp/models/dran.glb';
    await initDependencies(
      prefs: await SharedPreferences.getInstance(),
      repository: repo,
      picker: picker,
      studioRepository: FakeStudioRepository(),
    );
    tester.view.physicalSize = const Size(1700, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MissingDataApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '/tmp/beyblade_parts.xlsx');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hells Scythe'));
    await tester.pumpAndSettle();

    expect(find.text('Full body image (optional)'), findsOneWidget);

    // a picture for the second slot goes to that column only
    await tester.tap(find.byKey(const ValueKey('pick-image-fullBodyImage')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('put-image-main')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('put-image-fullBodyImage')));
    await tester.pumpAndSettle();
    expect(repo.imagesPut, [('203', 'fullBodyImage')]);

    // the 3D model field gets the picked file, relative to the workbook folder
    await tester.tap(find.byTooltip('Choose a .glb file'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'models/dran.glb'), findsOneWidget);
    await tester.tap(find.text('Apply 1'));
    await tester.pumpAndSettle();
    expect(repo.rowsData['203']!['model3d'], 'models/dran.glb');
  });
}
