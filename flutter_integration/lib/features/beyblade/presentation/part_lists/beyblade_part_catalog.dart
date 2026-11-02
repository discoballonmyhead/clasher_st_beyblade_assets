// The real PartCatalog behind ban / approve lists (parts_list.dart).
//
// Backed by the local parts catalog the deck builder already uses
// (BeybladeDataRepo): search by name or code, filter by part type, images,
// and recolors listed under their original. Registered in
// BeybladeDependencies.init(); resolvePartCatalog() then returns it
// everywhere (create-tournament page, Ban & approve lists page).
//
// PartList / PartRef keep their exact shape ({"blade": ["12"]}), so saved
// lists and tournament rules stay compatible.

import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/widgets/app_beyblade_loading_indicator.dart';
import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/domain/repositories/beyblade_data_repo.dart';
import 'package:clasher_st/features/beyblade/parts_list.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/part_image_thumb.dart';
import 'package:flutter/material.dart';

/// One part type as PartRef knows it ("blade") and as the catalog knows it
/// ("blades" - the sheet short key used by BeybladeDataRepo).
class PartTypeInfo {
  const PartTypeInfo(this.refKey, this.sheetKey, this.label);

  final String refKey;
  final String sheetKey;
  final String label;
}

const kListablePartTypes = <PartTypeInfo>[
  PartTypeInfo('blade', 'blades', 'Blade'),
  PartTypeInfo('ratchet', 'ratchets', 'Ratchet'),
  PartTypeInfo('bit', 'bits', 'Bit'),
  PartTypeInfo('lockChip', 'lockChips', 'Lock chip'),
  PartTypeInfo('mainBlade', 'mainBlades', 'Main blade'),
  PartTypeInfo('assistBlade', 'assistBlades', 'Assist blade'),
  PartTypeInfo('overBlade', 'overBlades', 'Over blade'),
  PartTypeInfo('metalBlade', 'metalBlades', 'Metal blade'),
];

PartTypeInfo? partTypeByRefKey(String refKey) {
  for (final t in kListablePartTypes) {
    if (t.refKey == refKey) return t;
  }
  return null;
}

/// A part with its PartRef type key attached.
class ListablePart {
  const ListablePart(this.type, this.part);

  final PartTypeInfo type;
  final BeybladePart part;

  PartRef get ref => PartRef(type.refKey, part.dataId);
  bool get isVariant => part.parentPartId != null;

  String get displayName {
    final v = part.variantLabel?.trim();
    return (v == null || v.isEmpty) ? part.name : '${part.name} ($v)';
  }
}

class BeybladePartCatalog extends PartCatalog {
  BeybladePartCatalog(this._repo);

  final BeybladeDataRepo _repo;

  /// `refKey|dataId` -> part. Filled by [warm]; nameOf() is synchronous,
  /// so it answers from here.
  final Map<String, ListablePart> _byRef = {};
  Future<void>? _warming;
  bool _loaded = false;

  static String _k(String refKey, String dataId) => '$refKey|$dataId';

  /// Loads every listable part (cheap: local database). Safe to call
  /// repeatedly; [force] re-reads it, which the picker does on every open so
  /// a catalog update shows up without restarting the app.
  Future<void> warm({bool force = false}) {
    if (force) _warming = null;
    return _warming ??= _load();
  }

  @override
  bool get isReady => _loaded;

  @override
  Future<void> ready() => warm();

  Future<void> _load() async {
    final loaders = <String, Future<List<BeybladePart>> Function()>{
      'blades': _repo.getAllBlades,
      'ratchets': _repo.getAllRatchets,
      'bits': _repo.getAllBits,
      'lockChips': _repo.getAllLockChips,
      'mainBlades': _repo.getAllMainBlades,
      'assistBlades': _repo.getAllAssistBlades,
      'overBlades': _repo.getAllOverBlades,
      'metalBlades': _repo.getAllMetalBlades,
    };
    final next = <String, ListablePart>{};
    for (final t in kListablePartTypes) {
      try {
        for (final p in await loaders[t.sheetKey]!()) {
          next[_k(t.refKey, p.dataId)] = ListablePart(t, p);
        }
      } catch (_) {
        // A part type that fails to load just isn't offered.
      }
    }
    _byRef
      ..clear()
      ..addAll(next);
    _loaded = true;
  }

  List<ListablePart> get all => _byRef.values.toList(growable: false);

  ListablePart? lookup(PartRef ref) => _byRef[_k(ref.partType, ref.dataId)];

  /// The original plus every variant of [ref]'s part (same type).
  List<PartRef> variantGroup(PartRef ref) {
    final p = lookup(ref);
    if (p == null) return [ref];
    final root = p.part.parentPartId ?? p.part.dataId;
    return [
      for (final x in _byRef.values)
        if (x.type.refKey == ref.partType &&
            (x.part.dataId == root || x.part.parentPartId == root))
          x.ref,
    ];
  }

  @override
  String nameOf(PartRef part) =>
      lookup(part)?.displayName ??
      '${typeLabel(part.partType)} #${part.dataId}';

  @override
  String typeLabel(String partType) =>
      partTypeByRefKey(partType)?.label ?? super.typeLabel(partType);

  @override
  Widget? thumbnail(PartRef part, {double size = 24}) {
    final p = lookup(part)?.part;
    if (p == null) return null;
    return PartImageThumb(
      imageUrl: preferredThumbUrl(p),
      size: size,
      scale: imageScaleFor(p),
    );
  }

