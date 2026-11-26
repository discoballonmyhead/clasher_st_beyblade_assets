import 'dart:math' as math;

import 'package:clasher_st/core/widgets/app_info_chip.dart';
import 'package:clasher_st/core/widgets/holo_extras.dart';
import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/minified_beyblade_tile.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/part_image_thumb.dart';
import 'package:flutter/material.dart';

import 'holo_stat_panel.dart';
import 'holo_stat_radar.dart';
import 'stat_style.dart';

// =============================================================================
// THE GRAPH ON ITS OWN, IN THREE SIZES
// -----------------------------------------------------------------------------
//   showComboStats / showPartStats  a mini dialog (InfoChip's popup style):
//       the minified combo (or the part), the compact radar, its numbers and
//       "Detailed graph".
//   StatGraphPage                    the graph alone, full screen: the big
//       radar with the toggle and rows, then -- for a combo -- what each part
//       adds, each with its own small radar. Two columns on web / tablets.
//   ComboStatsStrip                  a one-line strip (tiny radar, mass, the
//       top stats) for lists; tap for the mini dialog.
// =============================================================================

/// The full-screen graph of a part or a combo.
class StatGraphPage extends StatelessWidget {
  const StatGraphPage({
    super.key,
    required this.title,
    required this.stats,
    this.subtitle,
    this.mass,
    this.legality,
    this.header,
    this.parts = const [],
    this.description,
  });

  /// A part's graph.
  factory StatGraphPage.part(BeybladePart part, {Key? key}) => StatGraphPage(
        key: key,
        title: part.name,
        subtitle: [
          displayLabelForPartType(partTypeKeyFor(part)),
          part.code,
          if (part.variantLabel != null) part.variantLabel!,
        ].join(' · '),
        stats: part.stats,
        mass: part.mass,
        legality: part.legality,
        description: part.description,
        header: PartImageThumb(
          imageUrl: preferredThumbUrl(part, compact: false),
          size: 72,
          scale: imageScaleFor(part),
        ),
      );

  /// A combo's graph, with what each of its parts adds.
  factory StatGraphPage.combo(Beyblade bey, {Key? key, String? title}) =>
      StatGraphPage(
        key: key,
        title: title ?? bey.nomenclatureName,
        subtitle: 'Combo · ${bey.stackedParts.length} parts',
        stats: bey.combinedStats,
        mass: bey.totalMass,
        legality: bey.legality,
        parts: bey.stackedParts,
        header: SizedBox(width: 280, child: MinifiedBeybladeTile(beyblade: bey)),
      );

  final String title;
  final String? subtitle;
  final StatBlock stats;
  final double? mass;
  final WboLegality? legality;
  final Widget? header;
  final String? description;

  /// A combo's parts, for "What each part adds". Empty for a part.
  final List<BeybladePart> parts;

  /// Pushes [page] (works the same on web, no route to register).
  static Future<void> open(BuildContext context, StatGraphPage page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // One scale for the combo and its parts' small graphs? No: each part has
    // its own range (a ratchet tops out near 20, a blade near 80), so every
    // graph scales to itself and the ring numbers say what the edge is worth.
    return Scaffold(
      appBar: AppBar(title: Text('Stats', overflow: TextOverflow.ellipsis)),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= 980 && parts.isNotEmpty;
          final pad = box.maxWidth >= 600 ? 24.0 : 16.0;

          final intro = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (header != null) ...[header!, const SizedBox(width: 14)],
              Expanded(
                child: HoloSheetHeader(
                  title: title,
                  subtitle: subtitle,
                  icon: Icons.radar,
                ),
              ),
            ],
          );

          final main = HoloStatPanel(
            stats: stats,
            mass: mass,
            legality: legality,
            radarMaxSize: wide ? 460 : 520,
          );

          final about = description == null
              ? null
              : Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: HoloCard(
                    child: Text(description!,
                        style: TextStyle(
                            fontSize: 14, height: 1.45, color: cs.onSurface)),
                  ),
                );

          final breakdown = parts.isEmpty
              ? null
              : _PartBreakdown(parts: parts, combo: stats);

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: wide
                  ? Padding(
                      padding: EdgeInsets.all(pad),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 6,
                            child: SingleChildScrollView(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  intro,
                                  const SizedBox(height: 16),
                                  main,
                                  if (about != null) about,
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 5,
                            child: SingleChildScrollView(child: breakdown),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      padding: EdgeInsets.all(pad),
                      children: [
                        intro,
                        const SizedBox(height: 16),
                        main,
                        if (about != null) about,
                        if (breakdown != null) ...[
                          const SizedBox(height: 20),
                          breakdown,
                        ],
                      ],
                    ),
            ),
          );
        }),
      ),
    );
  }
}

/// "What each part adds": one card per part with its small radar and its
/// share of each combo stat.
class _PartBreakdown extends StatelessWidget {
  const _PartBreakdown({required this.parts, required this.combo});

