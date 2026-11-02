import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

// Belongs with your beyblade inventory feature; the create-tournament page
// is just one place that uses it.

enum PartListKind {
  ban,
  approve;

  static PartListKind fromJson(String? value) =>
      value == 'approve' ? approve : ban;

  String toJson() => name;

  String get label => switch (this) {
        ban => 'Ban list',
        approve => 'Approve list',
      };

  String get shortLabel => switch (this) {
        ban => 'Ban',
        approve => 'Approve',
      };

  /// What the list does, in one sentence players and hosts can both read.
  String get rule => switch (this) {
        ban => "Players can't use any part on this list.",
        approve => 'Players can only use parts on this list. Part types '
            'you leave out stay open.',
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

/// A ban or approve list. The same entity whether it's saved in the
/// user's inventory ([id] set) or built inline for one tournament ([id]
/// null).
///
/// [parts] maps part type to data ids:
/// `{"blade": ["12", "40"], "bit": ["3"]}`.
class PartList extends Equatable {
  const PartList({
    this.id,
    this.name = '',
    required this.kind,
    this.parts = const {},
    this.updatedAt,
  });

  final String? id;
  final String name;
  final PartListKind kind;
  final Map<String, List<String>> parts;
  final DateTime? updatedAt;

  bool get isSaved => id != null;

  int get partCount => parts.values.fold(0, (n, ids) => n + ids.length);

  bool get isEmpty => partCount == 0;

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

  PartList copyWith({
    String? name,
    PartListKind? kind,
    Map<String, List<String>>? parts,
  }) =>
      PartList(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        parts: parts ?? this.parts,
        updatedAt: updatedAt,
      );

  /// Same contents, not tied to the saved list: editing it can't change
  /// the original.
  PartList unsavedCopy() => PartList(name: name, kind: kind, parts: parts);

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
      updatedAt: DateTime.tryParse((json['updated_at'] as String?) ?? ''),
    );
  }

  Map<String, List<String>> get partsJson => {
        for (final e in parts.entries) e.key: List.of(e.value),
      };

  @override
  List<Object?> get props => [id, name, kind, parts, updatedAt];
}

/// The one hook into your parts catalog.
///
/// BeybladePartCatalog (presentation/part_lists/beyblade_part_catalog.dart)
/// implements it on top of BeybladeDataRepo and is registered in
/// BeybladeDependencies.init():
///
///     sl.registerLazySingleton<PartCatalog>(() => BeybladePartCatalog(sl()));
///
/// [resolvePartCatalog] only falls back to [ManualEntryPartCatalog] when
/// nothing is registered (tests).
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
}

PartCatalog resolvePartCatalog() => GetIt.instance.isRegistered<PartCatalog>()
    ? GetIt.instance<PartCatalog>()
    : const ManualEntryPartCatalog();

/// Stopgap until the real catalog is wired: type a part type and data id
/// by hand. Fine for testing; not something to ship to players.
class ManualEntryPartCatalog extends PartCatalog {
  const ManualEntryPartCatalog();

  static const _types = [
    'blade',
    'ratchet',
    'bit',
    'lockChip',
    'mainBlade',
    'assistBlade',
    'overBlade',
    'metalBlade',
  ];

  @override
  Future<PartRef?> pickPart(BuildContext context,
          {required PartListKind kind}) =>
      showDialog<PartRef>(
        context: context,
        builder: (_) => _ManualPartDialog(types: _types, labelOf: typeLabel),
      );

  @override
  String nameOf(PartRef part) => '${typeLabel(part.partType)} #${part.dataId}';
}

class _ManualPartDialog extends StatefulWidget {
  const _ManualPartDialog({required this.types, required this.labelOf});

  final List<String> types;
  final String Function(String) labelOf;

  @override
  State<_ManualPartDialog> createState() => _ManualPartDialogState();
}

class _ManualPartDialogState extends State<_ManualPartDialog> {
  late String _type = widget.types.first;
  final _id = TextEditingController();

  @override
  void dispose() {
    _id.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add part'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'Part type'),
            items: [
              for (final t in widget.types)
                DropdownMenuItem(value: t, child: Text(widget.labelOf(t))),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _id,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Data id'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final id = _id.text.trim();
            if (id.isEmpty) return;
            Navigator.of(context).pop(PartRef(_type, id));
          },
          child: const Text('Add'),
        ),
      ],
    );
  }
}
