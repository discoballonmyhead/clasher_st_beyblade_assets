import 'dart:math' as math;

import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/loyalty_badge.dart';
import 'package:flutter/material.dart';

import 'holo_stat_radar.dart';
import 'holo_stat_rows.dart';
import 'stat_style.dart';

// =============================================================================
// HOLO STAT PANEL
// -----------------------------------------------------------------------------
// Radar + rows in a HoloCard, the one stat block every screen uses:
//   part page, part sheet, builder, combo sheet, the full graph page.
//
//   * Wide (>= 560px of its own width, e.g. web): radar left, rows right.
//     Narrow: radar on top, rows under it. Decided from the panel's own
//     constraints, so a panel in a side pane lays out like a phone.
//   * Two-number stats get a toggle (Both / Start / End, or Both / Mode 1 /
//     Mode 2) and the mode badges.
//   * Tapping an axis or a row highlights that stat in both.
//   * [compact]: smaller radar, short labels, no toggle -- for sheets and
//     cards; [onOpenDetailed] adds the "Detailed graph" action.
// =============================================================================

class HoloStatPanel extends StatefulWidget {
  const HoloStatPanel({
    super.key,
    required this.stats,
    this.scale = const StatScale.auto(),
    this.mass,
    this.legality,
    this.compact = false,
    this.onOpenDetailed,
    this.radarMaxSize,
    this.showRows = true,
    this.card = true,
  });

  final StatBlock stats;
  final StatScale scale;

  /// Shown in the header next to the legality, when given (weight is not a
  /// radar axis).
  final double? mass;
  final WboLegality? legality;

  final bool compact;
  final VoidCallback? onOpenDetailed;

  /// Caps the radar; default 340 (compact 220).
  final double? radarMaxSize;
  final bool showRows;

  /// Wrap in a HoloCard (off when the caller already has one).
  final bool card;

  @override
  State<HoloStatPanel> createState() => _HoloStatPanelState();
}

class _HoloStatPanelState extends State<HoloStatPanel> {
  StatPairView _pair = StatPairView.both;
  StatKey? _highlight;

  void _toggle(StatKey k) =>
      setState(() => _highlight = _highlight == k ? null : k);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final stats = widget.stats;
    final names = StatStyle.pairNames(stats);
    final radarMax = widget.radarMaxSize ?? (widget.compact ? 220.0 : 340.0);

    final header = (widget.mass != null ||
            widget.legality != null ||
            widget.onOpenDetailed != null)
        ? Row(
            children: [
              if (widget.mass != null) ...[
                Icon(Icons.scale_outlined, size: 16, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Text(
                  '${_mass(widget.mass!)} g',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 10),
              ],
              if (widget.legality != null)
                LegalityBadge(legality: widget.legality!),
              const Spacer(),
              if (widget.onOpenDetailed != null)
                HoloActionButton(
                  label: 'Detailed graph',
                  icon: Icons.open_in_full,
                  dense: true,
                  variant: HoloButtonVariant.outline,
                  onPressed: widget.onOpenDetailed,
                ),
            ],
          )
        : null;

    final toggle = !widget.compact && stats.hasTwo
        ? HoloSegmented<StatPairView>(
            options: [
              const HoloOption(StatPairView.both, 'Both'),
              HoloOption(StatPairView.first, names.$1),
              HoloOption(StatPairView.second, names.$2),
            ],
            value: _pair,
            onChanged: (v) => setState(() => _pair = v),
          )
        : null;

    final shown = switch (_pair) {
      StatPairView.both => stats,
      StatPairView.first => stats.firstOnly,
      StatPairView.second => stats.secondOnly,
    };

    Widget radar(double max) => HoloStatRadar(
          stats: stats,
          pair: _pair,
          scale: widget.scale,
          compact: widget.compact,
          maxSize: max,
          highlight: _highlight,
          onAxisTap: _toggle,
        );

    Widget rows() => HoloStatRows(
          stats: shown,
          scale: widget.scale,
          dense: widget.compact,
          highlight: _highlight,
          onTap: _toggle,
        );

    final body = LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final wide = w >= 560 && widget.showRows;
      if (wide) {
        final rw = math.min(radarMax, w * 0.46);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(width: rw, height: rw, child: radar(rw)),
            const SizedBox(width: 20),
            Expanded(child: rows()),
          ],
        );
      }
      final rw = math.min(radarMax, w);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: SizedBox(width: rw, height: rw, child: radar(rw))),
          if (widget.showRows) ...[
            const SizedBox(height: 8),
            rows(),
          ],
        ],
      );
    });

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (header != null) ...[header, const SizedBox(height: 10)],
        if (stats.hasTwo) ...[
          HoloStatModeBadges(stats: stats),
          const SizedBox(height: 10),
        ],
        if (toggle != null) ...[toggle, const SizedBox(height: 12)],
        body,
      ],
    );

    if (!widget.card) return content;
    return HoloCard(
      padding: EdgeInsets.all(widget.compact ? 12 : 16),
      child: content,
    );
  }

  static String _mass(double m) =>
      m == m.roundToDouble() ? m.toStringAsFixed(0) : m.toStringAsFixed(1);
}
