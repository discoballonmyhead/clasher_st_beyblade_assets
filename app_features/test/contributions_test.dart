// The contributions feature: the Apps Script client (incl. its 302 answer), the checks before sending, and the
// Settings -> Send pictures page end to end with fakes.
import 'dart:convert';
import 'dart:typed_data';

import 'package:clasher_st/features/contributions/data/apps_script_contributions_repository.dart';
import 'package:clasher_st/features/contributions/data/contributions_config.dart';
import 'package:clasher_st/features/contributions/domain/contributions_repository.dart';
import 'package:clasher_st/features/contributions/domain/entities.dart';
import 'package:clasher_st/features/contributions/domain/usecases.dart';
import 'package:clasher_st/features/contributions/presentation/cubit/contribute_cubit.dart';
import 'package:clasher_st/features/contributions/presentation/pages/contribute_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
final picture = PickedPicture(bytes: jpeg, mimeType: 'image/jpeg');
const kai = Contributor(username: 'kai', userId: 'u-1');
const dran = ContributionTarget(type: 'blades', id: '65', name: 'Dran Sword');

ContributionDraft draft({ContributionTarget target = dran, String? credit, String? note, bool consent = true,
        ContributionKind kind = ContributionKind.image, PickedPicture? pic}) =>
    ContributionDraft(kind: kind, target: target, picture: pic ?? picture, credit: credit, note: note,
        consent: consent);

class _Identity implements ContributorIdentity {
  _Identity(this.who);
  Contributor? who;
  @override
  Future<Contributor?> current() async => who;
}

class _Repo implements ContributionsRepository {
  final sent = <(ContributionDraft, Contributor)>[];
  bool configured = true;
  ContributionException? failWith;
  @override
  bool get isConfigured => configured;
  @override
  Future<ContributionReceipt> submit(ContributionDraft d, Contributor c) async {
    if (failWith != null) throw failWith!;
    sent.add((d, c));
    return const ContributionReceipt('sub-1');
  }
}

class _Search implements ContributionTargetSearch {
  @override
  Future<List<ContributionTarget>> search(String type, String query, {int limit = 30}) async => switch (type) {
        'parts' => query.isEmpty ? [] : [dran],
        'bladers' => [const ContributionTarget(type: 'bladers', id: 'BL1', name: 'Blader One')],
        _ => [],
      };
}

class _Picker implements ContributionPicturePicker {
  @override
  Future<PickedPicture?> pick({bool camera = false}) async => picture;
}

