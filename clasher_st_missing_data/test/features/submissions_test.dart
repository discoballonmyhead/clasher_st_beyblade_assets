import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:missing_data_app/app.dart';
import 'package:missing_data_app/core/di/service_locator.dart';
import 'package:missing_data_app/core/error/failure.dart';
import 'package:missing_data_app/core/settings/app_settings.dart';
import 'package:missing_data_app/features/submissions/data/apps_script_submissions_repository.dart';
import 'package:missing_data_app/features/submissions/domain/submission.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repository.dart';
import '../support/fake_studio_repository.dart';

final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

Submission sub(String id, {String type = 'blades', String target = '203', String kind = 'image',
        String credit = '@kai_photos', String username = 'kai', String note = '', String field = '',
        String value = ''}) =>
    Submission(id: id, submittedAt: DateTime(2026, 11, 16), status: 'new', kind: kind, targetType: type,
        targetId: target, targetName: 'Hells Scythe', username: username, credit: credit, note: note,
        field: field, value: value, batch: field.isEmpty ? '' : 'b1');

class _Subs implements SubmissionsRepository {
  _Subs(this.items);
  List<Submission> items;
  final statuses = <String, String>{};
  final imagesAsked = <String>[];
  @override
  bool get isConfigured => true;
  @override
  Future<Result<List<Submission>>> list({String status = 'new'}) async =>
      Ok([for (final s in items) if (!statuses.containsKey(s.id)) s]);
  @override
  Future<Result<Uint8List>> image(String id) async {
    imagesAsked.add(id);
    return Ok(png);
  }
  @override
  Future<Result<void>> setStatus(String id, String status, {String note = ''}) async {
    statuses[id] = status;
    return const Ok(null);
  }
}

