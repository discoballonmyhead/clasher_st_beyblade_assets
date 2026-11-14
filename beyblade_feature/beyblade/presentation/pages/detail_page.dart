import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/widgets/app_beyblade_loading_indicator.dart';
import 'package:clasher_st/core/widgets/app_info_chip.dart';
import 'package:clasher_st/core/widgets/holo_detail_row.dart';
import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/beyblade/b_routes/beyblade_routes.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/domain/repositories/beyblade_data_repo.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/catalog_extras.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/loyalty_badge.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/part_image_thumb.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/stat_bar_row.dart';
import 'package:clasher_st/features/user_collection/domain/entities/entities.dart';
import 'package:clasher_st/features/user_collection/domain/usecases/usecases.dart';
import 'package:clasher_st/features/user_collection/presentation/cubit/inventory_cubit/inventory_cubit.dart';
import 'package:clasher_st/features/user_collection/presentation/cubit/wishlist_cubit/wishlist_cubit.dart';
import 'package:clasher_st/features/user_collection/presentation/pages/collection_analytics_page.dart';
import 'package:clasher_st/features/user_collection/presentation/widgets/manage_inventory_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

// ── SUBJECT ──────────────────────────────────────────────────────────────────

/// Which of the three catalog things this page is showing.
///
/// This is presentation-layer only: it describes a page argument, not a
/// domain fact, which is why it lives here and not in entities.dart. It
/// travels through GoRouter as `extra`, since a live object can't be
/// encoded into a URL path.
sealed class DetailSubject {
  const DetailSubject();
}

class PartDetailSubject extends DetailSubject {
  const PartDetailSubject(this.part, this.partTypeKey);
  final BeybladePart part;
  final String partTypeKey;
}

class ProductDetailSubject extends DetailSubject {
  const ProductDetailSubject(this.product);
  final Product product;
}

class AccessoryDetailSubject extends DetailSubject {
  const AccessoryDetailSubject(this.accessory);
  final Accessory accessory;
}

/// Builds the right subject from whichever of the three resolved a
/// caller happens to hold. Every list that can open this page (the
/// collection grid, the wishlist, the loans list) faces the same
/// "one of these three is non-null" problem, so it's solved once here.
/// Returns null when nothing resolved — the caller should not navigate.
DetailSubject? detailSubjectFor({
  BeybladePart? part,
  String? partTypeKey,
  Product? product,
  Accessory? accessory,
}) {
  if (part != null) {
    return PartDetailSubject(part, partTypeKey ?? partTypeKeyFor(part));
  }
  if (product != null) return ProductDetailSubject(product);
  if (accessory != null) return AccessoryDetailSubject(accessory);
  return null;
}

/// One product this part shipped in, and what it came with. When the catalog declares the box's stock
/// combo ([combo], sheet stockCombos), [siblingItems] are that combo's other parts -- exactly the ratchet
/// and bit (or lock chip, assist blade ...) this part is assembled with out of the box, even in a set with
/// several beys. Without a declared combo it falls back to everything else in the box.
class ShippedIn {
  const ShippedIn({
    required this.product,
    required this.siblingItems,
    this.combo,
  });
  final Product product;
  final List<ResolvedContentItem> siblingItems;
  final StockCombo? combo;
}

/// A product's declared stock combo with its parts resolved, for the product page.
class ResolvedStockCombo {
  const ResolvedStockCombo({required this.combo, required this.parts});
  final StockCombo combo;
  final List<ResolvedContentItem> parts;
}

/// One resolved row of a product's contents: either a part (with the
/// type key needed to route back into this page) or an accessory.
class ResolvedContentItem {
  const ResolvedContentItem({
    this.part,
    this.partTypeKey,
    this.accessory,
    required this.quantity,
  });

  final BeybladePart? part;
  final String? partTypeKey;
  final Accessory? accessory;
  final int quantity;

  String get name => part?.name ?? accessory?.name ?? 'Unknown';
  String? get imageUrl => part != null
      ? preferredThumbUrl(part)
      : preferredAccessoryThumbUrl(accessory);
}

// ── PAGE ─────────────────────────────────────────────────────────────────────

class DetailPage extends StatefulWidget {
  const DetailPage({super.key, required this.subject});
  final DetailSubject subject;

