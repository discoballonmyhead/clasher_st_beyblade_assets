import 'package:clasher_st/core/constants/trc_constant_tokens.dart';
import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/services/translation/translation_helper.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/combo_decks_paged_cubit/combo_decks_paged_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/paged_list_view.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/resolved_minified_bey_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

/// Pick combos for a deck. Its own page and its own cubit: it loads the
/// account's combos a page at a time (searchable) and shares nothing with
/// the page that opened it.
///
/// Each tile is the minified bey, resolved only when the tile is built
/// (i.e. scrolls into view). Picks are kept by id with the combo itself,
/// so they survive scrolling, searching and new pages; the order you pick
/// in is the deck's order. Returns the picked combos, or null.
class ComboPickerPage extends StatefulWidget {
  const ComboPickerPage({
    super.key,
    this.minSelected = 3,
    this.maxSelected,
    this.initial = const [],
  });

  final int minSelected;

  /// Null = no limit.
  final int? maxSelected;

  /// Already picked when the page opens (editing a deck).
  final List<Combo> initial;

  static Future<List<Combo>?> open(
    BuildContext context, {
    int minSelected = 3,
    int? maxSelected,
    List<Combo> initial = const [],
  }) {
    return Navigator.of(context).push<List<Combo>>(
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => GetIt.instance<ComboPickerCubit>()..load(),
          child: ComboPickerPage(
            minSelected: minSelected,
            maxSelected: maxSelected,
            initial: initial,
          ),
        ),
      ),
    );
  }

  @override
  State<ComboPickerPage> createState() => _ComboPickerPageState();
}

class _ComboPickerPageState extends State<ComboPickerPage> {
  /// Insertion order = pick order.
  late final Map<String, Combo> _picked = {
    for (final c in widget.initial) c.id: c,
  };

  bool get _full =>
      widget.maxSelected != null && _picked.length >= widget.maxSelected!;

  bool get _ready => _picked.length >= widget.minSelected;

  void _toggle(Combo combo) {
    setState(() {
      if (_picked.containsKey(combo.id)) {
        _picked.remove(combo.id);
      } else if (!_full) {
        _picked[combo.id] = combo;
      }
    });
  }

  void _done() => Navigator.of(context).pop(_picked.values.toList());

  @override
  Widget build(BuildContext context) {
    final rc = ResponsiveProvider.config(context);
    final cs = Theme.of(context).colorScheme;
    final cubit = context.read<ComboPickerCubit>();
    return ResponsiveScaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
            TrTokens.selectCombosTitleFormat.trArgs(['${_picked.length}'])),
        actions: [
          TextButton(
            onPressed: _ready ? _done : null,
            child: Text(TrTokens.doneTxt.tr),
          ),
        ],
      ),
      body: Padding(
        padding: EdgeInsets.symmetric(horizontal: rc.horizontalPadding),
        child: BlocBuilder<ComboPickerCubit, PagedState<Combo>>(
          builder: (context, state) => PagedListView<Combo>(
            state: state,
            searchHint: TrTokens.comboSearchHint.tr,
            onSearch: cubit.search,
            onRefresh: cubit.load,
            onLoadMore: cubit.loadMore,
            header: _PickedBar(
              picked: _picked.values.toList(),
              minSelected: widget.minSelected,
              onRemove: _toggle,
            ),
            empty: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(TrTokens.noCombosCreatedTxt.tr,
                    textAlign: TextAlign.center),
              ),
            ),
            itemBuilder: (context, combo) {
              final order = _orderOf(combo.id);
              return _PickTile(
                combo: combo,
                order: order,
                enabled: order != null || !_full,
                onTap: () => _toggle(combo),
              );
            },
          ),
        ),
      ),
    );
  }

  /// 1-based position in the pick order, or null when not picked.
  int? _orderOf(String id) {
    var i = 0;
    for (final key in _picked.keys) {
      i++;
      if (key == id) return i;
    }
    return null;
  }
}

/// The picks so far as removable chips, in pick order, plus how many more
/// are needed.
class _PickedBar extends StatelessWidget {
  const _PickedBar({
    required this.picked,
    required this.minSelected,
    required this.onRemove,
  });

  final List<Combo> picked;
  final int minSelected;
  final ValueChanged<Combo> onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final short = minSelected - picked.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (picked.isNotEmpty)
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: picked.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, i) => InputChip(
                  avatar: CircleAvatar(
                    radius: 10,
                    backgroundColor: cs.primary,
                    child: Text('${i + 1}',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: cs.onPrimary)),
                  ),
                  label: Text(picked[i].name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  onDeleted: () => onRemove(picked[i]),
                  deleteButtonTooltipMessage: TrTokens.removeTxt.tr,
                ),
              ),
            ),
          if (short > 0)
            Padding(
              padding: EdgeInsets.only(top: picked.isEmpty ? 0 : 6),
              child: Text(
                TrTokens.pickAtLeastTxt.trParams({'count': '$minSelected'}),
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

/// The minified bey with its name, and the pick number when picked.
class _PickTile extends StatelessWidget {
  const _PickTile({
    required this.combo,
    required this.order,
    required this.enabled,
    required this.onTap,
  });

  final Combo combo;

  /// 1-based pick position, or null.
  final int? order;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final selected = order != null;
    return Semantics(
      button: true,
      selected: selected,
      label: combo.name,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? cs.primary : Colors.transparent,
              width: 2,
            ),
          ),
          child: Stack(
            children: [
              // The whole tile picks, also while the bey is still loading
              // or couldn't be resolved.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: enabled ? onTap : null,
                child: AbsorbPointer(
                  child: ResolvedMinifiedBeyTile(loadout: combo.loadout),
                ),
              ),
              Positioned(
                top: 8,
                left: 8,
                child: IgnorePointer(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(6)),
                    child: Text(combo.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IgnorePointer(
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? cs.primary : Colors.black38,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: selected
                        ? Text('$order',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: cs.onPrimary))
                        : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
