import 'package:clasher_st/core/constants/trc_constant_tokens.dart';
import 'package:clasher_st/core/services/translation/translation_helper.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

// Tournament kits (formerly "ban / approve lists"). Belongs with the
// beyblade inventory feature; the create-tournament page is one place that
// uses it. Class names are unchanged so existing code keeps working.
//
//   ban / approve   part rules: what players may bring        (part_rules)
//   pool / deck     organiser kit: what the organiser hands out (organizer_kit)

enum PartListKind {
  ban,
  approve,
  pool,
  deck;

  static PartListKind fromJson(String? value) => switch (value) {
        'approve' => approve,
        'pool' => pool,
        'deck' => deck,
        _ => ban,
      };

  String toJson() => name;

  /// Ban list and allowed parts: rules for the decks players bring.
  static const partRuleKinds = [ban, approve];

  /// Parts pool and deck kit: what the organiser hands out (Mirror Match).
  static const organizerKinds = [pool, deck];

  bool get isPartRule => this == ban || this == approve;
  bool get isOrganizerKit => this == pool || this == deck;

  String get label => switch (this) {
        ban => TrTokens.banListTxt.tr,
        approve => TrTokens.approveListTxt.tr,
        pool => TrTokens.kitKindPool.tr,
        deck => TrTokens.kitKindDeck.tr,
      };

  String get shortLabel => switch (this) {
        ban => TrTokens.banShortTxt.tr,
        approve => TrTokens.approveShortTxt.tr,
        pool => TrTokens.kitKindPoolShort.tr,
        deck => TrTokens.kitKindDeckShort.tr,
      };

  /// What the kit does, in one sentence players and hosts can both read.
  String get rule => switch (this) {
        ban => TrTokens.ruleBanTxt.tr,
        approve => TrTokens.ruleApproveTxt.tr,
        pool => TrTokens.kitRulePool.tr,
        deck => TrTokens.kitRuleDeck.tr,
      };

  IconData get icon => switch (this) {
        ban => Icons.block,
        approve => Icons.verified_outlined,
        pool => Icons.inventory_2_outlined,
        deck => Icons.style_outlined,
      };
}

/// One part: its type and its data id.
///
/// The same pair `analytics.extract_parts_from_deck` produces from a deck
/// loadout: the loadout key with "DataId" removed ("bladeDataId" ->
/// "blade") and the id as text. Keeping that shape means checking a deck
/// against a list later is a direct comparison.
class PartRef extends Equatable {
  const PartRef(this.partType, this.dataId);

  final String partType;
  final String dataId;

  /// From a loadout field: `PartRef.fromLoadoutField('bladeDataId', 12)`
  /// gives `PartRef('blade', '12')`.
  factory PartRef.fromLoadoutField(String key, Object id) =>
      PartRef(key.replaceFirst(RegExp(r'DataId$'), ''), id.toString().trim());

  @override
  List<Object?> get props => [partType, dataId];
}

/// One ready-made deck in a deck kit: a name and its combos, each combo
/// a loadout as `BeybladeLoadout.toJson()` writes it, empty fields left out:
/// `{"bladeDataId": "12", "ratchetDataId": "3", "bitDataId": "7"}`.
class KitDeck extends Equatable {
  const KitDeck({this.name = '', this.combos = const []});

  final String name;
  final List<Map<String, String>> combos;

  /// Keeps only filled loadout fields, as text.
  static Map<String, String> cleanCombo(Map<String, dynamic> loadout) => {
        for (final e in loadout.entries)
          if (e.key.endsWith('DataId') &&
              e.value != null &&
              '${e.value}'.trim().isNotEmpty)
            e.key: '${e.value}'.trim(),
      };

  factory KitDeck.fromJson(Map<String, dynamic> json) => KitDeck(
        name: (json['name'] as String?) ?? '',
        combos: [
          for (final c in (json['combos'] as List?) ?? const [])
            if (c is Map) cleanCombo(Map<String, dynamic>.from(c)),
        ],
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'combos': [for (final c in combos) Map<String, String>.of(c)],
      };

  /// How a combo reads, top to bottom (the server stores keys sorted
  /// alphabetically, so order is restored here).
  static const fieldOrder = [
    'lockChipDataId',
    'bladeDataId',
    'overBladeDataId',
    'metalBladeDataId',
    'mainBladeDataId',
    'assistBladeDataId',
    'ratchetDataId',
    'bitDataId',
  ];

  /// The parts of [combo], in reading order.
  static List<PartRef> comboParts(Map<String, String> combo) => [
        for (final k in fieldOrder)
          if (combo[k] != null) PartRef.fromLoadoutField(k, combo[k]!),
        for (final e in combo.entries)
          if (!fieldOrder.contains(e.key))
            PartRef.fromLoadoutField(e.key, e.value),
      ];

  /// The parts of combo [i], in reading order.
  List<PartRef> partsOf(int i) => comboParts(combos[i]);

  KitDeck copyWith({String? name, List<Map<String, String>>? combos}) =>
      KitDeck(name: name ?? this.name, combos: combos ?? this.combos);

  @override
  List<Object?> get props => [name, combos];
}

/// A kit. The same entity whether it's saved in the user's inventory
/// ([id] set) or built inline for one tournament ([id] null).
///
/// [parts] maps part type to data ids: `{"blade": ["12", "40"], "bit": ["3"]}`.
/// Deck kits keep their decks in [decks]; the server fills [parts] with
/// every part the decks use.
class PartList extends Equatable {
  const PartList({
    this.id,
    this.name = '',
    required this.kind,
    this.parts = const {},
    this.decks = const [],
    this.updatedAt,
  });

  final String? id;
  final String name;
  final PartListKind kind;
  final Map<String, List<String>> parts;
  final List<KitDeck> decks;
  final DateTime? updatedAt;

