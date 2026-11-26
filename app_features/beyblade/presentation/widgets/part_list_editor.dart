import 'package:clasher_st/core/constants/trc_constant_tokens.dart';
import 'package:clasher_st/core/init_injection/injection.dart';
import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/services/translation/translation_helper.dart';
import 'package:clasher_st/core/widgets/app_beyblade_loading_indicator.dart';
import 'package:clasher_st/core/widgets/holo_extras.dart';
import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/parts_list.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/bey_builder_sheet.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/parts_list_cubit/parts_list_cubit.dart';
import 'package:clasher_st/features/tournaments/presentation/pages/deck_registration_page.dart';
import 'package:flutter/material.dart';

/// The colour a kit kind reads in: bans red, allowed green, organiser kits
/// in the theme's secondary / primary.
Color kitKindColor(BuildContext context, PartListKind kind) {
  final t = HoloTokens.of(context);
  final cs = Theme.of(context).colorScheme;
  return switch (kind) {
    PartListKind.ban => t.danger,
    PartListKind.approve => t.success,
    PartListKind.pool => cs.secondary,
    PartListKind.deck => cs.primary,
  };
}

/// Rebuilds once the part catalog has loaded, so part names never stay on
/// the "Blade #12" fallback.
mixin _CatalogReady<T extends StatefulWidget> on State<T> {
  final PartCatalog catalog = resolvePartCatalog();

  @override
  void initState() {
    super.initState();
    if (!catalog.isReady) {
      catalog.ready().then((_) {
        if (mounted) setState(() {});
      });
    }
  }
}

/// Kind switch, the kit's contents and the ways to fill it: add parts one
/// by one, add a ready-made deck, or start from the meta.
///
/// The owner keeps the [PartList] and gets every change through [onChanged].
/// Used by the create-tournament page and by the Tournament kits pages in
/// the Beyblade feature, so both behave the same.
class PartListEditor extends StatefulWidget {
  const PartListEditor({
    super.key,
    required this.list,
    required this.onChanged,
    this.kinds = PartListKind.values,
    this.combosPerDeck,
  });

  final PartList list;
  final ValueChanged<PartList> onChanged;

  /// The kinds offered by the switch (e.g. only ban / allowed for part
  /// rules). The switch is hidden when there is one.
  final List<PartListKind> kinds;

  /// Deck kits: forces this many combos per deck (the tournament's deck
  /// size). Null: the host picks 1 to 5.
  final int? combosPerDeck;

  @override
  State<PartListEditor> createState() => _PartListEditorState();
}

