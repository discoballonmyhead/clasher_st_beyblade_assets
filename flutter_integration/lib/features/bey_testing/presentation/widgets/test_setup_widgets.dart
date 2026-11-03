import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/accessory_picker.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/resolved_bey_thumb.dart';
import 'package:flutter/material.dart';

// The accessory picker moved to the beyblade feature so tournaments use the
// same one (features/beyblade/presentation/widgets/accessory_picker.dart).
// Re-exported here, so every testing page keeps its imports:
//   AccessoryPickerSheet / AccessoryChoice / AccessoryName / accessoryTypeLabel
export 'package:clasher_st/features/beyblade/presentation/widgets/accessory_picker.dart';

// Testing-only pieces:
//   SetupTile             one "Stadium: X" row that opens the picker
//   TestBeyName           a build's name from its part data ids

/// "Stadium · Xtreme Stadium ›" row; tap to change.
class SetupTile extends StatelessWidget {
  const SetupTile({
    super.key,
    required this.icon,
    required this.label,
    required this.dataId,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String? dataId;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: cs.primary),
            const SizedBox(width: 12),
            SizedBox(
              width: 96,
              child: Text(label,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            ),
            Expanded(
              child: AccessoryName(
                dataId: dataId,
                fallback: 'Not set',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: dataId == null ? cs.onSurfaceVariant : cs.onSurface),
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// A build's display name from its part data ids.
class TestBeyName extends StatelessWidget {
  const TestBeyName({
    super.key,
    required this.loadout,
    this.style,
    this.prefix = '',
  });

  final BeybladeLoadout? loadout;
  final TextStyle? style;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    final l = loadout;
    Text text(String s) =>
        Text('$prefix$s', maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    if (l == null) return text('Unknown build');
    return ResolvedBeyBuilder(
      loadout: l,
      builder: (context, bey) => text(bey.nomenclatureName),
      loading: (_) => text('…'),
      failed: (_) => text('Unavailable build'),
    );
  }
}