void main() {
  test('credits are merged once, keeping what was there', () {
    expect(mergeCredits(null, '@kai'), '@kai');
    expect(mergeCredits('Wiki', '@kai'), 'Wiki; @kai');
    expect(mergeCredits('Wiki; @KAI', '@kai'), 'Wiki; @KAI');
    expect(mergeCredits(' a ;; b ', ''), 'a; b');
  });

  group('web app client', () {
    late AppSettings settings;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = AppSettings(await SharedPreferences.getInstance());
      await settings.setPublishing(const PublishingConstants(
          submissionsUrl: 'https://script.example/exec', submissionsAdminKey: 'admin'));
    });

    test('list, picture and status with the admin key, through the 302', () async {
      final calls = <Map<String, dynamic>>[];
      final client = MockClient((req) async {
        if (req.method == 'POST') {
          final b = jsonDecode(req.body) as Map<String, dynamic>;
          calls.add(b);
          expect(b['adminKey'], 'admin');
          return http.Response('', 302, headers: {'location': 'https://echo.example/${b['action']}'});
        }
        return switch (req.url.path) {
          '/list' => http.Response(jsonEncode({'ok': true, 'items': [
              {'id': 'a', 'submittedAt': '2026-11-16T10:00:00Z', 'status': 'new', 'kind': 'fullBodyImage',
                'targetType': 'bladers', 'targetId': 'BL1', 'targetName': 'Blader One', 'username': 'kai',
                'credit': '@kai_photos', 'note': '', 'mimeType': 'image/png', 'bytes': 8},
              {'id': 'v', 'submittedAt': '2026-11-16T10:00:00Z', 'status': 'new', 'kind': 'value',
                'targetType': 'blades', 'targetId': '203', 'targetName': 'Hells Scythe', 'username': 'kai',
                'credit': 'kai', 'field': 'mass', 'value': '35.2', 'batch': 'b1'},
            ]}), 200),
          '/image' => http.Response(jsonEncode({'ok': true, 'mimeType': 'image/png', 'base64': base64Encode(png)}), 200),
          _ => http.Response(jsonEncode({'ok': true}), 200),
        };
      });
      final repo = AppsScriptSubmissionsRepository(settings, client: client);
      final items = (await repo.list()).valueOrNull!;
      expect(items.first.pictureField, 'fullBodyImage');
      expect(items.first.creditText, '@kai_photos');
      expect(items.first.isValue, isFalse);
      expect(items.last.isValue, isTrue);
      expect((items.last.field, items.last.value, items.last.batch), ('mass', '35.2', 'b1'));
      expect((await repo.image('a')).valueOrNull, png);
      expect(await repo.setStatus('a', 'applied', note: 'Bladers #BL1'), isA<Ok<void>>());
      expect(calls.map((c) => c['action']), ['list', 'image', 'setStatus']);
      expect(calls.last['status'], 'applied');
    });

    test('a refusal or a non-JSON page becomes a readable failure', () async {
      final denied = AppsScriptSubmissionsRepository(settings,
          client: MockClient((_) async => http.Response(jsonEncode({'ok': false, 'error': 'Wrong admin key.'}), 200)));
      expect((await denied.list()).fold((f) => f.message, (_) => ''), 'Wrong admin key.');
      final html = AppsScriptSubmissionsRepository(settings,
          client: MockClient((_) async => http.Response('<html>Google sign in</html>', 200)));
      expect((await html.list()).fold((f) => f.message, (_) => ''), contains('/exec'));
    });

    test('not configured without URL and key', () async {
      await settings.setPublishing(const PublishingConstants());
      expect(AppsScriptSubmissionsRepository(settings).isConfigured, isFalse);
    });
  });

  testWidgets('Data -> Submissions: apply puts the picture and the credit on the row; reject marks it',
      (tester) async {
    await sl.reset();
    SharedPreferences.setMockInitialValues({});
    final repo = FakeRepository();
    final subs = _Subs([
      sub('s1'),
      sub('s2', target: '65', credit: '', username: 'ren'),
      sub('s3', type: 'products', target: 'P1'),
    ]);
    await initDependencies(prefs: await SharedPreferences.getInstance(), repository: repo,
        studioRepository: FakeStudioRepository(), submissionsRepository: subs);
    tester.view.physicalSize = const Size(1700, 1160);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MissingDataApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '/tmp/beyblade_parts.xlsx');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 5 && find.text('Not now').evaluate().isNotEmpty; i++) {
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byTooltip('Submissions (sent from the app)'));
    await tester.pumpAndSettle();
    expect(find.text('Submissions (3 new)'), findsOneWidget);
    // a products picture can't go into the parts workbook
    expect(tester.widget<FilledButton>(find.byKey(const ValueKey('apply-s3'))).onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('apply-s1')));
    await tester.pumpAndSettle();
    expect(repo.imagesPut, [('203', null)]);
    expect(repo.rowsData['203']!['credits'], '@kai_photos');
    expect(subs.statuses['s1'], 'applied');
    expect(find.byKey(const ValueKey('submission-s1')), findsNothing);

    // no credit given: the username is credited
    await tester.tap(find.byKey(const ValueKey('apply-s2')));
    await tester.pumpAndSettle();
    expect(repo.rowsData['65']!['credits'], 'ren');

    await tester.tap(find.byKey(const ValueKey('reject-s3')));
    await tester.pumpAndSettle();
    expect(subs.statuses['s3'], 'rejected');
    expect(find.text('Nothing new.'), findsOneWidget);
  });

  testWidgets('Data -> Submissions: a typed-in value goes into its column, with the credit', (tester) async {
    await sl.reset();
    SharedPreferences.setMockInitialValues({});
    final repo = FakeRepository();
    final subs = _Subs([
      sub('v1', kind: 'value', field: 'mass', value: '35.2', credit: '', username: 'ren'),
      sub('v2', kind: 'value', target: '65', field: 'mass', value: '36'),
    ]);
    await initDependencies(prefs: await SharedPreferences.getInstance(), repository: repo,
        studioRepository: FakeStudioRepository(), submissionsRepository: subs);
    tester.view.physicalSize = const Size(1700, 1160);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MissingDataApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '/tmp/beyblade_parts.xlsx');
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 5 && find.text('Not now').evaluate().isNotEmpty; i++) {
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byTooltip('Submissions (sent from the app)'));
    await tester.pumpAndSettle();
    expect(find.text('Submissions (2 new)'), findsOneWidget);
    expect(find.byKey(const ValueKey('value-v1')), findsOneWidget);
    expect(subs.imagesAsked, isEmpty, reason: 'values have no picture to download');

    await tester.tap(find.byKey(const ValueKey('apply-v1')));
    await tester.pumpAndSettle();
    expect(repo.rowsData['203']!['mass'], '35.2');
    expect(repo.rowsData['203']!['credits'], 'ren');
    expect(repo.imagesPut, isEmpty);
    expect(subs.statuses['v1'], 'applied');

    // a filled-in value is replaced, and the message says what it was
    await tester.tap(find.byKey(const ValueKey('apply-v2')));
    await tester.pumpAndSettle();
    expect(repo.rowsData['65']!['mass'], '36');
    await tester.pump(const Duration(seconds: 7)); // the first message's snack bar goes away
    await tester.pumpAndSettle();
    expect(find.textContaining('it was "34.6"'), findsOneWidget);
    expect(find.text('Nothing new.'), findsOneWidget);
  });
}
