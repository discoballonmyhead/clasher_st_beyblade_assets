import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/error/failure.dart';
import '../../../core/settings/app_settings.dart';
import '../domain/submission.dart';

/// Talks to submissions/Code.gs with the admin key (Settings -> Publishing). Requests are POSTs with a JSON
/// body; Apps Script answers a POST with a 302 to the JSON, which is fetched with a GET.
class AppsScriptSubmissionsRepository implements SubmissionsRepository {
  AppsScriptSubmissionsRepository(this._settings, {http.Client? client}) : _client = client;

  final AppSettings _settings;
  final http.Client? _client;

  static const _timeout = Duration(seconds: 60);

  PublishingConstants get _pub => _settings.publishing;

  @override
  bool get isConfigured => _pub.hasSubmissions;

  Future<Map<String, dynamic>> _call(Map<String, Object?> body) async {
    if (!isConfigured) {
      throw const _Problem('Set the submissions web app URL and admin key in Settings -> Publishing.');
    }
    final client = _client ?? http.Client();
    try {
      final req = http.Request('POST', Uri.parse(_pub.submissionsUrl))
        ..followRedirects = false
        ..headers['Content-Type'] = 'text/plain;charset=utf-8'
        ..body = jsonEncode({...body, 'adminKey': _pub.submissionsAdminKey});
      var res = await http.Response.fromStream(await client.send(req).timeout(_timeout));
      if (res.statusCode == 301 || res.statusCode == 302 || res.statusCode == 303) {
        final loc = res.headers['location'];
        if (loc == null) throw const _Problem('The web app didn\'t answer.');
        res = await client.get(Uri.parse(loc)).timeout(_timeout);
      }
      final Map<String, dynamic> j;
      try {
        j = Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
      } catch (_) {
        throw _Problem('The web app gave an unexpected answer (HTTP ${res.statusCode}). Check the URL is the '
            'deployment\'s /exec link and that it\'s deployed for "Anyone".');
      }
      if (j['ok'] != true) throw _Problem('${j['error'] ?? 'The web app refused the request.'}');
      return j;
    } on TimeoutException {
      throw const _Problem('The web app took too long to answer.');
    } on http.ClientException catch (e) {
      throw _Problem('Couldn\'t reach the web app: ${e.message}');
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<Result<T>> _guard<T>(Future<T> Function() run) async {
    try {
      return Ok(await run());
    } on _Problem catch (p) {
      return Err(Failure(p.message));
    } catch (e) {
      return Err(Failure('$e'));
    }
  }

  @override
  Future<Result<List<Submission>>> list({String status = 'new'}) => _guard(() async {
        final j = await _call({'action': 'list', 'status': status});
        return [
          for (final r in (j['items'] as List? ?? const []))
            if (r is Map) _submission(Map<String, dynamic>.from(r)),
        ];
      });

  @override
  Future<Result<Uint8List>> image(String id) => _guard(() async {
        final j = await _call({'action': 'image', 'id': id});
        return base64Decode('${j['base64'] ?? ''}');
      });

  @override
  Future<Result<void>> setStatus(String id, String status, {String note = ''}) =>
      _guard(() => _call({'action': 'setStatus', 'id': id, 'status': status, 'note': note}));

  static Submission _submission(Map<String, dynamic> r) {
    String s(String k) => r[k] == null ? '' : '${r[k]}';
    return Submission(
      id: s('id'),
      submittedAt: DateTime.tryParse(s('submittedAt')),
      status: s('status'),
      kind: s('kind'),
      targetType: s('targetType'),
      targetId: s('targetId'),
      targetName: s('targetName'),
      username: s('username'),
      credit: s('credit'),
      note: s('note'),
      mimeType: s('mimeType'),
      bytes: int.tryParse(s('bytes')) ?? 0,
      platform: s('platform'),
      appVersion: s('appVersion'),
    );
  }
}

class _Problem implements Exception {
  const _Problem(this.message);
  final String message;
}