  @override
  State<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends State<DetailPage> {
  late Future<_ResolvedDetail> _future;
  List<CollectionEvent> _history = const [];

  @override
  void initState() {
    super.initState();
    _future = _resolve();
    _loadHistory();
  }

  (InventoryItemType, String, String?) get _subjectKey =>
      switch (widget.subject) {
        PartDetailSubject(:final part, :final partTypeKey) => (
            InventoryItemType.part,
            part.dataId,
            partTypeKey
          ),
        ProductDetailSubject(:final product) => (
            InventoryItemType.product,
            product.productId,
            null
          ),
        AccessoryDetailSubject(:final accessory) => (
            InventoryItemType.accessory,
            accessory.dataId,
            null
          ),
      };

  Future<void> _loadHistory() async {
    final (_, catalogId, partTypeKey) = _subjectKey;
    final history = await GetIt.instance<GetCollectionHistoryUseCase>()
        .forItem(catalogId, partTypeKey: partTypeKey);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _history = history);
    });
  }

  Future<_ResolvedDetail> _resolve() async {
    final repo = GetIt.instance<BeybladeDataRepo>();
    switch (widget.subject) {
      case PartDetailSubject(:final part, :final partTypeKey):
        final variants = await repo.getVariantGroup(partTypeKey, part.dataId);
        final links =
            await repo.getProductContentsForItem(partTypeKey, part.dataId);
        final declared =
            await repo.getStockCombosForPart(partTypeKey, part.dataId);
        final stockCombos = <ShippedIn>[];
        final productIds = <String>{};
        for (final link in links) {
          if (!productIds.add(link.productId)) continue;
          final product = await repo.getProductByProductId(link.productId);
          if (product == null) continue;
          final combos =
              declared.where((c) => c.productId == product.productId);
          if (combos.isNotEmpty) {
            for (final c in combos) {
              stockCombos.add(ShippedIn(
                product: product,
                combo: c,
                siblingItems: await _comboParts(repo, c,
                    skip: (partTypeKey, part.dataId)),
              ));
            }
            continue;
          }
          final allContents =
              await repo.getContentsForProduct(product.productId);
          final siblings = <ResolvedContentItem>[];
          for (final siblingLink in allContents) {
            final isSelf = siblingLink.partType == partTypeKey &&
                siblingLink.partDataId == part.dataId;
            if (isSelf) continue;
            siblings.add(await _resolveContent(repo, siblingLink));
          }
          siblings.removeWhere((s) => s.part == null && s.accessory == null);
          stockCombos.add(ShippedIn(product: product, siblingItems: siblings));
        }
        // declared combos of products whose contents don't list this part
        for (final c in declared) {
          if (productIds.contains(c.productId)) continue;
          final product = await repo.getProductByProductId(c.productId);
          if (product == null) continue;
          stockCombos.add(ShippedIn(
            product: product,
            combo: c,
            siblingItems:
                await _comboParts(repo, c, skip: (partTypeKey, part.dataId)),
          ));
        }
        return _ResolvedDetail(
          variants: variants,
          stockCombos: stockCombos,
          bladers: await repo.getBladersForPart(part),
        );

      case AccessoryDetailSubject(:final accessory):
        final links = await repo.getProductContentsForItem(
            'accessories', accessory.dataId);
        final products = <Product>[];
        for (final link in links) {
          final p = await repo.getProductByProductId(link.productId);
          if (p != null) products.add(p);
        }
        return _ResolvedDetail(
            variants: const [], includedInProducts: products);

      case ProductDetailSubject(:final product):
        final links = await repo.getContentsForProduct(product.productId);
        final contents = <ResolvedContentItem>[];
        for (final link in links) {
          final resolved = await _resolveContent(repo, link);
          if (resolved.part != null || resolved.accessory != null) {
            contents.add(resolved);
          }
        }
        final combos = <ResolvedStockCombo>[
          for (final c in await repo.getStockCombosForProduct(product.productId))
            ResolvedStockCombo(combo: c, parts: await _comboParts(repo, c)),
        ];
        return _ResolvedDetail(
          variants: const [],
          productContents: contents,
          productStockCombos: combos,
        );
    }
  }

  /// The parts of a declared stock combo, top to bottom (minus [skip], the part whose page this is).
  Future<List<ResolvedContentItem>> _comboParts(
      BeybladeDataRepo repo, StockCombo combo,
      {(String, String)? skip}) async {
    final out = <ResolvedContentItem>[];
    for (final (type, id) in combo.partRefs) {
      if (skip != null && skip.$1 == type && skip.$2 == id) continue;
      final p = await repo.getPartByTypeAndDataId(type, id);
      if (p != null) {
        out.add(ResolvedContentItem(part: p, partTypeKey: type, quantity: 1));
      }
    }
    return out;
  }

  Future<ResolvedContentItem> _resolveContent(
      BeybladeDataRepo repo, ProductContent link) async {
    if (link.partType == 'accessories') {
      return ResolvedContentItem(
        accessory: await repo.getAccessoryByDataId(link.partDataId),
        quantity: link.quantity,
      );
    }
    return ResolvedContentItem(
      part: await repo.getPartByTypeAndDataId(link.partType, link.partDataId),
      partTypeKey: link.partType,
      quantity: link.quantity,
    );
  }

  String get _title => switch (widget.subject) {
        PartDetailSubject(:final part) => part.name,
        ProductDetailSubject(:final product) => product.productName,
        AccessoryDetailSubject(:final accessory) => accessory.name,
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        // maxLines + ellipsis: a long part name used to fight the actions.
        title: Text(_title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [_WishlistButton(subjectKey: _subjectKey)],
      ),
      body: SafeArea(
        child: FutureBuilder<_ResolvedDetail>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return HoloEmptyState(
                icon: Icons.error_outline,
                title: 'Could not load this item',
                message: 'Its catalog data could not be read.',
                action: HoloActionButton(
                  label: 'Retry',
                  icon: Icons.refresh,
                  variant: HoloButtonVariant.outline,
                  onPressed: () => setState(() => _future = _resolve()),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: BeybladeSpinner());
            }
            final resolved = snapshot.data!;

            return Column(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      // Was unbounded: text ran the full width of a tablet.
                      constraints: BoxConstraints(maxWidth: rc.maxContentWidth),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final wide = constraints.maxWidth >=
                              AppBreakpoints.tabletMedium;
                          return SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                              rc.horizontalPadding,
                              rc.md,
                              rc.horizontalPadding,
                              rc.xxl,
                            ),
                            child: wide
                                ? _TwoPane(
                                    subject: widget.subject,
                                    resolved: resolved,
                                    history: _history,
                                  )
                                : _OnePane(
                                    subject: widget.subject,
                                    resolved: resolved,
                                    history: _history,
                                  ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                _ActionBar(
                  subjectKey: _subjectKey,
                  itemName: _title,
                  onChanged: _loadHistory,
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ResolvedDetail {
  const _ResolvedDetail({
    required this.variants,
    this.includedInProducts = const [],
    this.productContents = const [],
    this.stockCombos = const [],
    this.bladers = const [],
    this.productStockCombos = const [],
  });

  final List<BeybladePart> variants;
  final List<Product> includedInProducts;
  final List<ResolvedContentItem> productContents;
  final List<ShippedIn> stockCombos;

  /// Who uses this part in the show.
  final List<Blader> bladers;

  /// A product page's declared stock combos.
  final List<ResolvedStockCombo> productStockCombos;
}

// ── LAYOUTS ──────────────────────────────────────────────────────────────────

/// Phone and small tablet: one column, ordered by what people look for
/// first. Identity, then the four headline facts, then performance, then
/// the optional depth.
class _OnePane extends StatelessWidget {
  const _OnePane({
    required this.subject,
    required this.resolved,
    required this.history,
  });

  final DetailSubject subject;
  final _ResolvedDetail resolved;
  final List<CollectionEvent> history;

  @override
  Widget build(BuildContext context) {
    final rc = ResponsiveProvider.config(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Identity(subject: subject, compact: true),
        SizedBox(height: rc.lg),
        ..._detailSections(context, subject, resolved, history),
      ],
    );
  }
}

/// Desktop and large tablet: the artwork and headline facts stay on the
/// left while the detail scrolls on the right.
class _TwoPane extends StatelessWidget {
  const _TwoPane({
    required this.subject,
    required this.resolved,
    required this.history,
  });

  final DetailSubject subject;
  final _ResolvedDetail resolved;
  final List<CollectionEvent> history;

  @override
  Widget build(BuildContext context) {
    final rc = ResponsiveProvider.config(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Fixed, not Expanded: the artwork should not grow with the window.
        SizedBox(
          width: 320,
          child: _Identity(subject: subject, compact: false),
        ),
        SizedBox(width: rc.xl),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _detailSections(context, subject, resolved, history),
          ),
        ),
      ],
    );
  }
}

