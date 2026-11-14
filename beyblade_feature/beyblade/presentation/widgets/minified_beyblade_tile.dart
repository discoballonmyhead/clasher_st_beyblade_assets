import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/loyalty_badge.dart';
import 'package:flutter/material.dart';

import 'part_image_thumb.dart';

/// The "minified" view of a build — 3 tiles per row, connected in build
/// order like [BeybladeStackPreview], but horizontal instead of
/// vertical, since a build can have up to 6 parts and a single row that
/// small would make each one illegible (the "Pokémon team row" look
/// doesn't scale to this many pieces at a useful size).
///
/// The connector between the 3rd tile of one row and the 1st of the next
/// is the part worth reading carefully: those two tiles are diagonally
/// opposite corners, not adjacent, so that segment is drawn as three
/// straight pieces (down, across, down) rather than assuming every
/// connector is a simple horizontal line between neighbors. Every
/// segment's position is computed from the same row/column math as the
/// tiles themselves, not hand-tuned pixel offsets, so it stays correct
/// regardless of how many parts there are or how wide the screen is.
///
/// [beyblade] is nullable — null renders the empty-slot state (a plain
/// "tap to build" card), used by the 3 local deck slots for a slot
/// nothing has been saved to yet. [onTap] works the same way regardless:
/// pass it to open the builder (fresh for an empty slot, pre-loaded via
/// initialLoadout for a filled one — the caller decides which), omit it
/// for a purely static display context.
class MinifiedBeybladeTile extends StatelessWidget {
  const MinifiedBeybladeTile(
      {super.key,
      required this.beyblade,
      this.onTap,
      this.emptyLabel = 'Empty slot'});

  final Beyblade? beyblade;
  final VoidCallback? onTap;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final bey = beyblade;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: bey == null
            ? _EmptySlotContent(label: emptyLabel)
            : _FilledContent(beyblade: bey),
      ),
    );
  }
}

class _EmptySlotContent extends StatelessWidget {
  const _EmptySlotContent({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    return Padding(
      padding: EdgeInsets.symmetric(vertical: rc.lg, horizontal: rc.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.add_circle_outline, size: 32, color: cs.onSurfaceVariant),
          SizedBox(height: rc.sm),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _FilledContent extends StatelessWidget {
  const _FilledContent({required this.beyblade});
  final Beyblade beyblade;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final rc = ResponsiveProvider.config(context);
    final parts = beyblade.stackedParts;

    return Padding(
      padding: EdgeInsets.all(rc.sm * 1.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ConnectedPartsGrid(parts: parts),
          SizedBox(height: rc.sm),
          Text(
            parts.map((p) => p.name).join(' + '),
            style: tt.titleSmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('${beyblade.totalMass.toStringAsFixed(1)}g',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              SizedBox(width: rc.sm),
              LegalityBadge(legality: beyblade.legality),
            ],
          ),
        ],
      ),
    );
  }
}

/// The actual grid + connector geometry. 3 columns, however many rows
/// [parts] needs. Every tile and every connector segment's position is
/// derived from (index ~/ perRow, index % perRow) — nothing here is a
/// guessed pixel offset, so it's correct for 3 parts (1 row, no wrap) or
/// 6 (2 full rows, one wrap connector) without special-casing either.
class _ConnectedPartsGrid extends StatelessWidget {
  const _ConnectedPartsGrid({required this.parts});
  final List<BeybladePart> parts;

  static const _perRow = 3;
  static const _lineThickness = 2.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    final gap = rc.sm;
    // Taller than the intra-row gap — this is what the wrap connector's
    // two vertical segments actually have room to be drawn inside.
    final rowGap = rc.sm * 2.5;

    return LayoutBuilder(
      builder: (context, constraints) {
        final tileSize = (constraints.maxWidth - gap * (_perRow - 1)) / _perRow;
        final rows = (parts.length / _perRow).ceil();
        final totalHeight = rows * tileSize + (rows - 1) * rowGap;

        Offset centerOf(int index) {
          final col = index % _perRow;
          final row = index ~/ _perRow;
          final left = col * (tileSize + gap);
          final top = row * (tileSize + rowGap);
          return Offset(left + tileSize / 2, top + tileSize / 2);
        }

        final connectors = <Widget>[];
        for (var i = 0; i < parts.length - 1; i++) {
          final sameRow = (i ~/ _perRow) == ((i + 1) ~/ _perRow);
          final from = centerOf(i);
          final to = centerOf(i + 1);

          if (sameRow) {
            // One straight horizontal segment between neighbors.
            connectors.add(Positioned(
              left: from.dx + tileSize / 2,
              top: from.dy - _lineThickness / 2,
              width: gap,
              height: _lineThickness,
              child: ColoredBox(color: cs.outlineVariant),
            ));
          } else {
            // Wrap point: tile i is the last in its row, tile i+1 is the
            // first of the next — diagonally placed, not adjacent. Drawn
            // as down / across / down rather than one straight line,
            // since a straight line between these two points would cut
            // diagonally across whatever tile is in between them.
            final midY = from.dy + tileSize / 2 + rowGap / 2;
            connectors.add(Positioned(
              left: from.dx - _lineThickness / 2,
              top: from.dy + tileSize / 2,
              width: _lineThickness,
              height: rowGap / 2,
              child: ColoredBox(color: cs.outlineVariant),
            ));
            connectors.add(Positioned(
              left: from.dx < to.dx ? from.dx : to.dx,
              top: midY - _lineThickness / 2,
              width: (to.dx - from.dx).abs(),
              height: _lineThickness,
              child: ColoredBox(color: cs.outlineVariant),
            ));
            connectors.add(Positioned(
              left: to.dx - _lineThickness / 2,
              top: midY,
              width: _lineThickness,
              height: rowGap / 2,
              child: ColoredBox(color: cs.outlineVariant),
            ));
          }
        }

        return SizedBox(
          width: constraints.maxWidth,
          height: totalHeight,
          child: Stack(
            children: [
              ...connectors,
              for (var i = 0; i < parts.length; i++)
                Positioned(
                  left: (i % _perRow) * (tileSize + gap),
                  top: (i ~/ _perRow) * (tileSize + rowGap),
                  width: tileSize,
                  height: tileSize,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(rc.borderRadius / 2),
                    child: PartImageThumb(
                        imageUrl: preferredThumbUrl(parts[i]),
                        size: tileSize,
                        scale: imageScaleFor(parts[i])),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