class _PartListEditorState extends State<PartListEditor>
    with _CatalogReady<PartListEditor> {
  /// Combos per deck for a new deck kit when nothing forces it.
  int _deckSize = 3;

  int get _size =>
      widget.combosPerDeck ??
      (widget.list.decks.isEmpty ? _deckSize : widget.list.comboCount);

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _addParts() async {
    final list = widget.list;
    final refs = await catalog.pickParts(context, kind: list.kind);
    if (refs.isEmpty || !mounted) return;
    final added = refs.where((r) => !list.contains(r)).toList();
    if (added.isEmpty) {
      _snack(TrTokens.partAlreadyOnListFormat.tr
          .replaceFirst('%s', catalog.nameOf(refs.first)));
      return;
    }
    var next = list;
    for (final r in added) {
      next = next.withPart(r);
    }
    widget.onChanged(next);
  }

  /// A kit combo back as a loadout for the builders; null if it has no bit.
  BeybladeLoadout? _loadoutOf(Map<String, String> combo) {
    try {
      return BeybladeLoadout.fromJson(Map<String, dynamic>.from(combo));
    } catch (_) {
      return null;
    }
  }

  /// Builds a deck with the deck builder; [index] edits that deck, which
  /// opens with its combos in place so any one of them can be rebuilt.
  Future<void> _buildDeck({int? index}) async {
    final list = widget.list;
    final size = _size;
    List<BeybladeLoadout>? built;
    final current = index == null
        ? null
        : [for (final c in list.decks[index].combos) _loadoutOf(c)]
            .whereType<BeybladeLoadout>()
            .toList();
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (pageContext) => DeckRegistrationPage(
        title: index == null
            ? TrTokens.kitAddDeckTitle.tr
            : TrTokens.kitEditDeckTitle.tr,
        tournamentName:
            list.name.isEmpty ? TrTokens.kitDeckKitName.tr : list.name,
        beyCount: size,
        initialBeys: current,
        onSubmit: (beys, _) async {
          built = beys;
          if (pageContext.mounted) Navigator.of(pageContext).pop();
        },
      ),
    ));
    final beys = built;
    if (beys == null || !mounted) return;
    final combos = [for (final b in beys) KitDeck.cleanCombo(b.toJson())];
    final name = index == null
        ? TrTokens.kitDeckNumbered.trParams({'n': list.decks.length + 1})
        : list.decks[index].name;
    widget.onChanged(
        list.withDeck(KitDeck(name: name, combos: combos), index: index));
  }

  /// Rebuilds one combo of a deck in the bey builder, keeping the others.
  Future<void> _editCombo(int deckIndex, int comboIndex) async {
    final deck = widget.list.decks[deckIndex];
    final l = await BeyBuilderSheet.show(context,
        initialLoadout: _loadoutOf(deck.combos[comboIndex]));
    if (l == null || !mounted) return;
    final latest = widget.list.decks[deckIndex];
    final combos = [...latest.combos];
    if (comboIndex >= combos.length) return;
    combos[comboIndex] = KitDeck.cleanCombo(l.toJson());
    widget.onChanged(widget.list
        .withDeck(latest.copyWith(combos: combos), index: deckIndex));
  }

  Future<void> _renameDeck(int index) async {
    final name = await showHoloTextDialog(
      context,
      title: TrTokens.kitRenameDeckTitle.tr,
      label: TrTokens.kitDeckNameLabel.tr,
      initial: widget.list.decks[index].name,
      maxLength: 40,
      cancelLabel: TrTokens.cancelTxt.tr,
    );
    if (name == null || name.isEmpty || !mounted) return;
    final d = widget.list.decks[index];
    widget
        .onChanged(widget.list.withDeck(d.copyWith(name: name), index: index));
  }

  Future<void> _fromMeta() async {
    final list = widget.list;
    if (list.kind == PartListKind.deck) {
      final combos = await MetaPicksSheet.showCombos(context,
          catalog: catalog, pick: _size);
      if (combos == null || !mounted) return;
      widget.onChanged(list.withDeck(KitDeck(
          name: TrTokens.kitMetaDeckNumbered
              .trParams({'n': list.decks.length + 1}),
          combos: combos)));
      return;
    }
    final refs = await MetaPicksSheet.showParts(context,
        catalog: catalog, kind: list.kind, already: list);
    if (refs == null || refs.isEmpty || !mounted) return;
    var next = list;
    for (final r in refs) {
      next = next.withPart(r);
    }
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    final list = widget.list;
    final kinds = widget.kinds.contains(list.kind)
        ? widget.kinds
        : [list.kind, ...widget.kinds];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (kinds.length > 1) ...[
          HoloSegmented<PartListKind>(
            value: list.kind,
            onChanged: (k) => widget.onChanged(list.copyWith(kind: k)),
            options: [
              for (final k in kinds) HoloOption(k, k.label, icon: k.icon)
            ],
          ),
          const SizedBox(height: 8),
        ],
        Text(list.kind.rule,
            style: TextStyle(
                fontSize: 12.5, height: 1.35, color: cs.onSurfaceVariant)),
        SizedBox(height: rc.md),
        if (list.kind == PartListKind.deck)
          ..._deckBody(context, list)
        else
          ..._partsBody(context, list),
        SizedBox(height: rc.sm),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (list.kind == PartListKind.deck)
              HoloActionButton(
                label: TrTokens.kitAddDeck.tr,
                icon: Icons.add,
                dense: true,
                variant: HoloButtonVariant.outline,
                onPressed: list.decks.length >= 20 ? null : () => _buildDeck(),
              )
            else
              HoloActionButton(
                label: TrTokens.addPartBtn.tr,
                icon: Icons.add,
                dense: true,
                variant: HoloButtonVariant.outline,
                onPressed: _addParts,
              ),
            HoloActionButton(
              label: TrTokens.kitStartFromMeta.tr,
              icon: Icons.trending_up,
              dense: true,
              variant: HoloButtonVariant.tonal,
              onPressed: _fromMeta,
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _partsBody(BuildContext context, PartList list) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    if (list.isEmpty) {
      return [
        HoloCard(
          wash: true,
          padding: const EdgeInsets.all(14),
          child: Text(
            TrTokens.noPartsYetTxt.tr,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ),
      ];
    }
    // One group per part type.
    return [
      for (final entry in list.parts.entries) ...[
        HoloSubLabel(
          title: catalog.typeLabel(entry.key),
          trailing: Text('${entry.value.length}',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant)),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final id in entry.value)
              InputChip(
                avatar: catalog.thumbnail(PartRef(entry.key, id)),
                label: Text(catalog.nameOf(PartRef(entry.key, id))),
                onDeleted: () =>
                    widget.onChanged(list.withoutPart(PartRef(entry.key, id))),
              ),
          ],
        ),
        SizedBox(height: rc.md),
      ],
    ];
  }

  List<Widget> _deckBody(BuildContext context, PartList list) {
    final cs = Theme.of(context).colorScheme;
    return [
      if (list.decks.isEmpty && widget.combosPerDeck == null) ...[
        HoloNumberStepper(
          label: TrTokens.kitCombosPerDeckLabel.tr,
          helper: TrTokens.kitCombosPerDeckHelper.tr,
          value: _deckSize,
          min: 1,
          max: 5,
          onChanged: (v) => setState(() => _deckSize = v),
        ),
        const SizedBox(height: 12),
      ] else
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(children: [
            HoloPill(
                label:
                    TrTokens.kitCombosPerDeckCount.trParams({'count': _size}),
                color: cs.primary,
                icon: Icons.style_outlined),
            if (widget.combosPerDeck != null &&
                list.comboCount != 0 &&
                list.comboCount != widget.combosPerDeck) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  TrTokens.kitDeckSizeMismatch.trParams(
                      {'have': list.comboCount, 'need': widget.combosPerDeck}),
                  style: TextStyle(
                      fontSize: 12, color: HoloTokens.of(context).danger),
                ),
              ),
            ],
          ]),
        ),
      if (list.decks.isEmpty)
        HoloCard(
          wash: true,
          padding: const EdgeInsets.all(14),
          child: Text(
            TrTokens.kitNoDecksYet.tr,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        )
      else
        for (var i = 0; i < list.decks.length; i++) _deckCard(context, list, i),
    ];
  }

  Widget _deckCard(BuildContext context, PartList list, int i) {
    final cs = Theme.of(context).colorScheme;
    final deck = list.decks[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: HoloCard(
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    deck.name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: cs.onSurface),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: TrTokens.kitDeckOptions.tr,
                  icon: const Icon(Icons.more_vert, size: 20),
                  shape: const ChamferBorder.tab(cut: 10),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                        value: 'rename', child: Text(TrTokens.kitRename.tr)),
                    PopupMenuItem(
                        value: 'replace',
                        child: Text(TrTokens.kitEditCombos.tr)),
                    PopupMenuItem(
                        value: 'remove', child: Text(TrTokens.removeTxt.tr)),
                  ],
                  onSelected: (v) {
                    switch (v) {
                      case 'rename':
                        _renameDeck(i);
                      case 'replace':
                        _buildDeck(index: i);
                      default:
                        widget.onChanged(list.withoutDeck(i));
                    }
                  },
                ),
              ],
            ),
            // Tap a combo to rebuild just that one.
            for (var c = 0; c < deck.combos.length; c++)
              InkWell(
                onTap: () => _editCombo(i, c),
                child: Padding(
                  padding: const EdgeInsets.only(top: 6, right: 6, bottom: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text('${c + 1}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppTheme.primaryText(cs),
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            )),
                      ),
                      for (final p in deck.partsOf(c).take(3))
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: catalog.thumbnail(p, size: 22) ??
                              const SizedBox.shrink(),
                        ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          catalog.comboName(deck.combos[c]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: cs.onSurface),
                        ),
                      ),
                      Tooltip(
                        message: TrTokens.kitEditCombo.tr,
                        child: Icon(Icons.edit_outlined,
                            size: 16, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Dran Sword, Hells Scythe, 3-60 +4" for a kit card; deck kits show
/// their first combos. Empty kits show nothing.
class PartListPreview extends StatefulWidget {
  const PartListPreview({super.key, required this.list, this.maxNames = 3});

  final PartList list;
  final int maxNames;

  @override
  State<PartListPreview> createState() => _PartListPreviewState();
}

class _PartListPreviewState extends State<PartListPreview>
    with _CatalogReady<PartListPreview> {
  @override
  Widget build(BuildContext context) {
    final list = widget.list;
    final names = list.kind == PartListKind.deck
        ? [
            for (final d in list.decks)
              for (final c in d.combos) catalog.comboName(c),
          ]
        : [
            for (final e in list.parts.entries)
              for (final id in e.value) catalog.nameOf(PartRef(e.key, id)),
          ];
    if (names.isEmpty) return const SizedBox.shrink();
    final shown = names.take(widget.maxNames).join(', ');
    final more = names.length - widget.maxNames;
    return Text(
      more > 0 ? '$shown +$more' : shown,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
          fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }
}

// ── Start from the meta ──────────────────────────────────────────────────────

/// The parts or combos that win most right now (real results, bots left
/// out), to start a kit from. Parts: tick any to add. Combos: tick exactly
/// as many as a deck holds.
class MetaPicksSheet extends StatefulWidget {
  const MetaPicksSheet._(
      {required this.catalog,
      required this.combos,
      this.kind,
      this.already,
      this.pick = 3});

  final PartCatalog catalog;
  final bool combos;
  final PartListKind? kind;
  final PartList? already;
  final int pick;

  static Future<List<PartRef>?> showParts(
    BuildContext context, {
    required PartCatalog catalog,
    required PartListKind kind,
    required PartList already,
  }) async {
    final r = await _show(
        context,
        MetaPicksSheet._(
            catalog: catalog, combos: false, kind: kind, already: already));
    return r?.cast<PartRef>();
  }

  static Future<List<Map<String, String>>?> showCombos(
    BuildContext context, {
    required PartCatalog catalog,
    required int pick,
  }) async {
    final r = await _show(
        context, MetaPicksSheet._(catalog: catalog, combos: true, pick: pick));
    return r?.cast<Map<String, String>>();
  }

  static Future<List<Object>?> _show(BuildContext context, Widget sheet) =>
      showModalBottomSheet<List<Object>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        constraints: const BoxConstraints(maxWidth: 720),
        builder: (_) => sheet,
      );

  @override
  State<MetaPicksSheet> createState() => _MetaPicksSheetState();
}

class _MetaPicksSheetState extends State<MetaPicksSheet> {
  final _repo = sl<PartListsRepository>();
  bool _yearly = false;
  late Future<List<Object>> _rows = _load();
  final Set<int> _picked = {};

  Future<List<Object>> _load() async {
    await widget.catalog.ready();
    return widget.combos
        ? await _repo.metaCombos(yearly: _yearly)
        : await _repo.metaParts(yearly: _yearly, limit: 30);
  }

  void _reload(bool yearly) => setState(() {
        _yearly = yearly;
        _picked.clear();
        _rows = _load();
      });

  bool get _ready =>
      widget.combos ? _picked.length == widget.pick : _picked.isNotEmpty;

  String get _title => switch (widget.kind) {
        PartListKind.ban => TrTokens.metaBanTitle.tr,
        PartListKind.approve => TrTokens.metaAllowTitle.tr,
        PartListKind.pool => TrTokens.metaPoolTitle.tr,
        _ => TrTokens.metaDeckTitle.tr,
      };

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HoloSheetHeader(
                title: _title,
                icon: Icons.trending_up,
                subtitle: widget.combos
                    ? TrTokens.metaCombosHint.trParams({'count': widget.pick})
                    : TrTokens.metaPartsHint.tr,
              ),
              HoloSegmented<bool>(
                options: [
                  HoloOption(false, TrTokens.metaThisMonth.tr,
                      icon: Icons.calendar_view_month),
                  HoloOption(true, TrTokens.metaThisYear.tr,
                      icon: Icons.calendar_today_outlined),
                ],
                value: _yearly,
                onChanged: _reload,
              ),
              const SizedBox(height: 10),
              Expanded(
                child: FutureBuilder<List<Object>>(
                  future: _rows,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Center(child: BeybladeSpinner());
                    }
                    if (snap.hasError) {
                      return HoloEmptyState(
                        icon: Icons.error_outline,
                        title: TrTokens.metaLoadError.tr,
                        message: partListsErrorMessage(snap.error!),
                        action: HoloActionButton(
                          label: TrTokens.retryTxt.tr,
                          variant: HoloButtonVariant.outline,
                          onPressed: () => _reload(_yearly),
                        ),
                      );
                    }
                    final rows = snap.data ?? const <Object>[];
                    if (rows.isEmpty) {
                      return HoloEmptyState(
                        icon: Icons.query_stats,
                        title: TrTokens.metaNotEnoughTitle.tr,
                        message: _yearly
                            ? TrTokens.metaTooFewYear.tr
                            : TrTokens.metaTooFewMonth.tr,
                      );
                    }
                    return HoloCard(
                      padding: EdgeInsets.zero,
                      child: ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, i) => _row(context, rows[i], i,
                            last: i == rows.length - 1),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              HoloActionButton(
                label: widget.combos
                    ? (_ready
                        ? TrTokens.metaAddThisDeck.tr
                        : TrTokens.metaPickMore
                            .trParams({'count': widget.pick - _picked.length}))
                    : (_picked.isEmpty
                        ? TrTokens.metaPickParts.tr
                        : TrTokens.metaAddCount
                            .trParams({'count': _picked.length})),
                icon: Icons.check,
                expand: true,
                onPressed: !_ready
                    ? null
                    : () async {
                        final rows = await _rows;
                        if (!context.mounted) return;
                        final picked =
                            (_picked.toList()..sort()).map((i) => rows[i]);
                        Navigator.of(context).pop<List<Object>>(widget.combos
                            ? [for (final r in picked) (r as MetaCombo).combo]
                            : [for (final r in picked) (r as MetaPart).ref]);
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, Object row, int i, {required bool last}) {
    final cs = Theme.of(context).colorScheme;
    final on = _picked.contains(i);
    final String name;
    final String stats;
    Widget? thumb;
    var already = false;
    if (row is MetaPart) {
      name =
          '${widget.catalog.nameOf(row.ref)} · ${widget.catalog.typeLabel(row.ref.partType)}';
      stats = TrTokens.metaWinStats.trParams(
          {'rate': row.winRate.toStringAsFixed(1), 'games': row.games});
      thumb = widget.catalog.thumbnail(row.ref, size: 34);
      already = widget.already?.contains(row.ref) ?? false;
    } else {
      final c = row as MetaCombo;
      name = widget.catalog.comboName(c.combo);
      stats = TrTokens.metaWinStats
          .trParams({'rate': c.winRate.toStringAsFixed(1), 'games': c.games});
    }
    final blocked =
        already || (!on && widget.combos && _picked.length >= widget.pick);
    void toggle() => setState(() => on ? _picked.remove(i) : _picked.add(i));

    return InkWell(
      onTap: blocked ? null : toggle,
      child: Container(
        decoration: BoxDecoration(
            border:
                last ? null : Border(bottom: BorderSide(color: cs.outline))),
        padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
        child: Row(
          children: [
            SizedBox(
              width: 26,
              child: Text('${i + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primaryText(cs),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ),
            if (thumb != null) ...[thumb, const SizedBox(width: 10)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface)),
                  const SizedBox(height: 1),
                  Text(already ? TrTokens.metaAlreadyInKit.tr : stats,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: cs.onSurfaceVariant,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                ],
              ),
            ),
            const SizedBox(width: 8),
            HoloSquareIconButton(
              icon: on || already ? Icons.check : Icons.add,
              filled: on,
              semanticLabel: on ? TrTokens.metaPicked.tr : TrTokens.metaPick.tr,
              onPressed: blocked ? null : toggle,
            ),
          ],
        ),
      ),
    );
  }
}
