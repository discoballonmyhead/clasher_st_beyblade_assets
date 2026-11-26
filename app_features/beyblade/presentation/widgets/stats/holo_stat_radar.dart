import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:flutter/material.dart';

import 'stat_style.dart';

// =============================================================================
// HOLO STAT RADAR
// -----------------------------------------------------------------------------
// The six stats as a spider graph, in the holow_components vein: a hexagon
// grid with alternating bands, the brand gradient as the shape's fill, a
// stroke in the theme's accent, chamfer-square (diamond) vertices in each
// stat's own colour and 800-weight uppercase axis labels with tabular figures.
//
//   * Grows outward from the centre when it first appears, axis by axis, and
//     eases from the old shape to the new one when the stats change (the
//     builder swapping a part). Reduced-motion settings skip the animation.
//   * Two-number stats draw a second, dashed shape: the end of the battle for
//     a dynamic stat ("25/55"), the other mode for a dual-mode one ("25-55").
//     [pair] shows both, or one of them.
//   * Sizes itself from its constraints (square, capped by [maxSize]), so the
//     same widget works as a 96px thumbnail and as a 520px web hero. Below
//     ~150px it drops to short labels; below ~110px to none.
//   * Blank stats plot as 0. Weight is not an axis (it is shown on its own).
// =============================================================================

/// Which numbers of two-number stats to draw.
enum StatPairView { both, first, second }

class HoloStatRadar extends StatefulWidget {
  const HoloStatRadar({
    super.key,
    required this.stats,
    this.pair = StatPairView.both,
    this.scale = const StatScale.auto(),
    this.compact = false,
    this.maxSize = 420,
    this.highlight,
    this.onAxisTap,
    this.animate = true,
    this.duration = const Duration(milliseconds: 850),
    this.semanticsLabel,
  });

  final StatBlock stats;
  final StatPairView pair;
  final StatScale scale;

  /// Short labels, no values or ring numbers: for tiles, sheets and lists.
  final bool compact;

  /// The graph never grows past this (it is always square).
  final double maxSize;

  /// Draws this axis's spoke and vertex in its colour.
  final StatKey? highlight;

  /// Tap near an axis (or its label).
  final ValueChanged<StatKey>? onAxisTap;

  final bool animate;
  final Duration duration;

  /// Read by screen readers; defaults to every stat with its value.
  final String? semanticsLabel;

  @override
  State<HoloStatRadar> createState() => _HoloStatRadarState();
}

