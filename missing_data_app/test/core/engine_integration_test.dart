import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:missing_data_app/core/bridge/engine_bridge.dart';
import 'package:missing_data_app/features/missing_data/data/datasources/engine_data_source.dart';
import 'package:missing_data_app/features/missing_data/data/repositories/missing_data_repository_impl.dart';
import 'package:missing_data_app/features/missing_data/domain/entities/row.dart';
import 'package:missing_data_app/core/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Talks to the real Python engine (missing_data_tool.py serve) on a copy of the sample workbook.
/// Skipped when Python or the tools folder isn't there.
void main() {
  final toolsDir = Directory.current.parent.path;
  final python = Platform.environment['MDT_PYTHON'] ?? 'python3';
  final hasTools = File('$toolsDir/missing_data_tool.py').existsSync();

  late EngineBridge bridge;
  late MissingDataRepositoryImpl repo;
  late String workbook;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'python': python, 'toolsDir': toolsDir});
    final settings = AppSettings(await SharedPreferences.getInstance());
    bridge = EngineBridge();
    repo = MissingDataRepositoryImpl(EngineDataSource(bridge, settings));
    final tmp = await Directory.systemTemp.createTemp('mdt');
    workbook = '${tmp.path}/beyblade_parts.xlsx';
    await File('$toolsDir/samples/beyblade_parts.xlsx').copy(workbook);
  });

  tearDownAll(() => bridge.dispose());

  test('open, analyse, edit, auto-fill, undo, save against the real engine', () async {
    final summary = (await repo.open(workbook)).valueOrNull!;
    expect(summary.sheets.map((s) => s.name), contains('Parts_X_Blades'));
    expect(summary.dirty, isFalse);

    final analysis = (await repo.analyze('Parts_X_Blades')).valueOrNull!;
    expect(analysis.total, greaterThan(0));

    final rows = (await repo.rows('Parts_X_Blades', sort: RowSort.missing)).valueOrNull!;
    expect(rows.rows, isNotEmpty);
    final first = rows.rows.first;

    final detail = (await repo.row('Parts_X_Blades', first.id)).valueOrNull!;
    expect(detail.fields, contains('mass'));

    final changed = (await repo.updateRow('Parts_X_Blades', first.id, {'edition': 'Edited from Flutter'})).valueOrNull;
    expect(changed, 1);
    final after = (await repo.row('Parts_X_Blades', first.id)).valueOrNull!;
    expect(after.values['edition'], 'Edited from Flutter');
    expect(after.updatedAt, isNotNull, reason: 'editing stamps last edited');
    expect((await repo.summary()).valueOrNull!.dirty, isTrue);

    final undone = (await repo.undo()).valueOrNull;
    expect(undone, contains('edit'));
    final reverted = (await repo.row('Parts_X_Blades', first.id)).valueOrNull!;
    expect(reverted.values['edition'], detail.values['edition']);

    expect((await repo.proposals('Parts_X_Blades')), isNotNull);
    expect((await repo.save()).fold((f) => f.message, (_) => 'ok'), 'ok');
    expect((await repo.summary()).valueOrNull!.dirty, isFalse);

    // Several cubits ask at once after an auto-fill; the bridge must queue the writes.
    final burst = await Future.wait([
      for (var i = 0; i < 12; i++) repo.rows('Parts_X_Blades', sort: RowSort.updated),
      repo.summary(),
      repo.analyze('Parts_X_Blades'),
    ]);
    expect(burst.every((r) => r.valueOrNull != null), isTrue);

    final bad = await repo.row('Parts_X_Blades', '99999');
    expect(bad.fold((f) => f.message, (_) => ''), contains('No row'));
  }, skip: hasTools ? false : 'missing_data_tool.py not found next to the app');
}