  bool get isSaved => id != null;

  int get partCount => parts.values.fold(0, (n, ids) => n + ids.length);

  int get deckCount => decks.length;

  /// Combos per deck (every deck in a kit has the same number); 0 when empty.
  int get comboCount => decks.isEmpty ? 0 : decks.first.combos.length;

  bool get isEmpty =>
      kind == PartListKind.deck ? decks.isEmpty : partCount == 0;

  /// "12 parts" / "3 decks · 3 combos".
  String get sizeLabel => kind == PartListKind.deck
      ? '${deckCount == 1 ? TrTokens.kitOneDeck.tr : TrTokens.kitDecksCount.trParams({
                  'count': deckCount
                })}'
          ' · ${comboCount == 1 ? TrTokens.oneComboTxt.tr : TrTokens.combosTxt.trParams({
                  'count': comboCount
                })}'
      : TrTokens.partsCountFormat.tr.replaceFirst('%s', '$partCount');

  bool contains(PartRef part) =>
      parts[part.partType]?.contains(part.dataId) ?? false;

  /// Adds [part] at the end of its type's group. No-op if already there.
  PartList withPart(PartRef part) {
    if (contains(part)) return this;
    return copyWith(parts: {
      ...parts,
      part.partType: [...?parts[part.partType], part.dataId],
    });
  }

  PartList withoutPart(PartRef part) {
    final ids = [...?parts[part.partType]]..remove(part.dataId);
    final next = {...parts};
    if (ids.isEmpty) {
      next.remove(part.partType);
    } else {
      next[part.partType] = ids;
    }
    return copyWith(parts: next);
  }

  /// Adds [deck], or replaces the deck at [index].
  PartList withDeck(KitDeck deck, {int? index}) {
    final next = [...decks];
    if (index == null || index < 0 || index >= next.length) {
      next.add(deck);
    } else {
      next[index] = deck;
    }
    return copyWith(decks: next);
  }

  PartList withoutDeck(int index) =>
      copyWith(decks: [...decks]..removeAt(index));

  PartList copyWith({
    String? name,
    PartListKind? kind,
    Map<String, List<String>>? parts,
    List<KitDeck>? decks,
  }) =>
      PartList(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        parts: parts ?? this.parts,
        decks: decks ?? this.decks,
        updatedAt: updatedAt,
      );

  /// Same contents, not tied to the saved kit: editing it can't change
  /// the original.
  PartList unsavedCopy() =>
      PartList(name: name, kind: kind, parts: parts, decks: decks);

  factory PartList.fromJson(Map<String, dynamic> json) {
    final raw = (json['parts'] as Map?) ?? const {};
    return PartList(
      id: json['id'] as String?,
      name: (json['name'] as String?) ?? '',
      kind: PartListKind.fromJson(json['kind'] as String?),
      parts: {
        for (final e in raw.entries)
          e.key as String: [for (final id in e.value as List) id.toString()],
      },
      decks: [
        for (final d in (json['decks'] as List?) ?? const [])
          if (d is Map) KitDeck.fromJson(Map<String, dynamic>.from(d)),
      ],
      updatedAt: DateTime.tryParse((json['updated_at'] as String?) ?? ''),
    );
  }

  Map<String, List<String>> get partsJson => {
        for (final e in parts.entries) e.key: List.of(e.value),
      };

  List<Map<String, dynamic>> get decksJson =>
      [for (final d in decks) d.toJson()];

  @override
  List<Object?> get props => [id, name, kind, parts, decks, updatedAt];
}

/// The one hook into your parts catalog.
///
/// BeybladePartCatalog (presentation/part_lists/beyblade_part_catalog.dart)
/// implements it on top of BeybladeDataRepo and is registered in
/// BeybladeDependencies.init():
///
///     sl.registerLazySingleton<PartCatalog>(() => BeybladePartCatalog(sl()));
abstract class PartCatalog {
  const PartCatalog();

  /// Lets the user pick one part. Null if they cancel.
  Future<PartRef?> pickPart(BuildContext context, {required PartListKind kind});

  /// Lets the user pick one or more parts at once (e.g. a part together
  /// with all its recolors). Empty if they cancel. Defaults to [pickPart].
  Future<List<PartRef>> pickParts(BuildContext context,
      {required PartListKind kind}) async {
    final part = await pickPart(context, kind: kind);
    return part == null ? const [] : [part];
  }

  /// True once [nameOf] and [thumbnail] can answer from loaded data.
  bool get isReady => true;

  /// Loads whatever [nameOf] needs. Widgets that show part names call it
  /// and rebuild when it completes, so a list never stays on "Blade #12".
  Future<void> ready() async {}

  /// A small picture of the part, or null when the catalog has none.
  Widget? thumbnail(PartRef part, {double size = 24}) => null;

  /// Display name for a part, e.g. "Dran Sword". Return something
  /// readable even when the id is unknown.
  String nameOf(PartRef part);

  /// "blade" -> "Blade", "lockChip" -> "Lock chip". Override if your
  /// catalog has proper labels.
  String typeLabel(String partType) {
    final spaced = partType.replaceAllMapped(
        RegExp(r'(?<=[a-z0-9])([A-Z])'), (m) => ' ${m[1]!.toLowerCase()}');
    return spaced.isEmpty
        ? partType
        : spaced[0].toUpperCase() + spaced.substring(1);
  }

  /// "Dran Sword 3-60 Flat" for one combo of a deck kit.
  String comboName(Map<String, String> combo) =>
      KitDeck.comboParts(combo).map(nameOf).join(' ');
}

/// The registered catalog (BeybladeDependencies.init registers it).
PartCatalog resolvePartCatalog() => GetIt.instance<PartCatalog>();
