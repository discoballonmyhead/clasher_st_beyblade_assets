import 'package:clasher_st/core/constants/trc_constant_tokens.dart';
import 'package:clasher_st/core/init_injection/injection.dart';
import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/services/translation/translation_helper.dart';
import 'package:clasher_st/core/widgets/app_beyblade_loading_indicator.dart';
import 'package:clasher_st/core/widgets/app_info_chip.dart';
import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/utils/catalog_randomizer.dart';
import 'package:clasher_st/features/beyblade/utils/deck_randomizer.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

// =============================================================================
// RANDOM DECKS: choice, roller, sheet
// -----------------------------------------------------------------------------
// One place decides where random beys come from, used by deck registration,
// the single walk-in page and the bulk walk-in page:
//   RandomizerChoice  what to roll from (catalog or saved combos) + filters
//   RandomDeckRoller  rolls decks; holds one loaded catalog per screen
//   RandomizerSheet   lets the user change the choice
// =============================================================================

enum RandomSource { catalog, savedCombos }

class RandomizerChoice extends Equatable {
  const RandomizerChoice({
    this.source = RandomSource.catalog,
    this.filter = const RandomBuildFilter(),
    this.uniqueParts = true,
  });

  final RandomSource source;
  final RandomBuildFilter filter;

  /// No part (variants included) twice in one deck: the tournament rule.
  final bool uniqueParts;

  /// The last choice confirmed in the sheet, kept for the rest of the app
  /// session so a host rolling many walk-ins sets the filters once.
  static RandomizerChoice lastUsed = const RandomizerChoice();

  /// Short description for buttons and hints, e.g. "X · Takara Tomy".
  String get summary {
    if (source == RandomSource.savedCombos) return 'From your saved combos';
    final parts = <String>[
      if (filter.generations.isEmpty)
        'Any generation'
      else
        filter.generations.join(', '),
      if (filter.manufacturers.isNotEmpty) filter.manufacturers.join(', '),
    ];
    return parts.join(' · ');
  }

  RandomizerChoice copyWith({
    RandomSource? source,
    RandomBuildFilter? filter,
    bool? uniqueParts,
  }) =>
      RandomizerChoice(
        source: source ?? this.source,
        filter: filter ?? this.filter,
        uniqueParts: uniqueParts ?? this.uniqueParts,
      );

  @override
  List<Object?> get props => [source, filter, uniqueParts];
}

/// Rolls random decks for one screen. Opens the catalog once, on first use,
/// and reuses it, so rolling a deck for each of 30 pasted names costs one
/// catalog load. A failed load is forgotten so the next roll retries.
class RandomDeckRoller {
  RandomDeckRoller([CatalogRandomizer? randomizer])
      : _randomizer = randomizer ?? sl<CatalogRandomizer>();

  final CatalogRandomizer _randomizer;
  Future<RandomizerSession>? _session;

  Future<RandomizerSession> session() {
    final existing = _session;
    if (existing != null) return existing;
    final opening = _randomizer.openSession();
    _session = opening;
    opening.then<void>((_) {}, onError: (Object _) => _session = null);
    return opening;
  }

  /// [count] loadouts, or null when the choice can't produce that many
  /// (too few saved combos, or filters that leave too few parts).
  Future<List<BeybladeLoadout>?> roll(
    RandomizerChoice choice,
    int count, {
    List<Combo> savedCombos = const [],
  }) async {
    if (choice.source == RandomSource.savedCombos) {
      return DeckRandomizer.pickDistinct(savedCombos, count)
          ?.map((c) => c.loadout)
          .toList();
    }
    final s = await session();
    return s.deck(count, choice.filter, uniqueParts: choice.uniqueParts);
  }

  /// One loadout for a single slot. With unique parts on, it avoids every
  /// part already in [others] (the deck's other slots). Saved-combo mode
  /// avoids combos whose loadout is already in [others].
  Future<BeybladeLoadout?> rollOne(
    RandomizerChoice choice, {
    List<BeybladeLoadout> others = const [],
    List<Combo> savedCombos = const [],
  }) async {
    if (choice.source == RandomSource.savedCombos) {
      final pool = [
        for (final c in savedCombos)
          if (!others.contains(c.loadout)) c,
      ];
      return DeckRandomizer.pickOne(pool)?.loadout;
    }
    final s = await session();
    final used = choice.uniqueParts
        ? {for (final o in others) ...s.familiesOf(o)}
        : null;
    return s.build(choice.filter, usedFamilies: used);
  }
}

