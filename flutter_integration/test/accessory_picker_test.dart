import 'package:clasher_st/features/bey_testing/presentation/widgets/test_setup_widgets.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/domain/repositories/beyblade_data_repo.dart';
import 'package:clasher_st/features/tournaments/presentation/widgets/stadium_picker_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

Accessory _acc(String id, String name, AccessoryType type) => Accessory(
      dataId: id,
      accessoryType: type,
      manufacturer: 'Takara-Tomy',
      hobbyName: 'Beyblade',
      hobbyGeneration: 'X',
      name: name,
      isIncomplete: false,
    );

class _FakeRepo implements BeybladeDataRepo {
  @override
  Future<List<Accessory>> getAllAccessories() async => [
        _acc('1', 'Xtreme Stadium', AccessoryType.stadium),
        _acc('2', 'Wide Xtreme Stadium', AccessoryType.stadium),
        _acc('3', 'String Launcher', AccessoryType.launcher),
      ];

  @override
  dynamic noSuchMethod(Invocation i) => Future.value(<Never>[]);
}

void main() {
  setUp(() async {
    await GetIt.instance.reset();
    AccessoryCache.clear();
    GetIt.instance.registerSingleton<BeybladeDataRepo>(_FakeRepo());
  });

  testWidgets('tournament stadium: pick, show the name, clear', (tester) async {
    String? value;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => TournamentStadiumField(
            value: value,
            onChanged: (id) => setState(() => value = id),
          ),
        ),
      ),
    ));
    expect(find.text(kNoSpecificStadium), findsOneWidget);

    await tester.tap(find.byType(TournamentStadiumField));
    await tester.pumpAndSettle();
    expect(find.text('String Launcher'), findsNothing, reason: 'stadiums only');
    await tester.tap(find.text('Wide Xtreme Stadium'));
    await tester.pumpAndSettle();
    expect(value, '2');
    expect(find.text('Wide Xtreme Stadium'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear'));
    await tester.pumpAndSettle();
    expect(value, isNull);
  });

  testWidgets('bey_testing keeps its API: SetupTile + AccessoryPickerSheet',
      (tester) async {
    AccessoryChoice? choice;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => SetupTile(
            icon: Icons.rocket_launch_outlined,
            label: 'Your launcher',
            dataId: '3',
            onTap: () async => choice = await AccessoryPickerSheet.show(context,
                type: AccessoryType.launcher,
                title: 'Your launcher',
                selectedId: '3'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('String Launcher'), findsOneWidget, reason: 'AccessoryName');

    await tester.tap(find.byType(SetupTile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('None / not tracked'));
    await tester.pumpAndSettle();
    expect(choice, isNotNull);
    expect(choice!.dataId, isNull);
  });
}
