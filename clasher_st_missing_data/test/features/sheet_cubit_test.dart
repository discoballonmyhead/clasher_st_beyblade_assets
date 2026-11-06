import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:missing_data_app/core/services/data_change_notifier.dart';
import 'package:missing_data_app/core/settings/app_settings.dart';
import 'package:missing_data_app/features/missing_data/domain/entities/row.dart';
import 'package:missing_data_app/features/missing_data/domain/usecases/sheet_usecases.dart';
import 'package:missing_data_app/features/missing_data/presentation/cubits/sheet/sheet_cubit.dart';
import 'package:missing_data_app/features/missing_data/presentation/cubits/sheet/sheet_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repository.dart';

void main() {
  late FakeRepository repo;
  late DataChangeNotifier changes;
  late AppSettings settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    settings = AppSettings(await SharedPreferences.getInstance());
    repo = FakeRepository();
    changes = DataChangeNotifier();
  });

  SheetCubit build() => SheetCubit(analyze: AnalyzeSheet(repo), listRows: ListRows(repo), changes: changes, settings: settings);

  blocTest<SheetCubit, SheetState>(
    'selecting a tab loads its analysis and rows',
    build: build,
    act: (c) => c.selectSheet('Parts_X_Blades'),
    verify: (c) {
      expect(c.state.sheet, 'Parts_X_Blades');
      expect(c.state.rows.map((r) => r.id), ['65', '203']);
      expect(c.state.analysis!.withGaps.map((g) => g.field), containsAll(['type', 'mass']));
      expect(c.state.loading, isFalse);
    },
  );

  blocTest<SheetCubit, SheetState>(
    'filtering by a field lists only rows missing it; next gap focuses them',
    build: build,
    act: (c) async {
      await c.selectSheet('Parts_X_Blades');
      await c.selectField('type');
      c.nextGap();
    },
    verify: (c) {
      expect(c.state.rows.map((r) => r.id), ['203']);
      expect(c.state.focusedId, '203');
    },
  );

  blocTest<SheetCubit, SheetState>(
    'an edit elsewhere (data change) refreshes the rows',
    build: build,
    act: (c) async {
      await c.selectSheet('Parts_X_Blades');
      await repo.updateRow('Parts_X_Blades', '203', {'type': 'attack', 'mass': '36'});
      changes.notify(DataChange.rowsEdited);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    },
    verify: (c) => expect(c.state.rows.firstWhere((r) => r.id == '203').missing, isEmpty),
  );

  blocTest<SheetCubit, SheetState>(
    'sort choice is remembered',
    build: build,
    act: (c) async {
      await c.selectSheet('Parts_X_Blades');
      await c.sortBy(RowSort.updated);
    },
    verify: (_) => expect(settings.rowSort, 'updated'),
  );
}