/// Bottom sheet for changing the random choice. Returns the confirmed
/// choice (also stored in [RandomizerChoice.lastUsed]) or null.
class RandomizerSheet extends StatefulWidget {
  const RandomizerSheet._({
    required this.beyCount,
    required this.savedComboCount,
    required this.roller,
    required this.initial,
    required this.confirmLabel,
  });

  final int beyCount;
  final int savedComboCount;
  final RandomDeckRoller roller;
  final RandomizerChoice initial;
  final String confirmLabel;

  static Future<RandomizerChoice?> show(
    BuildContext context, {
    required int beyCount,
    required RandomDeckRoller roller,
    int savedComboCount = 0,
    String? confirmLabel,
  }) async {
    final choice = await showModalBottomSheet<RandomizerChoice>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => RandomizerSheet._(
        beyCount: beyCount,
        savedComboCount: savedComboCount,
        roller: roller,
        initial: RandomizerChoice.lastUsed,
        confirmLabel: confirmLabel ?? 'Roll $beyCount beys',
      ),
    );
    if (choice != null) RandomizerChoice.lastUsed = choice;
    return choice;
  }

  @override
  State<RandomizerSheet> createState() => _RandomizerSheetState();
}

class _RandomizerSheetState extends State<RandomizerSheet> {
  late RandomizerChoice _choice = widget.initial;
  late final Future<RandomizerSession> _session = widget.roller.session();

  bool get _combosEnough => widget.savedComboCount >= widget.beyCount;

  @override
  void initState() {
    super.initState();
    // A remembered "saved combos" choice can't be used on a screen with
    // too few of them; fall back to the catalog.
    if (_choice.source == RandomSource.savedCombos && !_combosEnough) {
      _choice = _choice.copyWith(source: RandomSource.catalog);
    }
  }

  void _setFilter(RandomBuildFilter f) =>
      setState(() => _choice = _choice.copyWith(filter: f));

  Set<String> _toggle(Set<String> set, String value) {
    final next = {...set};
    if (!next.remove(value)) next.add(value);
    return next;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    final catalog = _choice.source == RandomSource.catalog;

    return Padding(
      padding: EdgeInsets.fromLTRB(
          rc.horizontalPadding, 0, rc.horizontalPadding, rc.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HoloSectionLabel(
            title: TrTokens.randomFromTxt.tr,
            info: InfoChip(
              title: TrTokens.randomBeysTxt.tr,
              popupIcon: Icons.casino_outlined,
              details: TrTokens.randomBeysInfo.tr,
            ),
          ),
          SizedBox(height: rc.sm),
          HoloSegmented<RandomSource>(
            value: _choice.source,
            onChanged: (v) =>
                setState(() => _choice = _choice.copyWith(source: v)),
            options: [
              HoloOption(RandomSource.catalog, TrTokens.catalogSource.tr,
                  icon: Icons.dataset_outlined),
              HoloOption(
                RandomSource.savedCombos,
                TrTokens.myCombosSource.tr,
                icon: Icons.bookmarks_outlined,
                badge: '${widget.savedComboCount}',
                enabled: _combosEnough,
              ),
            ],
          ),
          if (!_combosEnough) ...[
            SizedBox(height: rc.xs),
            Text(
              TrTokens.minCombosRequired.trArgs([widget.beyCount]),
              style: TextStyle(fontSize: rc.bodySM, color: cs.onSurfaceVariant),
            ),
          ],
          if (catalog)
            Flexible(
              child: FutureBuilder<RandomizerSession>(
                future: _session,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: rc.lg),
                      child: Text(
                        TrTokens.catalogLoadError.tr,
                        style: TextStyle(color: cs.error),
                      ),
                    );
                  }
                  final session = snap.data;
                  if (session == null) {
                    return Padding(
                      padding: EdgeInsets.symmetric(vertical: rc.lg),
                      child: const Center(child: BeybladeSpinner()),
                    );
                  }
                  return _CatalogFilters(
                    facets: session.facets,
                    choice: _choice,
                    feasible: session.deck(widget.beyCount, _choice.filter,
                            uniqueParts: _choice.uniqueParts) !=
                        null,
                    beyCount: widget.beyCount,
                    onGeneration: (g) => _setFilter(_choice.filter.copyWith(
                        generations: g == null
                            ? const {}
                            : _toggle(_choice.filter.generations, g))),
                    onManufacturer: (m) => _setFilter(_choice.filter.copyWith(
                        manufacturers: m == null
                            ? const {}
                            : _toggle(_choice.filter.manufacturers, m))),
                    onExcludeIllegal: (v) =>
                        _setFilter(_choice.filter.copyWith(excludeIllegal: v)),
                    onAllowSeparated: (v) =>
                        _setFilter(_choice.filter.copyWith(allowSeparated: v)),
                    onUniqueParts: (v) => setState(
                        () => _choice = _choice.copyWith(uniqueParts: v)),
                    onConfirm: () => Navigator.of(context).pop(_choice),
                    confirmLabel: widget.confirmLabel,
                  );
                },
              ),
            )
          else ...[
            SizedBox(height: rc.lg),
            HoloActionButton(
              label: widget.confirmLabel,
              icon: Icons.casino_outlined,
              expand: true,
              onPressed: _combosEnough
                  ? () => Navigator.of(context).pop(_choice)
                  : null,
            ),
          ],
        ],
      ),
    );
  }
}

