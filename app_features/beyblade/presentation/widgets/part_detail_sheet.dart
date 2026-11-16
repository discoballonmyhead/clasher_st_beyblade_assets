import 'package:clasher_st/core/responsive/responsive_provider.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/loyalty_badge.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/part_image_thumb.dart';
import 'package:flutter/material.dart';

class PartDetailSheet extends StatelessWidget {
  const PartDetailSheet({super.key, required this.part});

  final BeybladePart part;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    final tt = Theme.of(context).textTheme;
    final stats = _statsOf(part);

    return Padding(
      padding: EdgeInsets.fromLTRB(
          rc.horizontalPadding, 0, rc.horizontalPadding, rc.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PartImageThumb(
                  imageUrl: part.imageUrl,
                  size: 72,
                  scale: imageScaleFor(part)),
              SizedBox(width: rc.sm * 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(part.name, style: tt.titleLarge),
                    Text('${part.code} · id ${part.dataId}',
                        style:
                            tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              LegalityBadge(legality: part.legality),
            ],
          ),
          SizedBox(height: rc.lg),
          _row(context, 'Mass', '${part.mass} g'),
          if (part.edition != null) _row(context, 'Edition', part.edition!),
          if (stats != null) ...[
            SizedBox(height: rc.sm),
            Divider(color: cs.outlineVariant),
            SizedBox(height: rc.sm),
            ...stats.providedKeys.map(
              (key) => _row(
                  context,
                  _label(key),
                  stats[key]
                      .values
                      .map((v) => v.toStringAsFixed(0))
                      .join(' – ')),
            ),
          ],
        ],
      ),
    );
  }

  StatBlock? _statsOf(BeybladePart p) => switch (p) {
        Blade b => b.stats,
        Ratchet r => r.stats,
        Bit b => b.stats,
        LockChip l => l.stats,
        OverBlade o => o.stats,
        MetalBlade m => m.stats,
        MainBlade m => m.stats,
        AssistBlade a => a.stats,
        _ => null,
      };

  String _label(StatKey key) => switch (key) {
        StatKey.attack => 'Attack',
        StatKey.defense => 'Defense',
        StatKey.stamina => 'Stamina',
        StatKey.dash => 'Dash',
        StatKey.burstResistance => 'Burst Resistance',
      };

  Widget _row(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant)),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}
