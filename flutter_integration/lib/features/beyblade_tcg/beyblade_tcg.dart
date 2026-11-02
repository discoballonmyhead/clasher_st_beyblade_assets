// =============================================================================
// BEYBLADE TCG CATALOG (hobby "Beyblade TCG")
// -----------------------------------------------------------------------------
// The card game is its own hobby: own rows (hobbyName = "Beyblade TCG"), own
// image packs (beyblade_tcg_images_<Gen>.zip) and data packs. hobbyGeneration
// tells the games apart: "Original" = the V-Force TCG (Blade / Bit-Beast
// cards, Battle Edge, Spin Strength), "X" = the Beyblade X TCG (not released yet).
//
// Data comes from the same catalog.zip the parts already use (tcgCards.json,
// tcgSets.json). Additive only - nothing in the parts catalog changes:
//
// 1) beyblade_cat_remdsrc.dart, downloadCatalogSheets(): keep these optional
//    sheets too (don't add them to trackedBeyBladeData - that list is
//    "required", and older releases don't have them):
//
//        final optional = kOptionalCatalogSheets.toSet();
//        ...
//        if (!tracked.contains(sheet) && !optional.contains(sheet)) continue;
//
// 2) beyblade_sync_cubit.dart, right after `final sheets = await
//    _catalogRemote.downloadCatalogSheets(release);`:
//
//        await sl<TcgCatalog>().ingestSheets(sheets);
//
// 3) DI (beyblade_dependencies.dart):
//
//        sl.registerLazySingleton<TcgCatalog>(() => TcgCatalog(
//            HiveKeyValueStore(sl<Box>(instanceName: AppConstants.appFlagsBoxName))));
//
//    (any Box works - TcgCatalog only stores two JSON strings under its own
//    keys; HiveKeyValueStore is the 6-line adapter at the bottom of this file).
//
// Card images: TcgCard.imageUrl / minifiedImageUrl, same rules as parts
// (preferredImageSource). Image packs key files as tcgCards-<dataID>.webp.
// =============================================================================

import 'dart:convert';
import 'dart:developer' as dev;

import 'package:equatable/equatable.dart';

const kTcgHobbyName = 'Beyblade TCG';

/// Catalog sheets that may be in catalog.zip but aren't required.
const kOptionalCatalogSheets = <String>['tcgCards', 'tcgSets', 'codeSeries'];

// ── Entities ──────────────────────────────────────────────────────────────

class TcgSet extends Equatable {
  const TcgSet({
    required this.setId,
    this.parentSetId,
    this.variantLabel,
    this.setCode,
    required this.setName,
    this.manufacturer,
    required this.hobbyName,
    required this.hobbyGeneration,
    this.region,
    this.releaseDate,
    this.cardCount,
    this.productId,
    this.description,
    this.imageUrl,
    this.minifiedImageUrl,
    required this.isIncomplete,
  });

  final String setId;
  final String? parentSetId;
  final String? variantLabel;
  final String? setCode;
  final String setName;
  final String? manufacturer;
  final String hobbyName;
  final String hobbyGeneration;
  final String? region;
  final DateTime? releaseDate;
  final int? cardCount;

  /// The booster/deck in the Products catalog, when known.
  final String? productId;
  final String? description;
  final String? imageUrl;
  final String? minifiedImageUrl;
  final bool isIncomplete;

  @override
  List<Object?> get props => [
    setId,
    setCode,
    setName,
    hobbyGeneration,
    imageUrl,
    minifiedImageUrl,
  ];
}

class TcgCard extends Equatable {
  const TcgCard({
    required this.dataId,
    this.parentCardId,
    this.variantLabel,
    this.manufacturer,
    required this.hobbyName,
    required this.hobbyGeneration,
    this.setCode,
    this.setName,
    this.cardNumber,
    required this.name,
    this.subtitle,
    this.cardType,
    this.rarity,
    this.attribute,
    this.cost,
    this.power,
    this.battleEdge,
    this.spinStrength,
    this.effectText,
    this.loreText,
    this.linkedPartType,
    this.linkedPartDataId,
    this.illustrator,
    this.legality,
    this.imageUrl,
    this.minifiedImageUrl,
    required this.isIncomplete,
  });

  final String dataId;

  /// Same element/variant model as parts: null = the original card, else the
  /// dataId of the card this is a parallel/foil/alt-art of.
  final String? parentCardId;
  final String? variantLabel;
  final String? manufacturer;
  final String hobbyName;
  final String hobbyGeneration;
  final String? setCode;
  final String? setName;
  final String? cardNumber;
  final String name;
  final String? subtitle;
  final String? cardType;
  final String? rarity;
  final String? attribute;
  final num? cost;
  final num? power;