class _CatalogFilters extends StatelessWidget {
  const _CatalogFilters({
    required this.facets,
    required this.choice,
    required this.feasible,
    required this.beyCount,
    required this.onGeneration,
    required this.onManufacturer,
    required this.onExcludeIllegal,
    required this.onAllowSeparated,
    required this.onUniqueParts,
    required this.onConfirm,
    required this.confirmLabel,
  });

  final CatalogFacets facets;
  final RandomizerChoice choice;
  final bool feasible;
  final int beyCount;
  final ValueChanged<String?> onGeneration;
  final ValueChanged<String?> onManufacturer;
  final ValueChanged<bool> onExcludeIllegal;
  final ValueChanged<bool> onAllowSeparated;
  final ValueChanged<bool> onUniqueParts;
  final VoidCallback onConfirm;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    final f = choice.filter;

    Widget chips(List<String> values, Set<String> selected,
            ValueChanged<String?> onTap) =>
        Wrap(
          spacing: rc.xs,
          runSpacing: rc.xs,
          children: [
            FilterChip(
              label: const Text('Any'), // Map this if needed
              selected: selected.isEmpty,
              onSelected: (_) => onTap(null),
            ),
            for (final v in values)
              FilterChip(
                label: Text(v),
                selected: selected.contains(v),
                onSelected: (_) => onTap(v),
              ),
          ],
        );

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: rc.lg),
          HoloSubLabel(title: TrTokens.generationTxt.tr),
          SizedBox(height: rc.xs),
          chips(facets.generations, f.generations, onGeneration),
          SizedBox(height: rc.md),
          HoloSubLabel(
            title: TrTokens.manufacturerTxt.tr,
            info: InfoChip(
              title: TrTokens.manufacturerTxt.tr,
              popupIcon: Icons.factory_outlined,
              details: TrTokens.manufacturerInfo.tr,
            ),
          ),
          SizedBox(height: rc.xs),
          chips(facets.manufacturers, f.manufacturers, onManufacturer),
          SizedBox(height: rc.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: choice.uniqueParts,
            onChanged: onUniqueParts,
            title: Text(TrTokens.noRepeatedParts.tr),
            subtitle: Text(TrTokens.noRepeatedPartsSub.tr),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: f.excludeIllegal,
            onChanged: onExcludeIllegal,
            title: Text(TrTokens.leaveOutIllegal.tr),
            subtitle: Text(TrTokens.leaveOutIllegalSub.tr),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: f.allowSeparated,
            onChanged: onAllowSeparated,
            title: Text(TrTokens.allowLockChip.tr),
            subtitle: Text(TrTokens.allowLockChipSub.tr),
          ),
          if (!feasible)
            Padding(
              padding: EdgeInsets.only(bottom: rc.sm),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      size: 18, color: HoloTokens.of(context).warning),
                  SizedBox(width: rc.xs),
                  Expanded(
                    child: Text(
                      TrTokens.tooFewPartsError.trArgs([beyCount]),
                      style: TextStyle(
                          fontSize: rc.bodySM, color: cs.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(height: rc.sm),
          HoloActionButton(
            label: confirmLabel,
            icon: Icons.casino_outlined,
            expand: true,
            onPressed: feasible ? onConfirm : null,
          ),
        ],
      ),
    );
  }
}
