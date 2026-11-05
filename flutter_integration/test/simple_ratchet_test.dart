// The simple-ratchet rule: a blade (single-blade build) or assist blade (lock
// chip build) with requiresSimpleRatchet only takes a ratchet with
// simpleRatchet = 1 - in the models, the builder, its picker and the randomizer.
import 'package:clasher_st/features/beyblade/data/models/models.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/domain/repositories/beyblade_data_repo.dart';
import 'package:clasher_st/features/beyblade/domain/usecases/usecases.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/bey_builder_cubit/bey_builder_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/bey_builder_cubit/bey_builder_state.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/beyblade_builder_content.dart';
import 'package:clasher_st/features/beyblade/utils/catalog_randomizer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

const _stats = StatBlock.empty();

Blade blade(String id, String name, {bool needsSimple = false}) => Blade(
      dataId: id, manufacturer: 'Takara-Tomy', hobbyName: 'Beyblade', hobbyGeneration: 'X',
      code: 'BX-$id', name: name, mass: 35, legality: WboLegality.legal, isIncomplete: false,
      archetype: BeybladeArchetype.attack, spinDirection: SpinDirection.right, stats: _stats,
      hasIntegratedRatchet: false, requiresSimpleRatchet: needsSimple);

Ratchet ratchet(String id, String name, {bool simple = false}) => Ratchet(
      dataId: id, manufacturer: 'Takara-Tomy', hobbyName: 'Beyblade', hobbyGeneration: 'X',
      code: 'BX-$id', name: name, mass: 6, legality: WboLegality.legal, isIncomplete: false,
      stats: _stats, isSimple: simple);

Bit bit(String id, String name) => Bit(
      dataId: id, manufacturer: 'Takara-Tomy', hobbyName: 'Beyblade', hobbyGeneration: 'X',
      code: 'BX-$id', name: name, mass: 2, legality: WboLegality.legal, isIncomplete: false,
      baseName: name, movementStyle: BeybladeArchetype.attack, stats: _stats, isTwoStat: false,
      hasIntegratedRatchet: false);

LockChip lockChip(String id) => LockChip(
      dataId: id, manufacturer: 'Takara-Tomy', hobbyName: 'Beyblade', hobbyGeneration: 'X',
      code: 'UX-$id', name: 'Lock $id', mass: 2, legality: WboLegality.legal, isIncomplete: false);

MainBlade mainBlade(String id) => MainBlade(
      dataId: id, manufacturer: 'Takara-Tomy', hobbyName: 'Beyblade', hobbyGeneration: 'X',
      code: 'CX-$id', name: 'Main $id', mass: 20, legality: WboLegality.legal, isIncomplete: false,
      type: BeybladeArchetype.attack, spinDirection: SpinDirection.right, stats: _stats);

AssistBlade assistBlade(String id, String name, {bool needsSimple = false}) => AssistBlade(
      dataId: id, manufacturer: 'Takara-Tomy', hobbyName: 'Beyblade', hobbyGeneration: 'X',
      code: 'CX-$id', name: name, mass: 5, legality: WboLegality.legal, isIncomplete: false,
      type: BeybladeArchetype.attack, spinDirection: SpinDirection.right, stats: _stats,
      requiresSimpleRatchet: needsSimple);

final needy = blade('1', 'Needy Blade', needsSimple: true);
final easy = blade('2', 'Easy Blade');
final simple = ratchet('10', 'Simple 3-60', simple: true);
final plain = ratchet('11', 'Plain 4-80');
final plain2 = ratchet('12', 'Plain 9-60');
final ball = bit('20', 'Ball');
final needyAssist = assistBlade('30', 'Needy Assist', needsSimple: true);
final easyAssist = assistBlade('31', 'Easy Assist');

/// Records what the builder resolves; the preview itself isn't under test.
class FakeResolver implements ResolveBeybladeUseCase {
  final resolved = <BeybladeLoadout>[];
  @override
  Future<Beyblade?> call(BeybladeLoadout loadout) async {
    resolved.add(loadout);
    return null;
  }
}

class FakeRepo implements BeybladeDataRepo {
  @override
  Future<List<Blade>> getAllBlades() async => [needy, easy];
  @override
  Future<List<Ratchet>> getAllRatchets() async => [simple, plain, plain2];
  @override
  Future<List<Bit>> getAllBits() async => [ball];
  @override
  Future<List<LockChip>> getAllLockChips() async => [lockChip('40')];
  @override
  Future<List<MainBlade>> getAllMainBlades() async => [mainBlade('50')];
  @override
  Future<List<AssistBlade>> getAllAssistBlades() async => [needyAssist, easyAssist];
  @override
  dynamic noSuchMethod(Invocation i) => Future.value(<Never>[]);
}

Map<String, dynamic> row(Map<String, dynamic> extra) => {
      'dataID': '1', 'manufacturer': 'Takara-Tomy', 'hobbyName': 'Beyblade', 'hobbyGeneration': 'X',
      'code': 'BX-01', 'name': 'Test', 'wbolegality': 1, 'mass': 30, 'type': 'attack', 'spinDir': 'right',
      ...extra,
    };

