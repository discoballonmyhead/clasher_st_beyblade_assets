import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/theme/app_theme.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/loyalty_badge.dart';
import 'package:flutter/material.dart';

import 'part_image_thumb.dart';

/// One part in a list. Shows what tells look-alike parts apart: the
/// variant label (recolour, special edition), the generation and the
/// manufacturer (a Hasbro and a Takara Tomy release of the same part),
/// and a caution marker when the part's data isn't verified yet.
class PartListTile extends StatelessWidget {
  const PartListTile(
      {super.key, required this.part, this.onTap, this.selected = false});

  final BeybladePart part;
  final VoidCallback? onTap;

  /// Highlights this tile — used by the builder's pickers to show which
  /// part (if any) of this type is currently chosen. Ignored by the
  /// plain search page, which never has a "current selection" concept.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final rc = ResponsiveProvider.config(context);
    final variant = part.variantLabel?.trim();
    final meta = <String>[
      if (part.code.trim().isNotEmpty) part.code,
      if (part.mass > 0) '${part.mass}g',
      if (part.hobbyGeneration.trim().isNotEmpty) part.hobbyGeneration,
      if (part.manufacturer.trim().isNotEmpty) part.manufacturer,
      // The simple-ratchet rule, visible where parts are picked.
      //TODO TR THIS
      if (part case Ratchet(isSimple: true)) 'simple ratchet',
      if (part
          case Blade(requiresSimpleRatchet: true) ||
              AssistBlade(requiresSimpleRatchet: true))
        'needs simple ratchet',
    ];

    // Material, not a coloured Container: ListTile paints its ink on the
    // nearest Material, and debug builds assert when a colour sits between.
    return Material(
      color: selected
          ? cs.primaryContainer.withValues(alpha: 0.5)
          : Colors.transparent,
      child: ListTile(
        contentPadding:
            EdgeInsets.symmetric(horizontal: rc.sm, vertical: rc.sm / 2),
        leading: PartImageThumb(
            imageUrl: preferredThumbUrl(part), scale: imageScaleFor(part)),
        title: Text.rich(
          TextSpan(children: [
            TextSpan(text: part.name),
            if (variant != null && variant.isNotEmpty)
              TextSpan(
                text: '  $variant',
                style: TextStyle(
                    color: cs.onSurfaceVariant, fontWeight: FontWeight.w500),
              ),
          ]),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: tt.titleSmall,
        ),
        subtitle: Row(
          children: [
            Flexible(
              child: Text(
                meta.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            if (part.isIncomplete) ...[
              const SizedBox(width: 4),
              Tooltip(
                //TODO TR THIS
                message: 'Data for this part is not verified yet',
                child: Icon(Icons.report_outlined,
                    size: 14, color: HoloTokens.of(context).warning),
              ),
            ],
          ],
        ),
        trailing: selected
            ? Icon(Icons.check_circle, color: cs.primary)
            : LegalityBadge(legality: part.legality),
        onTap: onTap,
      ),
    );
  }
}
