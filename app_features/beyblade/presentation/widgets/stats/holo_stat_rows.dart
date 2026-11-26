import 'package:clasher_st/core/widgets/app_info_chip.dart';
import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:flutter/material.dart';

import 'stat_style.dart';

// =============================================================================
// HOLO STAT ROWS + MODE BADGES
// -----------------------------------------------------------------------------
// The radar shows a shape; these rows give the numbers. One row per stat:
// a colour tab, the label, the value with tabular figures and a square track
// whose fill ends in a slant (HoloProgressBar's look). A two-number stat
// fills to its first number and outlines the rest of the way to its second,
// so "25 › 55" and "25 | 55" read at a glance without a second bar.
// =============================================================================

class HoloStatRows extends StatelessWidget {
  const HoloStatRows({
    super.key,
    required this.stats,
    this.scale = const StatScale.auto(),
    this.keys,
    this.dense = false,
    this.highlight,
    this.onTap,
    this.animate = true,
  });

  final StatBlock stats;
  final StatScale scale;

  /// Which stats, in order. Default: all six (blank ones read 0, dimmed).
  final List<StatKey>? keys;

  /// Shorter rows and short labels, for sheets and narrow cards.
  final bool dense;
  final StatKey? highlight;
  final ValueChanged<StatKey>? onTap;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final max = scale.maxFor([stats]);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final k in keys ?? StatKey.values)
          HoloStatRow(
            statKey: k,
            value: stats[k],
            max: max,
            dense: dense,
            highlighted: highlight == k,
            onTap: onTap == null ? null : () => onTap!(k),
            animate: animate,
          ),
      ],
    );
  }
}

class HoloStatRow extends StatelessWidget {
  const HoloStatRow({
    super.key,
    required this.statKey,
    required this.value,
    required this.max,
    this.dense = false,
    this.highlighted = false,
    this.onTap,
    this.animate = true,
  });

  final StatKey statKey;
  final StatValue value;
  final double max;
  final bool dense;
  final bool highlighted;
  final VoidCallback? onTap;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = StatStyle.color(context, statKey);
    final provided = value.isProvided;
    final f1 = max <= 0 ? 0.0 : (value.value / max).clamp(0.0, 1.0);
    final f2 = max <= 0 ? 0.0 : (value.secondValue / max).clamp(0.0, 1.0);

    final row = Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 5 : 7, horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 10,
                height: 10,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: provided ? color : cs.outlineVariant,
                    shape: const ChamferBorder.tab(cut: 3),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  (dense ? statKey.shortLabel : statKey.label).toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: dense ? 10.5 : 11.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: highlighted ? color : cs.onSurfaceVariant,
                  ),
                ),
              ),
              if (value.hasTwo) ...[
                Tooltip(
                  message: value.explanation ?? '',
                  child: Icon(
                    value.isDynamic ? Icons.trending_up : Icons.swap_horiz,
                    size: 14,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                value.format(blank: '0'),
                style: TextStyle(
                  fontSize: dense ? 12.5 : 14,
                  fontWeight: FontWeight.w800,
                  color: provided ? cs.onSurface : cs.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          SizedBox(height: dense ? 4 : 6),
          SizedBox(
            height: dense ? 5 : 6,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: animate ? 0 : 1, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) => CustomPaint(
                painter: _TrackPainter(
                  first: f1 * t,
                  second: value.hasTwo ? f2 * t : null,
                  color: provided ? color : cs.outlineVariant,
                  track: cs.surfaceContainerHighest,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return Semantics(
      label: '${statKey.label}: ${value.format(blank: '0')}'
          '${value.explanation == null ? '' : '. ${value.explanation}'}',
      excludeSemantics: true,
      button: onTap != null,
      child: onTap == null
          ? row
          : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(6), child: row),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter(
      {required this.first,
      required this.second,
      required this.color,
      required this.track});

  final double first;
  final double? second;
  final Color color, track;

  Path _bar(Size size, double f) {
    final w = size.width * f;
    final slant = f >= 1 ? 0.0 : size.height.clamp(0.0, w);
    return Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w - slant, size.height)
      ..lineTo(0, size.height)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = track);
    final s = second;
    if (s != null && s > first) {
      // the way to the second number: outlined
      canvas.drawPath(
          _bar(size, s),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = color.withValues(alpha: 0.9));
      canvas.drawPath(_bar(size, s), Paint()..color = color.withValues(alpha: 0.18));
    }
    canvas.drawPath(_bar(size, first), Paint()..color = color);
    if (s != null && s < first) {
      // the second number is lower: a notch where it lands
      final x = size.width * s;
      canvas.drawRect(Rect.fromLTWH(x - 1, -1, 2, size.height + 2),
          Paint()..color = track.withValues(alpha: 0.95));
    }
  }

  @override
  bool shouldRepaint(_TrackPainter o) =>
      o.first != first || o.second != second || o.color != color || o.track != track;
}

/// "Changes mid-battle" / "Two modes" pills for a part or combo with
/// two-number stats; nothing otherwise. Each pill explains itself on tap.
class HoloStatModeBadges extends StatelessWidget {
  const HoloStatModeBadges({super.key, required this.stats});

  final StatBlock stats;

  @override
  Widget build(BuildContext context) {
    if (!stats.hasTwo) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final tokens = HoloTokens.of(context);
    Widget pill(String label, IconData icon, Color color, String title, String details) =>
        InkWell(
          onTap: () => InfoChip.showInfo<void>(
            context,
            title: title,
            icon: icon,
            builder: (context) => Text(details,
                style: TextStyle(fontSize: 13.5, height: 1.4, color: cs.onSurface)),
          ),
          child: HoloPill(label: label, color: color, icon: icon),
        );
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        if (stats.hasDynamic)
          pill(
            'Changes mid-battle',
            Icons.trending_up,
            tokens.warning,
            'Dynamic stats',
            'Some stats change during the battle (a gimmick). The graph draws '
                'the start as the filled shape and the end as the dashed one; '
                'values read "start › end".',
          ),
        if (stats.hasDualMode)
          pill(
            'Two modes',
            Icons.swap_horiz,
            cs.secondary,
            'Dual-mode stats',
            'This part switches between two modes with different stats. The '
                'graph draws mode 1 filled and mode 2 dashed; values read '
                '"mode 1 | mode 2".',
          ),
      ],
    );
  }
}