  /// Original 2000s TCG stats; null for games that don't use them.
  final num? battleEdge;
  final num? spinStrength;
  final String? effectText;
  final String? loreText;

  /// Optional link to the physical part, e.g. ("Parts_X_Blades", "65").
  final String? linkedPartType;
  final String? linkedPartDataId;
  final String? illustrator;
  final String? legality;
  final String? imageUrl;
  final String? minifiedImageUrl;
  final bool isIncomplete;

  bool get isVariant => parentCardId != null;

  @override
  List<Object?> get props => [
    dataId,
    parentCardId,
    variantLabel,
    hobbyGeneration,
    setName,
    cardNumber,
    name,
    imageUrl,
    minifiedImageUrl,
  ];
}

// ── Parsing (tolerant: an odd row never sinks the catalog) ────────────────

String? _s(Map<String, dynamic> r, String k) {
  final v = r[k];
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty || s == 'null' ? null : s;
}

num? _n(Map<String, dynamic> r, String k) {
  final v = r[k];
  if (v is num) return v;
  return num.tryParse(_s(r, k) ?? '');
}

bool _b(Map<String, dynamic> r, String k) {
  final v = _s(r, k)?.toLowerCase();
  return v == '1' || v == 'true' || v == 'yes';
}

TcgSet? tcgSetFromRow(Map<String, dynamic> r) {
  final id = _s(r, 'setID');
  final name = _s(r, 'setName') ?? _s(r, 'setCode');
  if (id == null || name == null) return null;
  return TcgSet(
    setId: id,
    parentSetId: _s(r, 'parentSetId'),
    variantLabel: _s(r, 'variantLabel'),
    setCode: _s(r, 'setCode'),
    setName: name,
    manufacturer: _s(r, 'manufacturer'),
    hobbyName: _s(r, 'hobbyName') ?? kTcgHobbyName,
    hobbyGeneration: _s(r, 'hobbyGeneration') ?? '',
    region: _s(r, 'region'),
    releaseDate: DateTime.tryParse(_s(r, 'releaseDate') ?? ''),
    cardCount: _n(r, 'cardCount')?.toInt(),
    productId: _s(r, 'productID'),
    description: _s(r, 'description'),
    imageUrl: _s(r, 'imageUrl'),
    minifiedImageUrl: _s(r, 'minifiedImageUrl'),
    isIncomplete: _b(r, 'incompleteData'),
  );
}

TcgCard? tcgCardFromRow(Map<String, dynamic> r) {
  final id = _s(r, 'dataID');
  final name = _s(r, 'name');
  if (id == null || name == null) return null;
  if (_s(r, 'deleted')?.toLowerCase() == 'true') return null;
  return TcgCard(
    dataId: id,
    parentCardId: _s(r, 'parentCardId'),
    variantLabel: _s(r, 'variantLabel'),
    manufacturer: _s(r, 'manufacturer'),
    hobbyName: _s(r, 'hobbyName') ?? kTcgHobbyName,
    hobbyGeneration: _s(r, 'hobbyGeneration') ?? '',
    setCode: _s(r, 'setCode'),
    setName: _s(r, 'setName'),
    cardNumber: _s(r, 'cardNumber'),
    name: name,
    subtitle: _s(r, 'subtitle'),
    cardType: _s(r, 'cardType'),
    rarity: _s(r, 'rarity'),
    attribute: _s(r, 'attribute'),
    cost: _n(r, 'cost'),
    power: _n(r, 'power'),
    battleEdge: _n(r, 'battleEdge'),
    spinStrength: _n(r, 'spinStrength'),
    effectText: _s(r, 'effectText'),
    loreText: _s(r, 'loreText'),
    linkedPartType: _s(r, 'linkedPartType'),
    linkedPartDataId: _s(r, 'linkedPartDataID'),
    illustrator: _s(r, 'illustrator'),
    legality: _s(r, 'legality'),
    imageUrl: _s(r, 'imageUrl'),
    minifiedImageUrl: _s(r, 'minifiedImageUrl'),
    isIncomplete: _b(r, 'incompleteData'),
  );
}

List<T> _parseList<T>(String? raw, T? Function(Map<String, dynamic>) row) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return const [];
    return [
      for (final e in decoded)
        if (e is Map) row(Map<String, dynamic>.from(e)),
    ].whereType<T>().toList(growable: false);
  } catch (e) {
    dev.log('TCG sheet unreadable: $e', name: 'TcgCatalog');
    return const [];
  }
}

// ── Store ─────────────────────────────────────────────────────────────────

/// The two calls TcgCatalog needs from local storage. Adapt any Hive box.
abstract class KeyValueStore {
  String? getString(String key);
  Future<void> putString(String key, String value);
}