class _HoloStatRadarState extends State<HoloStatRadar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.duration);

  static const _n = 6;
  List<double> _fromA = List.filled(_n, 0), _fromB = List.filled(_n, 0);
  late List<double> _toA, _toB;
  late double _fromMax, _toMax;

  @override
  void initState() {
    super.initState();
    _toA = _targetA();
    _toB = _targetB();
    _toMax = _fromMax = _maxOf();
    _start(fromZero: true);
  }

  @override
  void didUpdateWidget(HoloStatRadar old) {
    super.didUpdateWidget(old);
    if (old.stats != widget.stats ||
        old.pair != widget.pair ||
        old.scale.runtimeType != widget.scale.runtimeType) {
      final t = _progress;
      _fromA = _lerpList(_fromA, _toA, t);
      _fromB = _lerpList(_fromB, _toB, t);
      _fromMax = ui.lerpDouble(_fromMax, _toMax, t)!;
      _toA = _targetA();
      _toB = _targetB();
      _toMax = _maxOf();
      _start(fromZero: false);
    }
  }

  void _start({required bool fromZero}) {
    final reduce = WidgetsBinding.instance.platformDispatcher
        .accessibilityFeatures.disableAnimations;
    if (!widget.animate || reduce) {
      _c.value = 1;
    } else {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double get _progress => Curves.easeOutCubic.transform(_c.value);

  StatBlock get _a => switch (widget.pair) {
        StatPairView.second => widget.stats.secondOnly,
        _ => widget.stats.firstOnly,
      };

  bool get _showB => widget.pair == StatPairView.both && widget.stats.hasTwo;

  List<double> _targetA() => [for (final k in StatKey.values) _a.value(k)];
  List<double> _targetB() => _showB
      ? [for (final k in StatKey.values) widget.stats[k].secondValue]
      : _targetA();

  double _maxOf() => widget.scale.maxFor([widget.stats]);

  static List<double> _lerpList(List<double> a, List<double> b, double t) =>
      [for (var i = 0; i < a.length; i++) a[i] + (b[i] - a[i]) * t];

  String _semantics() =>
      widget.semanticsLabel ??
      'Stats: ${StatKey.values.map((k) => '${k.label} ${widget.stats[k].format(blank: '0')}').join(', ')}';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final palette = _RadarPalette(
      fill: StatStyle.fill(context),
      stroke: StatStyle.stroke(context),
      second: StatStyle.secondStroke(context),
      grid: cs.outlineVariant,
      outer: cs.outline,
      band: cs.surfaceContainerHighest,
      surface: cs.surface,
      label: cs.onSurfaceVariant,
      value: cs.onSurface,
      axis: {for (final k in StatKey.values) k: StatStyle.color(context, k)},
    );
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.3);
    // Canvas text doesn't inherit the theme: hand the painter the app's font.
    final baseStyle = DefaultTextStyle.of(context)
        .style
        .merge(Theme.of(context).textTheme.labelSmall)
        .copyWith(fontSize: 10, height: 1.1, letterSpacing: 0, decoration: TextDecoration.none);

    return LayoutBuilder(builder: (context, box) {
      final w = box.hasBoundedWidth ? box.maxWidth : widget.maxSize;
      final h = box.hasBoundedHeight ? box.maxHeight : w;
      final side = math.min(math.min(w, h), widget.maxSize);
      final compact = widget.compact || side < 200;

      return Semantics(
        label: _semantics(),
        container: true,
        image: true,
        child: SizedBox.square(
          dimension: side,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: widget.onAxisTap == null
                ? null
                : (d) {
                    final k = _axisAt(d.localPosition, side);
                    if (k != null) widget.onAxisTap!(k);
                  },
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final t = _c.value;
                return CustomPaint(
                  painter: _RadarPainter(
                    t: t,
                    a: _lerpList(_fromA, _toA, _progress),
                    b: _lerpList(_fromB, _toB, _progress),
                    showB: _showB,
                    max: ui.lerpDouble(_fromMax, _toMax, _progress)!,
                    stats: widget.stats,
                    pair: widget.pair,
                    compact: compact,
                    tiny: side < 150,
                    noLabels: side < 110,
                    highlight: widget.highlight,
                    palette: palette,
                    textScale: textScale.toDouble(),
                    textDirection: Directionality.of(context),
                    baseStyle: baseStyle,
                  ),
                );
              },
            ),
          ),
        ),
      );
    });
  }

  StatKey? _axisAt(Offset p, double side) {
    final c = Offset(side / 2, side / 2);
    final d = p - c;
    if (d.distance > side / 2) return null;
    var ang = math.atan2(d.dy, d.dx) + math.pi / 2; // 0 = top, clockwise
    if (ang < 0) ang += 2 * math.pi;
    final i = ((ang / (2 * math.pi / _n)) + 0.5).floor() % _n;
    return StatKey.values[i];
  }
}

class _RadarPalette {
  const _RadarPalette({
    required this.fill,
    required this.stroke,
    required this.second,
    required this.grid,
    required this.outer,
    required this.band,
    required this.surface,
    required this.label,
    required this.value,
    required this.axis,
  });

