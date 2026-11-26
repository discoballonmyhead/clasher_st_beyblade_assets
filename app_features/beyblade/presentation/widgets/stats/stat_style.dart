import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:flutter/material.dart';

// =============================================================================
// STAT STYLE
// -----------------------------------------------------------------------------
// One place for how a stat looks: its colour, icon and the scale a graph
// uses. Every stat widget (radar, rows, panel, the full graph page) reads
// from here, so Attack is the same red on a part page, in the builder and in
// a deck sheet. Colours are lifted a little in dark mode so they keep their
// contrast on dark surfaces.
// =============================================================================

class StatStyle {
  StatStyle._();

  static const _light = <StatKey, Color>{
    StatKey.attack: Color(0xFFE5484D),
    StatKey.defense: Color(0xFF3E7BFA),
    StatKey.stamina: Color(0xFF2F9E64),
    StatKey.height: Color(0xFF0E9AA7),
    StatKey.dash: Color(0xFFF2711C),
    StatKey.burstResistance: Color(0xFF8E4EC6),
  };

  static Color color(BuildContext context, StatKey key) {
    final base = _light[key]!;
    return Theme.of(context).brightness == Brightness.dark
        ? Color.lerp(base, Colors.white, 0.18)!
        : base;
  }

  static IconData icon(StatKey key) => switch (key) {
        StatKey.attack => Icons.flash_on_outlined,
        StatKey.defense => Icons.shield_outlined,
        StatKey.stamina => Icons.all_inclusive,
        StatKey.height => Icons.height,
        StatKey.dash => Icons.speed,
        StatKey.burstResistance => Icons.lock_outline,
      };

  /// The polygon's fill: the brand gradient, faded so the grid shows through.
  static Gradient fill(BuildContext context, {double opacity = 0.32}) {
    final g = HoloTokens.of(context).brandGradient;
    if (g is LinearGradient) {
      return LinearGradient(
        begin: g.begin,
        end: g.end,
        stops: g.stops,
        colors: [for (final c in g.colors) c.withValues(alpha: opacity)],
      );
    }
    final p = Theme.of(context).colorScheme.primary;
    return LinearGradient(colors: [
      p.withValues(alpha: opacity),
      p.withValues(alpha: opacity * 0.6),
    ]);
  }

  /// The polygon's outline.
  static Color stroke(BuildContext context) => HoloTokens.of(context).stroke;

  /// The second polygon (end of battle / the other mode).
  static Color secondStroke(BuildContext context) =>
      Theme.of(context).colorScheme.secondary;

  /// Name of the two numbers of a two-number stat, for legends and toggles.
  static (String, String) pairNames(StatBlock stats) => stats.hasDualMode
      ? ('Mode 1', 'Mode 2')
      : ('Start', 'End');
}

/// What a graph's outer ring is worth.
sealed class StatScale {
  const StatScale();

  /// A round number just above the highest stat shown (10, 20, 50, 60 ...),
  /// so the shape fills the graph whatever the part type's range is.
  const factory StatScale.auto({double minimum}) = _AutoScale;

  /// A fixed outer value, e.g. 100 to compare parts on one footing.
  const factory StatScale.fixed(double max) = _FixedScale;

  double maxFor(Iterable<StatBlock> blocks);

  /// Rounds [v] up to a value a ring label reads well at.
  static double niceCeiling(double v) {
    if (v <= 0) return 10;
    final step = v <= 20
        ? 5.0
        : v <= 100
            ? 10.0
            : v <= 200
                ? 20.0
                : 50.0;
    return (v / step).ceil() * step;
  }
}

class _AutoScale extends StatScale {
  const _AutoScale({this.minimum = 10});
  final double minimum;

  @override
  double maxFor(Iterable<StatBlock> blocks) {
    final peak = blocks.fold(0.0, (m, b) => b.peak > m ? b.peak : m);
    final nice = StatScale.niceCeiling(peak);
    return nice < minimum ? minimum : nice;
  }
}

class _FixedScale extends StatScale {
  const _FixedScale(this.max);
  final double max;

  @override
  double maxFor(Iterable<StatBlock> blocks) => max <= 0 ? 1 : max;
}
