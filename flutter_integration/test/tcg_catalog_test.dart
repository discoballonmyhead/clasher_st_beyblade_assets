import 'dart:convert';

import 'package:clasher_st/features/beyblade_tcg/beyblade_tcg.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryStore implements TcgStore {
  final data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
}

Map<String, Object?> _card(String id, String name, String number,
        {String? parent, String gen = 'Original'}) =>
    {
      'dataID': id,
      'parentCardId': parent,
      'name': name,
      'cardNumber': number,
      'setName': 'Starter Set',
      'hobbyName': 'Beyblade TCG',
      'hobbyGeneration': gen,
      'battleEdge': 3,
    };

void main() {
  test('ingests the catalog sheets and keeps them until the next release',
      () async {
    final catalog = TcgCatalog(_MemoryStore());
    expect(await catalog.cards(), isEmpty);

    await catalog.ingestSheets({
      'blades': '[]',
      'tcgCards': jsonEncode([
        _card('2', 'Dragoon', '002'),
        _card('1', 'Dranzer', '001'),
        _card('3', 'Dranzer', '001', parent: '1'),
        {'dataID': '4', 'name': 'Gone', 'deleted': 'true'},
      ]),
      'tcgSets': jsonEncode([
        {'setID': 'S1', 'setName': 'Starter Set', 'hobbyGeneration': 'Original'}
      ]),
    });
    final cards = await catalog.cards();
    expect(cards.map((c) => c.dataId), ['1', '3', '2'], reason: 'by number');
    expect(cards.first.battleEdge, 3);
    expect(await catalog.sets(), hasLength(1));

    // A release without TCG sheets leaves the cards alone.
    await catalog.ingestSheets({'blades': '[]'});
    expect(await catalog.cards(), hasLength(3));

    expect(filterTcgCards(cards).map((c) => c.dataId), ['1', '2'],
        reason: 'variants hidden until searched');
    expect(filterTcgCards(cards, query: 'dranzer'), hasLength(2));
    expect(tcgVariantGroup(cards, cards[1]).map((c) => c.dataId), ['1', '3']);
  });

  test('local image pack paths override the CDN urls', () async {
    final catalog = TcgCatalog(_MemoryStore());
    await catalog.ingestSheets({
      'tcgCards': jsonEncode([
        {..._card('1', 'Dranzer', '001'), 'imageUrl': 'https://cdn/x.webp'}
      ]),
    });
    await catalog.applyLocalImagePaths({'tcgCards-1': '/local/1.webp'});
    expect((await catalog.cards()).single.imageUrl, '/local/1.webp');
  });
}
