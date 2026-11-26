import 'dart:async';
import 'dart:developer' as dev;

import 'package:clasher_st/core/constants/trc_constant_tokens.dart';
import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/responsive/responsive_extras.dart';
import 'package:clasher_st/core/services/translation/translation_helper.dart';
import 'package:clasher_st/core/widgets/app_beyblade_loading_indicator.dart';
import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/bey_testing/bt_routes/bey_test_routes.dart';
import 'package:clasher_st/features/beyblade/b_routes/beyblade_routes.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/beyblade_sync_cubit/beyblade_sync_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/ad_slot_placeholder.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/part_image_thumb.dart';
import 'package:clasher_st/features/news/presentation/cubit/news_feed_cubit.dart';
import 'package:clasher_st/features/news/presentation/widgets/latest_releases_section.dart';
import 'package:clasher_st/features/settings/stngs_routes/settings_routes.dart';
import 'package:clasher_st/features/store_tracker/route_build/store_tracker_routes.dart';
import 'package:clasher_st/features/user_collection/domain/entities/entities.dart';
import 'package:clasher_st/features/user_collection/domain/usecases/usecases.dart';
import 'package:clasher_st/features/user_collection/presentation/cubit/collection_summary_cubit/collection_summary_cubit.dart';
import 'package:clasher_st/features/user_collection/presentation/cubit/wishlist_cubit/wishlist_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

class BeybladeHomePage extends StatelessWidget {
  const BeybladeHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    // Keyed by user: signing in as someone else builds fresh cubits and
    // reruns initState, so the old user's summary never shows. The tab
    // stays alive in the IndexedStack, so without the key it wouldn't
    // reload.
    // final userId = context.select((AuthCubit c) => c.state.user?.id);
    return const _BeybladeHomeView();
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
      backgroundColor: cs.surface,
      maxWidth: rc.maxContentWidth,
      appBar: AppBar(
        title: const Text('BeyVentory'),
        centerTitle: false,
        actions: [
          IconButton(
            tooltip: TrTokens.searchPartsTxt.tr,
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
          padding: EdgeInsets.fromLTRB(
              rc.horizontalPadding, rc.md, rc.horizontalPadding, rc.xxl),
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
                child: AdSlotPlaceholder(
                  image: AssetImage('assets/images/releasesnads/ad_i.webp'),
                  height: 112,
                ),
              ),
            ),
            SizedBox(height: rc.lg),

            // ── Collection ─────────────────────────────────────────────────
            SectionTitle(
              title: TrTokens.yourCollectionTxt.tr,
              // action: TextButton.icon(
              //   icon: const Icon(Icons.insights_outlined, size: 18),
              //   label: Text(TrTokens.accessHead.tr),
              //   onPressed: () => context.push(BeybladeRoutes.analytics),
              // ),
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
            SectionTitle(title: TrTokens.manageTxt.tr),
            AdaptiveGrid(
              minTileWidth: 260,
              children: [
                _NavCard(
                  icon: Icons.inventory_2_outlined,
                  title: TrTokens.colHead.tr,
                  subtitle: TrTokens.myCollectionCardSub.tr,
                  onTap: () => context.push(BeybladeRoutes.inventory),
                ),
                _NavCard(
                  icon: Icons.favorite_border,
                  title: TrTokens.colWishlist.tr,
                  subtitle: TrTokens.wishlistCardSub.tr,
                  onTap: () => context.push(BeybladeRoutes.wishlist),
                ),
                _NavCard(
                  icon: Icons.collections_bookmark_outlined,
                  title: TrTokens.decksCombosCardTitle.tr,
                  subtitle: TrTokens.decksCombosCardSub.tr,
                  onTap: () => context.push(BeybladeRoutes.combosDecks),
                ),
                _NavCard(
                  icon: Icons.inventory_2_outlined,
                  title: TrTokens.kitsPageTitle.tr,
                  subtitle: TrTokens.kitsCardSubtitle.tr,
                  onTap: () => context.push(BeybladeRoutes.partLists),
                ),
                //TODO UPCOMING
                // _NavCard(
                //   icon: Icons.style_outlined,
                //   title: TrTokens.cardGameCardTitle.tr,
                //   subtitle: TrTokens.cardGameCardSub.tr,
                //   onTap: () => context.push(BeybladeRoutes.tcg),
                // ),
                _NavCard(
                  icon: Icons.science_outlined,
                  title: TrTokens.testingCardTitle.tr,
                  subtitle: TrTokens.testingCardSub.tr,
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
                  title: TrTokens.settingsDataCardTitle.tr,
                  subtitle: TrTokens.settingsDataCardSub.tr,
                  onTap: () => context.push(SettingsRoutes.home),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

//TODO push thiss to the shell page
  /// The policy-update notice sits under the list, outside the scroll view,
  /// so it stays on screen until it is accepted. Takes no space otherwise.
  // Widget _withPolicyBar(Widget content) => Column(
  //       children: [
  //         Expanded(child: content),
  //         const PolicyUpdateBar(),
  //       ],
  //     );
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
            Text(TrTokens.emptyCollectionTitleTxt.tr,
                style: tt.titleSmall, textAlign: TextAlign.center),
            const SizedBox(height: 4),
            Text(
              TrTokens.emptyCollectionDescTxt.tr,
              textAlign: TextAlign.center,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(220, 46)),
              onPressed: onAddPressed,
              icon: const Icon(Icons.add),
              label: Text(TrTokens.findPartsToAddTxt.tr),
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
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
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
                            child: Text(TrTokens.latestTxt.tr,
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
              Text(
                TrTokens.itemsCountTxt.trArgs([summary.totalCount]),
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
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
                                HoloActionButton(
                                  label: TrTokens.inventoryTitle.tr,
                                  // icon: Icons.move_down,
                                  variant: HoloButtonVariant.outline,
                                  dense: true,
                                  height: 40,
                                  onPressed: () =>
                                      context.push(BeybladeRoutes.inventory),
                                ),
                                const SizedBox(width: 8),
                                HoloActionButton(
                                  label: TrTokens.colWishlist.tr,
                                  // icon: Icons.call_made,
                                  variant: HoloButtonVariant.outline,
                                  dense: true,
                                  height: 40,
                                  onPressed: () =>
                                      context.push(BeybladeRoutes.wishlist),
                                ),
                                const SizedBox(width: 8),
                                HoloIconButton(
                                  icon: Icons.insights_outlined,
                                  onPressed: () =>
                                      context.push(BeybladeRoutes.analytics),
                                  variant: HoloButtonVariant.outline,
                                  size: 36,
                                  iconSize: 20,
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