/// Shared by both layouts so the two can never drift out of sync.
List<Widget> _detailSections(
  BuildContext context,
  DetailSubject subject,
  _ResolvedDetail resolved,
  List<CollectionEvent> history,
) {
  final rc = ResponsiveProvider.config(context);
  Widget gap() => SizedBox(height: rc.lg);

  return [
    switch (subject) {
      PartDetailSubject(:final part, :final partTypeKey) => _PartSections(
          part: part,
          partTypeKey: partTypeKey,
          variants: resolved.variants,
          stockCombos: resolved.stockCombos,
          bladers: resolved.bladers,
        ),
      AccessoryDetailSubject(:final accessory) => _AccessorySections(
          accessory: accessory,
          products: resolved.includedInProducts,
        ),
      ProductDetailSubject(:final product) => _ProductSections(
          product: product,
          contents: resolved.productContents,
          stockCombos: resolved.productStockCombos,
        ),
    },
    if (history.isNotEmpty) ...[
      gap(),
      _HistorySection(events: history),
    ],
  ];
}

// ── IDENTITY (artwork + name + status) ───────────────────────────────────────

class _Identity extends StatelessWidget {
  const _Identity({required this.subject, required this.compact});

  final DetailSubject subject;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);

    // compact: false asks for the full-resolution image, which is the whole
    // point of a detail view -- the old code always took the thumb.
    final (imageUrl, scale, title, subtitle, legality, incomplete) =
        switch (subject) {
      PartDetailSubject(:final part) => (
          preferredThumbUrl(part, compact: false),
          imageScaleFor(part),
          part.name,
          '${part.manufacturer} · ${part.hobbyGeneration}',
          part.legality,
          part.isIncomplete,
        ),
      ProductDetailSubject(:final product) => (
          preferredProductThumbUrl(product, compact: false),
          1.0,
          product.productName,
          '${product.manufacturer} · ${product.hobbyGeneration}',
          null,
          product.isIncomplete,
        ),
      AccessoryDetailSubject(:final accessory) => (
          preferredAccessoryThumbUrl(accessory),
          1.0,
          accessory.name,
          '${accessory.manufacturer} · ${accessory.hobbyGeneration}',
          null,
          accessory.isIncomplete,
        ),
    };

    final nameBlock = Column(
      crossAxisAlignment:
          compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        // Two lines then ellipsis, and tappable for the rest -- the old
        // headlineSmall with no limit could push the artwork off-screen.
        InkWell(
          onTap: () => HoloDetailSheet.show(
            context,
            title: 'Name',
            value: title,
          ),
          borderRadius: BorderRadius.circular(8),
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: compact ? TextAlign.start : TextAlign.center,
            style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: compact ? TextAlign.start : TextAlign.center,
          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        SizedBox(height: rc.sm),
        // Wrap, never Row: three status chips on a 320px phone is exactly
        // where a Row overflows.
        Wrap(
          spacing: 6,
          runSpacing: 6,
          alignment: compact ? WrapAlignment.start : WrapAlignment.center,
          children: [
            if (legality != null) LegalityBadge(legality: legality),
            if (incomplete)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  HoloPill(
                    label: 'Partial data',
                    color: HoloTokens.of(context).warning,
                    icon: Icons.warning_amber_outlined,
                  ),
                  InfoChip(
                    title: 'Incomplete record',
                    color: HoloTokens.of(context).warning,
                    details: 'Some fields for this item are missing from the '
                        'catalog sheet, so stats or contents below may be '
                        'blank. This is a gap in the source data, not an '
                        'error in the app.',
                  ),
                ],
              ),
          ],
        ),
      ],
    );

    if (!compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: PartImageThumb(
              imageUrl: imageUrl,
              size: 260,
              scale: scale,
            ),
          ),
          SizedBox(height: rc.md),
          nameBlock,
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PartImageThumb(imageUrl: imageUrl, size: 104, scale: scale),
        SizedBox(width: rc.md),
        Expanded(child: nameBlock),
      ],
    );
  }
}

