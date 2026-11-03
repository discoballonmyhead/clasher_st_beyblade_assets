import 'package:clasher_st/core/init_injection/injection.dart';
import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/responsive/responsive_extras.dart';
import 'package:clasher_st/core/widgets/app_beyblade_loading_indicator.dart';
import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/beyblade_sync_cubit/beyblade_sync_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/part_image_thumb.dart';
import 'package:clasher_st/features/beyblade_tcg/beyblade_tcg.dart';
import 'package:flutter/material.dart';

/// Browse the Beyblade TCG cards that came with the catalog download:
/// search by name or number, filter by game (generation) and set, tap a
/// card for its details and its foils / parallels.
class TcgCardsPage extends StatefulWidget {
  const TcgCardsPage({super.key});

  @override
  State<TcgCardsPage> createState() => _TcgCardsPageState();
}

class _TcgCardsPageState extends State<TcgCardsPage> {
  final _query = TextEditingController();
  late Future<(List<TcgCard>, List<TcgSet>)> _data = sl<TcgCatalog>().load();
  String? _generation;
  String? _set;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _checkForUpdate() async {
    setState(() => _checking = true);
    await sl<BeybladeSyncCubit>().checkForUpdates(userInitiated: true);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _data = sl<TcgCatalog>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final rc = ResponsiveProvider.config(context);
    final cs = Theme.of(context).colorScheme;

    return ResponsiveScaffold(
      maxWidth: rc.maxContentWidth,
      appBar: AppBar(title: const Text('Card game')),
      body: FutureBuilder<(List<TcgCard>, List<TcgSet>)>(
        future: _data,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: BeybladeSpinner());
          }
          final cards = snap.data?.$1 ?? const <TcgCard>[];
          if (cards.isEmpty) {
            return Padding(
              padding: EdgeInsets.all(rc.horizontalPadding),
              child: HoloEmptyState(
                icon: Icons.style_outlined,
                title: 'No cards on this device yet',
                message: 'Cards arrive with a catalog update that includes '
                    'the card game.',
                action: HoloActionButton(
                  label: _checking ? 'Checking…' : 'Check for updates',
                  icon: Icons.sync,
                  isLoading: _checking,
                  onPressed: _checking ? null : _checkForUpdate,
                ),
              ),
            );
          }

          final generations =
              ({for (final c in cards) c.hobbyGeneration}..remove('')).toList()
                ..sort();
          final setNames = ({
            for (final c in cards)
              if (_generation == null || c.hobbyGeneration == _generation)
                if (c.setName != null) c.setName!,
          }).toList()
            ..sort();
          final shown = filterTcgCards(cards,
              generation: _generation, setName: _set, query: _query.text);

          return ListView(
            padding: EdgeInsets.all(rc.horizontalPadding),
            children: [
              TextField(
                controller: _query,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Card name or number',
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: _query.clear,
                        ),
                ),
              ),
              SizedBox(height: rc.sm),
              if (generations.length > 1)
                _Chips(
                  values: generations,
                  selected: _generation,
                  label: _gameLabel,
                  onSelected: (g) => setState(() {
                    _generation = g;
                    _set = null;
                  }),
                ),
              if (setNames.length > 1)
                _Chips(
                  values: setNames,
                  selected: _set,
                  label: (s) => s,
                  onSelected: (s) => setState(() => _set = s),
                ),
              SizedBox(height: rc.sm),
              Text('${shown.length} cards',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              SizedBox(height: rc.xs),
              for (final card in shown)
                Padding(
                  padding: EdgeInsets.only(bottom: rc.xs),
                  child: _CardRow(
                    card: card,
                    onTap: () => _CardSheet.show(context, card, cards),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

String _gameLabel(String generation) => switch (generation) {
      'Original' => 'V-Force',
      'X' => 'Beyblade X',
      _ => generation,
    };

class _Chips extends StatelessWidget {
  const _Chips({
    required this.values,
    required this.selected,
    required this.label,
    required this.onSelected,
  });

  final List<String> values;
  final String? selected;
  final String Function(String) label;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: const Text('All'),
                selected: selected == null,
                onSelected: (_) => onSelected(null),
              ),
            ),
            for (final v in values)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(label(v)),
                  selected: selected == v,
                  onSelected: (_) => onSelected(v),
                ),
              ),
          ],
        ),
      );
}

