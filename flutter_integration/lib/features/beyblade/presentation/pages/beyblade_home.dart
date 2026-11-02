import 'dart:developer' as dev;

import 'package:clasher_st/core/constants/app_constants.dart';
import 'package:clasher_st/core/init_injection/injection.dart';
import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/responsive/responsive_extras.dart';
import 'package:clasher_st/core/theme/app_theme.dart';
import 'package:clasher_st/core/widgets/app_beyblade_loading_indicator.dart';
import 'package:clasher_st/core/widgets/app_dialog_widget.dart';
import 'package:clasher_st/features/auth/presentation/cubits/auth_flow_cubit/auth_cubit.dart';
import 'package:clasher_st/features/beyblade/b_routes/beyblade_routes.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/beyblade_sync_cubit/beyblade_sync_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/part_image_thumb.dart';
import 'package:clasher_st/features/news/presentation/cubit/news_feed_cubit.dart';
import 'package:clasher_st/features/news/presentation/widgets/latest_releases_section.dart';
import 'package:clasher_st/features/user_collection/domain/entities/entities.dart';
import 'package:clasher_st/features/user_collection/domain/usecases/usecases.dart';
import 'package:clasher_st/features/user_collection/presentation/cubit/collection_summary_cubit/collection_summary_cubit.dart';
import 'package:clasher_st/features/user_collection/presentation/cubit/wishlist_cubit/wishlist_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:clasher_st/features/bey_testing/presentation/bey_test_routes.dart';
import 'package:clasher_st/features/store_tracker/route_build/store_tracker_routes.dart';
import 'package:clasher_st/core/constants/trc_constant_tokens.dart';
import 'package:clasher_st/core/services/translation/translation_helper.dart';
import 'package:clasher_st/core/ads/ads.dart';
import 'package:clasher_st/core/ads/app_banner_ad.dart';
import 'package:clasher_st/features/shop/presentation/shop_routes.dart';

class BeybladeHomePage extends StatelessWidget {
  const BeybladeHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // Keyed by user: signing in as someone else builds fresh cubits and
    // reruns initState, so the old user's summary never shows. The tab
    // stays alive in the IndexedStack, so without the key it wouldn't
    // reload.
    final userId = context.select((AuthCubit c) => c.state.user?.id);
    return MultiBlocProvider(
      key: ValueKey(userId),
      providers: [
        BlocProvider<NewsFeedCubit>(create: (_) => sl<NewsFeedCubit>()),
        BlocProvider<CollectionSummaryCubit>(
            create: (_) => sl<CollectionSummaryCubit>()),
      ],
      child: const _BeybladeHomeView(),
    );
  }
}

class _BeybladeHomeView extends StatefulWidget {
  const _BeybladeHomeView();
  @override
  State<_BeybladeHomeView> createState() => _BeybladeHomePageState();
}

class _BeybladeHomePageState extends State<_BeybladeHomeView> {
  String? _expandedGeneration;

