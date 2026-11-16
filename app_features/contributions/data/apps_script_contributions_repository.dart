import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;

import 'package:clasher_st/features/contributions/data/contributions_config.dart';
import 'package:clasher_st/features/contributions/domain/contributions_repository.dart';
import 'package:clasher_st/features/contributions/domain/entities.dart';
import 'package:http/http.dart' as http;

/// Posts submissions to the Apps Script web app.
///
/// Two Apps Script habits handled here:
/// * the body is JSON sent as text/plain (no CORS preflight on web, which Apps Script can't answer);
/// * the script runs on the POST, then answers with a 302 to a googleusercontent URL that holds the JSON.
///   dart:io doesn't follow redirects for a POST, so the answer is fetched with a GET (browsers follow it
///   themselves).
class AppsScriptContributionsRepository implements ContributionsRepository {
  AppsScriptContributionsRepository(this._config, {http.Client? client}) : _client = client;

  final ContributionsConfig _config;
  final http.Client? _client;

  static const _timeout = Duration(seconds: 60);
  static const _logName = '[Contributions]';

  @override
  bool get isConfigured => _config.isConfigured;

  @override
  Future<ContributionReceipt> submit(ContributionDraft d, Contributor who) async {
    if (!isConfigured) {
      throw const ContributionException('not_configured', 'Sending pictures isn\'t set up in this version.');
    }
    final credit = (d.credit ?? '').trim();
    final body = jsonEncode({
      'action': 'submit',
      if (_config.submitKey.isNotEmpty) 'submitKey': _config.submitKey,
      'submission': {
        'kind': d.kind.wire,
        'targetType': d.target.type,
        'targetId': d.target.id,
        'targetName': d.target.name,
        'username': who.username,
        'userId': who.userId,
        'credit': credit.isEmpty ? who.username : credit,
        'note': d.note?.trim(),
        'consent': d.consent,
        'appVersion': _config.appVersion,
        'platform': _config.platform,
        'image': {'mimeType': d.picture.mimeType, 'base64': base64Encode(d.picture.bytes)},
      },
    });

    final client = _client ?? http.Client();
    try {
      final req = http.Request('POST', Uri.parse(_config.endpoint))
        ..followRedirects = false
        ..headers['Content-Type'] = 'text/plain;charset=utf-8'
        ..body = body;
      var res = await http.Response.fromStream(await client.send(req).timeout(_timeout));
      if (res.isRedirect || res.statusCode == 302 || res.statusCode == 303) {
        final location = res.headers['location'];
        if (location == null) throw const ContributionException('server', 'The server didn\'t answer.');
        res = await client.get(Uri.parse(location)).timeout(_timeout);
      }
      return _receipt(res);
    } on ContributionException {
      rethrow;
    } on TimeoutException {
      throw const ContributionException('network', 'Sending took too long. Check your connection and try again.');
    } catch (e) {
      dev.log('submit failed: $e', name: _logName);
      throw const ContributionException('network', 'Couldn\'t reach the server. Check your connection and try again.');
    } finally {
      if (_client == null) client.close();
    }
  }

  ContributionReceipt _receipt(http.Response res) {
    Map<String, dynamic> j;
    try {
      j = Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
    } catch (_) {
      dev.log('unexpected answer (HTTP ${res.statusCode}): ${res.body.length > 200 ? res.body.substring(0, 200) : res.body}',
          name: _logName);
      throw const ContributionException('server', 'The server gave an unexpected answer. Try again later.');
    }
    if (j['ok'] == true && j['id'] is String) return ContributionReceipt(j['id'] as String);
    throw ContributionException(
      '${j['code'] ?? 'server'}',
      '${j['error'] ?? 'The picture wasn\'t accepted.'}',
    );
  }
}