class _CardRow extends StatelessWidget {
  const _CardRow({required this.card, required this.onTap});

  final TcgCard card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final meta = [
      if (card.cardNumber != null) card.cardNumber!,
      if (card.rarity != null) card.rarity!,
      if (card.cardType != null) card.cardType!,
      if (card.variantLabel != null) card.variantLabel!,
    ];
    return HoloCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
      child: Row(
        children: [
          PartImageThumb(
            imageUrl:
                preferredImageSource(card.minifiedImageUrl, card.imageUrl),
            size: 48,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(card.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(meta.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}

class _CardSheet extends StatelessWidget {
  const _CardSheet({required this.card, required this.all});

  final TcgCard card;
  final List<TcgCard> all;

  static Future<void> show(
          BuildContext context, TcgCard card, List<TcgCard> all) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        constraints: const BoxConstraints(maxWidth: 720),
        builder: (_) => _CardSheet(card: card, all: all),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    final variants =
        tcgVariantGroup(all, card).where((c) => c.dataId != card.dataId);
    final facts = <(String, String)>[
      if (card.setName != null) ('Set', card.setName!),
      if (card.cardNumber != null) ('Number', card.cardNumber!),
      if (card.rarity != null) ('Rarity', card.rarity!),
      if (card.cardType != null) ('Type', card.cardType!),
      if (card.attribute != null) ('Attribute', card.attribute!),
      if (card.cost != null) ('Cost', '${card.cost}'),
      if (card.power != null) ('Power', '${card.power}'),
      if (card.battleEdge != null) ('Battle Edge', '${card.battleEdge}'),
      if (card.spinStrength != null) ('Spin Strength', '${card.spinStrength}'),
      if (card.illustrator != null) ('Illustrator', card.illustrator!),
    ];

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: EdgeInsets.fromLTRB(
            rc.horizontalPadding, 0, rc.horizontalPadding, rc.lg),
        children: [
          HoloSectionLabel(
            title: card.name,
            subtitle: card.subtitle ?? _gameLabel(card.hobbyGeneration),
          ),
          SizedBox(height: rc.sm),
          Center(
            child: PartImageThumb(
              imageUrl: preferredImageSource(
                  card.minifiedImageUrl, card.imageUrl,
                  compact: false),
              size: 240,
            ),
          ),
          SizedBox(height: rc.md),
          for (final (label, value) in facts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 12.5, color: cs.onSurfaceVariant)),
                  ),
                  Expanded(
                    child: Text(value,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          if (card.effectText != null) ...[
            SizedBox(height: rc.md),
            Text(card.effectText!),
          ],
          if (card.loreText != null) ...[
            SizedBox(height: rc.sm),
            Text(card.loreText!,
                style: TextStyle(
                    fontStyle: FontStyle.italic, color: cs.onSurfaceVariant)),
          ],
          if (variants.isNotEmpty) ...[
            SizedBox(height: rc.md),
            const HoloSubLabel(title: 'Other versions'),
            SizedBox(height: rc.xs),
            for (final v in variants)
              Padding(
                padding: EdgeInsets.only(bottom: rc.xs),
                child: _CardRow(
                  card: v,
                  onTap: () {
                    // This sheet's context goes away with pop; open the next
                    // one from the navigator's.
                    final nav = Navigator.of(context);
                    nav.pop();
                    _CardSheet.show(nav.context, v, all);
                  },
                ),
              ),
          ],
        ],
      ),
    );
  }
}