  /// Distinguishes "the user hasn't touched a tile yet" from "the user
  /// deliberately collapsed the auto-expanded one". Without it, the
  /// listener below would helpfully re-open a tile the user just closed.
  bool _userHasToggled = false;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    dev.log('Loading dashboard', name: 'BeybladeHome');
    context.read<BeybladeSyncCubit>().ensureFreshOnFirstVisit();
    context.read<WishlistCubit>().ensureLoaded();
    context.read<NewsFeedCubit>().load();
    context.read<CollectionSummaryCubit>().load();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);

    return ResponsiveScaffold(
      // Your token: 480 / 720 / 960 by tier.
      maxWidth: rc.maxContentWidth,
      appBar: AppBar(
        title: const Text('Bey Station'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: 'Search parts',
            icon: const Icon(Icons.search),
            onPressed: () => context.push(BeybladeRoutes.search),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: cs.primary,
        onRefresh: () async => _loadAll(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(rc.horizontalPadding,
              rc.horizontalPadding, rc.horizontalPadding, rc.xxl),
          children: [
            // ── Feature strip ──────────────────────────────────────────────
            // Splits on tablet and up, via deviceInfo.shouldShowSplitLayout.
            SplitPane(
              startFlex: 3,
              endFlex: 2,
              stackedEnd: true,
              start: BlocBuilder<NewsFeedCubit, NewsFeedState>(
                builder: (context, state) {
                  if (state.loading) {
                    return const SizedBox(
                        height: 112, child: Center(child: BeybladeSpinner()));
                  }
                  if (state.releases.isEmpty) return const SizedBox.shrink();
                  return LatestReleasesCard(
                    releases: state.releases,
                    height: 112,
                    routeForTarget: (id) => '/products/$id',
                  );
                },
              ),
              end: const SizedBox(
                height: 112,
                child: AppBannerAd(
                  placement: AdPlacement.homeBanner,
                  maxHeight: 112,
                  // No ad (no consent, no fill, desktop): the meme stays.
                  fallback: AdSlotPlaceholder(
                    image: AssetImage('assets/images/releasesnads/newad.webp'),
                    height: 112,
                  ),
                ),
              ),
            ),
            SizedBox(height: rc.lg),

            // ── Collection ─────────────────────────────────────────────────
            SectionTitle(
              title: 'Your collection',
              action: TextButton.icon(
                icon: const Icon(Icons.insights_outlined, size: 18),
                label: const Text('Analytics'),
                onPressed: () => context.push(BeybladeRoutes.analytics),
              ),
            ),

            BlocConsumer<CollectionSummaryCubit, CollectionSummaryState>(
              listener: (context, state) {
                if (state.loading || _userHasToggled) return;
                setState(() => _expandedGeneration =
                    initiallyExpandedGeneration(state.summaries));
              },
              builder: (context, state) {
                if (state.loading) {
                  return const Card(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: BeybladeSpinner()),
                    ),
                  );
                }

                if (state.summaries.isEmpty) {
                  return _EmptyCollectionCard(
                    onAddPressed: () => context.push(BeybladeRoutes.search),
                  );
                }

                return AdaptiveGrid(
                  minTileWidth: 340,
                  children: [
                    for (final summary in state.summaries)
                      _GenerationSummaryTile(
                        summary: summary,
                        expanded: _expandedGeneration == summary.generation,
                        onToggle: () => setState(() {
                          _userHasToggled = true;
                          _expandedGeneration =
                              _expandedGeneration == summary.generation
                                  ? null
                                  : summary.generation;
                        }),
                      ),
                  ],
                );
              },
            ),

            SizedBox(height: rc.lg),

            // ── Navigation ─────────────────────────────────────────────────
            const SectionTitle(title: 'Manage'),
            AdaptiveGrid(
              minTileWidth: 260,
              children: [
                _NavCard(
                  icon: Icons.inventory_2_outlined,
                  title: 'My Collection',
                  subtitle: 'Everything you own, lent and borrowed',
                  onTap: () => context.push(BeybladeRoutes.inventory),
                ),
                _NavCard(
                  icon: Icons.favorite_border,
                  title: 'Wishlist',
                  subtitle: 'Parts and products you want next',
                  onTap: () => context.push(BeybladeRoutes.wishlist),
                ),
                _NavCard(
                  icon: Icons.collections_bookmark_outlined,
                  title: 'Decks & Combos',
                  subtitle: 'Build and manage your combos and decks',
                  onTap: () => context.push(BeybladeRoutes.combosDecks),
                ),
                _NavCard(
                  icon: Icons.rule_outlined,
                  title: 'Ban & approve lists',
                  subtitle: 'Part rules to reuse in your tournaments',
                  onTap: () => context.push(BeybladeRoutes.partLists),
                ),
                _NavCard(
                  icon: Icons.style_outlined,
                  title: 'Card game',
                  subtitle: 'Beyblade TCG cards and sets',
                  onTap: () => context.push(BeybladeRoutes.tcg),
                ),
                _NavCard(
                  icon: Icons.science_outlined,
                  title: 'Testing',
                  subtitle: 'Combo & deck tests, battles and backups',
                  onTap: () => context.push(BeyTestRoutes.home),
                ),
                _NavCard(
                  icon: Icons.storefront_outlined,
                  title: TrTokens.storeTrackerHead.tr,
                  subtitle: TrTokens.storeTrackerHomeSubhead.tr,
                  onTap: () => context.push(StoreTrackerRoutes.list),
                ),
                //TODO BETA
                // _NavCard(
                //   icon: Icons.storefront_outlined,
                //   title: TrTokens.shopHead.tr,
                //   subtitle: TrTokens.shopSettingsSubhead.tr,
                //   onTap: () => context.push(ShopRoutes.shop),
                // ),
                _NavCard(
                  icon: Icons.settings_outlined,
                  title: 'Settings & Data',
                  subtitle: 'Part data sync, backups and preferences',
                  onTap: () => context.push(AppConstants.settingsRoute),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCollectionCard extends StatelessWidget {
  const _EmptyCollectionCard({required this.onAddPressed});
  final VoidCallback onAddPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 34, color: cs.onSurfaceVariant.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text('Nothing in your collection yet',
                style: tt.titleSmall, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              'Add the parts you own and the rest of the app fills in around them.',
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(220, 46)),
              onPressed: onAddPressed,
              icon: const Icon(Icons.add),
              label: const Text('Find parts to add'),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenerationSummaryTile extends StatelessWidget {
  const _GenerationSummaryTile({
    required this.summary,
    required this.expanded,
    required this.onToggle,
  });

  final GenerationSummary summary;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(summary.generation,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800)),
                        ),
                        if (summary.isLatest) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: ShapeDecoration(
                              color: cs.primaryContainer,
                              shape: AppTheme.bevelChip,
                            ),
                            child: Text('Latest',
                                style: tt.labelSmall?.copyWith(
                                    color: cs.onPrimaryContainer,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text('${summary.totalCount} item(s)',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: expanded
                    ? Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 16,
                              runSpacing: 10,
                              children: summary.countsByPartType.entries
                                  .map((e) => _CountChip(
                                      groupKey: e.key, count: e.value))
                                  .toList(),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(0, 42)),
                                    onPressed: () =>
                                        context.push(BeybladeRoutes.inventory),
                                    child: const Text('Inventory'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(0, 42)),
                                    onPressed: () =>
                                        context.push(BeybladeRoutes.wishlist),
                                    child: const Text('Wishlist'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CountChip extends StatelessWidget {
  const _CountChip({required this.groupKey, required this.count});
  final String groupKey;
  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Tooltip(
      // The icon alone doesn't say which type it is, and several types
      // legitimately share one. The tooltip carries the label instead of
      // widening every chip.
      message: displayLabelForPartType(groupKey),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(iconForGroupKey(groupKey), size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 5),
          Text('$count',
              style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: ShapeDecoration(
                  color: cs.primary.withValues(alpha: 0.12),
                  shape: AppTheme.bevelChip,
                ),
                child: Icon(icon, size: 20, color: cs.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: tt.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
            ],
          ),
        ),
      ),
    );
  }
}

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
class AdSlotPlaceholder extends StatefulWidget {
  const AdSlotPlaceholder({
    super.key,
    required this.image,
    this.headline = 'Ad space',
    this.subline =
        'One day this pays for the servers. For now, enjoy the meme.',
    this.label = 'PLACEHOLDER',
    this.height = 112,
    this.maxWidth = double.infinity,
    this.shape,
    this.backgroundColor,
    this.accentColor,
    this.imageOpacity = 1.0,
    this.imageAlignment = Alignment.center,
    this.fit = BoxFit
        .cover, // 👈 Added this parameter (defaults to cover for standard banners)
    this.scrimStrength = 0.72,
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
    final url = Uri.parse('https://paypal.me/');
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
      title: 'Support the Dev',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdSlotPlaceholder(
            image: const AssetImage('assets/images/releasesnads/dev.webp'),
            fit: BoxFit.contain,
            headline: 'Keep the servers running!',
            subline: 'Servers aren\'t free, but this app is.',
            label: 'SUPPORT',
            margin: const EdgeInsets.only(bottom: 20),
            onTap: _launchPayPal,
          ),
          Text(
            'This app is currently ad-free and maintained by a solo developer. '
            'If you enjoy using it and want to help cover the server and coffee costs, '
            'consider dropping a tip via PayPal!',
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
        builder: (dialogContext) => ElevatedButton.icon(
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            await _launchPayPal();
          },
          icon: const Icon(Icons.favorite),
          label: const Text('Donate via PayPal, or cash'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF0079C1), // PayPal Blue
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ),
      secondaryButton: Builder(
        builder: (dialogContext) => TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Maybe Later'),
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
                              bg.withValues(alpha: widget.scrimStrength),
                              bg.withValues(alpha: widget.scrimStrength * 0.75),
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
                                  widget.headline,
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
                                    widget.subline!,
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
                            widget.label!,
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
