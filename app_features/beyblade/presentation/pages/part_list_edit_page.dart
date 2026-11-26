import 'package:clasher_st/core/constants/trc_constant_tokens.dart';
import 'package:clasher_st/core/pages/link_problem_page.dart';
import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/services/translation/translation_helper.dart';
import 'package:clasher_st/core/widgets/app_beyblade_loading_indicator.dart';
import 'package:clasher_st/core/widgets/holo_extras.dart';
import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/part_list_editcubit/part_list_edit_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/part_list_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Create or edit one saved list.
///
/// Routes: `/beyblade/part-lists/new` and `/beyblade/part-lists/:id`. The
/// route provides [PartListEditCubit] and calls `open(id)`; this page only
/// renders its state.
class PartListEditPage extends StatefulWidget {
  const PartListEditPage({super.key});

  @override
  State<PartListEditPage> createState() => _PartListEditPageState();
}

class _PartListEditPageState extends State<PartListEditPage> {
  late final _name = TextEditingController(
      text: context.read<PartListEditCubit>().state.draft.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _onState(BuildContext context, PartListEditState state) {
    // Loaded or refreshed: put the stored name in the field. Typing goes
    // through rename(), so this never fights the user.
    if (state.draft.name != _name.text) _name.text = state.draft.name;

    final messenger = ScaffoldMessenger.of(context);
    switch (state.status) {
      case PartListEditStatus.saved:
        messenger.showSnackBar(SnackBar(
          content: Text(TrTokens.savedToListsFormat.tr
              .replaceFirst('%s', state.draft.name)),
        ));
        context.pop();
        return;
      case PartListEditStatus.deleted:
        context.pop();
        return;
      default:
        break;
    }
    if (state.error != null && state.status == PartListEditStatus.ready) {
      messenger.showSnackBar(SnackBar(content: Text(state.error!)));
    }
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(TrTokens.nameListToSaveMsg.tr)),
      );
      return;
    }
    context.read<PartListEditCubit>().save();
  }

  Future<void> _delete() async {
    final cubit = context.read<PartListEditCubit>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: const ChamferBorder.tab(cut: 16),
        title: Text(TrTokens.deleteListDialogTitle.tr),
        content: Text(TrTokens.deleteListDialogDesc.tr),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          HoloActionButton(
            label: TrTokens.cancelTxt.tr,
            dense: true,
            variant: HoloButtonVariant.outline,
            onPressed: () => Navigator.pop(c, false),
          ),
          HoloActionButton(
            label: TrTokens.deleteTxt.tr,
            dense: true,
            variant: HoloButtonVariant.danger,
            onPressed: () => Navigator.pop(c, true),
          ),
        ],
      ),
    );
    if (ok == true) await cubit.delete();
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PartListEditCubit, PartListEditState>(
      listenWhen: (p, c) =>
          p.status != c.status ||
          p.error != c.error ||
          p.draft.name != c.draft.name,
      listener: _onState,
      buildWhen: (p, c) =>
          p.status != c.status ||
          p.saving != c.saving ||
          p.deleting != c.deleting ||
          p.draft != c.draft,
      builder: (context, state) => switch (state.status) {
        PartListEditStatus.notFound => const LinkProblemPage(),
        PartListEditStatus.loading => _shell(
            context,
            title: '',
            body: const Center(child: BeybladeSpinner()),
          ),
        PartListEditStatus.failure => _shell(
            context,
            title: '',
            body: HoloEmptyState(
              icon: Icons.error_outline,
              title: TrTokens.listLoadFailedTxt.tr,
              message: state.error,
              action: HoloActionButton(
                label: TrTokens.retryTxt.tr,
                onPressed: context.read<PartListEditCubit>().retry,
              ),
            ),
          ),
        _ => _form(context, state),
      },
    );
  }

  Widget _shell(
    BuildContext context, {
    required String title,
    required Widget body,
    List<Widget>? actions,
  }) {
    final rc = ResponsiveProvider.config(context);
    return ResponsiveScaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      maxWidth: rc.maxContentWidth,
      appBar: AppBar(title: Text(title), actions: actions),
      body: body,
    );
  }

  Widget _form(BuildContext context, PartListEditState state) {
    final rc = ResponsiveProvider.config(context);
    final cubit = context.read<PartListEditCubit>();
    return _shell(
      context,
      title: state.isNew
          ? TrTokens.kitNewTitle
              .trParams({'kind': state.draft.kind.label.toLowerCase()})
          : TrTokens.settingsEditKit.tr,
      actions: [
        if (!state.isNew)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: HoloIconButton(
              tooltip: TrTokens.deleteTxt.tr,
              icon: Icons.delete_outline,
              size: 40,
              variant: HoloButtonVariant.danger,
              onPressed: state.busy ? null : _delete,
            ),
          ),
      ],
      body: Padding(
        padding: EdgeInsets.fromLTRB(
            rc.horizontalPadding, rc.md, rc.horizontalPadding, rc.sm),
        child: ListView(
          children: [
            HoloInput(
              controller: _name,
              label: TrTokens.listNameLabel.tr,
              hint: TrTokens.listNameHint.tr,
              maxLength: 60,
              onChanged: cubit.rename,
              textCapitalization: TextCapitalization.sentences,
            ),
            SizedBox(height: rc.md),
            PartListEditor(list: state.draft, onChanged: cubit.edit),
            SizedBox(height: rc.lg),
            HoloActionButton(
              label: state.saving ? TrTokens.savingMsg.tr : TrTokens.kitSave.tr,
              icon: Icons.save_outlined,
              expand: true,
              isLoading: state.saving,
              onPressed: state.canSave ? _save : null,
            ),
          ],
        ),
      ),
    );
  }
}
