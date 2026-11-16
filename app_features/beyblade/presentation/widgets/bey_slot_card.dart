import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:flutter/material.dart';

import 'part_image_thumb.dart';
import 'resolved_bey_thumb.dart';

// =============================================================================
// BEY SLOT CARD
// -----------------------------------------------------------------------------
// One fixed-height row for a bey in a deck slot, whatever its shape: a
// 3-part unibody build and a 6-part Lock Chip build take the same space,
// parts without images get a placeholder, long names wrap to two lines and
// then ellipsize, and the meta line says which generation and manufacturer
// the parts come from.
// =============================================================================

/// The parts that identify a build at a glance: the top (blade, or lock
/// chip + main/metal blade), the ratchet when there is one, and the bit.
/// Over Blade and Assist Blade are left out, matching the naming rule in
/// Beyblade.nomenclatureName.
List<BeybladePart> keyPartsOf(Beyblade b) {
  final top = switch (b.assembly) {
    UnibodyAssembly(:final blade) => <BeybladePart>[blade],
    SeparatedAssembly(:final lockChip, :final core) => <BeybladePart>[
        lockChip,
        switch (core) {
          MainCore(:final mainBlade) => mainBlade,
          OverMetalCore(:final metalBlade) => metalBlade,
        },
      ],
  };
  return [...top, if (b.ratchet != null) b.ratchet!, b.bit];
}

/// A warning naming two slots that use the same part, or null. Compares
/// part ids directly (cheap, no catalog lookup); the randomizer's stricter
/// variant-aware rule covers random decks.
String? duplicatePartWarning(List<BeybladeLoadout?> beys) {
  final seen = <String, int>{};
  for (var i = 0; i < beys.length; i++) {
    final l = beys[i];
    if (l == null) continue;
    final ids = <String>{
      for (final e in {
        'blade': l.bladeDataId,
        'ratchet': l.ratchetDataId,
        'bit': l.bitDataId,
        'lockChip': l.lockChipDataId,
        'overBlade': l.overBladeDataId,
        'metalBlade': l.metalBladeDataId,
        'mainBlade': l.mainBladeDataId,
        'assistBlade': l.assistBladeDataId,
      }.entries)
        if (e.value != null && e.value!.isNotEmpty) '${e.key}:${e.value}',
    };
    for (final id in ids) {
      final first = seen[id];
      if (first != null) {
        return 'Bey ${first + 1} and Bey ${i + 1} use the same '
            '${id.split(':').first.replaceAllMapped(RegExp('[A-Z]'), (m) => ' ${m[0]!.toLowerCase()}')}. '
            'Tournaments usually allow each part once per deck.';
      }
      seen[id] = i;
    }
  }
  return null;
}

/// Overlapping thumbnails of [parts], each ringed so neighbours stay
/// distinguishable. Width grows by 60 % of [size] per extra part.
class BeyPartsStrip extends StatelessWidget {
  const BeyPartsStrip({super.key, required this.parts, this.size = 40});

  final List<BeybladePart> parts;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final step = size * 0.6;
    final width = parts.isEmpty ? size : size + step * (parts.length - 1);
    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < parts.length; i++)
            Positioned(
              left: i * step,
              top: 0,
              child: DecoratedBox(
                decoration: ShapeDecoration(
                  shape: ChamferBorder.tab(
                    cut: size * 0.2,
                    side: BorderSide(color: cs.surface, width: 2),
                  ),
                ),
                child: PartImageThumb(
                  imageUrl: preferredThumbUrl(parts[i]),
                  size: size,
                  scale: imageScaleFor(parts[i]),
                  borderRadius: BorderRadius.circular(size * 0.18),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Name + meta line for a resolved bey. Works for every generation and
/// manufacturer; nothing here assumes Beyblade X specifics beyond what the
/// entity guarantees.
class BeyIdentity extends StatelessWidget {
  const BeyIdentity({super.key, required this.beyblade, this.nameStyle});

  final Beyblade beyblade;
  final TextStyle? nameStyle;

  static String _title(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    final b = beyblade;
    final parts = b.stackedParts;
    final gens = {for (final p in parts) p.hobbyGeneration}
      ..removeWhere((g) => g.trim().isEmpty);
    final makers = {for (final p in parts) p.manufacturer}
      ..removeWhere((m) => m.trim().isEmpty);
    final incomplete = parts.any((p) => p.isIncomplete);
    final meta = <String>[
      if (gens.isNotEmpty) gens.join(' / '),
      if (makers.length == 1) makers.first,
      if (makers.length > 1) 'Mixed makers',
      if (b.archetype != BeybladeArchetype.unknown) _title(b.archetype.name),
      '${b.totalMass.toStringAsFixed(1)} g',
    ];
    final metaStyle =
        TextStyle(fontSize: rc.bodySM, color: cs.onSurfaceVariant, height: 1.3);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          b.nomenclatureName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: nameStyle ??
              TextStyle(
                  fontSize: rc.body,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  color: cs.onSurface),
        ),
        const SizedBox(height: 3),
        Wrap(
          spacing: 6,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (b.spinDirection != SpinDirection.unknown)
              Tooltip(
                message: b.spinDirection == SpinDirection.left
                    ? 'Left spin'
                    : 'Right spin',
                child: Icon(
                  b.spinDirection == SpinDirection.left
                      ? Icons.rotate_left
                      : Icons.rotate_right,
                  size: 15,
                  color: cs.onSurfaceVariant,
                ),
              ),
            Text(meta.join(' · '), style: metaStyle),
            if (b.legality == WboLegality.legal)
              Tooltip(
                message: 'Tournament legal',
                child: Icon(Icons.verified_outlined,
                    size: 15, color: HoloTokens.of(context).success),
              )
            else if (b.legality == WboLegality.illegal)
              Tooltip(
                message: 'Contains a part that is not tournament legal',
                child: Icon(Icons.gpp_bad_outlined,
                    size: 15, color: HoloTokens.of(context).danger),
              ),
            if (incomplete)
              Tooltip(
                message: 'Some of this build\'s part data is not verified yet',
                child: Icon(Icons.report_outlined,
                    size: 15, color: HoloTokens.of(context).warning),
              ),
          ],
        ),
      ],
    );
  }
}

