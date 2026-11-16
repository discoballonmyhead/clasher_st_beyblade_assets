import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/bey_builder_cubit/bey_builder_state.dart';
import 'package:flutter/material.dart';

import 'loyalty_badge.dart';
import 'part_image_thumb.dart';

/// Vertical stacked tiles with a connecting line between them, showing
/// build order. Two entry points sharing one rendering path:
/// - [.fromBuilderState] — the in-progress builder, showing empty "not
///   selected" slots for parts not yet picked.
/// - [.fromResolved] — a finished [Beyblade] (the display page's
///   "Combined" view), where every slot is filled and each tile shows
///   its code/mass/legality too, not just name — there's real room for
///   it here, unlike the in-progress builder's tighter tiles.
class BeybladeStackPreview extends StatelessWidget {
  BeybladeStackPreview.fromBuilderState(BeyBuilderState state, {super.key})
      : slots = _slotsFromState(state);

  BeybladeStackPreview.fromResolved(Beyblade beyblade, {super.key})
      : slots = _slotsFromResolved(beyblade);

  final List<(String, BeybladePart?)> slots;

  static List<(String, BeybladePart?)> _slotsFromState(BeyBuilderState state) {
    if (state.bladeMode == BladeMode.unibody) {
      return [
        ('Blade', state.selectedBlade),
        if (!state.ratchetDisabled) ('Ratchet', state.selectedRatchet),
        ('Bit', state.selectedBit),
      ];
    }
    final mainCore = state.coreMode == CoreMode.main;
    return [
      ('Lock Chip', state.selectedLockChip),
      if (mainCore) ('Main Blade', state.selectedMainBlade),
      if (!mainCore) ('Over Blade', state.selectedOverBlade),
      if (!mainCore) ('Metal Blade', state.selectedMetalBlade),
      ('Assist Blade', state.selectedAssistBlade),
      if (!state.ratchetDisabled) ('Ratchet', state.selectedRatchet),
      ('Bit', state.selectedBit),
    ];
  }

  static List<(String, BeybladePart?)> _slotsFromResolved(Beyblade beyblade) =>
      [for (final part in beyblade.stackedParts) (_labelFor(part), part)];

  static String _labelFor(BeybladePart part) => switch (part) {
        LockChip _ => 'Lock Chip',
        OverBlade _ => 'Over Blade',
        MetalBlade _ => 'Metal Blade',
        MainBlade _ => 'Main Blade',
        AssistBlade _ => 'Assist Blade',
        Blade _ => 'Blade',
        Ratchet _ => 'Ratchet',
        Bit _ => 'Bit',
        _ => 'Part',
      };

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < slots.length; i++) ...[
          _StackTile(label: slots[i].$1, part: slots[i].$2),
          if (i != slots.length - 1) const _Connector(),
        ],
      ],
    );
  }
}

class _Connector extends StatelessWidget {
  const _Connector();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    // Aligned under the 56px thumbnail's center — same constant and same
    // math as the builder's own connector, so the two don't drift apart.
    return Padding(
      padding:
          EdgeInsets.only(left: rc.sm + 27, top: rc.sm / 2, bottom: rc.sm / 2),
      child: Container(width: 2, height: 12, color: cs.outlineVariant),
    );
  }
}

class _StackTile extends StatelessWidget {
  const _StackTile({required this.label, required this.part});

  final String label;
  final BeybladePart? part;

  static const _imageSize = 56.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final rc = ResponsiveProvider.config(context);
    final filled = part != null;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(rc.sm),
      decoration: BoxDecoration(
        color: filled ? cs.surfaceContainerHighest : null,
        borderRadius: BorderRadius.circular(rc.borderRadius),
        border: filled ? null : Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (filled)
            PartImageThumb(
                imageUrl: preferredThumbUrl(part),
                size: _imageSize,
                scale: imageScaleFor(part!))
          else
            SizedBox(
                width: _imageSize,
                height: _imageSize,
                child:
                    Icon(Icons.add_circle_outline, color: cs.onSurfaceVariant)),
          SizedBox(width: rc.sm * 1.5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                Text(
                  part?.name ?? 'Not selected',
                  style: tt.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (filled) ...[
                  const SizedBox(height: 3),
                  // Wrap, not Row — code + mass + legality is three
                  // separate pieces of text that could overflow a fixed
                  // Row on a narrow screen; Wrap just moves the third one
                  // to its own line instead of crashing.
                  Wrap(
                    spacing: 10,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(part!.code,
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                      Text('${part!.mass.toStringAsFixed(1)}g',
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant)),
                      LegalityBadge(legality: part!.legality),
                    ],
                  ),
                  if (part!.isIncomplete)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text('Data incomplete',
                          style: tt.labelSmall?.copyWith(color: cs.error)),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