class _WishlistButton extends StatelessWidget {
  const _WishlistButton({required this.subjectKey});
  final (InventoryItemType, String, String?) subjectKey;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (itemType, catalogId, partTypeKey) = subjectKey;

    return BlocBuilder<WishlistCubit, WishlistState>(
      builder: (context, _) {
        final wishlisted = context
            .read<WishlistCubit>()
            .isWishlisted(catalogId, partTypeKey: partTypeKey);
        return IconButton(
          tooltip: wishlisted ? 'Remove from wishlist' : 'Add to wishlist',
          icon: Icon(wishlisted ? Icons.favorite : Icons.favorite_border,
              color: wishlisted ? cs.error : null),
          onPressed: () => context.read<WishlistCubit>().toggle(
                itemType: itemType,
                catalogId: catalogId,
                partTypeKey: partTypeKey,
              ),
        );
      },
    );
  }
}

// ── LABEL HELPERS ────────────────────────────────────────────────────────────

String _archetypeLabel(BeybladeArchetype a) => switch (a) {
      BeybladeArchetype.attack => 'Attack',
      BeybladeArchetype.defense => 'Defense',
      BeybladeArchetype.stamina => 'Stamina',
      BeybladeArchetype.balance => 'Balance',
      BeybladeArchetype.unknown => 'Unknown',
    };

String _spinLabel(SpinDirection s) => switch (s) {
      SpinDirection.left => 'Left',
      SpinDirection.right => 'Right',
      SpinDirection.unknown => 'Unknown',
    };

/// Attack red, Defense blue, Stamina green, matching the reference
/// screenshots. Dash and Burst Resistance don't appear there at all
/// (blades have neither), so those two colours are a choice of mine
/// rather than sourced from the reference.
const _statColors = <StatKey, Color>{
  StatKey.attack: Colors.redAccent,
  StatKey.defense: Colors.blueAccent,
  StatKey.stamina: Colors.greenAccent,
  StatKey.dash: Colors.orangeAccent,
  StatKey.burstResistance: Colors.purpleAccent,
};

String _statLabel(StatKey key) => switch (key) {
      StatKey.attack => 'Attack',
      StatKey.defense => 'Defense',
      StatKey.stamina => 'Stamina',
      StatKey.dash => 'Dash',
      StatKey.burstResistance => 'Burst Resistance',
    };

/// Archetype and spin, where the subtype has them. Returned as nullable
/// pairs so the fact grid can skip a fact rather than print "Unknown".
(String?, String?) _archetypeAndSpin(BeybladePart part) => switch (part) {
      Blade b => (_archetypeLabel(b.archetype), _spinLabel(b.spinDirection)),
      Bit b => (_archetypeLabel(b.movementStyle), null),
      OverBlade b => (_archetypeLabel(b.type), _spinLabel(b.spinDirection)),
      MetalBlade b => (_archetypeLabel(b.type), _spinLabel(b.spinDirection)),
      MainBlade b => (_archetypeLabel(b.type), _spinLabel(b.spinDirection)),
      AssistBlade b => (_archetypeLabel(b.type), _spinLabel(b.spinDirection)),
      _ => (null, null),
    };

// ── PART SECTIONS ────────────────────────────────────────────────────────────

class _PartSections extends StatelessWidget {
  const _PartSections({
    required this.part,
    required this.partTypeKey,
    required this.variants,
    required this.stockCombos,
    this.bladers = const [],
  });

  final BeybladePart part;
  final String partTypeKey;
  final List<BeybladePart> variants;
  final List<ShippedIn> stockCombos;
  final List<Blader> bladers;

