import 'package:clasher_st/core/widgets/app_beyblade_loading_indicator.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/minified_beyblade_tile.dart';
import 'package:flutter/material.dart';

import 'resolved_bey_thumb.dart';

/// Resolves a loadout and hands it to the real MinifiedBeybladeTile —
/// the actual "showcase the combination" widget, not the smaller
/// ResolvedBeyChip. Needs real width (the connected-tiles grid doesn't
/// compress well), so this is meant for a dialog/sheet context, not
/// crammed into a list row.
class ResolvedMinifiedBeyTile extends StatelessWidget {
  const ResolvedMinifiedBeyTile({super.key, required this.loadout, this.onTap});
  final BeybladeLoadout loadout;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ResolvedBeyBuilder(
      loadout: loadout,
      builder: (context, beyblade) =>
          MinifiedBeybladeTile(beyblade: beyblade, onTap: onTap),
      loading: (_) => const Card(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: BeybladeSpinner()))),
      failed: (_) => const MinifiedBeybladeTile(
          beyblade: null, emptyLabel: 'This build is unavailable'),
    );
  }
}

/// Opens a dialog showing every bey in [deck], each as a full
/// ResolvedMinifiedBeyTile — the "view full deck" entry point used by
/// both the participant tile and the match card, so both get identical
/// treatment rather than two slightly different implementations.
Future<void> showDeckDialog(BuildContext context,
    {required String title, required List<BeybladeLoadout> beys}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < beys.length; i++) ...[
                ResolvedMinifiedBeyTile(loadout: beys[i]),
                if (i != beys.length - 1) const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'))
      ],
    ),
  );
}