  /// One part per pick.
  @override
  Future<PartRef?> pickPart(
    BuildContext context, {
    required PartListKind kind,
  }) async {
    final picked = await PartPickerSheet.show(
      context,
      catalog: this,
      kind: kind,
    );
    return (picked == null || picked.isEmpty) ? null : picked.first;
  }

  /// A part, or a part with all its recolors when "Include all its
  /// variants" is ticked (the default).
  @override
  Future<List<PartRef>> pickParts(
    BuildContext context, {
    required PartListKind kind,
  }) async =>
      await PartPickerSheet.show(
        context,
        catalog: this,
        kind: kind,
        allowGroup: true,
      ) ??
      const [];
}

// ── Picker ────────────────────────────────────────────────────────────────

class PartPickerSheet extends StatefulWidget {
  const PartPickerSheet._({
    required this.catalog,
    required this.kind,
    required this.allowGroup,
  });

  final BeybladePartCatalog catalog;
  final PartListKind kind;
  final bool allowGroup;

  static Future<List<PartRef>?> show(
    BuildContext context, {
    required BeybladePartCatalog catalog,
    required PartListKind kind,
    bool allowGroup = false,
  }) => showModalBottomSheet<List<PartRef>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 720),
    builder: (_) =>
        PartPickerSheet._(catalog: catalog, kind: kind, allowGroup: allowGroup),
  );

  @override
  State<PartPickerSheet> createState() => _PartPickerSheetState();
}

class _PartPickerSheetState extends State<PartPickerSheet> {
  final _query = TextEditingController();
  String? _type; // refKey, null = all
  bool _includeVariants = true;
  bool _showVariants = false;
  late final Future<void> _ready = widget.catalog.warm(force: true);

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<ListablePart> _results() {
    final q = _query.text.trim().toLowerCase();
    final list =
        widget.catalog.all.where((p) {
          if (_type != null && p.type.refKey != _type) return false;
          if (!_showVariants && q.isEmpty && p.isVariant) return false;
          if (q.isEmpty) return true;
          return p.part.name.toLowerCase().contains(q) ||
              p.part.code.toLowerCase().contains(q) ||
              (p.part.variantLabel?.toLowerCase().contains(q) ?? false);
        }).toList()..sort((a, b) {
          final t = kListablePartTypes
              .indexOf(a.type)
              .compareTo(kListablePartTypes.indexOf(b.type));
          if (t != 0) return t;
          final n = a.part.name.toLowerCase().compareTo(
            b.part.name.toLowerCase(),
          );
          if (n != 0) return n;
          return (a.isVariant ? 1 : 0).compareTo(b.isVariant ? 1 : 0);
        });
    return list.length > 300 ? list.sublist(0, 300) : list;
  }

  void _pick(ListablePart p) {
    final refs = widget.allowGroup && _includeVariants
        ? widget.catalog.variantGroup(p.ref)
        : [p.ref];
    Navigator.of(context).pop(refs);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    final height = MediaQuery.sizeOf(context).height * 0.85;

    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          rc.horizontalPadding,
          0,
          rc.horizontalPadding,
          rc.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HoloSectionLabel(
              title: widget.kind == PartListKind.ban
                  ? 'Add a part to ban'
                  : 'Add an allowed part',
            ),
            SizedBox(height: rc.sm),
            TextField(
              controller: _query,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Name or code, e.g. Dran Sword or BX-01',
                suffixIcon: _query.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: _query.clear,
                      ),
              ),
            ),
            SizedBox(height: rc.sm),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _chip(
                    'All',
                    _type == null,
                    () => setState(() => _type = null),
                  ),
                  for (final t in kListablePartTypes)
                    _chip(
                      t.label,
                      _type == t.refKey,
                      () => setState(() => _type = t.refKey),
                    ),
                ],
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _showVariants,
                    onChanged: (v) =>
                        setState(() => _showVariants = v ?? false),
                    title: const Text('Show recolors / variants'),
                  ),
                ),
                if (widget.allowGroup)
                  Expanded(
                    child: CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _includeVariants,
                      onChanged: (v) =>
                          setState(() => _includeVariants = v ?? true),
                      title: const Text('Include all its variants'),
                    ),
                  ),
              ],
            ),
            Expanded(
              child: FutureBuilder<void>(
                future: _ready,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(child: BeybladeSpinner());
                  }
                  final results = _results();
                  if (results.isEmpty) {
                    return Center(
                      child: Text(
                        widget.catalog.all.isEmpty
                            ? 'The parts catalog is empty on this device.'
                            : 'No parts match.',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    );
                  }
                  return ListView.separated(
                    itemCount: results.length,
                    separatorBuilder: (_, __) => SizedBox(height: rc.xs),
                    itemBuilder: (context, i) => _PartRow(
                      part: results[i],
                      onTap: () => _pick(results[i]),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 6),
    child: ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    ),
  );
}

class _PartRow extends StatelessWidget {
  const _PartRow({required this.part, required this.onTap});

  final ListablePart part;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = part.part;
    final meta = <String>[
      part.type.label,
      if (p.code.trim().isNotEmpty) p.code,
      p.hobbyGeneration,
      if (p.manufacturer != 'Takara-Tomy') p.manufacturer,
    ];
    return HoloCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      child: Row(
        children: [
          SizedBox(width: part.isVariant ? 18 : 0),
          PartImageThumb(
            imageUrl: preferredThumbUrl(p),
            size: 44,
            scale: imageScaleFor(p),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  part.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  meta.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          Icon(Icons.add_circle_outline, color: cs.primary),
        ],
      ),
    );
  }
}
