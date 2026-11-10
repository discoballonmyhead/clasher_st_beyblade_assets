import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:missing_data_app/core/bridge/engine_pool.dart';
import 'package:missing_data_app/core/error/failure.dart';
import 'package:missing_data_app/features/missing_data/data/datasources/engine_data_source.dart';
import 'package:missing_data_app/features/missing_data/data/repositories/missing_data_repository_impl.dart';
import 'package:missing_data_app/features/missing_data/domain/entities/row.dart';
import 'package:missing_data_app/features/missing_data/domain/entities/structure.dart';
import 'package:missing_data_app/core/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Talks to the real Python engine (missing_data_tool.py serve) on a copy of the sample workbook.
/// Skipped when Python or the tools folder isn't there.
void main() {
  final toolsDir = Directory.current.parent.path;
  final python = Platform.environment['MDT_PYTHON'] ?? 'python3';
  final hasTools = File('$toolsDir/missing_data_tool.py').existsSync();

  late WorkbookEngines engines;
  late MissingDataRepositoryImpl repo;
  late String workbook;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'python': python,
      'toolsDir': toolsDir,
    });
    final settings = AppSettings(await SharedPreferences.getInstance());
    engines = WorkbookEngines();
    repo = MissingDataRepositoryImpl(EngineDataSource(engines, settings));
    final tmp = await Directory.systemTemp.createTemp('mdt');
    workbook = '${tmp.path}/beyblade_parts.xlsx';
    await File('$toolsDir/samples/beyblade_parts.xlsx').copy(workbook);
  });

  tearDownAll(() => engines.dispose());

  test(
    'open, analyse, edit, auto-fill, undo, save against the real engine',
    () async {
      final summary = (await repo.open(workbook)).valueOrNull!;
      expect(summary.sheets.map((s) => s.name), contains('Parts_X_Blades'));
      expect(summary.dirty, isFalse);

      final analysis = (await repo.analyze('Parts_X_Blades')).valueOrNull!;
      expect(analysis.total, greaterThan(0));

      final rows = (await repo.rows(
        'Parts_X_Blades',
        sort: RowSort.missing,
      )).valueOrNull!;
      expect(rows.rows, isNotEmpty);
      final first = rows.rows.first;

      final detail = (await repo.row('Parts_X_Blades', first.id)).valueOrNull!;
      expect(detail.fields, contains('mass'));

      final changed = (await repo.updateRow('Parts_X_Blades', first.id, {
        'edition': 'Edited from Flutter',
      })).valueOrNull;
      expect(changed, 1);
      final after = (await repo.row('Parts_X_Blades', first.id)).valueOrNull!;
      expect(after.values['edition'], 'Edited from Flutter');
      expect(after.updatedAt, isNotNull, reason: 'editing stamps last edited');
      expect((await repo.summary()).valueOrNull!.dirty, isTrue);

      final undone = (await repo.undo()).valueOrNull;
      expect(undone, contains('edit'));
      final reverted = (await repo.row(
        'Parts_X_Blades',
        first.id,
      )).valueOrNull!;
      expect(reverted.values['edition'], detail.values['edition']);

      expect((await repo.proposals('Parts_X_Blades')), isNotNull);
      expect((await repo.save()).fold((f) => f.message, (_) => 'ok'), 'ok');
      expect((await repo.summary()).valueOrNull!.dirty, isFalse);

      // Several cubits ask at once after an auto-fill; the bridge must queue the writes.
      final burst = await Future.wait([
        for (var i = 0; i < 12; i++)
          repo.rows('Parts_X_Blades', sort: RowSort.updated),
        repo.summary(),
        repo.analyze('Parts_X_Blades'),
      ]);
      expect(burst.every((r) => r.valueOrNull != null), isTrue);

      final bad = await repo.row('Parts_X_Blades', '99999');
      expect(bad.fold((f) => f.message, (_) => ''), contains('No row'));
    },
    skip: hasTools ? false : 'missing_data_tool.py not found next to the app',
  );

  test('columns, rows and the change log against the real engine', () async {
    await repo.open(workbook);
    const tab = 'Parts_X_Blades';

    expect(
      (await repo.addColumn(
        sheets: [tab, 'Parts_X_Bits'],
        name: 'tipShape',
        inherit: true,
      )) is Ok,
      isTrue,
    );
    final dup = await repo.addColumn(sheets: [tab], name: 'tipShape');
    expect(
      dup.fold((f) => f.message, (_) => ''),
      contains('already has a column'),
    );
    final cols = (await repo.columns(tab)).valueOrNull!;
    expect(cols.last.name, 'tipShape');
    expect(cols.last.custom && cols.last.inherit, isTrue);
    final gap = (await repo.analyze(tab)).valueOrNull!.fields
        .firstWhere((f) => f.field == 'tipShape');
    expect(gap.custom, isTrue);

    final base = (await repo.rows(tab)).valueOrNull!.rows.first.id;
    await repo.updateRow(tab, base, {'tipShape': 'flat'});
    final id = (await repo.addRow(
      tab,
      copyFrom: base,
      mode: NewRowMode.variant,
      values: {'variantLabel': 'Gold'},
    )).valueOrNull!;
    final v = (await repo.row(tab, id)).valueOrNull!;
    expect(v.parentId, base);
    expect(
      v.values['tipShape'],
      'flat',
      reason: 'inherited custom column copied',
    );
    expect(v.customFields, contains('tipShape'));

    final log = (await repo.editLog()).valueOrNull!;
    expect(log.entries.first.action, 'add_row');
    expect(log.entries.first.source, 'missing_data_app');
    expect(
      log.entries.map((e) => e.action),
      containsAll(['add_column', 'set', 'add_row']),
    );
    expect(
      (await repo.editLog(query: 'add_column')).valueOrNull!.total,
      2,
      reason: 'one per tab',
    );

    // undo the row: it and its log line are gone
    await repo.undo();
    expect(
      (await repo.row(tab, id)).fold((f) => f.message, (_) => ''),
      contains('No row'),
    );
    expect((await repo.editLog()).valueOrNull!.entries.first.action, 'set');

    // saved and reopened: the column, its registry and the log survive
    await repo.save();
    await repo.open(workbook);
    expect(
      (await repo.columns(tab)).valueOrNull!
          .any((c) => c.name == 'tipShape' && c.custom),
      isTrue,
    );
    expect((await repo.editLog()).valueOrNull!.total, 3);
    expect((await repo.summary()).valueOrNull!.customColumns, 2);
  }, skip: hasTools ? false : 'missing_data_tool.py not found next to the app');

  test('a session stopped without saving loses nothing: reopen offers the edits back', () async {
    final copy = '${File(workbook).parent.path}/crash.xlsx';
    await File(workbook).copy(copy);
    await repo.open(copy);
    final id = (await repo.addRow(
      'Parts_X_Blades',
      values: {'name': 'Typed before the crash'},
    )).valueOrNull!;
    await repo.updateRow('Parts_X_Blades', id, {'attack': '44'});
    await engines.bridge.stop(); // the window closes: the engine ends without saving

    final s = (await repo.open(copy))
        .valueOrNull!; // a new engine starts on the next call
    expect(s.unsavedEntries, 2);
    expect(
      (await repo.row('Parts_X_Blades', id)).fold((f) => f.message, (_) => ''),
      contains('No row'),
    );
    expect((await repo.recoverUnsaved()).valueOrNull, 2);
    final row = (await repo.row('Parts_X_Blades', id)).valueOrNull!;
    expect(row.values['name'], 'Typed before the crash');
    expect(row.values['attack'], 44);
    await repo.save();
    expect(
      (await repo.open(copy)).valueOrNull!.unsavedEntries,
      0,
      reason: 'saved: nothing left to recover',
    );
  }, skip: hasTools ? false : 'missing_data_tool.py not found next to the app');

  test('delete, recently deleted, restore, id check and renumber against the real engine', () async {
    final tmp = await Directory.systemTemp.createTemp('mdt-del');
    final wb = '${tmp.path}/beyblade_parts.xlsx';
    await File('$toolsDir/samples/beyblade_parts.xlsx').copy(wb);
    await File('$toolsDir/samples/beyblade_products.xlsx')
        .copy('${tmp.path}/beyblade_products.xlsx');
    await repo.open(wb);
    final ids = [
      for (final r in (await repo.rows('Parts_X_Blades')).valueOrNull!.rows)
        r.id,
    ];
    expect(ids, containsAll(['1', '65', '66', '72']));

    final del = (await repo.deleteRows('Parts_X_Blades', ['72'])).valueOrNull!;
    expect(del.deleted, ['72']);
    final bin = (await repo.deletedRows()).valueOrNull!;
    expect(bin.single.rowId, '72');
    expect(bin.single.hasImage, isTrue, reason: 'its picture is kept with it');

    final back = (await repo.restoreDeleted([bin.single.key])).valueOrNull!;
    expect(back.single.id, '72');
    expect((await repo.deletedRows()).valueOrNull, isEmpty);
    expect(
      (await repo.row('Parts_X_Blades', '72')).valueOrNull!.image,
      isNotNull,
      reason: 'picture restored',
    );

    final issues = (await repo.idCheck()).valueOrNull!;
    final blades = issues.firstWhere((i) => i.sheet == 'Parts_X_Blades');
    expect(blades.gapCount, greaterThan(0));

    final r = (await repo.renumber('Parts_X_Blades')).valueOrNull!;
    expect(r.pendingFiles, ['beyblade_products.xlsx']);
    final now = [
      for (final x in (await repo.rows('Parts_X_Blades')).valueOrNull!.rows)
        int.parse(x.id),
    ]..sort();
    expect(now, List.generate(now.length, (i) => i + 1));
    expect(
      (await repo.idCheck()).valueOrNull!.where(
        (i) => i.sheet == 'Parts_X_Blades',
      ),
      isEmpty,
    );

    expect(
      (await repo.undo()).valueOrNull,
      startsWith('renumber'),
      reason: 'one undo step, labelled for the app',
    );
    expect([
      for (final x in (await repo.rows('Parts_X_Blades')).valueOrNull!.rows)
        x.id,
    ], containsAll(['65', '72']));
  }, skip: hasTools ? false : 'missing_data_tool.py not found next to the app');
}