  final Gradient fill;
  final Color stroke, second, grid, outer, band, surface, label, value;
  final Map<StatKey, Color> axis;
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.t,
    required this.a,
    required this.b,
    required this.showB,
    required this.max,
    required this.stats,
    required this.pair,
    required this.compact,
    required this.tiny,
    required this.noLabels,
    required this.highlight,
    required this.palette,
    required this.textScale,
    required this.textDirection,
    required this.baseStyle,
  });

  final TextStyle baseStyle;
  final double t;
  final List<double> a, b;
  final bool showB;
  final double max;
  final StatBlock stats;
  final StatPairView pair;
  final bool compact, tiny, noLabels;
  final StatKey? highlight;
  final _RadarPalette palette;
  final double textScale;
  final TextDirection textDirection;

  static const _n = 6;
  static double _angle(int i) => -math.pi / 2 + i * 2 * math.pi / _n;

  /// Per-axis progress: each axis starts a little after the previous one,
  /// so the shape unfolds around the graph instead of popping in.
  double _axisT(int i) {
    const stagger = 0.06;
    final start = i * stagger;
    final v = ((t - start) / (1 - stagger * (_n - 1))).clamp(0.0, 1.0);
    return Curves.easeOutBack.transform(v).clamp(0.0, 1.08);
  }

  Offset _point(Offset c, double r, int i, double fraction) => Offset(
      c.dx + math.cos(_angle(i)) * r * fraction,
      c.dy + math.sin(_angle(i)) * r * fraction);

  Path _polygon(Offset c, double r, List<double> values) {
    final path = Path();
    for (var i = 0; i < _n; i++) {
      final f = (values[i] / max).clamp(0.0, 1.06) * _axisT(i);
      final p = _point(c, r, i, f);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  Path _ring(Offset c, double r, double fraction) {
    final path = Path();
    for (var i = 0; i < _n; i++) {
      final p = _point(c, r, i, fraction);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  double _width = 0;

  @override
  void paint(Canvas canvas, Size size) {
    _width = size.width;
    final side = size.shortestSide;
    final c = size.center(Offset.zero);
    final pad = noLabels
        ? side * 0.04
        : tiny
            ? side * 0.16
            : compact
                ? side * 0.17
                : math.max(34.0 * textScale, side * 0.2);
    final r = side / 2 - pad;
    if (r <= 4) return;
    final gridIn = Curves.easeOut.transform((t * 2.5).clamp(0.0, 1.0));

    // ── grid: alternating bands, rings, spokes ──
    const rings = [0.25, 0.5, 0.75, 1.0];
    for (var i = rings.length - 1; i >= 0; i--) {
      final band = Paint()
        ..color = (i.isEven ? palette.band : palette.surface)
            .withValues(alpha: (i.isEven ? 0.45 : 0.0) * gridIn);
      canvas.drawPath(_ring(c, r, rings[i]), band);
    }
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = palette.grid.withValues(alpha: 0.7 * gridIn);
    for (final f in rings.take(3)) {
      canvas.drawPath(_ring(c, r, f), ringPaint);
    }
    canvas.drawPath(
        _ring(c, r, 1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = compact ? 1.2 : 1.5
          ..strokeJoin = StrokeJoin.miter
          ..color = palette.outer.withValues(alpha: gridIn));
    for (var i = 0; i < _n; i++) {
      final k = StatKey.values[i];
      final hl = highlight == k;
      canvas.drawLine(
          c,
          _point(c, r, i, 1),
          Paint()
            ..strokeWidth = hl ? 2 : 1
            ..color = (hl ? palette.axis[k]! : palette.grid)
                .withValues(alpha: (hl ? 1 : 0.6) * gridIn));
    }

    // ── ring values (detailed only): along the top spoke ──
    if (!compact) {
      for (final f in rings) {
        final p = _point(c, r, 0, f);
        _text(canvas, _fmt(max * f), p + const Offset(5, -1),
            size: 9.5, weight: FontWeight.w600, color: palette.label,
            alpha: 0.85 * gridIn, align: _Align.left);
      }
    }

    final rect = Rect.fromCircle(center: c, radius: r);

    // ── second shape: end of battle / the other mode, dashed ──
    if (showB) {
      final pb = _polygon(c, r, b);
      canvas.drawPath(pb, Paint()..color = palette.second.withValues(alpha: 0.10));
      _dashed(
          canvas,
          pb,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = compact ? 1.4 : 1.8
            ..strokeJoin = StrokeJoin.miter
            ..color = palette.second);
    }

    // ── main shape ──
    final pa = _polygon(c, r, a);
    canvas.drawPath(pa, Paint()..shader = palette.fill.createShader(rect));
    canvas.drawPath(
        pa,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = compact ? 1.6 : 2.2
          ..strokeJoin = StrokeJoin.miter
          ..color = palette.stroke);

    // ── vertices: chamfer squares in each stat's colour ──
    final vs = tiny ? 2.6 : (compact ? 3.2 : 4.2);
    for (var i = 0; i < _n; i++) {
      final k = StatKey.values[i];
      final f = (a[i] / max).clamp(0.0, 1.06) * _axisT(i);
      final p = _point(c, r, i, f);
      final s = highlight == k ? vs * 1.45 : vs;
      final d = Path()
        ..moveTo(p.dx, p.dy - s)
        ..lineTo(p.dx + s, p.dy)
        ..lineTo(p.dx, p.dy + s)
        ..lineTo(p.dx - s, p.dy)
        ..close();
      canvas.drawPath(d, Paint()..color = palette.axis[k]!);
      canvas.drawPath(
          d,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = palette.surface);
    }

    // ── axis labels ──
    if (noLabels) return;
    for (var i = 0; i < _n; i++) {
      final k = StatKey.values[i];
      final ang = _angle(i);
      final anchor = _point(c, r + (compact ? 9 : 14), i, 1);
      final align = math.cos(ang).abs() < 0.2
          ? _Align.center
          : (math.cos(ang) > 0 ? _Align.left : _Align.right);
      final up = math.sin(ang) < -0.5; // the top axis: text above the point
      final hl = highlight == k;
      final title = compact ? k.shortLabel : k.axisLabel.toUpperCase();
      final titleSize = (tiny ? 8.5 : (compact ? 9.5 : 10.5));
      final value = stats[k];
      final valueText = _valueText(value);
      if (compact) {
        _text(canvas, title, anchor + Offset(0, up ? -titleSize : -titleSize / 2),
            size: titleSize, weight: FontWeight.w800,
            color: hl ? palette.axis[k]! : palette.label, align: align,
            spacing: 0.6, alpha: gridIn);
      } else {
        final lineH = 13.0 * textScale;
        final top = up ? anchor.dy - lineH * 2 : anchor.dy - lineH;
        _text(canvas, title, Offset(anchor.dx, top),
            size: titleSize, weight: FontWeight.w800,
            color: hl ? palette.axis[k]! : palette.label, align: align,
            spacing: 0.8, alpha: gridIn, maxWidth: pad * 2.6);
        _text(canvas, valueText, Offset(anchor.dx, top + lineH),
            size: 12.5, weight: FontWeight.w800,
            color: value.isProvided ? palette.value : palette.label,
            align: align, tabular: true, alpha: gridIn, maxWidth: pad * 2.6);
      }
    }
  }

  String _valueText(StatValue v) {
    if (!v.isProvided) return '0';
    return switch (pair) {
      StatPairView.first => _fmt(v.value),
      StatPairView.second => _fmt(v.secondValue),
      StatPairView.both => v.format(),
    };
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  void _dashed(Canvas canvas, Path path, Paint paint) {
    const dash = 5.0, gap = 4.0;
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + dash, m.length)), paint);
        d += dash + gap;
      }
    }
  }

  void _text(Canvas canvas, String s, Offset at,
      {required double size,
      required FontWeight weight,
      required Color color,
      _Align align = _Align.center,
      double spacing = 0,
      bool tabular = false,
      double alpha = 1,
      double? maxWidth}) {
    final tp = TextPainter(
      text: TextSpan(
        text: s,
        style: baseStyle.copyWith(
          fontSize: size * textScale,
          fontWeight: weight,
          letterSpacing: spacing,
          height: 1.1,
          color: color.withValues(alpha: color.a * alpha),
          fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
        ),
      ),
      textDirection: textDirection,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth ?? double.infinity);
    final x = switch (align) {
      _Align.left => at.dx,
      _Align.right => at.dx - tp.width,
      _Align.center => at.dx - tp.width / 2,
    };
    // never past the graph's edges (narrow graphs, large text)
    final dx = x.clamp(0.0, math.max(0.0, _width - tp.width)).toDouble();
    tp.paint(canvas, Offset(dx, at.dy));
    tp.dispose();
  }

  @override
  bool shouldRepaint(_RadarPainter o) =>
      o.t != t ||
      o.max != max ||
      o.showB != showB ||
      o.compact != compact ||
      o.highlight != highlight ||
      o.pair != pair ||
      o.stats != stats ||
      o.textScale != textScale ||
      o.baseStyle != baseStyle ||
      !_same(o.a, a) ||
      !_same(o.b, b);

  static bool _same(List<double> x, List<double> y) {
    for (var i = 0; i < x.length; i++) {
      if (x[i] != y[i]) return false;
    }
    return true;
  }
}

enum _Align { left, right, center }
