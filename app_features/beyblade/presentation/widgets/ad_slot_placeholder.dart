// ════════════════════════════════════════════════════════════════════════════
// =============================================================================
// AD SLOT PLACEHOLDER — "ads are coming here", with a meme to soften it.
// -----------------------------------------------------------------------------
//   import 'package:flutter/material.dart';
//   // optional: import '<path>/facet.dart';  // to pass a FacetBorder as shape
//
// Distinct from LatestReleasesCard: no carousel, no data source, no dialog.
// One slot, one permanent background image, one message. It exists so the space
// an ad will occupy is reserved and honest in the layout now, rather than the
// UI shifting under people the day ads ship.
//
// Nothing here fetches or tracks anything.
// =============================================================================
// import 'package:url_launcher/url_launcher.dart'; // Make sure to import url_launcher
import 'package:clasher_st/core/constants/trc_constant_tokens.dart';
import 'package:clasher_st/core/services/translation/translation_helper.dart';
import 'package:clasher_st/core/widgets/app_dialog_widget.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/developer_homage.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class AdSlotPlaceholder extends StatefulWidget {
  const AdSlotPlaceholder({
    super.key,
    required this.image,
    this.headline = TrTokens.adSpaceHeadlineTxt,
    this.subline = TrTokens.adSpaceSublineTxt,
    this.label = TrTokens.placeholderTxt,
    this.height = 112,
    this.maxWidth = double.infinity,
    this.shape,
    this.backgroundColor,
    this.accentColor,
    this.imageOpacity = 1.0,
    this.imageAlignment = Alignment.center,
    this.fit = BoxFit
        .cover, // 👈 Added this parameter (defaults to cover for standard banners)
    this.scrimStrength = 0.28,
    this.shimmer = true,
    this.onTap,
    this.margin,
  });

  /// The permanent background. AssetImage for a bundled meme, NetworkImage or
  /// CachedNetworkImageProvider if it's remote — any ImageProvider works.
  final ImageProvider image;

  final String headline;
  final String? subline;

  /// Corner tag. Set null to hide it.
  final String? label;

  final double height;
  final double maxWidth;

  /// Defaults to a rounded rectangle. Pass `FacetBorder.bevel(cut: 16)` to
  /// match the arena surfaces.
  final ShapeBorder? shape;

  /// Tints the scrim over the image. Defaults to the theme's surface.
  final Color? backgroundColor;

  /// Tag, rule and chevron. Defaults to the theme primary.
  final Color? accentColor;

  final double imageOpacity;
  final AlignmentGeometry imageAlignment;

  /// Controls how the image scales. Use BoxFit.contain to avoid cropping.
  final BoxFit fit;

  /// 0 = raw image, 1 = fully covered. The meme needs to read, the text needs
  /// to read; 0.72 is the balance point for most busy images.
  final double scrimStrength;

  final bool shimmer;

  /// If null, tapping will open the Support Dev dialog.
  final VoidCallback? onTap;

  final EdgeInsetsGeometry? margin;

  @override
  State<AdSlotPlaceholder> createState() => _AdSlotPlaceholderState();
}

