import 'dart:async';
import 'dart:convert';

import 'package:clasher_st/features/contributions/data/contributions_config.dart';
import 'package:clasher_st/features/contributions/domain/contributions_repository.dart';
import 'package:clasher_st/features/contributions/domain/entities.dart';
import 'package:http/http.dart' as http;

/// data/_wanted.json from the CDN (the packager writes it with every package). Kept in memory for a while so
/// going back and forth between the list and an entry doesn't download it again.
class HttpWantedSource implements WantedSource {
  HttpWantedSource(this._config, {http.Client? client, this.keepFor = const Duration(minutes: 10)})
      : _client = client;

  final ContributionsConfig _config;
  final http.Client? _client;
  final Duration keepFor;
  WantedList? _cached;
  DateTime? _cachedAt;

  @override
  bool get isConfigured => _config.wantedUrl.startsWith('https://') ||
      _config.wantedUrl.startsWith('http://127.0.0.1') ||
      _config.wantedUrl.startsWith('http://localhost');

  @override
  Future<WantedList> load({bool refresh = false}) async {
    if (!isConfigured) {
      throw const ContributionException('not_configured', 'The list of what\'s missing isn\'t set up in this version.');
    }
    final at = _cachedAt;
    if (!refresh && _cached != null && at != null && DateTime.now().difference(at) < keepFor) return _cached!;
    final client = _client ?? http.Client();
    try {
      final res = await client.get(Uri.parse(_config.wantedUrl)).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) {
        throw ContributionException('server', 'Couldn\'t load the list (HTTP ${res.statusCode}).');
      }
      final list = parseWanted(jsonDecode(utf8.decode(res.bodyBytes)));
      _cached = list;
      _cachedAt = DateTime.now();
      return list;
    } on ContributionException {
      rethrow;
    } on TimeoutException {
      throw const ContributionException('network', 'Loading took too long. Check your connection.');
    } on FormatException {
      throw const ContributionException('server', 'The list couldn\'t be read.');
    } catch (_) {
      throw const ContributionException('network', 'Couldn\'t load the list. Check your connection.');
    } finally {
      if (_client == null) client.close();
    }
  }
}

/// The wanted document (see wanted.py) -> [WantedList]. Unknown field types read as text; broken entries are
/// skipped.
WantedList parseWanted(Object? json) {
  if (json is! Map) throw const FormatException('not an object');
  String? str(Object? v) => v == null || '$v'.trim().isEmpty ? null : '$v';
  final sheets = <String, WantedSheet>{};
  final rawSheets = json['sheets'];
  if (rawSheets is Map) {
    rawSheets.forEach((key, v) {
      if (v is! Map) return;
      final fields = <String, WantedField>{};
      final rawFields = v['fields'];
      if (rawFields is Map) {
        rawFields.forEach((name, f) {
          if (f is! Map) return;
          final type = WantedFieldType.values.firstWhere((t) => t.name == f['type'], orElse: () => WantedFieldType.text);
          fields['$name'] = WantedField(
            name: '$name',
            type: type,
            label: str(f['label']) ?? '$name',
            unit: str(f['unit']),
            hint: str(f['hint']),
            choices: [for (final c in (f['choices'] as List? ?? const [])) '$c'],
          );
        });
      }
      sheets['$key'] = WantedSheet(key: '$key', label: str(v['label']) ?? '$key', generation: str(v['generation']),
          fields: fields);
    });
  }
  final items = <WantedItem>[];
  for (final r in (json['items'] as List? ?? const [])) {
    if (r is! Map) continue;
    final sheet = str(r['sheet']), id = str(r['id']);
    final missing = [for (final m in (r['missing'] as List? ?? const [])) '$m'];
    if (sheet == null || id == null || missing.isEmpty) continue;
    items.add(WantedItem(
      sheet: sheet,
      id: id,
      name: str(r['name']) ?? id,
      code: str(r['code']) ?? '',
      variant: str(r['variant']),
      generation: str(r['generation']),
      hobby: str(r['hobby']),
      thumb: str(r['thumb']),
      missing: missing,
    ));
  }
  return WantedList(sheets: sheets, items: items, generatedAt: DateTime.tryParse('${json['generatedAt'] ?? ''}'));
}
