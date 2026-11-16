import 'package:clasher_st/core/init_injection/injection.dart';
import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/domain/repositories/beyblade_data_repo.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/part_image_thumb.dart';
import 'package:flutter/material.dart';

// Catalog accessories (stadiums, launchers, grips ...), shared by every
// feature that records one:
//   bey_testing   session stadium / launchers, opponent launcher
//   tournaments   the optional tournament stadium
//
//   AccessoryCache        the catalog's accessories, loaded once, by id/type
//   AccessoryPickerSheet  pick one of a type (or "none")
//   AccessoryName         an accessory's name from its data id
//   AccessoryField        a tappable card showing the pick, with clear

/// Result of [AccessoryPickerSheet]: [dataId] null means "none".
class AccessoryChoice {
  const AccessoryChoice(this.dataId);
  final String? dataId;
}

/// A memory of the catalog's accessories (stadiums, launchers, grips ...), so
/// screens don't re-read the local database every time they need a name or
/// a list. It reads once, then answers from memory. The picker re-reads on
/// every open, and the sync cubit calls [clear] after a catalog update, so
/// the names never go stale.
class AccessoryCache {
  AccessoryCache._();

  static Future<List<Accessory>>? _all;

  /// Forget the loaded list (after a catalog update, or between tests).
  static void clear() => _all = null;

  static Future<List<Accessory>> all({bool refresh = false}) {
    if (refresh) _all = null;
    return _all ??= _loadAll();
  }

  static Future<List<Accessory>> _loadAll() async {
    try {
      final list = await sl<BeybladeDataRepo>().getAllAccessories();
      return [...list]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } catch (_) {
      _all = null; // try again next time
      rethrow;
    }
  }

  static Future<List<Accessory>> ofType(AccessoryType type,
          {bool refresh = false}) async =>
      [
        for (final a in await all(refresh: refresh))
          if (a.accessoryType == type) a,
      ];

  static Future<Accessory?> byId(String dataId) async {
    for (final a in await all()) {
      if (a.dataId == dataId) return a;
    }
    return null;
  }
}

String accessoryTypeLabel(AccessoryType t) => switch (t) {
      AccessoryType.stadium => 'Stadium',
      AccessoryType.launcher => 'Launcher',
      AccessoryType.grip => 'Grip',
      AccessoryType.deckBox => 'Deck box',
      AccessoryType.battlePass => 'Battle pass',
      AccessoryType.unknown => 'Accessory',
    };

IconData accessoryTypeIcon(AccessoryType t) => switch (t) {
      AccessoryType.stadium => Icons.stadium_outlined,
      AccessoryType.launcher => Icons.rocket_launch_outlined,
      AccessoryType.grip => Icons.back_hand_outlined,
      AccessoryType.deckBox => Icons.inventory_2_outlined,
      AccessoryType.battlePass => Icons.speed_outlined,
      AccessoryType.unknown => Icons.category_outlined,
    };

/// Small image of an accessory, or its type icon when it has none.
class AccessoryThumb extends StatelessWidget {
  const AccessoryThumb(
      {super.key, required this.accessory, required this.type, this.size = 40});

  final Accessory? accessory;
  final AccessoryType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final url = preferredAccessoryThumbUrl(accessory);
    return url == null
        ? SizedBox(
            width: size,
            height: size,
            child: Icon(accessoryTypeIcon(type),
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          )
        : PartImageThumb(imageUrl: url, size: size, scale: 1);
  }
}

class AccessoryPickerSheet extends StatefulWidget {
  const AccessoryPickerSheet({
    super.key,
    required this.type,
    required this.title,
    this.selectedId,
    this.noneLabel = 'None / not tracked',
  });

  final AccessoryType type;
  final String title;
  final String? selectedId;

  /// The first row, which picks "no accessory".
  final String noneLabel;

  /// Null when dismissed; otherwise the pick (possibly "none").
  static Future<AccessoryChoice?> show(
    BuildContext context, {
    required AccessoryType type,
    required String title,
    String? selectedId,
    String noneLabel = 'None / not tracked',
  }) =>
      showModalBottomSheet<AccessoryChoice>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        constraints: const BoxConstraints(maxWidth: 720),
        builder: (_) => FractionallySizedBox(
          heightFactor: 0.8,
          child: AccessoryPickerSheet(
              type: type,
              title: title,
              selectedId: selectedId,
              noneLabel: noneLabel),
        ),
      );

  @override
  State<AccessoryPickerSheet> createState() => _AccessoryPickerSheetState();
}