class _AdSlotPlaceholderState extends State<AdSlotPlaceholder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  @override
  void initState() {
    super.initState();
    if (widget.shimmer) _sweep.repeat();
  }

  @override
  void didUpdateWidget(covariant AdSlotPlaceholder old) {
    super.didUpdateWidget(old);
    if (widget.shimmer && !_sweep.isAnimating) {
      _sweep.repeat();
    } else if (!widget.shimmer && _sweep.isAnimating) {
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  /// Opens the PayPal link. Calls launchUrl directly: canLaunchUrl returns
  /// false on Android 11+ unless the manifest declares <queries>, which made
  /// the button silently do nothing.
  Future<void> _launchPayPal() async {
    // TODO: Replace with your actual PayPal URL
    final url = Uri.parse('https://paypal.me/SADHAN732');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {/* no browser available; nothing to do */}
  }

  /// If a custom onTap is provided, runs that. Otherwise shows the support
  /// dialog.
  void _handleTap() {
    if (widget.onTap != null) {
      widget.onTap!();
      return;
    }

    AppDialogWidget.show(
      context,
      title: TrTokens.donateDialogTitleTxt.tr,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DeveloperHomage(
            entries: developerHomages,
            height: 190,
            autoPlay: true,
            autoPlayInterval: const Duration(seconds: 4),
          ),
          const SizedBox(height: 20),
          Text(
            TrTokens.donateDialogBodyTxt.tr,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
      // Builder: its context is inside the dialog, so pop() closes the
      // dialog (on the root navigator), not the page behind it.
      actionButton: Builder(
        builder: (dialogContext) => ElevatedButton(
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            await _launchPayPal();
          },
          style: ElevatedButton.styleFrom(
            backgroundColor:
                const Color(0xFFCCFF00), // Vibrant Lime / Volt Green
            foregroundColor: Colors.black87,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.favorite, size: 18),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  TrTokens.donateBtnTxt.tr,
                  textAlign:
                      TextAlign.center, // Keeps wrapped text perfectly centered
                  // Notice: no maxLines and no ellipsis here!
                  // It will just wrap safely if the translation is super long.
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    fontSize: 15,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      secondaryButton: Builder(
        builder: (dialogContext) => TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(TrTokens.maybeLaterTxt.tr),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = widget.backgroundColor ?? cs.surfaceContainerHighest;
    final accent = widget.accentColor ?? cs.primary;
    final shape = widget.shape ??
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));

    return Padding(
      padding: widget.margin ?? EdgeInsets.zero,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: widget.maxWidth,
          maxHeight: widget.height,
        ),
        child: Material(
          color: bg,
          clipBehavior: Clip.antiAlias,
          shape: shape,
          child: InkWell(
            onTap: _handleTap,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth.isFinite
                    ? constraints.maxWidth
                    : MediaQuery.sizeOf(context).width;

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // ── The meme, always there ──
                    Opacity(
                      opacity: widget.imageOpacity.clamp(0.0, 1.0),
                      child: Image(
                        image: widget.image,
                        fit: widget.fit, // 👈 Uses the new 'fit' parameter here
                        alignment: widget.imageAlignment,
                        gaplessPlayback: true,
                      ),
                    ),

                    // ── Scrim: heavy at the left where the copy sits, thin on
                    // the right so the image still lands. ──
                    IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              bg.withValues(
                                  alpha: widget.scrimStrength.clamp(0.0, 1.0)),
                              bg.withValues(
                                alpha:
                                    widget.scrimStrength.clamp(0.0, 1.0) * 0.35,
                              ),
                              bg.withValues(alpha: 0.0),
                            ],
                            stops: const [0.0, 0.5, 1.0],
                          ),
                        ),
                      ),
                    ),

                    // ── Shimmer sweep — the only motion, and it's cheap. ──
                    if (widget.shimmer)
                      IgnorePointer(
                        child: AnimatedBuilder(
                          animation: _sweep,
                          builder: (context, _) {
                            // Travels left to right with a pause between runs.
                            final p = Curves.easeInOut.transform(
                                (_sweep.value * 1.6).clamp(0.0, 1.0));
                            return Transform.translate(
                              offset: Offset(-w + (p * (w * 2)), 0),
                              child: Transform.rotate(
                                angle: 0.32,
                                child: Container(
                                  width: 54,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        Colors.white.withValues(alpha: 0.0),
                                        Colors.white.withValues(alpha: 0.11),
                                        Colors.white.withValues(alpha: 0.0),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                    // ── Copy ──
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                      child: Row(
                        children: [
                          Container(width: 3, height: 30, color: accent),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.headline.tr,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: cs.onSurface,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                                if (widget.subline != null &&
                                    widget.subline!.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    widget.subline!.tr,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      fontSize: 11,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // Chevron to indicate it's clickable
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right, size: 18, color: accent),
                        ],
                      ),
                    ),

                    // ── Corner tag ──
                    if (widget.label != null)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(10, 4, 10, 5),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.9),
                            borderRadius: const BorderRadius.only(
                              bottomLeft: Radius.circular(12),
                            ),
                          ),
                          child: Text(
                            widget.label!.tr,
                            style: TextStyle(
                              fontSize: 9,
                              letterSpacing: 1.6,
                              fontWeight: FontWeight.w900,
                              color: ThemeData.estimateBrightnessForColor(
                                          accent) ==
                                      Brightness.dark
                                  ? Colors.white
                                  : Colors.black,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class DeveloperHomageEntry {
  const DeveloperHomageEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.image,
    this.role,
    this.link,
    this.accentColor = const Color(0xFF80CBC4),
  });

  final String id;
  final String name;
  final String description;
  final String image;
  final String? role;
  final String? link;
  final Color accentColor;
}

final List<DeveloperHomageEntry> developerHomages = [
  DeveloperHomageEntry(
    id: 'boxvman',
    name: 'MAN VS BOX',
    description: 'Engineering and collaboration partner',
    image: 'assets/images/releasesnads/tonaf.webp',
    accentColor: Color(0xFFD4A373), // Warm c
    link: 'https://youtube.com/@boxvsman',
  ),
  DeveloperHomageEntry(
    id: 'hba',
    name: 'Ha Noi Bladers Association (HBA)',
    description:
        'The community who helped build this, who contributes ideas, feedback, testing, and support.',
    image:
        'assets/images/releasesnads/762804091_122166306092710315_7956732445747408803_n.webp',
    accentColor: Color(0xFF00E676), // Bright stadium lime green
    link: 'https://www.facebook.com/hanoibeyblade/',
  ),
  DeveloperHomageEntry(
    id: 'community',
    name: 'The Viet Nam beyblade Community',
    role: 'Powered by',
    description:
        'A special appreciation for the Viet Nam beyblade community who help us grow',
    image: 'assets/images/releasesnads/ety.webp',
    accentColor: Color(0xFF4CAF50), // Insignia green ring accent
  ),
];
