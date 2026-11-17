// "Help complete the catalog": the packager's real wanted list (test/fixtures/_wanted.json, made from
// samples/*.xlsx), the list filters, the per-entry form (typed checks, values + picture sent together) and
// what the Apps Script client sends.
// Copy into the app's test/ folder (with fixtures/) and run `flutter test test/missing_data_test.dart`.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clasher_st/features/contributions/data/apps_script_contributions_repository.dart';
import 'package:clasher_st/features/contributions/data/contributions_config.dart';
import 'package:clasher_st/features/contributions/data/http_wanted_source.dart';
import 'package:clasher_st/features/contributions/data/wanted_target_search.dart';
import 'package:clasher_st/features/contributions/domain/contributions_repository.dart';
import 'package:clasher_st/features/contributions/domain/entities.dart';
import 'package:clasher_st/features/contributions/domain/usecases.dart';
import 'package:clasher_st/features/contributions/presentation/cubit/missing_cubits.dart';
import 'package:clasher_st/features/contributions/presentation/pages/fill_missing_page.dart';
import 'package:clasher_st/features/contributions/presentation/pages/missing_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
final picture = PickedPicture(bytes: jpeg, mimeType: 'image/jpeg');
const kai = Contributor(username: 'kai', userId: 'u-1');
final wantedJson = File('test/fixtures/_wanted.json').readAsStringSync();

class _Identity implements ContributorIdentity {
  _Identity(this.who);
  Contributor? who;
  @override
  Future<Contributor?> current() async => who;
}

class _Repo implements ContributionsRepository {
  final sent = <(ContributionDraft, Contributor)>[];
  ContributionException? failWith;
  @override
  bool get isConfigured => true;
  @override
  Future<ContributionReceipt> submit(ContributionDraft d, Contributor c) async {
    if (failWith != null) throw failWith!;
    sent.add((d, c));
    return const ContributionReceipt('sub-1');
  }
}

class _Picker implements ContributionPicturePicker {
  @override
  Future<PickedPicture?> pick({bool camera = false}) async => picture;
}

class _Source implements WantedSource {
  _Source({this.configured = true, this.fail});
  final bool configured;
  ContributionException? fail;
  int loads = 0;
  @override
  bool get isConfigured => configured;
  @override
  Future<WantedList> load({bool refresh = false}) async {
    loads++;
    if (fail != null) throw fail!;
    return parseWanted(jsonDecode(wantedJson));
  }
}

class _AllSearch implements ContributionTargetSearch {
  int calls = 0;
  @override
  Future<List<ContributionTarget>> search(String type, String query, {int limit = 30}) async {
    calls++;
    return [const ContributionTarget(type: 'blades', id: '65', name: 'Dran Sword')];
  }
}

