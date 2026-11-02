import 'package:clasher_st/core/constants/trc_constant_tokens.dart';
import 'package:clasher_st/core/services/translation/translation_helper.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/domain/repositories/beyblade_data_repo.dart';
import 'package:clasher_st/features/beyblade/parts_list.dart';
import 'package:clasher_st/features/beyblade/presentation/part_lists/beyblade_part_catalog.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/part_list_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

Blade _blade(String id, String name, {String? parent, String? label}) => Blade(
      dataId: id,
      parentPartId: parent,
      variantLabel: label,
      manufacturer: 'Takara-Tomy',
      hobbyName: 'Beyblade',
      hobbyGeneration: 'X',
      code: 'BX-01',
      name: name,
      mass: 35,
      legality: WboLegality.legal,
      isIncomplete: false,
      archetype: BeybladeArchetype.attack,
      spinDirection: SpinDirection.right,
      stats: const StatBlock.empty(),
      hasIntegratedRatchet: false,
    );

/// Only the getAll* calls the catalog makes; everything else is unused here.
class _FakeRepo implements BeybladeDataRepo {
  @override
  Future<List<Blade>> getAllBlades() async => [
        _blade('65', 'Dran Sword'),
        _blade('66', 'Dran Sword', parent: '65', label: 'Metal Coat: Red'),
        _blade('2', 'Hells Scythe'),
      ];

  @override
  dynamic noSuchMethod(Invocation i) => Future.value(<Never>[]);
}

void main() {
  late BeybladePartCatalog catalog;

  setUp(() async {
    await GetIt.instance.reset();
    catalog = BeybladePartCatalog(_FakeRepo());
    GetIt.instance.registerSingleton<PartCatalog>(catalog);
  });

  test('names, labels and variant groups come from the parts catalog', () async {
    expect(catalog.isReady, isFalse);
    await catalog.ready();
    expect(resolvePartCatalog(), same(catalog));
    expect(catalog.nameOf(const PartRef('blade', '66')),
        'Dran Sword (Metal Coat: Red)');
    expect(catalog.nameOf(const PartRef('blade', '999')), 'Blade #999');
    expect(catalog.typeLabel('lockChip'), 'Lock chip');
    expect(catalog.variantGroup(const PartRef('blade', '66')).toSet(),
        {const PartRef('blade', '65'), const PartRef('blade', '66')});
  });

  testWidgets('editor shows real names and adds a part with its variants',
      (tester) async {
    var list = const PartList(kind: PartListKind.ban, parts: {
      'blade': ['2'],
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: PartListEditor(
              list: list,
              onChanged: (l) => setState(() => list = l),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // Rebuilt once the catalog loaded: a name, not "Blade #2".
    expect(find.text('Hells Scythe'), findsOneWidget);

    await tester.tap(find.text(TrTokens.addPartBtn.tr));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'dran');
    await tester.pumpAndSettle();
    // Recolors are listed under the original only when "Show recolors" is on;
    // tapping the original adds it with every variant (the default).
    await tester.tap(find.text('Dran Sword').first);
    await tester.pumpAndSettle();

    expect(list.parts['blade'], ['2', '65', '66']);
    expect(find.text('Dran Sword (Metal Coat: Red)'), findsOneWidget);
  });

  testWidgets('list preview names the first parts', (tester) async {
    await catalog.ready();
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PartListPreview(
          list: PartList(kind: PartListKind.approve, parts: {
            'blade': ['65', '66', '2', '999'],
          }),
        ),
      ),
    ));
    expect(find.text('Dran Sword, Dran Sword (Metal Coat: Red), Hells Scythe +1'),
        findsOneWidget);
  });
}