void main() {
  group('Apps Script client', () {
    const config = ContributionsConfig(endpoint: 'https://script.example/exec', submitKey: 'sk',
        appVersion: '1.2.0', platform: 'android');

    test('posts text/plain JSON and reads the answer behind the 302', () async {
      late Map<String, dynamic> body;
      final client = MockClient((req) async {
        if (req.method == 'POST') {
          expect(req.url.toString(), 'https://script.example/exec');
          expect(req.headers['Content-Type'], startsWith('text/plain'));
          body = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response('', 302, headers: {'location': 'https://echo.example/answer'});
        }
        expect(req.url.toString(), 'https://echo.example/answer');
        return http.Response(jsonEncode({'ok': true, 'id': 'abc'}), 200);
      });
      final repo = AppsScriptContributionsRepository(config, client: client);
      final r = await repo.submit(draft(credit: '  @kai_photos '), kai);
      expect(r.id, 'abc');
      expect(body['action'], 'submit');
      expect(body['submitKey'], 'sk');
      final s = body['submission'] as Map<String, dynamic>;
      expect(s['username'], 'kai');
      expect(s['userId'], 'u-1');
      expect(s['credit'], '@kai_photos');
      expect(s['targetType'], 'blades');
      expect(s['targetId'], '65');
      expect(s['kind'], 'image');
      expect(s['consent'], true);
      expect(s['appVersion'], '1.2.0');
      expect(base64Decode((s['image'] as Map)['base64'] as String), jpeg);
    });

    test('an empty credit sends the username', () async {
      late Map<String, dynamic> s;
      final client = MockClient((req) async {
        s = (jsonDecode(req.body) as Map)['submission'] as Map<String, dynamic>;
        return http.Response(jsonEncode({'ok': true, 'id': 'x'}), 200);
      });
      await AppsScriptContributionsRepository(config, client: client).submit(draft(credit: ''), kai);
      expect(s['credit'], 'kai');
    });

    test('server refusals and network trouble become readable errors', () async {
      Future<ContributionException> err(MockClient c) async {
        try {
          await AppsScriptContributionsRepository(config, client: c).submit(draft(), kai);
        } on ContributionException catch (e) {
          return e;
        }
        fail('no error');
      }

      final limited = await err(MockClient((_) async => http.Response(
          jsonEncode({'ok': false, 'code': 'rate_limited', 'error': 'Try again in an hour.'}), 200)));
      expect(limited.code, 'rate_limited');
      expect(limited.message, 'Try again in an hour.');

      final html = await err(MockClient((_) async => http.Response('<html>Sign in</html>', 200)));
      expect(html.code, 'server');

      final offline = await err(MockClient((_) async => throw http.ClientException('offline')));
      expect(offline.code, 'network');
    });

    test('not configured without an https endpoint', () {
      expect(AppsScriptContributionsRepository(const ContributionsConfig(endpoint: '')).isConfigured, isFalse);
    });
  });

  group('checks before sending', () {
    test('signed out, no consent, no target, wrong kind and non-pictures are refused', () async {
      final repo = _Repo();
      final id = _Identity(null);
      final submit = SubmitContributionUseCase(repo, id);
      Future<String?> code(ContributionDraft d) async {
        try {
          await submit(d);
          return null;
        } on ContributionException catch (e) {
          return e.code;
        }
      }

      expect(await code(draft()), 'signed_out');
      id.who = kai;
      expect(await code(draft(consent: false)), 'invalid');
      expect(await code(draft(target: const ContributionTarget(type: 'blades', id: '', name: ''))), 'invalid');
      expect(await code(draft(target: const ContributionTarget.other())), 'invalid', reason: 'other needs a note');
      expect(await code(draft(kind: ContributionKind.fullBodyImage)), 'invalid');
      expect(await code(draft(pic: PickedPicture(bytes: Uint8List.fromList([1, 2, 3, 4]), mimeType: 'image/jpeg'))),
          'invalid');
      expect(await code(draft(pic: PickedPicture(bytes: Uint8List(6 * 1024 * 1024 + 1), mimeType: 'image/jpeg'))),
          'too_large');
      expect(await code(draft(target: const ContributionTarget.other(), note: 'a stadium')), isNull);
      expect(await code(draft()), isNull);
      expect(repo.sent.length, 2);
      repo.configured = false;
      expect(await code(draft()), 'not_configured');
    });

    test('sniffImageMime knows JPEG, PNG and WebP', () {
      expect(sniffImageMime(jpeg), 'image/jpeg');
      expect(sniffImageMime(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0])), 'image/png');
      expect(sniffImageMime(Uint8List.fromList(utf8.encode('RIFF....WEBPVP8 '))), 'image/webp');
      expect(sniffImageMime(Uint8List.fromList(utf8.encode('GIF89a'))), isNull);
    });
  });

  group('Send pictures page', () {
    Future<(_Repo, _Identity)> open(WidgetTester tester, {Contributor? who = kai, bool configured = true}) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = _Repo()..configured = configured;
      final id = _Identity(who);
      await tester.pumpWidget(MaterialApp(
        home: BlocProvider(
          create: (_) => ContributeCubit(
            submit: SubmitContributionUseCase(repo, id),
            search: _Search(),
            picker: _Picker(),
          )..start(),
          child: const ContributePage(),
        ),
      ));
      await tester.pumpAndSettle();
      return (repo, id);
    }

    testWidgets('pick a part, a picture, a credit, consent, send', (tester) async {
      final (repo, _) = await open(tester);
      expect(find.text('Sending as kai'), findsOneWidget);
      FilledButton send() => tester.widget<FilledButton>(find.byKey(const ValueKey('contribute-send')));
      expect(send().onPressed, isNull);

      await tester.enterText(find.byKey(const ValueKey('contribute-search')), 'dran');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dran Sword'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('contribute-target')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('contribute-gallery')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('contribute-credit')), '@kai_photos');
      expect(send().onPressed, isNull, reason: 'consent first');
      await tester.tap(find.byKey(const ValueKey('contribute-consent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('contribute-send')));
      await tester.pumpAndSettle();

      final (d, who) = repo.sent.single;
      expect(who.username, 'kai');
      expect(d.target, dran);
      expect(d.credit, '@kai_photos');
      expect(d.kind, ContributionKind.image);
      expect(find.text('Thanks!'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('contribute-another')));
      await tester.pumpAndSettle();
      expect(find.text('Sending as kai'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const ValueKey('contribute-send'))).onPressed, isNull,
          reason: 'a new picture and consent are needed again');
    });

    testWidgets('a blader can get a full-body picture', (tester) async {
      final (repo, _) = await open(tester);
      await tester.tap(find.text('Blader'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blader One'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Full body'));
      await tester.tap(find.byKey(const ValueKey('contribute-gallery')));
      await tester.tap(find.byKey(const ValueKey('contribute-consent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('contribute-send')));
      await tester.pumpAndSettle();
      expect(repo.sent.single.$1.kind, ContributionKind.fullBodyImage);
      expect(repo.sent.single.$1.target.id, 'BL1');
    });

    testWidgets('signed out or not set up: says so instead of the form', (tester) async {
      await open(tester, who: null);
      expect(find.textContaining('Sign in to send pictures'), findsOneWidget);
      expect(find.byKey(const ValueKey('contribute-send')), findsNothing);
    });

    testWidgets('a refusal from the server shows its message and keeps the form', (tester) async {
      final (repo, _) = await open(tester);
      repo.failWith = const ContributionException('rate_limited', 'Try again in an hour.');
      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('contribute-note')), 'Xtreme Stadium, blue');
      await tester.tap(find.byKey(const ValueKey('contribute-gallery')));
      await tester.tap(find.byKey(const ValueKey('contribute-consent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('contribute-send')));
      await tester.pumpAndSettle();
      expect(find.text('Try again in an hour.'), findsOneWidget);
      expect(find.byKey(const ValueKey('contribute-send')), findsOneWidget);
    });
  });
}
