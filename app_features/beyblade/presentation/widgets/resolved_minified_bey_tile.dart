import 'package:clasher_st/core/widgets/app_beyblade_loading_indicator.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/bey_inspect.dart';
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

  /// Defaults to the combo sheet (its parts, each opening the part sheet).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ResolvedBeyBuilder(
      loadout: loadout,
      builder: (context, beyblade) => MinifiedBeybladeTile(
          beyblade: beyblade,
          onTap: onTap ?? () => showComboSheet(context, beyblade: beyblade)),
      loading: (_) => const Card(
          child: Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: BeybladeSpinner()))),
      failed: (_) => const MinifiedBeybladeTile(
          beyblade: null, emptyLabel: 'This build is unavailable'),
    );
  }
}

/// The "view full deck" entry point (participant tile, match card,
/// profile, boards). Now the deck sheet: every combo with its parts, each
/// part opening its sheet and from there its page. One combo opens as a
/// combo sheet. Same signature as before, so callers don't change.
Future<void> showDeckDialog(BuildContext context,
        {required String title, required List<BeybladeLoadout> beys}) =>
    showDeckSheet(context, title: title, beys: beys);
