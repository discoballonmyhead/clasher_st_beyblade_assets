import 'package:clasher_st/core/theme/app_theme.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:flutter/material.dart';

/// Legal / Illegal / Unknown tag. Colours come from HoloTokens so they
/// follow light and dark mode; the fixed AppTheme.success/error/warning
/// constants are the dark-mode set and read poorly on light surfaces.
class LegalityBadge extends StatelessWidget {
  const LegalityBadge({super.key, required this.legality});

  final WboLegality legality;

  @override
  Widget build(BuildContext context) {
    final t = HoloTokens.of(context);
    final (label, color) = switch (legality) {
      WboLegality.legal => ('Legal', t.success),
      WboLegality.illegal => ('Illegal', t.danger),
      WboLegality.unknown => ('Unknown', t.warning),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: ShapeDecoration(
          color: color.withValues(alpha: 0.14), shape: AppTheme.bevelChip),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
