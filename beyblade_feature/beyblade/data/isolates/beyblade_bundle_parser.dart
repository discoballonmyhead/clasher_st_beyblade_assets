import 'dart:convert';
import 'dart:developer' as dev;

import 'parsed_results.dart';

/// Top-level (isolate-safe) parsing function, passed to `compute()`.
/// Reshapes JSON into plain Maps only — turning a row into an `<X>Model`
/// happens later, on the main isolate, in BeybladeLocalDataSource.
///
/// parseUpdatesBatch (the incremental `updates` endpoint parser) has
/// been removed -- that mechanism belonged to the old live-sync
/// architecture. Every update now ships as a full app release with a
/// freshly-packaged bundle, so there's no incremental "what changed
/// since a cursor" response left to parse.

const _logName = 'Beyblade.Parser';

String _preview(String s, [int max = 300]) =>
    s.length <= max ? s : '${s.substring(0, max)}…';

/// Parses the metadata bundle: one raw JSON string per tracked sheet.
ParsedFullBundle parseMetadataSheets(Map<String, String> rawJsonBySheet) {
  dev.log('parseMetadataSheets: ${rawJsonBySheet.length} sheet(s)',
      name: _logName);

  List<Map<String, dynamic>> rowsFor(String sheet) {
    final raw = rawJsonBySheet[sheet];
    if (raw == null) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded.containsKey('error')) {
        throw FormatException('Packager error: ${decoded['error']}');
      }
      return (decoded as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (e, st) {
      dev.log('$sheet failed, response started with:\n${_preview(raw)}',
          name: _logName, error: e, stackTrace: st, level: 1000);
      rethrow;
    }
  }

  final result = ParsedFullBundle(
    blades: rowsFor('blades'),
    ratchets: rowsFor('ratchets'),
    bits: rowsFor('bits'),
    lockChips: rowsFor('lockChips'),
    overBlades: rowsFor('overBlades'),
    metalBlades: rowsFor('metalBlades'),
    mainBlades: rowsFor('mainBlades'),
    assistBlades: rowsFor('assistBlades'),
    products: rowsFor('products'),
    accessories: rowsFor('accessories'),
    productContents: rowsFor('productContents'),
    stockCombos: rowsFor('stockCombos'),
    bladers: rowsFor('bladers'),
  );

  dev.log(
    'parseMetadataSheets done: blades=${result.blades.length} ratchets=${result.ratchets.length} bits=${result.bits.length} '
    'lockChips=${result.lockChips.length} overBlades=${result.overBlades.length} metalBlades=${result.metalBlades.length} '
    'mainBlades=${result.mainBlades.length} assistBlades=${result.assistBlades.length} products=${result.products.length} '
    'accessories=${result.accessories.length} productContents=${result.productContents.length} '
    'stockCombos=${result.stockCombos.length} bladers=${result.bladers.length}',
    name: _logName,
  );
  return result;
}
