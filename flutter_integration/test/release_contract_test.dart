// End-to-end contract: a release built by build_release.py, read by the app's own code.
//   E2E_RELEASE=<_release/<tag>>  E2E_ASSETS=<--app-assets dir>  flutter test test/release_contract_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:clasher_st/core/constants/app_constants.dart';
import 'package:clasher_st/features/beyblade/data/dsrces/beyblade_cat_remdsrc.dart';
import 'package:clasher_st/features/beyblade/data/isolates/beyblade_bundle_parser.dart';
import 'package:clasher_st/features/beyblade/data/isolates/parsed_results.dart';
import 'package:clasher_st/features/beyblade/data/models/models.dart';
import 'package:clasher_st/features/beyblade_tcg/beyblade_tcg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MemoryStore implements TcgStore {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

/// Every row through the app's models, exactly as the getters do on read.
Map<String, int> parseAll(ParsedFullBundle p) {
  final n = <String, int>{};
  void each(String name, List<Map<String, dynamic>> rows, Object Function(Map<String, dynamic>) f) {
    for (final r in rows) {
      f(r);
    }
    n[name] = rows.length;
  }

  each('blades', p.blades, (r) => BladeModel.fromSheetJson(r).toEntity());
  each('ratchets', p.ratchets, (r) => RatchetModel.fromSheetJson(r).toEntity());
  each('bits', p.bits, (r) => BitModel.fromSheetJson(r).toEntity());
  each('lockChips', p.lockChips, (r) => LockChipModel.fromSheetJson(r).toEntity());
  each('overBlades', p.overBlades, (r) => OverBladeModel.fromSheetJson(r).toEntity());
  each('metalBlades', p.metalBlades, (r) => MetalBladeModel.fromSheetJson(r).toEntity());
  each('mainBlades', p.mainBlades, (r) => MainBladeModel.fromSheetJson(r).toEntity());
  each('assistBlades', p.assistBlades, (r) => AssistBladeModel.fromSheetJson(r).toEntity());
  each('products', p.products, (r) => ProductModel.fromSheetJson(r).toEntity());
  each('accessories', p.accessories, (r) => AccessoryModel.fromSheetJson(r).toEntity());
  each('productContents', p.productContents, (r) => ProductContentModel.fromSheetJson(r).toEntity());
  return n;
}

/// ProductContents resolve the way detail_page.dart does: 'accessories' or a
/// getPartByTypeAndDataId key, and the id must exist there.
void checkContents(ParsedFullBundle p) {
  final ids = <String, Set<String>>{
    'blades': {for (final r in p.blades) '${r['dataID']}'},
    'ratchets': {for (final r in p.ratchets) '${r['dataID']}'},
    'bits': {for (final r in p.bits) '${r['dataID']}'},
    'lockChips': {for (final r in p.lockChips) '${r['dataID']}'},
    'overBlades': {for (final r in p.overBlades) '${r['dataID']}'},
    'metalBlades': {for (final r in p.metalBlades) '${r['dataID']}'},
    'mainBlades': {for (final r in p.mainBlades) '${r['dataID']}'},
    'assistBlades': {for (final r in p.assistBlades) '${r['dataID']}'},
    'accessories': {for (final r in p.accessories) '${r['dataID']}'},
  };
  for (final r in p.productContents) {
    final c = ProductContentModel.fromSheetJson(r).toEntity();
    expect(ids.keys, contains(c.partType), reason: 'partType of $r');
    expect(ids[c.partType], contains(c.partDataId), reason: 'part of $r');
  }
}

void main() {
  final release = Platform.environment['E2E_RELEASE'];
  final assets = Platform.environment['E2E_ASSETS'];

  test('the app downloads, verifies, parses and resolves the release', () async {
    final manifest = jsonDecode(File('$release/catalog_manifest.json').readAsStringSync())
        as Map<String, dynamic>;
    final zip = File('$release/catalog.zip').readAsBytesSync();
    final remote = BeybladeCatalogRemoteDataSourceImpl(
      supabaseClient: SupabaseClient('https://example.supabase.co', 'anon'),
      httpClient: MockClient((req) async {
        expect(req.url.toString(), manifest['dataUrl']);
        return http.Response.bytes(zip, 200);
      }),
    );
    final sheets = await remote.downloadCatalogSheets(CatalogRelease.fromJson(manifest));
    expect(sheets.keys, containsAll(AppConstants.trackedBeyBladeData));

    final parsed = parseMetadataSheets(sheets);
    expect(parsed.totalRecords, greaterThan(0));
    final counts = parseAll(parsed);
    checkContents(parsed);
    // ignore: avoid_print
    print('parsed with the app models: $counts');

    final tcg = TcgCatalog(_MemoryStore());
    await tcg.ingestSheets(sheets);
    final tcgRows = (jsonDecode(sheets['tcgCards'] ?? '[]') as List).length;
    expect(await tcg.cards(), hasLength(tcgRows));
  }, skip: release == null ? 'set E2E_RELEASE' : false);

  test('the bundled assets load like loadPartsDataBundle()', () async {
    final sheets = {
      for (final s in AppConstants.trackedBeyBladeData)
        s: File('$assets/$s.json').readAsStringSync(),
    };
    jsonDecode(File('$assets/manifest.json').readAsStringSync());
    final parsed = parseMetadataSheets(sheets);
    parseAll(parsed);
    checkContents(parsed);
  }, skip: assets == null ? 'set E2E_ASSETS' : false);
}
