import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:flutter/material.dart';

import 'beyblade_builder_content.dart';

/// Opens the bey builder as a tall bottom sheet and returns the confirmed
/// loadout, or null when dismissed. One entry point for every screen that
/// lets someone build a bey (deck registration, walk-ins, testing), so they
/// all behave the same.
class BeyBuilderSheet {
  BeyBuilderSheet._();

  static Future<BeybladeLoadout?> show(
    BuildContext context, {
    BeybladeLoadout? initialLoadout,
  }) async {
    final rc = ResponsiveProvider.config(context);
    final bey = await showModalBottomSheet<Beyblade>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SizedBox(
        height: MediaQuery.sizeOf(sheetContext).height * 0.9,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              rc.horizontalPadding, rc.md, rc.horizontalPadding, 0),
          child: BeybladeBuilderContent(
            initialLoadout: initialLoadout,
            onConfirm: (b) => Navigator.of(sheetContext).pop(b),
          ),
        ),
      ),
    );
    return bey?.loadout;
  }
}
