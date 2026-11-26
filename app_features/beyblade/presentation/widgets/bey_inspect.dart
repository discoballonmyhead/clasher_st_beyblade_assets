import 'package:clasher_st/core/widgets/app_beyblade_loading_indicator.dart';
import 'package:clasher_st/features/beyblade/b_routes/beyblade_routes.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/presentation/pages/detail_page.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/minified_beyblade_tile.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/part_detail_sheet.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/part_image_thumb.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/resolved_bey_thumb.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

// =============================================================================
// ONE WAY TO LOOK AT A PART, A COMBO OR A DECK, EVERYWHERE
// -----------------------------------------------------------------------------
//   part  -> showPartSheet: the part at a glance, and an arrow to its page
//   combo -> showComboSheet: the bey and each of its parts; tap a part for
//            its sheet (then the arrow to its page)
//   deck  -> showDeckSheet: every combo with its parts, same chain
// All sheets scroll and every text wraps or shortens, so long names never
// overflow. showDeckDialog (resolved_minified_bey_tile.dart) and a
// ResolvedMinifiedBeyTile without its own onTap open these, so tournament
// pages, match cards, profiles and the boards all behave the same.
// =============================================================================

/// Opens the part's own page (stats, the products it came in ...).
void openPartPage(BuildContext context, BeybladePart part) {
  context.push(BeybladeRoutes.detail,
      extra: PartDetailSubject(part, partTypeKeyFor(part)));
}

Future<T?> _sheet<T>(BuildContext context,
    {required Widget Function(BuildContext, ScrollController) builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.62,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: builder,
    ),
  );
}

/// The part at a glance; the arrow / "Full details" opens its page.
Future<void> showPartSheet(BuildContext context, BeybladePart part) {
  // Navigate with the context that opened the sheet: the sheet's own
  // context is gone once it closes.
  final router = GoRouter.of(context);
  return _sheet<void>(
    context,
    builder: (sheetContext, scroll) => ListView(
      controller: scroll,
      children: [
        PartDetailSheet(
          part: part,
          onOpenDetails: () {
            Navigator.of(sheetContext).pop();
            router.push(BeybladeRoutes.detail,
                extra: PartDetailSubject(part, partTypeKeyFor(part)));
          },
        ),
      ],
    ),
  );
}

/// A combo: its tile, then each part (tap for the part sheet). Pass the
/// resolved [beyblade] when you have it, or the [loadout] to resolve.
Future<void> showComboSheet(
  BuildContext context, {
  Beyblade? beyblade,
  BeybladeLoadout? loadout,
  String? title,
}) {
  assert(beyblade != null || loadout != null);
  return _sheet<void>(
    context,
    builder: (sheetContext, scroll) => ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        if (title != null) _Heading(title),
        beyblade != null
            ? _ComboBody(beyblade: beyblade, showTile: true)
            : ResolvedBeyBuilder(
                loadout: loadout!,
                builder: (_, bey) => _ComboBody(beyblade: bey, showTile: true),
                loading: (_) => const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: BeybladeSpinner())),
                failed: (_) => const _Unavailable(),
              ),
      ],
    ),
  );
}

/// A deck: each combo with its parts, open by default when there are
/// three or fewer. One combo opens straight as a combo sheet.
Future<void> showDeckSheet(
  BuildContext context, {
  required String title,
  required List<BeybladeLoadout> beys,
}) {
  if (beys.length == 1) {
    return showComboSheet(context, loadout: beys.first, title: title);
  }
  return _sheet<void>(
    context,
    builder: (sheetContext, scroll) => ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _Heading(title),
        if (beys.isEmpty) const _Unavailable(),
        for (var i = 0; i < beys.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: ResolvedBeyBuilder(
                loadout: beys[i],
                builder: (_, bey) => ExpansionTile(
                  initiallyExpanded: beys.length <= 3,
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                  childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  leading: CircleAvatar(
                    radius: 14,
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w800)),
                  ),
                  title: Text(bey.nomenclatureName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  children: [_ComboBody(beyblade: bey, showTile: false)],
                ),
                loading: (_) => const Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: BeybladeSpinner())),
                failed: (_) => const _Unavailable(),
              ),
            ),
          ),
      ],
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge),
      );
}

class _Unavailable extends StatelessWidget {
  const _Unavailable();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Text('This build is unavailable on this device.',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

/// The bey's tile (optional) and one tappable row per part.
class _ComboBody extends StatelessWidget {
  const _ComboBody({required this.beyblade, required this.showTile});

  final Beyblade beyblade;
  final bool showTile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showTile) ...[
          // No onTap: we're already showing this combo.
          MinifiedBeybladeTile(beyblade: beyblade),
          const SizedBox(height: 12),
          Text(beyblade.nomenclatureName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
        ],
        for (final part in beyblade.stackedParts) PartRow(part: part),
      ],
    );
  }
}

/// One part as a list row: picture, name, type; tap for its sheet.
class PartRow extends StatelessWidget {
  const PartRow({super.key, required this.part, this.onTap});

  final BeybladePart part;

  /// Defaults to the part sheet.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap ?? () => showPartSheet(context, part),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(children: [
          PartImageThumb(
            imageUrl: preferredThumbUrl(part),
            size: 44,
            scale: imageScaleFor(part),
            borderRadius: BorderRadius.circular(8),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(part.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(displayLabelForPartType(partTypeKeyFor(part)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        ]),
      ),
    );
  }
}
