// The six-stat model (single / dynamic "25/55" / dual mode "25-55", blank = 0), parsing real catalog rows,
// the combo calculator, and the stat widgets: the animated radar, the panel, the mini dialog and the graph
// page. Copy into the app's test/ folder (with fixtures/) and run `flutter test test/stats_test.dart`.
import 'dart:convert';
import 'dart:io';

import 'package:clasher_st/core/responsive/responsive_provider.dart';
import 'package:clasher_st/core/theme/app_theme.dart';
import 'package:clasher_st/features/beyblade/data/models/models.dart';
import 'package:clasher_st/features/beyblade/domain/engines/beyblade_stats_calculator.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/stats/holo_stat_panel.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/stats/holo_stat_radar.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/stats/holo_stat_rows.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/stats/stat_graph_page.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/stats/stat_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final _real = jsonDecode(File('test/fixtures/stats/real_rows.json').readAsStringSync())
    as Map<String, dynamic>;
Map<String, dynamic> _row(String sheet, String id) => Map<String, dynamic>.from(
    (_real[sheet] as List).firstWhere((r) => '${r['dataID']}' == id) as Map);

Map<String, dynamic> _base(String id, String name, {Map<String, dynamic> extra = const {}}) => {
      'dataID': id,
      'manufacturer': 'Takara-Tomy',
      'hobbyName': 'Beyblade',
      'hobbyGeneration': 'X',
      'code': 'BX-$id',
      'name': name,
      'wbolegality': 1,
      'mass': 10,
      ...extra,
    };

Blade _blade(Map<String, dynamic> stats, {String id = '1'}) => BladeModel.fromSheetJson(
        _base(id, 'Test Blade', extra: {'type': 'attack', 'spinDir': 'right', ...stats}))
    .toEntity();
Ratchet _ratchet(Map<String, dynamic> stats) =>
    RatchetModel.fromSheetJson(_base('2', '3-60', extra: stats)).toEntity();
Bit _bit(Map<String, dynamic> stats) => BitModel.fromSheetJson(
        _base('3', 'Flat', extra: {'baseName': 'F', 'movementStyle': 'attack', ...stats}))
    .toEntity();

Beyblade _combo(Blade blade, Ratchet ratchet, Bit bit) {
  const calc = BeybladeStatsCalculator();
  final parts = <BeybladePart>[blade, ratchet, bit];
  return Beyblade(
    loadout: BeybladeLoadout(bladeDataId: blade.dataId, ratchetDataId: ratchet.dataId, bitDataId: bit.dataId),
    assembly: UnibodyAssembly(blade),
    ratchet: ratchet,
    bit: bit,
    combinedStats: calc.combine(parts),
    totalMass: calc.totalMass(parts),
    archetype: bit.movementStyle,
    spinDirection: blade.spinDirection,
    legality: WboLegality.legal,
  );
}

Future<void> _pump(WidgetTester tester, Widget child, {Size size = const Size(420, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    builder: (context, c) => ResponsiveProvider(child: c!),
    home: Scaffold(body: SingleChildScrollView(child: child)),
  ));
}

