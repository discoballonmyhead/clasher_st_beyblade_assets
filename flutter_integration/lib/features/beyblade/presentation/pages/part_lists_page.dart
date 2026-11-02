// =============================================================================
// BAN / ALLOW LISTS ("meta") - managed in the Beyblade feature
// -----------------------------------------------------------------------------
// The host's saved lists, the same ones the create-tournament page offers
// under "My lists". Uses the existing PartListsCubit / PartListsRepository
// (inventory_get_part_lists / inventory_save_part_list /
// inventory_delete_part_list) - no new backend.
//
// Route (features/beyblade/b_routes/beyblade_routes.dart):
//
//   static const String partLists = '/beyblade/part-lists';
//   ...
//   GoRoute(
//     path: partLists,
//     builder: (_, __) => BlocProvider(
//       create: (_) => sl<PartListsCubit>()..load(),
//       child: const PartListsPage(),
//     ),
//   ),
//
// and a tile wherever the Beyblade home lists its tools:
//   context.push(BeybladeRoutes.partLists)
//
// PartListEditor is the same editor as a reusable widget, so the
// create-tournament page can use it too (see flutter_integration/README.md).
// =============================================================================

import 'package:clasher_st/core/constants/trc_constant_tokens.dart';
import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/responsive/responsive_extras.dart';
import 'package:clasher_st/core/services/translation/translation_helper.dart';
import 'package:clasher_st/core/widgets/app_beyblade_loading_indicator.dart';
import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/beyblade/parts_list.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/parts_list_cubit/parts_list_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/part_lists/beyblade_part_catalog.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/part_image_thumb.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class PartListsPage extends StatelessWidget {
  const PartListsPage({super.key});

  Future<void> _open(BuildContext context, PartList list) async {
    final cubit = context.read<PartListsCubit>();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BlocProvider.value(
          value: cubit,
          child: PartListEditPage(initial: list),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rc = ResponsiveProvider.config(context);
    final cs = Theme.of(context).colorScheme;
    final t = HoloTokens.of(context);

    return ResponsiveScaffold(
      maxWidth: rc.maxContentWidth,
      appBar: AppBar(title: const Text('Ban & allow lists')),
      body: BlocBuilder<PartListsCubit, PartListsState>(
        builder: (context, state) {
          if (state.loading && state.lists.isEmpty) {
            return const Center(child: BeybladeSpinner());
          }
          return ListView(
            padding: EdgeInsets.all(rc.horizontalPadding),
            children: [
              Text(
                'Reusable part rules for your tournaments. A ban list blocks '
                'the parts on it; an allow list only permits them (part types '
                'you leave out stay open). Pick one when you create a '
                'tournament - it gets its own copy.',
                style: TextStyle(
                  fontSize: rc.bodySM,
                  color: cs.onSurfaceVariant,
                ),
              ),
              SizedBox(height: rc.md),
              if (state.error != null)
                Padding(
                  padding: EdgeInsets.only(bottom: rc.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          state.error!,
                          style: TextStyle(color: cs.error),
                        ),
                      ),
                      TextButton(
                        onPressed: () => context.read<PartListsCubit>().load(),
                        child: Text(TrTokens.retryTxt.tr),
                      ),
                    ],
                  ),
                ),
              if (state.lists.isEmpty)
                HoloEmptyState(
                  icon: Icons.rule_outlined,
                  title: TrTokens.noSavedListsYetTxt.tr,
                  message: 'Create a ban or allow list once and reuse it.',
                )
              else
                for (final list in state.lists)
                  Padding(
                    padding: EdgeInsets.only(bottom: rc.sm),
                    child: HoloCard(
                      onTap: () => _open(context, list),
                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                      child: Row(
                        children: [
                          Icon(
                            list.kind == PartListKind.ban
                                ? Icons.block
                                : Icons.verified_outlined,
                            color: list.kind == PartListKind.ban
                                ? t.danger
                                : t.success,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  list.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    HoloPill(
                                      label: list.kind.shortLabel,
                                      color: list.kind == PartListKind.ban
                                          ? t.danger
                                          : t.success,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      TrTokens.partsCountFormat.tr.replaceFirst(
                                        '%s',
                                        list.partCount.toString(),
                                      ),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                  ),
              SizedBox(height: rc.lg),
              HoloActionButton(
                label: 'New list',
                icon: Icons.playlist_add,
                expand: true,
                onPressed: () =>
                    _open(context, const PartList(kind: PartListKind.ban)),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Create or edit one saved list.
class PartListEditPage extends StatefulWidget {
  const PartListEditPage({super.key, required this.initial});

  final PartList initial;

  @override
  State<PartListEditPage> createState() => _PartListEditPageState();
}

class _PartListEditPageState extends State<PartListEditPage> {
  late PartList _list = widget.initial;
  late final _name = TextEditingController(text: widget.initial.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final name = _name.text.trim();
    if (name.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text(TrTokens.nameListToSaveMsg.tr)),
      );
      return;
    }
    final cubit = context.read<PartListsCubit>();
    final saved = await cubit.save(_list.copyWith(name: name));
    if (!mounted) return;
    if (saved == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(cubit.state.error ?? TrTokens.couldNotSaveListMsg.tr),
        ),
      );
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        content: Text(TrTokens.savedToListsFormat.tr.replaceFirst('%s', name)),
      ),
    );
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final id = _list.id;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this list?'),
        content: const Text(
          'Tournaments that already use it keep their own copy.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (await context.read<PartListsCubit>().delete(id) && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rc = ResponsiveProvider.config(context);
    return ResponsiveScaffold(
      maxWidth: rc.maxContentWidth,
      appBar: AppBar(
        title: Text(_list.isSaved ? 'Edit list' : 'New list'),
        actions: [
          if (_list.isSaved)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(rc.horizontalPadding),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: TrTokens.listNameLabel.tr,
              hintText: TrTokens.listNameHint.tr,
            ),
          ),
          SizedBox(height: rc.md),
          PartListEditor(
            list: _list,
            onChanged: (l) => setState(() => _list = l),
          ),
          SizedBox(height: rc.lg),
          BlocBuilder<PartListsCubit, PartListsState>(
            buildWhen: (p, c) => p.saving != c.saving,
            builder: (context, state) => HoloActionButton(
              label: state.saving ? 'Saving…' : 'Save list',
              icon: Icons.save_outlined,
              expand: true,
              onPressed: state.saving || _list.isEmpty ? null : _save,
            ),
          ),
        ],
      ),
    );
  }
}

/// Kind switch + parts grouped by type + "Add part". Stateless: the owner
/// keeps the [PartList] and gets every change through [onChanged].
///
/// Works with any PartCatalog; with [BeybladePartCatalog] it shows images and
/// can add a part together with all its variants in one go.
class PartListEditor extends StatelessWidget {
  const PartListEditor({
    super.key,
    required this.list,
    required this.onChanged,
  });

  final PartList list;
  final ValueChanged<PartList> onChanged;

  Future<void> _add(BuildContext context, PartCatalog catalog) async {
    final refs = catalog is BeybladePartCatalog
        ? await catalog.pickParts(context, kind: list.kind)
        : [await catalog.pickPart(context, kind: list.kind)]
              .whereType<PartRef>()
              .toList();
    if (refs == null || refs.isEmpty || !context.mounted) return;
    var next = list;
    final already = refs.where(list.contains).toList();
    for (final r in refs) {
      next = next.withPart(r);
    }
    onChanged(next);
    if (already.length == refs.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            TrTokens.partAlreadyOnListFormat.tr.replaceFirst(
              '%s',
              catalog.nameOf(refs.first),
            ),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    final catalog = resolvePartCatalog();
    final rich = catalog is BeybladePartCatalog ? catalog : null;
    if (rich != null) rich.warm();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HoloSegmented<PartListKind>(
          value: list.kind,
          onChanged: (k) => onChanged(list.copyWith(kind: k)),
          options: [
            HoloOption(
              PartListKind.ban,
              TrTokens.banListTxt.tr,
              icon: Icons.block,
            ),
            HoloOption(
              PartListKind.approve,
              TrTokens.approveListTxt.tr,
              icon: Icons.verified_outlined,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          list.kind.rule,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.35,
            color: cs.onSurfaceVariant,
          ),
        ),
        SizedBox(height: rc.md),
        if (list.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Text(
              TrTokens.noPartsYetTxt.tr,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          )
        else
          for (final entry in list.parts.entries) ...[
            HoloSubLabel(
              title: catalog.typeLabel(entry.key),
              trailing: Text(
                '${entry.value.length}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final id in entry.value)
                  InputChip(
                    avatar: rich == null
                        ? null
                        : PartImageThumb(
                            imageUrl: preferredThumbUrl(
                              rich.lookup(PartRef(entry.key, id))?.part,
                            ),
                            size: 24,
                            scale: 1,
                          ),
                    label: Text(catalog.nameOf(PartRef(entry.key, id))),
                    onDeleted: () =>
                        onChanged(list.withoutPart(PartRef(entry.key, id))),
                  ),
              ],
            ),
            SizedBox(height: rc.md),
          ],
        SizedBox(height: rc.sm),
        OutlinedButton.icon(
          onPressed: () => _add(context, catalog),
          icon: const Icon(Icons.add),
          label: Text(TrTokens.addPartBtn.tr),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(double.infinity, 46),
          ),
        ),
      ],
    );
  }
}
