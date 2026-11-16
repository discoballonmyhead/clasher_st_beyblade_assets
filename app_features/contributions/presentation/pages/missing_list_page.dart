import 'package:clasher_st/features/contributions/contributions_routes.dart';
import 'package:clasher_st/features/contributions/domain/entities.dart';
import 'package:clasher_st/features/contributions/presentation/cubit/missing_cubits.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// "Help complete the catalog": everything the catalog is missing, from the published list. Tap an entry to
/// fill it in. Plain Material widgets; restyle as you like.
class MissingListPage extends StatelessWidget {
  const MissingListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MissingListCubit, MissingListState>(
      builder: (context, s) {
        final cubit = context.read<MissingListCubit>();
        return Scaffold(
          appBar: AppBar(
            title: const Text('Help complete the catalog'),
            actions: [
              IconButton(
                tooltip: 'Reload',
                onPressed: s.loading ? null : () => cubit.load(refresh: true),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            key: const ValueKey('missing-send-other'),
            onPressed: () => context.push(ContributionsRoutes.send),
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Send something else'),
          ),
          body: SafeArea(child: _body(context, s, cubit)),
        );
      },
    );
  }

  Widget _body(BuildContext context, MissingListState s, MissingListCubit cubit) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    if (s.loading && s.list == null) return const Center(child: CircularProgressIndicator());
    if (!s.configured) {
      return const _Centered('The list of what\'s missing isn\'t set up in this version. You can still send '
          'pictures with "Send something else".');
    }
    if (s.list == null) {
      return _Centered(s.error ?? 'Couldn\'t load the list.', action: TextButton(
        onPressed: () => cubit.load(refresh: true),
        child: const Text('Try again'),
      ));
    }
    final items = s.visible;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Text(
          '${s.list!.items.length} catalog entries are missing something. Pick one you know, fill in what you '
          'can, and send it: every contribution is checked before it\'s used, and you\'re credited in the app.',
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('missing-search'),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search by name or code'),
          onChanged: cubit.setQuery,
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: const Text('Everything'),
                selected: s.sheet == null,
                onSelected: (_) => cubit.setSheet(null),
              ),
            ),
            for (final (sheet, n) in s.sheetsWithCounts)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  key: ValueKey('missing-sheet-${sheet.key}'),
                  label: Text('${sheet.label}${sheet.generation == null ? '' : ' (${sheet.generation})'} · $n'),
                  selected: s.sheet == sheet.key,
                  onSelected: (_) => cubit.setSheet(sheet.key),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        SegmentedButton<GapKind>(
          key: const ValueKey('missing-gap'),
          segments: const [
            ButtonSegment(value: GapKind.all, label: Text('All')),
            ButtonSegment(value: GapKind.pictures, label: Text('Pictures')),
            ButtonSegment(value: GapKind.details, label: Text('Details')),
          ],
          selected: {s.gap},
          onSelectionChanged: (v) => cubit.setGap(v.first),
        ),
        const SizedBox(height: 8),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('Nothing here - thank you!', textAlign: TextAlign.center, style: tt.bodyMedium),
          ),
        for (final i in items) _ItemTile(item: i, list: s.list!),
      ],
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.list});
  final WantedItem item;
  final WantedList list;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sheet = list.sheets[item.sheet];
    final labels = [for (final f in item.missing) list.field(item.sheet, f)?.label ?? f];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        key: ValueKey('missing-${item.sheet}-${item.id}'),
        leading: _Thumb(url: item.thumb),
        title: Text([item.name, if (item.variant != null) item.variant!].join(' · '),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${sheet?.label ?? item.sheet}${item.code.isEmpty ? '' : ' · ${item.code}'}\nMissing: ${labels.join(', ')}',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        trailing: Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
        onTap: () => context.push(ContributionsRoutes.fill, extra: (item, sheet)),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.url});
  final String? url;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final placeholder = Icon(Icons.image_not_supported_outlined, color: cs.outline);
    return SizedBox(
      width: 48,
      height: 48,
      child: url == null || !url!.startsWith('http')
          ? placeholder
          : ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(url!, fit: BoxFit.contain, errorBuilder: (_, __, ___) => placeholder),
            ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered(this.text, {this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 8), action!],
          ]),
        ),
      );
}
