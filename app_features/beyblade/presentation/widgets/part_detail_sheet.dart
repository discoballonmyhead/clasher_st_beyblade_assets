import 'package:clasher_st/core/responsive/responsive_provider.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/loyalty_badge.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/part_image_thumb.dart';
import 'package:flutter/material.dart';

/// A part at a glance: picture, name, type, legality, mass, edition and
/// stats. Every text wraps or shortens instead of overflowing, whatever
/// the name / edition length or screen width.
///
/// [onOpenDetails] adds the arrow (and a "Full details" button) that opens
/// the part's own page. Use showPartSheet (bey_inspect.dart) to show it as
/// a scrollable bottom sheet with that wired in.
class PartDetailSheet extends StatelessWidget {
  const PartDetailSheet({super.key, required this.part, this.onOpenDetails});

  final BeybladePart part;
  final VoidCallback? onOpenDetails;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    final tt = Theme.of(context).textTheme;
    final stats = _statsOf(part);
    final type = displayLabelForPartType(partTypeKeyFor(part));

    return Padding(
      padding: EdgeInsets.fromLTRB(
          rc.horizontalPadding, 0, rc.horizontalPadding, rc.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PartImageThumb(
                imageUrl:
                    preferredThumbUrl(part, compact: false) ?? part.imageUrl,
                size: 72,
                scale: imageScaleFor(part),
              ),
              SizedBox(width: rc.sm * 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(part.name,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      [
                        type,
                        if (part.code.trim().isNotEmpty) part.code,
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 6),
                    LegalityBadge(legality: part.legality),
                  ],
                ),
              ),
              if (onOpenDetails != null)
                IconButton(
                  tooltip: 'Full details',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: onOpenDetails,
                ),
            ],
          ),
          SizedBox(height: rc.md),
          _row(context, 'Mass', '${part.mass} g'),
          if ((part.edition ?? '').trim().isNotEmpty)
            _row(context, 'Edition', part.edition!.trim()),
          if ((part.variantLabel ?? '').trim().isNotEmpty)
            _row(context, 'Variant', part.variantLabel!.trim()),
          _row(context, 'Maker', part.manufacturer),
          if (stats != null && stats.providedKeys.isNotEmpty) ...[
            SizedBox(height: rc.xs),
            Divider(color: cs.outlineVariant),
            SizedBox(height: rc.xs),
            for (final key in stats.providedKeys)
              _row(
                context,
                _label(key),
                stats[key].values.map((v) => v.toStringAsFixed(0)).join(' – '),
              ),
          ],
          if (onOpenDetails != null) ...[
            SizedBox(height: rc.md),
            FilledButton.tonalIcon(
              onPressed: onOpenDetails,
              icon: const Icon(Icons.arrow_forward),
              label: const Text('Full details'),
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

  /// Label left, value right; a long value wraps under itself instead of
  /// pushing past the edge.
  Widget _row(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            flex: 2,
            child: Text(label,
                style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ),
          const SizedBox(width: 12),
          Flexible(
            flex: 3,
            child: Text(value,
                textAlign: TextAlign.end,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: tt.titleSmall),
          ),
        ],
      ),
    );
  }
}