void main() {
  group('"Send something else" search shows only what\'s missing', () {
    test('parts, boxes, bladers and accessories with gaps, and what each lacks', () async {
      final all = _AllSearch();
      final s = WantedTargetSearch(_Source(), all);
      final parts = await s.search('parts', '');
      expect(parts.map((t) => (t.type, t.id)), [('ratchets', '13')], reason: 'cards and boxes aren\'t parts');
      expect(parts.single.missing, ['Picture']);
      expect(parts.single.name, '0-80 · G3063');
      final boxes = await s.search('products', 'bx-50');
      expect(boxes.map((t) => t.id), ['P3', 'P4']);
      expect(boxes.last.missing, ['Release date', 'Item cost', 'Picture']);
      expect((await s.search('bladers', '')).single.missing, ['Picture', 'Full-body picture']);
      expect(await s.search('products', 'dran sword 3-60f starter'), isEmpty, reason: 'the name doesn\'t match');
      expect(all.calls, 0, reason: 'never the whole catalog while the list is there');
    });

    test('the whole catalog only when the list isn\'t set up or can\'t load', () async {
      final all = _AllSearch();
      expect(await WantedTargetSearch(_Source(configured: false), all).search('parts', 'dran'), hasLength(1));
      final failing = _Source(fail: const ContributionException('network', 'Offline.'));
      expect(await WantedTargetSearch(failing, all).search('parts', 'dran'), hasLength(1));
      expect(all.calls, 2);
    });
  });

  group('the wanted list', () {
    test('parses the packager\'s real output', () {
      final l = parseWanted(jsonDecode(wantedJson));
      expect(l.items, hasLength(14));
      expect(l.sheets.keys, containsAll(['products', 'bladers', 'tcgCards', 'tcgSets']));
      final p2 = l.items.firstWhere((i) => i.sheet == 'products' && i.id == 'P2');
      expect(p2.missing, ['releaseDate', 'itemCost', 'image']);
      expect(p2.target, const ContributionTarget(type: 'products', id: 'P2', name: 'Xtreme Stadium'));
      expect(l.field('products', 'releaseDate')!.type, WantedFieldType.date);
      expect(l.field('products', 'itemCost')!.type, WantedFieldType.number);
      expect(l.field('bladers', 'fullBodyImage')!.isPicture, isTrue);
      expect(l.items.firstWhere((i) => i.id == 'P4').variant, '06');
      expect(l.generatedAt, isNotNull);
    });

    test('broken entries are skipped and unknown types read as text', () {
      final l = parseWanted({
        'sheets': {
          'blades': {
            'label': 'Blades',
            'fields': {'weight': {'type': 'mystery'}}
          }
        },
        'items': [
          {'sheet': 'blades', 'id': '1', 'name': 'A', 'missing': ['weight']},
          {'sheet': 'blades', 'name': 'no id', 'missing': ['weight']},
          {'sheet': 'blades', 'id': '3', 'missing': []},
          'junk',
        ],
      });
      expect(l.items.single.id, '1');
      expect(l.field('blades', 'weight')!.type, WantedFieldType.text);
      expect(() => parseWanted([1, 2]), throwsFormatException);
    });

    test('field checks by type', () {
      const n = WantedField(name: 'weight', type: WantedFieldType.number, label: 'Weight');
      expect(n.check(''), isNull);
      expect(n.check('34,6'), isNull);
      expect(n.check('heavy'), isNotNull);
      expect(n.check('-1'), isNotNull);
      const d = WantedField(name: 'releaseDate', type: WantedFieldType.date, label: 'Release date');
      expect(d.check('2024-07-15'), isNull);
      expect(d.check('15/07/2024'), isNotNull);
      const c = WantedField(name: 'spin', type: WantedFieldType.choice, label: 'Spin', choices: ['Right', 'Left']);
      expect(c.check('Left'), isNull);
      expect(c.check('Up'), isNotNull);
      const t = WantedField(name: 'subtitle', type: WantedFieldType.text, label: 'Subtitle');
      expect(t.check('x' * 301), isNotNull);
    });

    test('the HTTP source downloads once, then keeps the list until a refresh', () async {
      var calls = 0;
      final client = MockClient((req) async {
        calls++;
        expect(req.url.toString(), 'https://cdn.example/data/_wanted.json');
        return http.Response.bytes(utf8.encode(wantedJson), 200);
      });
      final src = HttpWantedSource(
        const ContributionsConfig(endpoint: '', wantedUrl: 'https://cdn.example/data/_wanted.json'),
        client: client,
      );
      expect(src.isConfigured, isTrue);
      expect((await src.load()).items, hasLength(14));
      await src.load();
      expect(calls, 1);
      await src.load(refresh: true);
      expect(calls, 2);
    });

    test('the HTTP source turns trouble into readable errors', () async {
      Future<String> code(http.Response r) async {
        final src = HttpWantedSource(
          const ContributionsConfig(endpoint: '', wantedUrl: 'https://cdn.example/w.json'),
          client: MockClient((_) async => r),
        );
        try {
          await src.load();
          return 'ok';
        } on ContributionException catch (e) {
          return e.code;
        }
      }

      expect(await code(http.Response('nope', 404)), 'server');
      expect(await code(http.Response('<html>', 200)), 'server');
      expect(HttpWantedSource(const ContributionsConfig(endpoint: '')).isConfigured, isFalse);
      expect(HttpWantedSource(const ContributionsConfig(endpoint: '', wantedUrl: 'http://cdn.example/w.json'))
          .isConfigured, isFalse);
    });
  });

  group('list filters', () {
    test('by sheet, by pictures / details, and by search', () async {
      final c = MissingListCubit(_Source());
      await c.load();
      expect(c.state.visible, hasLength(14));
      expect(c.state.sheetsWithCounts.map((e) => (e.$1.key, e.$2)),
          contains(('products', 5)));

      c.setSheet('bladers');
      expect(c.state.visible.single.id, 'BL2');
      c.setGap(GapKind.details);
      expect(c.state.visible, isEmpty, reason: 'the blader only lacks pictures');
      c.setSheet(null);
      expect(c.state.visible.every((i) => i.sheet != 'bladers' && i.sheet != 'ratchets'), isTrue);
      c.setGap(GapKind.pictures);
      expect(c.state.visible, hasLength(14));

      c.setGap(GapKind.all);
      c.setQuery('bx-50');
      expect(c.state.visible.map((i) => i.id), ['P3', 'P4']);
      c.setQuery('parallel');
      expect(c.state.visible.single.variant, 'Parallel Foil');
    });

    test('not set up or failing: says so', () async {
      final off = MissingListCubit(_Source(configured: false));
      await off.load();
      expect(off.state.configured, isFalse);
      final failing = MissingListCubit(_Source(fail: const ContributionException('network', 'Offline.')));
      await failing.load();
      expect(failing.state.list, isNull);
      expect(failing.state.error, 'Offline.');
    });
  });

  group('one entry', () {
    late WantedList list;
    setUp(() => list = parseWanted(jsonDecode(wantedJson)));

    FillMissingCubit cubitFor(String sheet, String id, _Repo repo, {Contributor? who = kai}) => FillMissingCubit(
          item: list.items.firstWhere((i) => i.sheet == sheet && i.id == id),
          sheet: list.sheets[sheet],
          submit: SubmitContributionUseCase(repo, _Identity(who)),
          picker: _Picker(),
        );

    test('values alone, cleaned, without a picture', () async {
      final repo = _Repo();
      final c = cubitFor('products', 'P2', repo);
      await c.start();
      expect(c.detailFields.map((f) => f.name), ['releaseDate', 'itemCost']);
      expect(c.pictureFields.map((f) => f.name), ['image']);
      c.setValue('itemCost', ' 15,99 ');
      c.setConsent(true);
      expect(c.canSubmit, isTrue);
      c.setValue('releaseDate', 'July');
      expect(c.canSubmit, isFalse, reason: 'a bad date blocks sending');
      c.setValue('releaseDate', '2023-07-15');
      await c.send();
      final (d, who) = repo.sent.single;
      expect(who, kai);
      expect(d.picture, isNull);
      expect(d.values, {'releaseDate': '2023-07-15', 'itemCost': '15.99'});
      expect(d.target.type, 'products');
      expect(c.state.receipt, isNotNull);
    });

    test('a blader\'s full-body picture goes as fullBodyImage', () async {
      final repo = _Repo();
      final c = cubitFor('bladers', 'BL2', repo);
      await c.start();
      expect(c.state.pictureField, 'image');
      c.setPictureField('fullBodyImage');
      await c.pickPicture();
      c.setConsent(true);
      await c.send();
      expect(repo.sent.single.$1.kind, ContributionKind.fullBodyImage);
      expect(repo.sent.single.$1.values, isEmpty);
    });

    test('nothing filled in, no consent, or signed out: can\'t send', () async {
      final c = cubitFor('products', 'P2', _Repo());
      await c.start();
      c.setConsent(true);
      expect(c.canSubmit, isFalse);
      c.setValue('itemCost', '3');
      c.setConsent(false);
      expect(c.canSubmit, isFalse);
      final out = cubitFor('products', 'P2', _Repo(), who: null);
      await out.start();
      out
        ..setValue('itemCost', '3')
        ..setConsent(true);
      expect(out.canSubmit, isFalse);
    });
  });

  group('Apps Script client', () {
    test('sends values, and the picture only when there is one', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = MockClient((req) async {
        bodies.add((jsonDecode(req.body) as Map<String, dynamic>)['submission'] as Map<String, dynamic>);
        return http.Response(jsonEncode({'ok': true, 'id': 'x', 'batch': 'b'}), 200);
      });
      final repo = AppsScriptContributionsRepository(
          const ContributionsConfig(endpoint: 'https://script.example/exec'), client: client);
      const target = ContributionTarget(type: 'products', id: 'P2', name: 'Xtreme Stadium');
      await repo.submit(
        const ContributionDraft(kind: ContributionKind.image, target: target,
            values: {'itemCost': '15.99', 'releaseDate': ' '}, consent: true),
        kai,
      );
      expect(bodies.last['values'], {'itemCost': '15.99'});
      expect(bodies.last.containsKey('image'), isFalse);
      await repo.submit(
        ContributionDraft(kind: ContributionKind.image, target: target, picture: picture,
            values: const {'itemCost': '15.99'}, consent: true),
        kai,
      );
      expect(bodies.last['image']['mimeType'], 'image/jpeg');
      expect(bodies.last['values'], {'itemCost': '15.99'});
    });
  });

  group('pages', () {
    void bigScreen(WidgetTester tester) {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('the list shows entries and filters them', (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(MaterialApp(
        home: BlocProvider(create: (_) => MissingListCubit(_Source())..load(), child: const MissingListPage()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Help complete the catalog'), findsOneWidget);
      expect(find.textContaining('14 catalog entries'), findsOneWidget);
      expect(find.byKey(const ValueKey('missing-products-P2')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('missing-sheet-bladers')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('missing-bladers-BL2')), findsOneWidget);
      expect(find.byKey(const ValueKey('missing-products-P2')), findsNothing);
      expect(find.textContaining('Missing: Picture, Full-body picture'), findsOneWidget);
    });

    testWidgets('the list explains when it isn\'t set up', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: BlocProvider(
            create: (_) => MissingListCubit(_Source(configured: false))..load(), child: const MissingListPage()),
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('isn\'t set up'), findsOneWidget);
      expect(find.byKey(const ValueKey('missing-send-other')), findsOneWidget);
    });

    testWidgets('fill in a date and a price, add a picture, send', (tester) async {
      bigScreen(tester);
      final list = parseWanted(jsonDecode(wantedJson));
      final repo = _Repo();
      await tester.pumpWidget(MaterialApp(
        home: BlocProvider(
          create: (_) => FillMissingCubit(
            item: list.items.firstWhere((i) => i.id == 'P2'),
            sheet: list.sheets['products'],
            submit: SubmitContributionUseCase(repo, _Identity(kai)),
            picker: _Picker(),
          )..start(),
          child: const FillMissingPage(),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Sending as kai'), findsOneWidget);
      FilledButton send() => tester.widget<FilledButton>(find.byKey(const ValueKey('fill-send')));

      await tester.enterText(find.byKey(const ValueKey('fill-field-releaseDate')), '15-07-2023');
      await tester.pumpAndSettle();
      expect(find.text('A date like 2024-07-15'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('fill-field-releaseDate')), '2023-07-15');
      await tester.enterText(find.byKey(const ValueKey('fill-field-itemCost')), '15.99');
      await tester.tap(find.byKey(const ValueKey('fill-gallery')));
      await tester.enterText(find.byKey(const ValueKey('fill-credit')), '@kai_photos');
      await tester.pumpAndSettle();
      expect(send().onPressed, isNull, reason: 'consent first');
      await tester.tap(find.byKey(const ValueKey('fill-consent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fill-send')));
      await tester.pumpAndSettle();

      final (d, _) = repo.sent.single;
      expect(d.values, {'releaseDate': '2023-07-15', 'itemCost': '15.99'});
      expect(d.picture, picture);
      expect(d.credit, '@kai_photos');
      expect(find.text('Thanks!'), findsOneWidget);
    });
  });
}
