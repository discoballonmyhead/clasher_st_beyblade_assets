import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/part_image_thumb.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/resolved_bey_thumb.dart';
import 'package:flutter/material.dart';

// =============================================================================
// BEY PARTS STACK
// -----------------------------------------------------------------------------
// A bey drawn as its parts stacked top to bottom, each one half-covered by
// the part above it, so the column reads as a side view of the bey:
//
//     ┌──────┐   blade (or lock chip, then main / over / metal / assist)
//     └─┬──┬─┘
//      ┌┴──┴┐    ratchet: its top half sits behind the blade
//      └┬──┬┘
//       └──┘     bit
//
// Works for every assembly, because it reads Beyblade.stackedParts, which
// already lists the parts top to bottom for unibody and separated builds.
//
// When the bey changes, the parts slide in one after another from
// [fromRight] ? the right : the left, top part first.
//
// The widget always takes the height of the tallest possible bey (see
// [BeyPartsStack.heightFor]), also while nothing is picked, so the layout
// around it never jumps when a bey is selected.
// =============================================================================

class BeyPartsStack extends StatelessWidget {
  const BeyPartsStack({
    super.key,
    required this.loadout,
    this.fromRight = false,
    this.partSize = 34,
    this.alignment = Alignment.topCenter,
  });

  /// The bey to draw. Null keeps the reserved space empty.
  final BeybladeLoadout? loadout;

  /// Slide the parts in from the right (true) or from the left (false).
  final bool fromRight;

  /// Edge of each part's square.
  final double partSize;

  /// Where the column sits inside its reserved box.
  final Alignment alignment;

  /// How much of each part the next one down covers: 0.5 means the ratchet
  /// shows its lower half below the blade, and so on.
  static const double overlap = 0.41;

  /// Parts in the tallest assembly: lock chip, main or over blade, assist or
  /// metal blade, ratchet, bit.
  static const int maxParts = 5;

  /// Height of a column of [parts] parts of [partSize].
  static double heightFor(double partSize, {int parts = maxParts}) =>
      parts <= 0 ? 0 : partSize + (parts - 1) * partSize * (1 - overlap);

  @override
  Widget build(BuildContext context) {
    final lo = loadout;
    return SizedBox(
      width: partSize,
      height: heightFor(partSize),
      child: lo == null
          ? const SizedBox.shrink()
          : ResolvedBeyBuilder(
              // A new bey replays the slide-in from the start.
              key: ValueKey(lo),
              loadout: lo,
              loading: (_) => const SizedBox.shrink(),
              failed: (_) => const SizedBox.shrink(),
              builder: (context, bey) => Semantics(
                label: bey.nomenclatureName,
                image: true,
                child: _AnimatedPartColumn(
                  parts: bey.stackedParts,
                  partSize: partSize,
                  fromRight: fromRight,
                  alignment: alignment,
                ),
              ),
            ),
    );
  }
}

/// A bey as a small horizontal strip of its parts, in stack order from the
/// left (blade first), each one tucked a little under the one before. No
/// animation: made for lists, such as a match's round history.
class BeyPartsStrip extends StatelessWidget {
  const BeyPartsStrip({
    super.key,
    required this.loadout,
    this.partSize = 20,
  });

  final BeybladeLoadout loadout;

  /// Edge of each part's square.
  final double partSize;

  /// How much of each part the next one covers.
  static const double overlap = 0.3;

  /// Width of a strip of [parts] parts of [partSize].
  static double widthFor(double partSize, int parts) =>
      parts <= 0 ? 0 : partSize + (parts - 1) * partSize * (1 - overlap);

  @override
  Widget build(BuildContext context) {
    final placeholder = SizedBox(width: partSize, height: partSize);
    return ResolvedBeyBuilder(
      key: ValueKey(loadout),
      loadout: loadout,
      loading: (_) => placeholder,
      failed: (_) => placeholder,
      builder: (context, bey) {
        final parts = bey.stackedParts;
        final step = partSize * (1 - overlap);
        return Tooltip(
          message: bey.nomenclatureName,
          child: Semantics(
            label: bey.nomenclatureName,
            image: true,
            child: SizedBox(
              width: widthFor(partSize, parts.length),
              height: partSize,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Painted right to left, so the blade ends up in front.
                  for (var i = parts.length - 1; i >= 0; i--)
                    Positioned(
                      left: step * i,
                      top: 0,
                      width: partSize,
                      height: partSize,
                      child: PartImageThumb(
                        imageUrl: preferredThumbUrl(parts[i]),
                        size: partSize,
                        scale: imageScaleFor(parts[i]),
                        background: Colors.transparent,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AnimatedPartColumn extends StatefulWidget {
  const _AnimatedPartColumn({
    required this.parts,
    required this.partSize,
    required this.fromRight,
    required this.alignment,
  });

  final List<BeybladePart> parts;
  final double partSize;
  final bool fromRight;
  final Alignment alignment;

  @override
  State<_AnimatedPartColumn> createState() => _AnimatedPartColumnState();
}

class _AnimatedPartColumnState extends State<_AnimatedPartColumn>
    with SingleTickerProviderStateMixin {
  /// One part's slide.
  static const _slide = Duration(milliseconds: 380);

  /// Gap between one part starting and the next.
  static const _stagger = Duration(milliseconds: 110);

  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: _slide +
        _stagger * (widget.parts.isEmpty ? 0 : widget.parts.length - 1),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reduced motion: show the finished stack, no slide.
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.value = 1;
    } else if (!_ctrl.isAnimating && _ctrl.value == 0) {
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Animation<double> _partAnimation(int i) {
    final total = _ctrl.duration!.inMilliseconds;
    if (total == 0) return const AlwaysStoppedAnimation(1);
    final start = (_stagger.inMilliseconds * i) / total;
    final end = ((_stagger.inMilliseconds * i) + _slide.inMilliseconds) / total;
    return CurvedAnimation(
      parent: _ctrl,
      curve: Interval(start.clamp(0.0, 1.0), end.clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.partSize;
    final step = size * (1 - BeyPartsStack.overlap);
    final parts = widget.parts;
    final dx = widget.fromRight ? 0.9 : -0.9;

    // Painted bottom-up, so each part sits in front of the one below it and
    // the blade ends up on top: the visual order of a real bey.
    final children = <Widget>[
      for (var i = parts.length - 1; i >= 0; i--)
        Positioned(
          top: step * i,
          left: 0,
          width: size,
          height: size,
          child: _SlideInPart(
            animation: _partAnimation(i),
            dx: dx,
            child: PartImageThumb(
              imageUrl: preferredThumbUrl(parts[i]),
              size: size,
              scale: imageScaleFor(parts[i]),
              // Transparent, so the artwork stacks instead of a pile of
              // grey squares.
              background: Colors.transparent,
            ),
          ),
        ),
    ];

    return Align(
      alignment: widget.alignment,
      child: SizedBox(
        width: size,
        height: BeyPartsStack.heightFor(size, parts: parts.length),
        child: Stack(clipBehavior: Clip.none, children: children),
      ),
    );
  }
}

class _SlideInPart extends StatelessWidget {
  const _SlideInPart({
    required this.animation,
    required this.dx,
    required this.child,
  });

  final Animation<double> animation;

  /// Start offset in part widths: negative from the left, positive from the
  /// right.
  final double dx;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: SlideTransition(
        position: Tween<Offset>(begin: Offset(dx, 0), end: Offset.zero)
            .animate(animation),
        child: child,
      ),
    );
  }
}