void main() {
  group('models read the sheet columns', () {
    test('simpleRatchet / requiresSimpleRatchet: 1, "1", true -> true; blank or missing -> false', () {
      expect(RatchetModel.fromSheetJson(row({'simpleRatchet': 1})).toEntity().isSimple, isTrue);
      expect(RatchetModel.fromSheetJson(row({'simpleRatchet': '1'})).toEntity().isSimple, isTrue);
      expect(RatchetModel.fromSheetJson(row({'simpleRatchet': null})).toEntity().isSimple, isFalse);
      expect(RatchetModel.fromSheetJson(row({})).toEntity().isSimple, isFalse, reason: 'older catalogs');
      expect(BladeModel.fromSheetJson(row({'requiresSimpleRatchet': 1})).toEntity().requiresSimpleRatchet,
          isTrue);
      expect(BladeModel.fromSheetJson(row({})).toEntity().requiresSimpleRatchet, isFalse);
      expect(
          AssistBladeModel.fromSheetJson(row({'requiresSimpleRatchet': true})).toEntity().requiresSimpleRatchet,
          isTrue);
    });
  });

  group('builder', () {
    late BeyBuilderCubit cubit;
    late FakeResolver resolver;
    setUp(() {
      resolver = FakeResolver();
      cubit = BeyBuilderCubit(resolver);
    });
    tearDown(() => cubit.close());

    test('a blade that needs a simple ratchet drops a plain one, and only takes simple ones', () async {
      cubit.selectRatchet(plain);
      cubit.selectBit(ball);
      cubit.selectBlade(needy);
      expect(cubit.state.selectedRatchet, isNull, reason: 'plain ratchet dropped');
      expect(cubit.state.requiresSimpleRatchet, isTrue);
      expect(cubit.missingSlots, ['Simple Ratchet']);

      cubit.selectRatchet(plain2);
      expect(cubit.state.selectedRatchet, isNull, reason: 'non-simple ignored');
      cubit.selectRatchet(simple);
      expect(cubit.state.selectedRatchet, simple);
      await Future<void>.delayed(Duration.zero);
      expect(resolver.resolved.last.ratchetDataId, '10');
      expect(resolver.resolved.last.bladeDataId, '1');
    });

    test('a blade that needs nothing keeps any ratchet', () {
      cubit.selectRatchet(plain);
      cubit.selectBlade(easy);
      expect(cubit.state.selectedRatchet, plain);
      expect(cubit.state.requiresSimpleRatchet, isFalse);
    });

    test('lock chip builds: the assist blade decides', () {
      cubit.setBladeMode(BladeMode.separated);
      cubit.setCoreMode(CoreMode.main);
      cubit.selectRatchet(plain);
      cubit.selectAssistBlade(needyAssist);
      expect(cubit.state.selectedRatchet, isNull);
      expect(cubit.state.simpleRatchetRequiredBy, needyAssist);
      cubit.selectAssistBlade(easyAssist);
      cubit.selectRatchet(plain);
      expect(cubit.state.selectedRatchet, plain);
    });

    test('a saved build that breaks the rule loads without its ratchet', () {
      cubit.loadParts(bladeMode: BladeMode.unibody, blade: needy, ratchet: plain, bit: ball);
      expect(cubit.state.selectedBlade, needy);
      expect(cubit.state.selectedRatchet, isNull);
      cubit.loadParts(bladeMode: BladeMode.unibody, blade: needy, ratchet: simple, bit: ball);
      expect(cubit.state.selectedRatchet, simple);
    });
  });

  test('the randomizer only pairs simple ratchets with parts that need one', () async {
    final session = await CatalogRandomizer(FakeRepo()).openSession();
    var needyRolls = 0;
    for (var i = 0; i < 300; i++) {
      final l = session.build(const RandomBuildFilter(), usedFamilies: null);
      expect(l, isNotNull);
      final needs = l!.bladeDataId == needy.dataId || l.assistBladeDataId == needyAssist.dataId;
      if (needs) {
        needyRolls++;
        expect(l.ratchetDataId, simple.dataId, reason: 'roll $i: $l');
      }
    }
    expect(needyRolls, greaterThan(20), reason: 'the needy parts were rolled');
  });

  testWidgets('builder widget: the ratchet picker offers only simple ratchets when needed', (tester) async {
    await GetIt.instance.reset();
    GetIt.instance
      ..registerSingleton<BeybladeDataRepo>(FakeRepo())
      ..registerSingleton<ResolveBeybladeUseCase>(FakeResolver());
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: BeybladeBuilderContent(onConfirm: (_) {}))),
    ));
    await tester.pumpAndSettle();

    // before: every ratchet is offered
    await tester.tap(find.text('Ratchet').first);
    await tester.pumpAndSettle();
    expect(find.text('Plain 4-80'), findsOneWidget);
    expect(find.text('Simple 3-60'), findsOneWidget);
    await tester.tap(find.text('Plain 4-80'));
    await tester.pumpAndSettle();

    // pick the blade that needs a simple ratchet: the plain one goes, the slot says so
    await tester.tap(find.text('Blade').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Needy Blade'));
    await tester.pumpAndSettle();
    expect(find.text('Simple Ratchet'), findsWidgets);
    expect(find.text('Plain 4-80'), findsNothing, reason: 'dropped from the build');

    await tester.tap(find.text('Simple Ratchet').first);
    await tester.pumpAndSettle();
    expect(find.text('Simple 3-60'), findsOneWidget);
    expect(find.text('Plain 4-80'), findsNothing);
    expect(find.text('Plain 9-60'), findsNothing);
    expect(find.textContaining('Needy Blade needs a simple ratchet'), findsOneWidget);
    await tester.tap(find.text('Simple 3-60'));
    await tester.pumpAndSettle();
    expect(find.text('Simple 3-60'), findsOneWidget, reason: 'picked into the slot');

    // switch to a blade that needs nothing: the full list is back
    await tester.tap(find.text('Needy Blade'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Easy Blade'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simple 3-60'));
    await tester.pumpAndSettle();
    expect(find.text('Plain 4-80'), findsOneWidget, reason: 'filter reset');
  });
}
