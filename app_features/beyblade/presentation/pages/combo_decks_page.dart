import 'package:clasher_st/core/constants/trc_constant_tokens.dart';
import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/services/translation/translation_helper.dart';
import 'package:clasher_st/core/widgets/app_dialog_widget.dart';
import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/combo_decks_paged_cubit/combo_decks_paged_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/pages/bey_builder_page.dart';
import 'package:clasher_st/features/beyblade/presentation/pages/combo_picker_page.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/paged_list_view.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/resolved_bey_thumb.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/resolved_minified_bey_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The account's decks and combos, a page at a time, each tab searchable.
/// Reads come from the account (or the phone's copy when offline / while
/// changes are still uploading); see CombosDecksRepositoryImpl.
class CombosDecksPage extends StatefulWidget {
  const CombosDecksPage({super.key});
  @override
  State<CombosDecksPage> createState() => _CombosDecksPageState();
}

class _CombosDecksPageState extends State<CombosDecksPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rc = ResponsiveProvider.config(context);
    final cs = Theme.of(context).colorScheme;
    return ResponsiveScaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(TrTokens.decksCombosCardTitle.tr),
        actions: [
          // One add button in the app bar: it creates whatever the open
          // tab holds. Builder: the cubits are provided below this
          // State's own context.
          Builder(
            builder: (context) => AnimatedBuilder(
              animation: _tabController,
              builder: (context, _) {
                final onDecks = _tabController.index == 0;
                return IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: onDecks
                      ? TrTokens.createDeckTxt.tr
                      : TrTokens.createComboTxt.tr,
                  onPressed: () =>
                      onDecks ? _createDeck(context) : _createCombo(context),
                );
              },
            ),
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.fromLTRB(
            rc.horizontalPadding, rc.sm, rc.horizontalPadding, rc.sm),
        child: Column(
          children: [
            HoloTabBar(
              controller: _tabController,
              tabs: const [
                HoloTab('Decks', icon: Icons.style_outlined),
                HoloTab('Combos', icon: Icons.bolt_outlined),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: const [_DecksTab(), _CombosTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Create ───────────────────────────────────────────────────────────────────

Future<String?> _promptForName(BuildContext context,
    {required String title, String initial = ''}) {
  final controller = TextEditingController(text: initial);
  return AppDialogWidget.show<String>(
    context,
    title: title,
    content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Name')),
    actionButton: FilledButton(
      onPressed: () {
        final trimmed = controller.text.trim();
        Navigator.of(context, rootNavigator: true)
            .pop(trimmed.isEmpty ? null : trimmed);
      },
      child: Text(TrTokens.saveTxt.tr),
    ),
    secondaryButton: OutlinedButton(
      onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
      child: Text(TrTokens.cancelTxt.tr),
    ),
  );
}

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Build a bey, name it, save it as a combo.
Future<void> _createCombo(BuildContext context) async {
  final beyblade = await Navigator.push<Beyblade>(
    context,
    MaterialPageRoute(
      builder: (routeContext) => BeyBuilderPage(
        onBuildConfirmed: (result) => Navigator.pop(routeContext, result),
      ),
    ),
  );
  if (beyblade == null || !context.mounted) return;

  final name =
      await _promptForName(context, title: TrTokens.nameThisComboTxt.tr);
  if (name == null || !context.mounted) return;

  try {
    await context.read<CombosPageCubit>().create(name, beyblade.loadout);
  } catch (_) {
    if (context.mounted) _snack(context, TrTokens.couldNotSaveTxt.tr);
  }
}

/// Pick 3+ combos on the picker page, name the deck, save it.
Future<void> _createDeck(BuildContext context) async {
  final combosCubit = context.read<CombosPageCubit>();
  final decksCubit = context.read<DecksPageCubit>();
  // Total across all pages, not just the loaded ones.
  if (combosCubit.state.loaded &&
      combosCubit.state.query.isEmpty &&
      combosCubit.state.total < 3) {
    _snack(context, TrTokens.need3CombosForDeckTxt.tr);
    return;
  }

  final picked = await ComboPickerPage.open(context, minSelected: 3);
  if (picked == null || picked.length < 3 || !context.mounted) return;

  final name =
      await _promptForName(context, title: TrTokens.nameThisDeckTxt.tr);
  if (name == null || !context.mounted) return;

  try {
    await decksCubit.create(name, picked);
  } on ArgumentError catch (e) {
    if (context.mounted) {
      _snack(
          context, e.message?.toString() ?? TrTokens.couldNotCreateDeckTxt.tr);
    }
  } catch (_) {
    if (context.mounted) _snack(context, TrTokens.couldNotCreateDeckTxt.tr);
  }
}

// ── Edit ─────────────────────────────────────────────────────────────────────

/// Renames a combo; decks that use it show the new name.
Future<void> _renameCombo(BuildContext context, Combo combo) async {
  final name = await _promptForName(context,
      title: TrTokens.renameComboTitle.tr, initial: combo.name);
  if (name == null || name == combo.name || !context.mounted) return;
  await _saveCombo(
      context,
      Combo(
          id: combo.id,
          name: name,
          loadout: combo.loadout,
          createdAt: combo.createdAt));
}

/// Opens the builder with the combo's parts; the result replaces them.
Future<void> _rebuildCombo(BuildContext context, Combo combo) async {
  final beyblade = await Navigator.push<Beyblade>(
    context,
    MaterialPageRoute(
      builder: (routeContext) => BeyBuilderPage(
        initialLoadout: combo.loadout,
        onBuildConfirmed: (result) => Navigator.pop(routeContext, result),
      ),
    ),
  );
  if (beyblade == null || !context.mounted) return;
  if (beyblade.loadout == combo.loadout) return;
  await _saveCombo(
      context,
      Combo(
          id: combo.id,
          name: combo.name,
          loadout: beyblade.loadout,
          createdAt: combo.createdAt));
}

Future<void> _saveCombo(BuildContext context, Combo combo) async {
  final decks = context.read<DecksPageCubit>();
  final saved = await context.read<CombosPageCubit>().update(combo);
  if (!context.mounted) return;
  if (saved == null) {
    _snack(context, TrTokens.couldNotSaveTxt.tr);
    return;
  }
  decks.comboChanged(saved);
  _snack(context, TrTokens.comboSavedTxt.tr);
}

/// Renames a deck.
Future<void> _renameDeck(BuildContext context, DeckEntry entry) async {
  final deck = entry.deck;
  final name = await _promptForName(context,
      title: TrTokens.renameDeckTitle.tr, initial: deck.name);
  if (name == null || name == deck.name || !context.mounted) return;
  await _saveDeck(
      context,
      Deck(
          id: deck.id,
          name: name,
          comboIds: deck.comboIds,
          createdAt: deck.createdAt),
      entry.combos);
}

/// Opens the picker with the deck's combos ticked; the picks (3 or more,
/// in the order picked) become the deck.
Future<void> _changeDeckCombos(BuildContext context, DeckEntry entry) async {
  final picked = await ComboPickerPage.open(context,
      minSelected: 3, initial: entry.combos);
  if (picked == null || picked.length < 3 || !context.mounted) return;
  final deck = entry.deck;
  await _saveDeck(
      context,
      Deck(
          id: deck.id,
          name: deck.name,
          comboIds: [for (final c in picked) c.id],
          createdAt: deck.createdAt),
      picked);
}

Future<void> _saveDeck(
    BuildContext context, Deck deck, List<Combo> combos) async {
  try {
    await context.read<DecksPageCubit>().update(deck, combos);
    if (context.mounted) _snack(context, TrTokens.deckSavedTxt.tr);
  } on ArgumentError catch (e) {
    if (context.mounted) {
      _snack(context, e.message?.toString() ?? TrTokens.couldNotSaveTxt.tr);
    }
  } catch (_) {
    if (context.mounted) _snack(context, TrTokens.couldNotSaveTxt.tr);
  }
}

/// Edit / delete menu for a combo or a deck card.
class _EditMenu extends StatelessWidget {
  const _EditMenu({
    required this.items,
    required this.onSelected,
    this.onDark = false,
  });

  /// (value, icon, label, danger)
  final List<(String, IconData, String, bool)> items;
  final ValueChanged<String> onSelected;

  /// Drawn over a picture (combo tiles): white icon on a dark chip.
  final bool onDark;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final danger = HoloTokens.of(context).danger;
    final button = PopupMenuButton<String>(
      tooltip: TrTokens.editOrDeleteTooltip.tr,
      icon: Icon(Icons.more_vert,
          size: 20, color: onDark ? Colors.white : cs.onSurfaceVariant),
      shape: const ChamferBorder.tab(cut: 10),
      onSelected: onSelected,
      itemBuilder: (_) => [
        for (final (value, icon, label, isDanger) in items)
          PopupMenuItem<String>(
            value: value,
            child: Row(children: [
              Icon(icon, size: 18, color: isDanger ? danger : cs.onSurface),
              const SizedBox(width: 10),
              Text(label, style: TextStyle(color: isDanger ? danger : null)),
            ]),
          ),
      ],
    );
    if (!onDark) return button;
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: button,
    );
  }
}

// ── Combos tab ───────────────────────────────────────────────────────────────

class _CombosTab extends StatelessWidget {
  const _CombosTab();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<CombosPageCubit>();
    return BlocBuilder<CombosPageCubit, PagedState<Combo>>(
      builder: (context, state) => PagedListView<Combo>(
        state: state,
        searchHint: TrTokens.comboSearchHint.tr,
        onSearch: cubit.search,
        onRefresh: cubit.load,
        onLoadMore: cubit.loadMore,
        empty: _EmptyState(
          icon: Icons.build_outlined,
          title: TrTokens.noCombosCreatedTxt.tr,
          buttonLabel: TrTokens.createComboTxt.tr,
          onPressed: () => _createCombo(context),
        ),
        itemBuilder: (context, combo) => Stack(
          children: [
            // Tap: change the parts.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _rebuildCombo(context, combo),
              child: ResolvedMinifiedBeyTile(loadout: combo.loadout),
            ),
            Positioned(top: 8, left: 8, child: _NameChip(name: combo.name)),
            Positioned(
              top: 4,
              right: 4,
              child: _EditMenu(
                onDark: true,
                items: [
                  (
                    'rename',
                    Icons.edit_outlined,
                    TrTokens.renameComboTitle.tr,
                    false
                  ),
                  (
                    'parts',
                    Icons.build_outlined,
                    TrTokens.changePartsTxt.tr,
                    false
                  ),
                  (
                    'delete',
                    Icons.delete_outline,
                    TrTokens.deleteComboTxt.tr,
                    true
                  ),
                ],
                onSelected: (v) async {
                  switch (v) {
                    case 'rename':
                      await _renameCombo(context, combo);
                    case 'parts':
                      await _rebuildCombo(context, combo);
                    default:
                      final decks = context.read<DecksPageCubit>();
                      final ok = await cubit.delete(combo.id);
                      if (ok) {
                        decks.comboDeleted(combo.id);
                      } else if (context.mounted) {
                        _snack(context, TrTokens.couldNotSaveTxt.tr);
                      }
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Decks tab ────────────────────────────────────────────────────────────────

class _DecksTab extends StatelessWidget {
  const _DecksTab();

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DecksPageCubit>();
    return BlocBuilder<CombosPageCubit, PagedState<Combo>>(
      buildWhen: (a, b) => a.total != b.total || a.loaded != b.loaded,
      builder: (context, combos) {
        final enoughCombos =
            !combos.loaded || combos.query.isNotEmpty || combos.total >= 3;
        return BlocBuilder<DecksPageCubit, PagedState<DeckEntry>>(
          builder: (context, state) => PagedListView<DeckEntry>(
            state: state,
            searchHint: TrTokens.deckSearchHint.tr,
            onSearch: cubit.search,
            onRefresh: cubit.load,
            onLoadMore: cubit.loadMore,
            empty: _EmptyState(
              icon: Icons.format_list_numbered,
              title: TrTokens.noDecksCreatedTxt.tr,
              buttonLabel: TrTokens.createDeckTxt.tr,
              onPressed: enoughCombos ? () => _createDeck(context) : null,
              footnote: enoughCombos ? null : TrTokens.need3CombosForDeckTxt.tr,
            ),
            itemBuilder: (context, entry) => _DeckCard(
              entry: entry,
              onRename: () => _renameDeck(context, entry),
              onChangeCombos: () => _changeDeckCombos(context, entry),
              onDelete: () async {
                final ok = await cubit.delete(entry.deck.id);
                if (!ok && context.mounted) {
                  _snack(context, TrTokens.couldNotSaveTxt.tr);
                }
              },
            ),
          ),
        );
      },
    );
  }
}

class _DeckCard extends StatelessWidget {
  const _DeckCard({
    required this.entry,
    required this.onDelete,
    required this.onRename,
    required this.onChangeCombos,
  });

  final DeckEntry entry;
  final VoidCallback onDelete;
  final VoidCallback onRename;
  final VoidCallback onChangeCombos;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final deck = entry.deck;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: entry.combos.isEmpty
            ? null
            : () => showDeckDialog(context,
                title: deck.name,
                beys: [for (final c in entry.combos) c.loadout]),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(deck.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                          TrTokens.combosCountFormat
                              .trArgs(['${entry.combos.length}']),
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                _EditMenu(
                  items: [
                    (
                      'rename',
                      Icons.edit_outlined,
                      TrTokens.renameDeckTitle.tr,
                      false
                    ),
                    (
                      'combos',
                      Icons.swap_horiz,
                      TrTokens.changeCombosTxt.tr,
                      false
                    ),
                    (
                      'delete',
                      Icons.delete_outline,
                      TrTokens.deleteDeckTxt.tr,
                      true
                    ),
                  ],
                  onSelected: (v) {
                    switch (v) {
                      case 'rename':
                        onRename();
                      case 'combos':
                        onChangeCombos();
                      default:
                        onDelete();
                    }
                  },
                ),
              ]),
              if (entry.combos.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final c in entry.combos)
                      ResolvedBeyChip(loadout: c.loadout),
                  ],
                ),
              ],
              if (entry.missing > 0) ...[
                const SizedBox(height: 8),
                Text(
                  TrTokens.deckMissingCombosTxt
                      .trParams({'count': '${entry.missing}'}),
                  style: TextStyle(fontSize: 12.5, color: cs.error),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared ───────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState(
      {required this.icon,
      required this.title,
      required this.buttonLabel,
      required this.onPressed,
      this.footnote});
  final IconData icon;
  final String title;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(title,
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.add),
                label: Text(buttonLabel)),
            if (footnote != null) ...[
              const SizedBox(height: 12),
              Text(footnote!,
                  style: TextStyle(color: cs.error),
                  textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}

class _NameChip extends StatelessWidget {
  const _NameChip({required this.name});
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: Colors.black54, borderRadius: BorderRadius.circular(6)),
      child: Text(name,
          style: const TextStyle(
              color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}