/// A deck slot. [loadout] null renders the empty state with Build / Random
/// actions; otherwise the bey is resolved and shown in one compact row.
class BeySlotCard extends StatelessWidget {
  const BeySlotCard({
    super.key,
    required this.index,
    required this.loadout,
    this.onTap,
    this.onRandom,
    this.onClear,
    this.emptyLabel,
    this.highlight = false,
  });

  /// 0-based slot index; shown 1-based.
  final int index;
  final BeybladeLoadout? loadout;

  /// Opens the builder (fresh for an empty slot, pre-filled otherwise).
  final VoidCallback? onTap;
  final VoidCallback? onRandom;
  final VoidCallback? onClear;
  final String? emptyLabel;
  final bool highlight;

  static const double minHeight = 76;

  @override
  Widget build(BuildContext context) {
    final l = loadout;
    return HoloCard(
      padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
      onTap: onTap,
      highlight: highlight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minHeight - 20),
        child: Row(
          children: [
            _SlotNumber(index: index, filled: l != null),
            const SizedBox(width: 10),
            Expanded(
              child: l == null
                  ? _EmptyBody(label: emptyLabel ?? 'Bey ${index + 1}')
                  : ResolvedBeyBuilder(
                      loadout: l,
                      builder: (context, bey) => Row(
                        children: [
                          BeyPartsStrip(parts: keyPartsOf(bey), size: 34),
                          const SizedBox(width: 10),
                          Expanded(child: BeyIdentity(beyblade: bey)),
                        ],
                      ),
                      loading: (_) => const _SkeletonBody(),
                      failed: (_) => const _UnavailableBody(),
                    ),
            ),
            // Empty slot: the dice is the fastest action, so it stays one
            // tap away. Filled slot: one menu keeps the name readable on
            // narrow phones.
            if (l == null && onRandom != null)
              IconButton(
                tooltip: 'Random bey',
                icon: const Icon(Icons.casino_outlined),
                onPressed: onRandom,
              )
            else if (l != null &&
                (onTap != null || onRandom != null || onClear != null))
              PopupMenuButton<_SlotAction>(
                tooltip: 'Slot actions',
                icon: const Icon(Icons.more_vert),
                onSelected: (a) {
                  switch (a) {
                    case _SlotAction.change:
                      onTap?.call();
                    case _SlotAction.random:
                      onRandom?.call();
                    case _SlotAction.clear:
                      onClear?.call();
                  }
                },
                itemBuilder: (_) => [
                  if (onTap != null)
                    const PopupMenuItem(
                        value: _SlotAction.change,
                        child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.edit_outlined),
                            title: Text('Change bey'))),
                  if (onRandom != null)
                    const PopupMenuItem(
                        value: _SlotAction.random,
                        child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.casino_outlined),
                            title: Text('Random bey'))),
                  if (onClear != null)
                    const PopupMenuItem(
                        value: _SlotAction.clear,
                        child: ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.close_rounded),
                            title: Text('Clear slot'))),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

enum _SlotAction { change, random, clear }

class _SlotNumber extends StatelessWidget {
  const _SlotNumber({required this.index, required this.filled});
  final int index;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: filled ? cs.primary : Colors.transparent,
        shape: ChamferBorder.tab(
          cut: 7,
          side: filled ? BorderSide.none : BorderSide(color: cs.outline),
        ),
      ),
      child: Text(
        '${index + 1}',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 13,
          color: filled ? cs.onPrimary : cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _EmptyBody extends StatelessWidget {
  const _EmptyBody({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    return Row(
      children: [
        Icon(Icons.add_circle_outline, color: cs.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: rc.body,
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface)),
              Text('Tap to build',
                  style: TextStyle(
                      fontSize: rc.bodySM, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SkeletonBody extends StatelessWidget {
  const _SkeletonBody();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.surfaceContainerHighest;
    Widget bar(double w, double h) => Container(width: w, height: h, color: c);
    return Row(
      children: [
        bar(64, 40),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [bar(140, 12), const SizedBox(height: 6), bar(90, 10)],
          ),
        ),
      ],
    );
  }
}

class _UnavailableBody extends StatelessWidget {
  const _UnavailableBody();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    return Row(
      children: [
        Icon(Icons.help_outline, color: HoloTokens.of(context).warning),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'This build uses parts that are not in the catalog on this '
            'device. Rebuild it, or update the catalog in Settings.',
            style: TextStyle(fontSize: rc.bodySM, color: cs.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}