  final List<BeybladePart> parts;
  final StatBlock combo;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final withStats = [for (final p in parts) if (!p.stats.isEmpty) p];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const HoloSectionLabel(
          title: 'What each part adds',
          subtitle: 'The combo\'s stats are its parts\' stats added up. '
              'Blank counts as 0.',
        ),
        const SizedBox(height: 10),
        if (withStats.isEmpty)
          HoloCard(
            child: Text('None of these parts has stats yet.',
                style: TextStyle(color: cs.onSurfaceVariant)),
          ),
        for (final p in withStats)
          HoloCard(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            onTap: () => StatGraphPage.open(context, StatGraphPage.part(p)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 96,
                  height: 96,
                  child: HoloStatRadar(stats: p.stats, compact: true, maxSize: 96),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        PartImageThumb(
                            imageUrl: preferredThumbUrl(p),
                            size: 28,
                            scale: imageScaleFor(p)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: cs.onSurface)),
                        ),
                        Icon(Icons.chevron_right,
                            size: 18, color: cs.onSurfaceVariant),
                      ]),
                      const SizedBox(height: 4),
                      Text(displayLabelForPartType(partTypeKeyFor(p)),
                          style: TextStyle(
                              fontSize: 11.5, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final k in p.stats.providedKeys)
                            _ShareChip(
                                statKey: k,
                                value: p.stats[k],
                                total: combo[k].value),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ShareChip extends StatelessWidget {
  const _ShareChip(
      {required this.statKey, required this.value, required this.total});
  final StatKey statKey;
  final StatValue value;
  final double total;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = StatStyle.color(context, statKey);
    final pct = total <= 0 ? null : (value.value / total * 100).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 3, 10, 3),
      decoration: ShapeDecoration(
        color: c.withValues(alpha: 0.12),
        shape: ChamferBorder.tab(
            cut: 6, side: BorderSide(color: c.withValues(alpha: 0.5))),
      ),
      child: Text(
        '${statKey.shortLabel} ${value.format()}${pct == null ? '' : ' · $pct%'}',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: cs.onSurface,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

// ── MINI DIALOG ──────────────────────────────────────────────────────────────

/// A combo's stats in a mini dialog: its minified tile, the compact radar,
/// the numbers and "Detailed graph".
Future<void> showComboStats(BuildContext context, Beyblade bey,
        {String? title}) =>
    _showStats(
      context,
      title: title ?? bey.nomenclatureName,
      stats: bey.combinedStats,
      // the minified tile already shows the mass and legality
      header: MinifiedBeybladeTile(beyblade: bey),
      detailed: StatGraphPage.combo(bey, title: title),
    );

/// A part's stats in a mini dialog.
Future<void> showPartStats(BuildContext context, BeybladePart part) =>
    _showStats(
      context,
      title: part.name,
      stats: part.stats,
      mass: part.mass,
      legality: part.legality,
      header: Row(children: [
        PartImageThumb(
            imageUrl: preferredThumbUrl(part), size: 44, scale: imageScaleFor(part)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            [displayLabelForPartType(partTypeKeyFor(part)), part.code].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
      detailed: StatGraphPage.part(part),
    );

Future<void> _showStats(
  BuildContext context, {
  required String title,
  required StatBlock stats,
  required Widget header,
  required StatGraphPage detailed,
  double? mass,
  WboLegality? legality,
}) {
  final nav = Navigator.of(context);
  return InfoChip.showInfo<void>(
    context,
    title: title,
    icon: Icons.radar,
    builder: (dialogContext) => ConstrainedBox(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.72),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            header,
            const SizedBox(height: 12),
            HoloStatPanel(
              stats: stats,
              mass: mass,
              legality: legality,
              compact: true,
              card: false,
              radarMaxSize: 240,
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: HoloActionButton(
                label: 'Detailed graph',
                icon: Icons.open_in_full,
                dense: true,
                onPressed: () {
                  Navigator.of(dialogContext).pop();
                  nav.push(MaterialPageRoute(builder: (_) => detailed));
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

// ── STRIP ────────────────────────────────────────────────────────────────────

/// One line for lists: a tiny radar, the mass and the top stats. Tap for
/// the mini dialog.
class ComboStatsStrip extends StatelessWidget {
  const ComboStatsStrip({super.key, required this.beyblade, this.onTap});

  final Beyblade beyblade;

  /// Default: [showComboStats].
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = beyblade.combinedStats;
    final top = [...s.providedKeys]
      ..sort((a, b) => s[b].value.compareTo(s[a].value));
    return InkWell(
      onTap: onTap ?? () => showComboStats(context, beyblade),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              height: 64,
              child: HoloStatRadar(stats: s, compact: true, maxSize: 64),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text('${beyblade.totalMass.toStringAsFixed(1)} g',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                          fontFeatures: const [FontFeature.tabularFigures()])),
                  for (final k in top.take(math.min(3, top.length)))
                    Text('${k.shortLabel} ${s[k].format()}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: StatStyle.color(context, k),
                            fontFeatures: const [FontFeature.tabularFigures()])),
                ],
              ),
            ),
            Icon(Icons.radar, size: 18, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