  @override
  Widget build(BuildContext context) {
    final rc = ResponsiveProvider.config(context);
    final tokens = HoloTokens.of(context);
    final stats = part.stats;

    // Only the keys this part actually reports. The old code looped
    // StatKey.values, so a Ratchet rendered five empty "N/A" bars and
    // maxValue came out 0.
    final provided = stats.providedKeys.toList();
    final averages = provided
        .map((k) =>
            stats[k].values.reduce((a, b) => a + b) / stats[k].values.length)
        .toList();
    final maxAcrossStats =
        averages.isEmpty ? 0.0 : averages.reduce((a, b) => a > b ? a : b);

    final (archetype, spin) = _archetypeAndSpin(part);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // TIER 2 -- the four things someone opens a part page to read.
        HoloFactGrid(
          children: [
            HoloStatTile(
              label: 'Type',
              value: displayLabelForPartType(partTypeKey),
              icon: iconForGroupKey(partTypeKey),
            ),
            HoloStatTile(
              label: 'Mass',
              value: '${part.mass}g',
              icon: Icons.scale_outlined,
            ),
            if (archetype != null)
              HoloStatTile(
                label: 'Archetype',
                value: archetype,
                icon: Icons.sports_martial_arts_outlined,
                accent: tokens.warning,
              ),
            if (spin != null)
              HoloStatTile(
                label: 'Spin',
                value: spin,
                icon: Icons.rotate_right,
              ),
          ],
        ),

        // TIER 3 -- performance. Omitted entirely for parts with no stats,
        // rather than showing a wall of N/A.
        if (provided.isNotEmpty) ...[
          SizedBox(height: rc.lg),
          HoloSectionLabel(
            title: 'Performance',
            index: '01',
            info: const InfoChip(
              title: 'How to read these bars',
              details:
                  'Bars are relative to this part\'s own highest stat, not to '
                  'every part in the game, so they show the shape of a part '
                  'rather than its absolute power. A range like "30 – 55" is '
                  'a two-stat part whose value depends on how it is used.',
            ),
          ),
          SizedBox(height: rc.sm),
          HoloCard(
            padding: EdgeInsets.symmetric(horizontal: rc.md, vertical: rc.sm),
            child: Column(
              children: [
                for (final key in provided)
                  StatBarRow(
                    label: _statLabel(key),
                    spread: stats[key],
                    maxValue: maxAcrossStats,
                    color: _statColors[key],
                  ),
              ],
            ),
          ),
        ],

        // TIER 4 -- the optional depth.
        SizedBox(height: rc.lg),
        _SpecsCard(
          index: provided.isEmpty ? '01' : '02',
          rows: [
            HoloDetailRow(
              label: 'Code',
              value: part.code,
              monospaceValue: true,
              icon: Icons.tag,
            ),
            HoloDetailRow(
              label: 'Hobby line',
              value: part.hobbyName,
              icon: Icons.category_outlined,
            ),
            HoloDetailRow(
              label: 'Generation',
              value: part.hobbyGeneration,
              icon: Icons.timeline_outlined,
            ),
            HoloDetailRow(
              label: 'Manufacturer',
              value: part.manufacturer,
              icon: Icons.factory_outlined,
            ),
            if (part.edition != null)
              HoloDetailRow(
                label: 'Edition',
                value: part.edition!,
                icon: Icons.auto_awesome_outlined,
              ),
            if (part.variantLabel != null)
              HoloDetailRow(
                label: 'Variant',
                value: part.variantLabel!,
                icon: Icons.palette_outlined,
                details:
                    'A variant is the same mould in a different colourway or '
                    'release. It shares the parent part\'s stats.',
              ),
            HoloDetailRow(
              label: 'Catalog id',
              value: part.dataId,
              monospaceValue: true,
              icon: Icons.fingerprint,
            ),
          ],
        ),

        if (variants.length > 1) ...[
          SizedBox(height: rc.lg),
          _VariantsStrip(
            variants: variants,
            current: part,
            partTypeKey: partTypeKey,
          ),
        ],

        if (part.has3dModel) ...[
          SizedBox(height: rc.md),
          Align(
            alignment: Alignment.centerLeft,
            child: Model3dButton(url: part.model3dUrl, title: part.name),
          ),
        ],

        if (bladers.isNotEmpty) ...[
          SizedBox(height: rc.lg),
          BladersSection(bladers: bladers),
        ],

        if (stockCombos.isNotEmpty) ...[
          SizedBox(height: rc.lg),
          _StockCombosSection(combos: stockCombos),
        ],
      ],
    );
  }
}