void main() {
  group('StatValue', () {
    test('numbers, dynamic and dual-mode spellings', () {
      expect(StatValue.parse(55), StatValue.single(55));
      expect(StatValue.parse('55'), StatValue.single(55));
      expect(StatValue.parse('25/55').mode, StatMode.dynamic);
      expect(StatValue.parse('25 > 55').mode, StatMode.dynamic, reason: 'older spelling');
      expect(StatValue.parse('25 → 55').mode, StatMode.dynamic);
      expect(StatValue.parse('25-55').mode, StatMode.dualMode);
      expect(StatValue.parse('30 -15'), StatValue.dualMode(30, 15));
      expect(StatValue.parse(null), StatValue.none);
      expect(StatValue.parse(''), StatValue.none);
      expect(StatValue.parse('lots'), StatValue.none);
      expect(StatValue.none.value, 0, reason: 'blank is 0');
    });

    test('a single flag overrides the delimiter; both or none leave it', () {
      expect(StatValue.parse('25-55', dynamicFlag: true).mode, StatMode.dynamic);
      expect(StatValue.parse('25/55', dualModeFlag: true).mode, StatMode.dualMode);
      expect(StatValue.parse('25/55', dynamicFlag: true, dualModeFlag: true).mode, StatMode.dynamic);
    });

    test('format, explanation and adding up', () {
      expect(StatValue.dynamic(25, 55).format(), '25 › 55');
      expect(StatValue.dualMode(30, 15).format(), '30 | 15');
      expect(StatValue.single(34.6).format(), '34.6');
      expect(StatValue.none.format(), '—');
      expect(StatValue.dynamic(25, 55).explanation, contains('becomes 55'));
      expect(StatValue.single(10) + StatValue.single(5), StatValue.single(15));
      expect(StatValue.single(10) + StatValue.none, StatValue.single(10));
      expect(StatValue.none + StatValue.none, StatValue.none);
      expect(StatValue.dynamic(25, 55) + StatValue.single(10), StatValue.dynamic(35, 65));
      expect(StatValue.dynamic(25, 55) + StatValue.dualMode(1, 2), StatValue.dualMode(26, 57),
          reason: 'dual mode wins when two parts disagree');
    });
  });

  group('real catalog rows', () {
    test('ScorpioSpear "25 > 55" is dynamic, HellsNether "50 - 70" dual mode, bits too', () {
      final scorpio = BladeModel.fromSheetJson(_row('blades', '245')).toEntity();
      expect(scorpio.stats[StatKey.attack], StatValue.dynamic(25, 55));
      expect(scorpio.isDynamicStat, isTrue);
      expect(scorpio.isDualMode, isFalse);
      final nether = BladeModel.fromSheetJson(_row('blades', '483')).toEntity();
      expect(nether.stats[StatKey.stamina], StatValue.dualMode(30, 15));
      expect(nether.isDualMode, isTrue);
      final turbo = BitModel.fromSheetJson(_row('bits', '441')).toEntity();
      expect(turbo.stats[StatKey.dash], StatValue.dualMode(10, 45));
      expect(turbo.stats[StatKey.burstResistance], StatValue.single(80));
      expect(turbo.isTwoStat, isTrue);
    });

    test('plain parts: six keys, blank ones not provided but 0', () {
      final dagger = BladeModel.fromSheetJson(_row('blades', '65')).toEntity();
      expect(dagger.stats.providedKeys, [StatKey.attack, StatKey.defense, StatKey.stamina]);
      expect(dagger.stats.value(StatKey.dash), 0);
      expect(dagger.stats.hasTwo, isFalse);
      final ratchet = RatchetModel.fromSheetJson(_row('ratchets', '1')).toEntity();
      expect(ratchet.stats.value(StatKey.attack), greaterThan(0));
    });

    test('description is read from the row', () {
      final b = _blade({'attack': 10, 'description': 'A sharp attack blade.'});
      expect(b.description, 'A sharp attack blade.');
      expect(_blade({'attack': 10}).description, isNull);
    });
  });

  group('combo stats', () {
    test('parts add up key by key; a dynamic blade gives a dynamic combo', () {
      final bey = _combo(
        _blade({'attack': '25/55', 'defense': 30, 'stamina': 20, 'dynamicStat': 1}),
        _ratchet({'attack': 10, 'defense': 12, 'stamina': 8, 'height': 60}),
        _bit({'attack': 40, 'defense': 5, 'stamina': 5, 'dash': 30, 'burstRes': 50}),
      );
      final s = bey.combinedStats;
      expect(s[StatKey.attack], StatValue.dynamic(75, 105));
      expect(s[StatKey.defense], StatValue.single(47));
      expect(s[StatKey.height], StatValue.single(60));
      expect(s[StatKey.dash], StatValue.single(30));
      expect(s.hasDynamic, isTrue);
      expect(s.firstOnly[StatKey.attack], StatValue.single(75));
      expect(s.secondOnly[StatKey.attack], StatValue.single(105));
      expect(s.peak, 105);
      expect(bey.totalMass, 30);
      expect(
          const BeybladeStatsCalculator()
              .contributions(bey.stackedParts, StatKey.dash)
              .map((c) => c.$1.name),
          ['Flat']);
    });

    test('scale: a round number just above the highest stat', () {
      expect(StatScale.niceCeiling(19), 20);
      expect(StatScale.niceCeiling(55), 60);
      expect(StatScale.niceCeiling(105), 120);
      expect(const StatScale.fixed(100).maxFor([const StatBlock.empty()]), 100);
    });
  });

  group('widgets', () {
    final dynamicBlade = _blade({'attack': '25/55', 'defense': 55, 'stamina': 30, 'dynamicStat': 1});

    testWidgets('the radar grows outward, then reads its stats to screen readers', (tester) async {
      await _pump(tester, SizedBox(
          width: 300, height: 300, child: HoloStatRadar(stats: dynamicBlade.stats)));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(RegExp(r'Attack 25 › 55, Defense 55')), findsOneWidget);
    });

    testWidgets('tapping near an axis reports that stat', (tester) async {
      StatKey? tapped;
      await _pump(tester, Center(
        child: SizedBox(
            width: 300,
            height: 300,
            child: HoloStatRadar(stats: dynamicBlade.stats, onAxisTap: (k) => tapped = k)),
      ));
      await tester.pumpAndSettle();
      final box = tester.getRect(find.byType(HoloStatRadar));
      await tester.tapAt(box.center + const Offset(0, -120)); // straight up: the first axis
      expect(tapped, StatKey.attack);
    });

    testWidgets('panel: badges and a Start / End toggle for a dynamic part', (tester) async {
      await _pump(tester, HoloStatPanel(stats: dynamicBlade.stats));
      await tester.pumpAndSettle();
      expect(find.text('CHANGES MID-BATTLE'), findsOneWidget);
      expect(find.text('25 › 55'), findsOneWidget);
      await tester.tap(find.text('END'));
      await tester.pumpAndSettle();
      expect(find.text('55'), findsNWidgets(2), reason: 'attack now shows its end value, like defense');
      expect(find.text('25 › 55'), findsNothing);
    });

    testWidgets('panel lays the radar beside the rows when it is wide', (tester) async {
      await _pump(tester, HoloStatPanel(stats: dynamicBlade.stats), size: const Size(1200, 900));
      await tester.pumpAndSettle();
      final radar = tester.getRect(find.byType(HoloStatRadar));
      final rows = tester.getRect(find.byType(HoloStatRows));
      expect(rows.left, greaterThan(radar.right - 1));
    });

    testWidgets('combo mini dialog -> detailed graph with what each part adds', (tester) async {
      final bey = _combo(dynamicBlade, _ratchet({'attack': 10, 'defense': 12, 'stamina': 8}),
          _bit({'attack': 40, 'dash': 30, 'burstRes': 50}));
      await _pump(tester, Builder(
        builder: (context) => TextButton(
            onPressed: () => showComboStats(context, bey), child: const Text('open')),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(HoloStatRadar), findsOneWidget);
      await tester.ensureVisible(find.text('DETAILED GRAPH').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('DETAILED GRAPH').last);
      await tester.pumpAndSettle();
      expect(find.byType(StatGraphPage), findsOneWidget);
      await tester.scrollUntilVisible(find.text('WHAT EACH PART ADDS'), 300,
          scrollable: find.descendant(
              of: find.byType(StatGraphPage), matching: find.byType(Scrollable)).first);
      expect(find.text('WHAT EACH PART ADDS'), findsOneWidget);
      expect(find.byType(HoloStatRadar), findsWidgets);
      // HoloSectionLabel's marquee waits 2 s between scrolls; let it finish.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