class TcgCatalog {
  TcgCatalog(this._store);

  final KeyValueStore _store;
  static const _cardsKey = 'tcg_catalog_cards_json';
  static const _setsKey = 'tcg_catalog_sets_json';
  static const _imagesKey = 'tcg_catalog_local_images_json';

  List<TcgCard>? _cards;
  List<TcgSet>? _sets;

  /// Call with the sheets map from downloadCatalogSheets(). A release without
  /// TCG sheets leaves the current TCG catalog as it is.
  Future<void> ingestSheets(Map<String, String> sheets) async {
    final cards = sheets['tcgCards'];
    final sets = sheets['tcgSets'];
    if (cards != null) await _store.putString(_cardsKey, cards);
    if (sets != null) await _store.putString(_setsKey, sets);
    _cards = null;
    _sets = null;
  }

  /// Downloaded image pack: {"tcgCards-12": "/path/tcgCards-12.webp", ...}
  /// (same keys the parts image packs use). Stored as an overlay so a later
  /// catalog update doesn't lose the local paths.
  Future<void> applyLocalImagePaths(Map<String, String> pathsByKey) async {
    final current = _localImages();
    for (final e in pathsByKey.entries) {
      if (e.key.startsWith('tcgCards-') || e.key.startsWith('tcgSets-')) {
        current[e.key] = e.value;
      }
    }
    await _store.putString(_imagesKey, jsonEncode(current));
    _cards = null;
    _sets = null;
  }

  Map<String, String> _localImages() {
    try {
      return Map<String, String>.from(
        jsonDecode(_store.getString(_imagesKey) ?? '{}') as Map,
      );
    } catch (_) {
      return {};
    }
  }

  List<TcgCard> get cards => _cards ??= () {
    final local = _localImages();
    return [
      for (final c in _parseList(_store.getString(_cardsKey), tcgCardFromRow))
        _withLocal(c, local),
    ];
  }();

  List<TcgSet> get sets =>
      _sets ??= _parseList(_store.getString(_setsKey), tcgSetFromRow);

  TcgCard _withLocal(TcgCard c, Map<String, String> local) {
    final full = local['tcgCards-${c.dataId}'];
    final mini = local['tcgCards-${c.dataId}-min'];
    if (full == null && mini == null) return c;
    return TcgCard(
      dataId: c.dataId,
      parentCardId: c.parentCardId,
      variantLabel: c.variantLabel,
      manufacturer: c.manufacturer,
      hobbyName: c.hobbyName,
      hobbyGeneration: c.hobbyGeneration,
      setCode: c.setCode,
      setName: c.setName,
      cardNumber: c.cardNumber,
      name: c.name,
      subtitle: c.subtitle,
      cardType: c.cardType,
      rarity: c.rarity,
      attribute: c.attribute,
      cost: c.cost,
      power: c.power,
      battleEdge: c.battleEdge,
      spinStrength: c.spinStrength,
      effectText: c.effectText,
      loreText: c.loreText,
      linkedPartType: c.linkedPartType,
      linkedPartDataId: c.linkedPartDataId,
      illustrator: c.illustrator,
      legality: c.legality,
      imageUrl: full ?? c.imageUrl,
      minifiedImageUrl: mini ?? c.minifiedImageUrl,
      isIncomplete: c.isIncomplete,
    );
  }

  /// Generations that have cards (for the image-pack sheet / filters).
  List<String> get generations =>
      ({for (final c in cards) c.hobbyGeneration}..remove('')).toList()..sort();

  List<TcgCard> cardsOf({String? generation, String? setName, String? query}) {
    final q = query?.trim().toLowerCase() ?? '';
    return cards.where((c) {
      if (generation != null && c.hobbyGeneration != generation) return false;
      if (setName != null && c.setName != setName) return false;
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q) ||
          (c.cardNumber?.toLowerCase().contains(q) ?? false) ||
          (c.subtitle?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  /// The original card plus its parallels/foils.
  List<TcgCard> variantGroup(String dataId) {
    final c = cards.where((x) => x.dataId == dataId).firstOrNull;
    if (c == null) return const [];
    final root = c.parentCardId ?? c.dataId;
    return cards
        .where((x) => x.dataId == root || x.parentCardId == root)
        .toList();
  }
}

/// Adapter for any Hive box (`Box` from hive / hive_ce - same API):
///
///   class HiveKeyValueStore implements KeyValueStore {
///     HiveKeyValueStore(this.box);
///     final Box box;
///     @override String? getString(String key) => box.get(key) as String?;
///     @override Future<void> putString(String key, String value) => box.put(key, value);
///   }
///
/// Kept as a comment so this file doesn't import a Hive package the app may
/// pull in under a different name - paste it next to your DI setup.