class _AccessoryPickerSheetState extends State<AccessoryPickerSheet> {
  late Future<List<Accessory>> _items =
      AccessoryCache.ofType(widget.type, refresh: true);
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HoloSectionLabel(title: widget.title),
          const SizedBox(height: 12),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Search',
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: FutureBuilder<List<Accessory>>(
              future: _items,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: TextButton.icon(
                      onPressed: () => setState(() => _items =
                          AccessoryCache.ofType(widget.type, refresh: true)),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Couldn’t load the catalog. Retry'),
                    ),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final list = [
                  for (final a in snap.data!)
                    if (_query.isEmpty ||
                        a.name.toLowerCase().contains(_query) ||
                        a.hobbyName.toLowerCase().contains(_query) ||
                        a.hobbyGeneration.toLowerCase().contains(_query) ||
                        a.manufacturer.toLowerCase().contains(_query))
                      a,
                ];
                return ListView(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.block),
                      title: Text(widget.noneLabel),
                      selected: widget.selectedId == null,
                      onTap: () => Navigator.of(context)
                          .pop(const AccessoryChoice(null)),
                    ),
                    if (list.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          snap.data!.isEmpty
                              ? 'No ${accessoryTypeLabel(widget.type).toLowerCase()}s '
                                  'in your catalog yet. Sync the catalog in '
                                  'Settings → Beyblade data.'
                              : 'Nothing matches “$_query”.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    for (final a in list)
                      ListTile(
                        leading:
                            AccessoryThumb(accessory: a, type: a.accessoryType),
                        title: Text(a.name),
                        subtitle: Text([
                          a.manufacturer,
                          if (a.subType != null && a.subType!.isNotEmpty)
                            a.subType!,
                          a.hobbyGeneration,
                        ].where((x) => x.isNotEmpty).join(' · ')),
                        selected: a.dataId == widget.selectedId,
                        trailing: a.dataId == widget.selectedId
                            ? Icon(Icons.check, color: cs.primary)
                            : null,
                        onTap: () => Navigator.of(context)
                            .pop(AccessoryChoice(a.dataId)),
                      ),
                    const SizedBox(height: 24),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// An accessory's name from its data id ([fallback] while loading or when
/// the id isn't in the catalog).
class AccessoryName extends StatelessWidget {
  const AccessoryName(
      {super.key, required this.dataId, this.fallback = '—', this.style});

  final String? dataId;
  final String fallback;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final id = dataId;
    if (id == null) {
      return Text(fallback,
          style: style, maxLines: 1, overflow: TextOverflow.ellipsis);
    }
    return FutureBuilder<Accessory?>(
      future: AccessoryCache.byId(id),
      builder: (context, snap) => Text(
        snap.data?.name ??
            (snap.connectionState == ConnectionState.done
                ? 'Unknown ($id)'
                : '…'),
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// A card that shows the chosen accessory (image + name), opens
/// [AccessoryPickerSheet] on tap and can be cleared. [value] null shows
/// [noneLabel].
class AccessoryField extends StatelessWidget {
  const AccessoryField({
    super.key,
    required this.type,
    required this.value,
    required this.onChanged,
    required this.title,
    this.noneLabel = 'None / not tracked',
    this.hint = 'Optional - tap to choose',
  });

  final AccessoryType type;
  final String? value;
  final ValueChanged<String?> onChanged;

  /// Picker sheet heading.
  final String title;
  final String noneLabel;
  final String hint;

  Future<void> _pick(BuildContext context) async {
    final c = await AccessoryPickerSheet.show(context,
        type: type, title: title, selectedId: value, noneLabel: noneLabel);
    if (c != null) onChanged(c.dataId);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final id = value;
    return HoloCard(
      onTap: () => _pick(context),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      child: Row(
        children: [
          id == null
              ? AccessoryThumb(accessory: null, type: type)
              : FutureBuilder<Accessory?>(
                  future: AccessoryCache.byId(id),
                  builder: (context, snap) =>
                      AccessoryThumb(accessory: snap.data, type: type),
                ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AccessoryName(
                  dataId: id,
                  fallback: noneLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(hint,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          if (id != null)
            IconButton(
              tooltip: 'Clear',
              icon: const Icon(Icons.close),
              onPressed: () => onChanged(null),
            )
          else
            const Icon(Icons.chevron_right),
        ],
      ),
    );
  }
}
