import 'dart:convert';
import 'dart:developer' as dev;

import 'package:archive/archive.dart';
import 'package:clasher_st/core/constants/app_constants.dart';
import 'package:clasher_st/features/beyblade_tcg/beyblade_tcg.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

class CatalogRelease {
  const CatalogRelease({
    required this.version,
    required this.releaseTag,
    required this.dataUrl,
    required this.dataSha256,
    required this.publishedAt,
  });

  final String version;
  final String releaseTag;
  final String dataUrl;
  final String dataSha256;
  final DateTime publishedAt;

  factory CatalogRelease.fromJson(Map<String, dynamic> json) => CatalogRelease(
        version: json['version'] as String,
        releaseTag: json['releaseTag'] as String? ?? '',
        dataUrl: json['dataUrl'] as String,
        dataSha256: (json['dataSha256'] as String).toLowerCase(),
        publishedAt: DateTime.fromMillisecondsSinceEpoch(
            (json['publishedAtMillis'] as num?)?.toInt() ?? 0),
      );
}

class CatalogDownloadException implements Exception {
  const CatalogDownloadException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class BeybladeCatalogRemoteDataSource {
  /// Null when no release is published yet, which is a normal state for
  /// a fresh environment, not an error — the bundled catalog stays.
  Future<CatalogRelease?> fetchLatestRelease({String channel = 'stable'});

  /// Downloads catalog.zip, verifies its SHA-256 against the release,
  /// and returns sheet name -> raw JSON text: the same shape the bundled
  /// loader produces, so both feed one parser. Optional sheets
  /// ([kOptionalCatalogSheets]) are included when the release has them.
  Future<Map<String, String>> downloadCatalogSheets(CatalogRelease release);
}

class BeybladeCatalogRemoteDataSourceImpl
    implements BeybladeCatalogRemoteDataSource {
  const BeybladeCatalogRemoteDataSourceImpl({
    required this.supabaseClient,
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  final SupabaseClient supabaseClient;
  final http.Client? _httpClient;

  static const _logName = '[Catalog RemoteDS]';

  /// Catalog.zip is tens of KB. Anything slower than this is a dead
  /// connection, and the app is fully usable on its current data.
  static const _timeout = Duration(seconds: 45);

  /// Deliberately works signed out. The RPC is granted to `anon`, so a
  /// first launch that hasn't logged in yet still gets current data.
  @override
  Future<CatalogRelease?> fetchLatestRelease(
      {String channel = 'stable'}) async {
    final raw = await supabaseClient.rpc('beyblade_catalog_manifest',
        params: {'p_channel': channel}).timeout(_timeout);
    if (raw is! Map || raw.isEmpty) return null;
    return CatalogRelease.fromJson(Map<String, dynamic>.from(raw));
  }

  @override
  Future<Map<String, String>> downloadCatalogSheets(
      CatalogRelease release) async {
    final uri = Uri.parse(release.dataUrl);
    dev.log('Downloading ${release.version} from $uri', name: _logName);

    final client = _httpClient ?? http.Client();
    final http.Response response;
    try {
      response = await client.get(uri).timeout(_timeout);
    } finally {
      if (_httpClient == null) client.close();
    }

    if (response.statusCode != 200) {
      throw CatalogDownloadException(
          'Catalog download failed (HTTP ${response.statusCode}).');
    }

    final bytes = response.bodyBytes;

    // Verified before anything is parsed or written. A truncated or
    // tampered file must never reach the replace step, which wipes the
    // current catalog first.
    final actual = sha256.convert(bytes).toString();
    if (actual != release.dataSha256) {
      throw const CatalogDownloadException('Catalog may be problematic.');
    }

    final archive = ZipDecoder().decodeBytes(bytes);
    final tracked = AppConstants.trackedBeyBladeData.toSet();
    // Extra sheets (TCG cards/sets, code series) are kept when present but
    // never required, so older releases still apply.
    final optional = kOptionalCatalogSheets.toSet();
    final sheets = <String, String>{};

    for (final file in archive) {
      if (!file.isFile) continue;
      // Zips built on Windows or with a top-level folder put a path in
      // front of the name; only the file name identifies the sheet.
      final name = file.name.split('/').last.split('\\').last;
      if (!name.endsWith('.json')) continue;
      final sheet = name.substring(0, name.length - '.json'.length);
      if (!tracked.contains(sheet) && !optional.contains(sheet)) continue;
      sheets[sheet] = utf8.decode(file.content as List<int>);
    }

    // Every tracked sheet must be present. A release missing one would
    // otherwise replace that whole part type with nothing.
    final missing = tracked.difference(sheets.keys.toSet());
    if (missing.isNotEmpty) {
      throw CatalogDownloadException(
          'Catalog release is missing: ${missing.join(', ')}.');
    }

    dev.log('Catalog ${release.version}: ${sheets.length} sheets verified',
        name: _logName);
    return sheets;
  }
}
