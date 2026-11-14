import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:flutter/material.dart';

class StatBarRow extends StatelessWidget {
  const StatBarRow(
      {super.key,
      required this.label,
      required this.spread,
      this.maxValue,
      this.color});

  final String label;
  final StatSpread spread;
  final double? maxValue;

  /// Per-stat color (Attack red, Defense blue, ...) -- when omitted,
  /// falls back to the theme's primary color, so existing call sites
  /// that don't pass one keep working unchanged.
  final Color? color;

  double get _fillValue {
    if (!spread.isProvided) return 0;
    final values = spread.values;
    return values.reduce((a, b) => a + b) / values.length;
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final valueText = spread.isProvided
        ? spread.values.map((v) => v.toStringAsFixed(0)).join(' – ')
        : 'N/A';
    final fraction = (maxValue == null || maxValue == 0)
        ? 0.0
        : (_fillValue / maxValue!).clamp(0.0, 1.0);
    final barColor = color ?? cs.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
              Text(valueText,
                  style: tt.titleSmall?.copyWith(
                      color: spread.isProvided ? null : cs.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: fraction),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor: cs.surfaceContainerHighest,
                color: spread.isProvided ? barColor : cs.outlineVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
