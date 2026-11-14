import 'dart:developer' as dev;

import 'package:clasher_st/features/beyblade/data/models/models.dart';
import 'package:hive_ce/hive.dart';

/// Stock combos and bladers on the phone. Kept apart from the part boxes on purpose: this feature opens its
/// own box (no new box to register in the app's Hive setup), and both sheets are small enough to store as
/// one list each. Replaced as a whole with every catalog apply, like the part boxes.
abstract class BeybladeExtrasLocalDataSource {
  /// Replaces both lists. Rows without their id are skipped (logged), so one bad row can't block a catalog.
  Future<void> replaceAll({
    required Iterable<Map<String, dynamic>> stockCombos,
    required Iterable<Map<String, dynamic>> bladers,
  });

  Future<List<StockComboModel>> getAllStockCombos();
  Future<List<BladerModel>> getAllBladers();
  Future<void> clear();
}

class HiveBeybladeExtrasLocalDataSource
    implements BeybladeExtrasLocalDataSource {
  HiveBeybladeExtrasLocalDataSource({this.boxName = defaultBoxName});

  static const defaultBoxName = 'beyblade_catalog_extras';
  static const _stockCombosKey = 'stockCombos';
  static const _bladersKey = 'bladers';
  static const _logName = '[BeyBlade ExtrasDS]';

  final String boxName;

  Future<Box> _box() async =>
      Hive.isBoxOpen(boxName) ? Hive.box(boxName) : Hive.openBox(boxName);

  @override
  Future<void> replaceAll({
    required Iterable<Map<String, dynamic>> stockCombos,
    required Iterable<Map<String, dynamic>> bladers,
  }) async {
    final box = await _box();
    final combos = _valid(stockCombos, StockComboModel.fromSheetJson, 'stock combo');
    final people = _valid(bladers, BladerModel.fromSheetJson, 'blader');
    await box.putAll({_stockCombosKey: combos, _bladersKey: people});
    dev.log('Stored ${combos.length} stock combo(s), ${people.length} blader(s)',
        name: _logName);
  }

  /// Rows the model can read, as plain maps (what Hive stores).
  List<Map<String, dynamic>> _valid(Iterable<Map<String, dynamic>> rows,
      Object Function(Map<String, dynamic>) parse, String what) {
    final out = <Map<String, dynamic>>[];
    for (final r in rows) {
      try {
        parse(r);
        out.add(Map<String, dynamic>.from(r));
      } catch (e) {
        dev.log('Skipped a $what row: $e - $r', name: _logName);
      }
    }
    return out;
  }

  Future<List<T>> _read<T>(
      String key, T Function(Map<String, dynamic>) parse) async {
    final raw = (await _box()).get(key);
    if (raw is! List) return const [];
    final out = <T>[];
    for (final r in raw) {
      try {
        out.add(parse(Map<String, dynamic>.from(r as Map)));
      } catch (e) {
        dev.log('Skipped a stored $key row: $e', name: _logName);
      }
    }
    return out;
  }

  @override
  Future<List<StockComboModel>> getAllStockCombos() =>
      _read(_stockCombosKey, StockComboModel.fromSheetJson);

  @override
  Future<List<BladerModel>> getAllBladers() =>
      _read(_bladersKey, BladerModel.fromSheetJson);

  @override
  Future<void> clear() async => (await _box()).clear();
}
