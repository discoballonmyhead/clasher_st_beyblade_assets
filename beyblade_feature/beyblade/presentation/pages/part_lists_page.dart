// Ban & approve lists, managed in the Beyblade feature.
//
// The host's saved lists: the same ones the create-tournament page offers
// under "My lists". Uses the existing PartListsCubit / PartListsRepository
// (inventory_get_part_lists / inventory_save_part_list /
// inventory_delete_part_list), so there's no new backend.
//
// Reached from the Bey Station "Manage" grid and from "Manage lists" in the
// create-tournament Part rules block (route BeybladeRoutes.partLists).

import 'package:clasher_st/core/constants/trc_constant_tokens.dart';
import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/services/translation/translation_helper.dart';
import 'package:clasher_st/core/widgets/app_beyblade_loading_indicator.dart';
import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/beyblade/parts_list.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/parts_list_cubit/parts_list_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/part_list_editor.dart';
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
      appBar: AppBar(title: Text(TrTokens.banApproveCardTitle.tr)),
      body: BlocBuilder<PartListsCubit, PartListsState>(
        builder: (context, state) {
          if (state.loading && state.lists.isEmpty) {
            return const Center(child: BeybladeSpinner());
          }
          return ListView(
            padding: EdgeInsets.all(rc.horizontalPadding),
            children: [
              Text(
                TrTokens.partListsPageDescTxt.tr,
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
                  message: TrTokens.noSavedListsMsgTxt.tr,
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
                                const SizedBox(height: 4),
                                PartListPreview(list: list),
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
                label: TrTokens.newListTxt.tr,
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
        title: Text(TrTokens.deleteListDialogTitle.tr),
        content: Text(
          TrTokens.deleteListDialogDesc.tr,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(TrTokens.cancelTxt.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(TrTokens.deleteTxt.tr),
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
        title: Text(
            _list.isSaved ? TrTokens.editListTxt.tr : TrTokens.newListTxt.tr),
        actions: [
          if (_list.isSaved)
            IconButton(
              tooltip: TrTokens.deleteTxt.tr,
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
              label: state.saving
                  ? TrTokens.savingMsg.tr
                  : TrTokens.saveListBtnTxt.tr,
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