/// The specifications card. Every row is a [HoloDetailRow], so a long
/// value truncates and opens rather than overflowing.
class _SpecsCard extends StatelessWidget {
  const _SpecsCard({required this.rows, this.index});
  final List<Widget> rows;
  final String? index;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HoloSectionLabel(title: 'Specifications', index: index),
        SizedBox(height: rc.sm),
        HoloCard(
          padding: EdgeInsets.symmetric(horizontal: rc.md, vertical: rc.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  Divider(
                      height: 1,
                      thickness: 1,
                      color: cs.outlineVariant.withValues(alpha: 0.4)),
                rows[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Horizontal variant picker.
///
/// The height is computed from the thumb, its border and its caption
/// instead of the old hardcoded 76 -- which was a 72px thumb plus two 2px
/// borders, i.e. exact, with no room for the label it now carries.
class _VariantsStrip extends StatelessWidget {
  const _VariantsStrip({
    required this.variants,
    required this.current,
    required this.partTypeKey,
  });

  final List<BeybladePart> variants;
  final BeybladePart current;
  final String partTypeKey;

  static const double _thumb = 72;
  static const double _border = 2;
  static const double _caption = 18;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HoloSectionLabel(
          title: 'Variants',
          subtitle: '${variants.length} colourways of this mould',
        ),
        SizedBox(height: rc.sm),
        SizedBox(
          height: _thumb + _border * 2 + _caption + 6,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: variants.length,
            separatorBuilder: (_, __) => SizedBox(width: rc.sm),
            itemBuilder: (context, i) {
              final v = variants[i];
              final isCurrent = v.dataId == current.dataId;
              return SizedBox(
                width: _thumb + _border * 2,
                child: Column(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(rc.borderRadius),
                      onTap: isCurrent
                          ? null
                          : () => context.push(BeybladeRoutes.detail,
                              extra: PartDetailSubject(v, partTypeKey)),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(rc.borderRadius),
                          border: Border.all(
                            color: isCurrent ? cs.primary : cs.outlineVariant,
                            width: _border,
                          ),
                        ),
                        // Via the helper, so a downloaded file wins.
                        child: PartImageThumb(
                          imageUrl: preferredThumbUrl(v),
                          size: _thumb,
                          scale: imageScaleFor(v),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isCurrent ? 'This one' : (v.variantLabel ?? v.code),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: tt.labelSmall?.copyWith(
                        color: isCurrent ? cs.primary : cs.onSurfaceVariant,
                        fontWeight:
                            isCurrent ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── STOCK COMBOS ─────────────────────────────────────────────────────────────

/// Capped at three in the body with the rest behind "See all": the old
/// page rendered every combo inline, which on a common blade meant a page
/// several screens long before History even started (Hick's law).
class _StockCombosSection extends StatelessWidget {
  const _StockCombosSection({required this.combos});
  final List<ShippedIn> combos;

  static const int _visible = 3;

  @override
  Widget build(BuildContext context) {
    final rc = ResponsiveProvider.config(context);
    final shown = combos.take(_visible).toList();
    final hidden = combos.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HoloSectionLabel(
          title: 'Stock combos',
          subtitle: 'Boxes this part shipped in',
          trailing: hidden <= 0
              ? null
              : HoloActionButton(
                  label: 'See all $hidden',
                  dense: true,
                  variant: HoloButtonVariant.outline,
                  onPressed: () => HoloDetailSheet.showRows(
                    context,
                    title: 'All ${combos.length} stock combos',
                    icon: Icons.inventory_2_outlined,
                    rows: [
                      for (final c in combos) _StockComboCard(combo: c),
                    ],
                  ),
                ),
        ),
        SizedBox(height: rc.sm),
        for (final combo in shown) _StockComboCard(combo: combo),
      ],
    );
  }
}

class _StockComboCard extends StatelessWidget {
  const _StockComboCard({required this.combo});
  final ShippedIn combo;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final rc = ResponsiveProvider.config(context);

    return HoloCard(
      margin: EdgeInsets.only(bottom: rc.sm),
      padding: EdgeInsets.all(rc.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => context.push(BeybladeRoutes.detail,
                extra: ProductDetailSubject(combo.product)),
            child: Row(
              children: [
                PartImageThumb(
                  imageUrl: preferredProductThumbUrl(combo.product),
                  size: 44,
                ),
                SizedBox(width: rc.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        combo.product.productName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: tt.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        combo.combo == null
                            ? combo.product.manufacturer
                            : '${combo.combo!.name} · ${combo.product.manufacturer}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
              ],
            ),
          ),
          if (combo.siblingItems.isNotEmpty) ...[
            SizedBox(height: rc.sm),
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.4)),
            SizedBox(height: rc.sm),
            Text(combo.combo == null ? 'Packed with' : 'Assembled with',
                style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
            SizedBox(height: rc.xs),
            Wrap(
              spacing: rc.sm,
              runSpacing: rc.sm,
              children: [
                for (final sibling in combo.siblingItems)
                  _SiblingChip(item: sibling),
              ],
            ),
          ],
          if (combo.combo != null) ...[
            SizedBox(height: rc.sm),
            StockComboActions(
                combo: combo.combo!, builderRoute: BeybladeRoutes.builder),
          ],
        ],
      ),
    );
  }
}

class _SiblingChip extends StatelessWidget {
  const _SiblingChip({required this.item});
  final ResolvedContentItem item;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);

    return InkWell(
      borderRadius: BorderRadius.circular(rc.borderRadius),
      onTap: () {
        final subject = detailSubjectFor(
          part: item.part,
          partTypeKey: item.partTypeKey,
          accessory: item.accessory,
        );
        if (subject == null) return;
        context.push(BeybladeRoutes.detail, extra: subject);
      },
      child: SizedBox(
        width: 64,
        child: Column(
          children: [
            PartImageThumb(
              imageUrl: item.imageUrl,
              size: 56,
              scale: item.part == null ? 1.0 : imageScaleFor(item.part),
            ),
            const SizedBox(height: 3),
            Text(
              item.name,
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── PRODUCT / ACCESSORY SECTIONS ─────────────────────────────────────────────

class _AccessorySections extends StatelessWidget {
  const _AccessorySections({required this.accessory, required this.products});
  final Accessory accessory;
  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    final rc = ResponsiveProvider.config(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HoloFactGrid(
          children: [
            HoloStatTile(
              label: 'Kind',
              value: accessory.accessoryType.toString(),
              icon: Icons.category_outlined,
            ),
            HoloStatTile(
              label: 'Generation',
              value: accessory.hobbyGeneration,
              icon: Icons.timeline_outlined,
            ),
          ],
        ),
        SizedBox(height: rc.lg),
        _SpecsCard(
          index: '01',
          rows: [
            HoloDetailRow(
              label: 'Hobby line',
              value: accessory.hobbyName,
              icon: Icons.category_outlined,
            ),
            HoloDetailRow(
              label: 'Manufacturer',
              value: accessory.manufacturer,
              icon: Icons.factory_outlined,
            ),
            HoloDetailRow(
              label: 'Catalog id',
              value: accessory.dataId,
              monospaceValue: true,
              icon: Icons.fingerprint,
            ),
          ],
        ),
        SizedBox(height: rc.lg),
        _ProductListSection(
          title: 'Included in',
          subtitle: 'Boxes that contain this accessory',
          products: products,
          emptyMessage: 'Not part of any known product yet.',
        ),
      ],
    );
  }
}

class _ProductSections extends StatelessWidget {
  const _ProductSections({
    required this.product,
    required this.contents,
    this.stockCombos = const [],
  });
  final Product product;
  final List<ResolvedContentItem> contents;

  /// The combos that come out of this box (declared in the catalog).
  final List<ResolvedStockCombo> stockCombos;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final rc = ResponsiveProvider.config(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HoloFactGrid(
          children: [
            if (product.productType != null)
              HoloStatTile(
                label: 'Kind',
                value: product.productType!,
                icon: Icons.inventory_2_outlined,
              ),
            HoloStatTile(
              label: 'Pieces',
              value: '${contents.length}',
              icon: Icons.widgets_outlined,
            ),
            HoloStatTile(
              label: 'Generation',
              value: product.hobbyGeneration,
              icon: Icons.timeline_outlined,
            ),
          ],
        ),
        SizedBox(height: rc.lg),
        _SpecsCard(
          index: '01',
          rows: [
            HoloDetailRow(
              label: 'Hobby line',
              value: product.hobbyName,
              icon: Icons.category_outlined,
            ),
            HoloDetailRow(
              label: 'Manufacturer',
              value: product.manufacturer,
              icon: Icons.factory_outlined,
            ),
            HoloDetailRow(
              label: 'Product id',
              value: product.productId,
              monospaceValue: true,
              icon: Icons.fingerprint,
            ),
          ],
        ),
        if (stockCombos.isNotEmpty) ...[
          SizedBox(height: rc.lg),
          HoloSectionLabel(
            title: 'Stock combos',
            subtitle: stockCombos.length == 1
                ? 'The combo out of the box'
                : '${stockCombos.length} combos out of the box',
          ),
          SizedBox(height: rc.sm),
          for (final c in stockCombos) _DeclaredComboCard(combo: c),
        ],
        SizedBox(height: rc.lg),
        HoloSectionLabel(
          title: 'Contents',
          subtitle: 'What comes in the box',
          index: '02',
        ),
        SizedBox(height: rc.sm),
        if (contents.isEmpty)
          HoloCard(
            child: Text('Contents not yet available.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          )
        else
          for (final item in contents)
            HoloCard(
              margin: EdgeInsets.only(bottom: rc.sm),
              padding: EdgeInsets.all(rc.sm + 2),
              onTap: () {
                final subject = detailSubjectFor(
                  part: item.part,
                  partTypeKey: item.partTypeKey,
                  accessory: item.accessory,
                );
                if (subject == null) return;
                context.push(BeybladeRoutes.detail, extra: subject);
              },
              child: Row(
                children: [
                  PartImageThumb(
                    imageUrl: item.imageUrl,
                    size: 44,
                    scale: item.part == null ? 1.0 : imageScaleFor(item.part),
                  ),
                  SizedBox(width: rc.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        Text(
                          item.part == null
                              ? 'Accessory · qty ${item.quantity}'
                              : '${displayLabelForPartType(item.partTypeKey ?? '')} · qty ${item.quantity}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: tt.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                ],
              ),
            ),
      ],
    );
  }
}

/// One declared stock combo on a product page: its name, its parts (tap one to open it) and its 3D model.
class _DeclaredComboCard extends StatelessWidget {
  const _DeclaredComboCard({required this.combo});
  final ResolvedStockCombo combo;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final rc = ResponsiveProvider.config(context);
    return HoloCard(
      margin: EdgeInsets.only(bottom: rc.sm),
      padding: EdgeInsets.all(rc.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(combo.combo.name,
              style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          SizedBox(height: rc.sm),
          Wrap(
            spacing: rc.sm,
            runSpacing: rc.sm,
            children: [for (final p in combo.parts) _SiblingChip(item: p)],
          ),
          SizedBox(height: rc.sm),
          StockComboActions(
              combo: combo.combo, builderRoute: BeybladeRoutes.builder),
        ],
      ),
    );
  }
}

class _ProductListSection extends StatelessWidget {
  const _ProductListSection({
    required this.title,
    required this.products,
    this.subtitle,
    this.emptyMessage,
  });

  final String title;
  final String? subtitle;
  final List<Product> products;
  final String? emptyMessage;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final rc = ResponsiveProvider.config(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HoloSectionLabel(title: title, subtitle: subtitle, index: '02'),
        SizedBox(height: rc.sm),
        if (products.isEmpty)
          HoloCard(
            child: Text(emptyMessage ?? 'Nothing here yet.',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          )
        else
          for (final product in products)
            HoloCard(
              margin: EdgeInsets.only(bottom: rc.sm),
              padding: EdgeInsets.all(rc.sm + 2),
              onTap: () => context.push(BeybladeRoutes.detail,
                  extra: ProductDetailSubject(product)),
              child: Row(
                children: [
                  PartImageThumb(
                    imageUrl: preferredProductThumbUrl(product),
                    size: 44,
                  ),
                  SizedBox(width: rc.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(product.productName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600)),
                        Text(product.manufacturer,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: tt.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                ],
              ),
            ),
      ],
    );
  }
}

// ── HISTORY ──────────────────────────────────────────────────────────────────

/// Four rows inline, the rest behind "See all". The old version rendered
/// twelve ListTiles unconditionally, which was usually the longest section
/// on the page and the least looked at.
class _HistorySection extends StatelessWidget {
  const _HistorySection({required this.events});
  final List<CollectionEvent> events;

  static const int _visible = 4;

  @override
  Widget build(BuildContext context) {
    final rc = ResponsiveProvider.config(context);
    final shown = events.take(_visible).toList();
    final hidden = events.length - shown.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HoloSectionLabel(
          title: 'History',
          trailing: hidden <= 0
              ? null
              : HoloActionButton(
                  label: 'See all $hidden',
                  dense: true,
                  variant: HoloButtonVariant.outline,
                  onPressed: () => HoloDetailSheet.showRows(
                    context,
                    title: 'All ${events.length} events',
                    icon: Icons.history,
                    rows: [for (final e in events) _HistoryRow(event: e)],
                  ),
                ),
        ),
        SizedBox(height: rc.sm),
        HoloCard(
          padding: EdgeInsets.symmetric(horizontal: rc.md, vertical: rc.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final e in shown) _HistoryRow(event: e)],
          ),
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.event});
  final CollectionEvent event;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final d = event.occurredAt;
    final date = '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Icon(Icons.circle, size: 7, color: cs.primary),
          ),
          const SizedBox(width: 10),
          // Expanded, so a long event description wraps instead of
          // overflowing the row.
          Expanded(
            child: Text(describeCollectionEvent(event),
                style: tt.bodySmall,
                maxLines: 3,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 10),
          Text(date,
              style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ── BOTTOM ACTION BAR ────────────────────────────────────────────────────────

/// "Add to Inventory" when the item isn't owned, and the owned count plus a
/// Manage button when it is.
///
/// Both buttons are [HoloActionButton], which is a Material + InkWell, NOT
/// a themed FilledButton. That matters: the app theme sets
/// `minimumSize: Size(double.infinity, 52)` on filled and outlined buttons,
/// and Size.fromHeight-style infinite widths throw "BoxConstraints forces an
/// infinite width" inside a Row. The old code only survived by passing
/// `minimumSize: Size.zero`, which is also why Manage was too small to hit.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.subjectKey,
    required this.itemName,
    required this.onChanged,
  });

  final (InventoryItemType, String, String?) subjectKey;
  final String itemName;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final rc = ResponsiveProvider.config(context);
    final (itemType, catalogId, partTypeKey) = subjectKey;

    return BlocBuilder<InventoryCubit, InventoryState>(
      builder: (context, state) {
        final owned = context
            .read<InventoryCubit>()
            .findByCatalogId(catalogId, partTypeKey: partTypeKey);

        return Container(
          padding: EdgeInsets.fromLTRB(
              rc.horizontalPadding, rc.sm, rc.horizontalPadding, rc.sm),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.center,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: rc.maxContentWidth),
                child: owned == null
                    ? HoloActionButton(
                        label: 'Add to inventory',
                        icon: Icons.add,
                        expand: true,
                        height: 50,
                        onPressed: () async {
                          final cubit = context.read<InventoryCubit>();
                          await cubit.ensureEntry(
                            itemType: itemType,
                            catalogId: catalogId,
                            partTypeKey: partTypeKey,
                          );
                          onChanged();
                        },
                      )
                    : Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('In your collection',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: tt.labelSmall
                                        ?.copyWith(color: cs.onSurfaceVariant)),
                                const SizedBox(height: 2),
                                Text(
                                  '${owned.entry.ownedQuantity} owned · '
                                  '${owned.entry.quantityInHand} in hand',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: tt.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(width: rc.sm),
                          // Bigger than before, and a real 48+ target.
                          HoloActionButton(
                            label: 'Manage',
                            icon: Icons.tune,
                            variant: HoloButtonVariant.outline,
                            height: 50,
                            onPressed: () async {
                              await showManageInventoryDialog(
                                context,
                                entry: owned.entry,
                                itemName: itemName,
                              );
                              onChanged();
                            },
                          ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}
