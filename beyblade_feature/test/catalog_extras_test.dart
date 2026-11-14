// Parses the packager's real output (test/fixtures, made from samples/*.xlsx by beyblade_data.py) through the
// feature's parser, models and repository: 3D models, bladers and stock combos.
//
// Copy into the app's test/ folder (with fixtures/) and run `flutter test test/catalog_extras_test.dart`.
import 'dart:io';

import 'package:clasher_st/features/beyblade/data/dsrces/beyblade_extras_ldsrc.dart';
import 'package:clasher_st/features/beyblade/data/dsrces/beyblade_ldsrc.dart';
import 'package:clasher_st/features/beyblade/data/isolates/beyblade_bundle_parser.dart';
import 'package:clasher_st/features/beyblade/data/models/models.dart';
import 'package:clasher_st/features/beyblade/data/repositories/bey_data_repo_impl.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

Map<String, String> _sheets() {
  final dir = Directory('test/fixtures');
  return {
    for (final f in dir.listSync().whereType<File>())
      if (f.path.endsWith('.json'))
        f.uri.pathSegments.last.replaceAll('.json', ''): f.readAsStringSync(),
  };
}

/// Only the part getters the repository's extras lookups use.
class _PartsOnly implements BeybladeDataLocalDatasource {
  _PartsOnly(this.blades, this.lockChips);
  final List<BladeModel> blades;
  final List<LockChipModel> lockChips;

  @override
  List<BladeModel> getAllBlades() => blades;
  @override
  List<LockChipModel> getAllLockChips() => lockChips;
  @override
  List<RatchetModel> getAllRatchets() => const [];
  @override
  List<BitModel> getAllBits() => const [];
  @override
  List<OverBladeModel> getAllOverBlades() => const [];
  @override
  List<MetalBladeModel> getAllMetalBlades() => const [];
  @override
  List<MainBladeModel> getAllMainBlades() => const [];
  @override
  List<AssistBladeModel> getAllAssistBlades() => const [];
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  final parsed = parseMetadataSheets(_sheets());

  test('the optional sheets come through the bundle parser', () {
    expect(parsed.stockCombos, hasLength(2));
    expect(parsed.bladers, hasLength(2));
    expect(parsed.totalRecords, greaterThan(0));
  });

  test('parts carry their 3D model and bladers; parts without them parse as before', () {
    final blades = parsed.blades.map((r) => BladeModel.fromSheetJson(r).toEntity()).toList();
    final dran = blades.firstWhere((b) => b.dataId == '65');
    expect(dran.has3dModel, isTrue);
    expect(dran.model3dUrl, endsWith('/data/models/blades-65.glb'));
    expect(dran.model3dHash, isNotNull);
    expect(dran.bladerIds, ['BL1', 'BL2']);

    final other = blades.firstWhere((b) => b.dataId != '65');
    expect(other.has3dModel, isFalse);
    expect(other.bladerIds, isEmpty);

    final chips = parsed.lockChips.map((r) => LockChipModel.fromSheetJson(r).toEntity()).toList();
    expect(chips.firstWhere((c) => c.dataId == '1').bladerIds, ['BL1']);
    // every other part type still parses (model3d columns are there, empty)
    for (final r in parsed.ratchets) {
      expect(RatchetModel.fromSheetJson(r).toEntity().model3dUrl, isNull);
    }
  });

  test('bladers: two optional pictures each', () {
    final bladers = parsed.bladers.map((r) => BladerModel.fromSheetJson(r).toEntity()).toList();
    final one = bladers.firstWhere((b) => b.bladerId == 'BL1');
    expect(one.imageUrl, endsWith('bladers-BL1.webp'));
    expect(one.fullBodyImageUrl, endsWith('bladers-BL1-fullBodyImage.webp'));
    expect(one.minifiedFullBodyImageUrl, endsWith('bladers-BL1-fullBodyImage-min.webp'));
    expect(one.avatarUrl, endsWith('bladers-BL1-min.webp'));
    final two = bladers.firstWhere((b) => b.bladerId == 'BL2');
    expect(two.imageUrl, isNull);
    expect(two.avatarUrl, isNull);
  });

  test('stock combos are loadouts: one-piece blade and custom line', () {
    final combos = parsed.stockCombos.map((r) => StockComboModel.fromSheetJson(r).toEntity()).toList();
    final starter = combos.firstWhere((c) => c.stockComboId == 'SC1');
    expect(starter.productId, 'P1');
    expect(starter.loadout.bladeDataId, '65');
    expect(starter.loadout.ratchetDataId, '13');
    expect(starter.loadout.bitDataId, '13');
    expect(starter.has3dModel, isTrue);
    expect(starter.usesPart('blades', '65'), isTrue);
    expect(starter.usesPart('bits', '65'), isFalse);
    // shareable like a user's build
    expect(BeybladeLoadout.fromShareCode(starter.loadout.toShareCode()), starter.loadout);

    final custom = combos.firstWhere((c) => c.stockComboId == 'SC2');
    expect(custom.loadout.bladeDataId, isNull);
    expect(custom.loadout.lockChipDataId, '2');
    expect(custom.loadout.mainBladeDataId, '1');
    expect(custom.loadout.assistBladeDataId, '2');
    expect(custom.partRefs.map((r) => r.$1), ['lockChips', 'mainBlades', 'assistBlades', 'ratchets', 'bits']);
  });

  test('parseIdList takes the packaged list or a hand-typed string', () {
    expect(parseIdList(['BL1', 'BL2']), ['BL1', 'BL2']);
    expect(parseIdList('BL1, BL2;BL1'), ['BL1', 'BL2']);
    expect(parseIdList(null), isEmpty);
    expect(parseIdList(''), isEmpty);
  });

  group('repository + extras store (Hive)', () {
    late Directory tmp;
    late BeyDataRepoImpl repo;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('beyextras');
      Hive.init(tmp.path);
      final extras = HiveBeybladeExtrasLocalDataSource(boxName: 'extras_test');
      await extras.replaceAll(
        stockCombos: [...parsed.stockCombos, {'stockComboID': 'BAD'}], // the bad row is skipped
        bladers: parsed.bladers,
      );
      repo = BeyDataRepoImpl(
        _PartsOnly(
          parsed.blades.map(BladeModel.fromSheetJson).toList(),
          parsed.lockChips.map(LockChipModel.fromSheetJson).toList(),
        ),
        extras,
      );
    });

    tearDown(() async {
      await Hive.close();
      await tmp.delete(recursive: true);
    });

    test('stock combos by product and by part', () async {
      expect((await repo.getAllStockCombos()).map((c) => c.stockComboId), ['SC1', 'SC2']);
      expect((await repo.getStockCombosForProduct('P4')).single.stockComboId, 'SC2');
      expect((await repo.getStockCombosForPart('blades', '65')).single.stockComboId, 'SC1');
      expect(await repo.getStockCombosForPart('blades', '1'), isEmpty);
    });

    test('bladers of a part and parts of a blader', () async {
      final dran = (await repo.getAllBlades()).firstWhere((b) => b.dataId == '65');
      expect((await repo.getBladersForPart(dran)).map((b) => b.name),
          ['EXAMPLE Blader One', 'EXAMPLE Blader Two']);
      final parts = await repo.getPartsForBlader('BL1');
      expect(parts.map((p) => '${p.$1}#${p.$2.dataId}'), ['blades#65', 'lockChips#1']);
      expect(await repo.getBladerById('nobody'), isNull);
    });
  });
}
