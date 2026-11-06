import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../domain/entities/workbook.dart';
import '../cubits/row_editor/row_editor_cubit.dart';
import '../cubits/row_editor/row_editor_state.dart';
import '../cubits/sheet/sheet_cubit.dart';
import '../cubits/sheet/sheet_state.dart';
import '../cubits/wiki/wiki_cubit.dart';
import '../cubits/wiki/wiki_state.dart';
import '../cubits/workbook/workbook_cubit.dart';
import '../cubits/workbook/workbook_state.dart';
import '../widgets/add_column_dialog.dart';
import '../widgets/autofill_dialog.dart';
import '../widgets/edit_log_dialog.dart';
import '../widgets/formatting.dart';
import '../widgets/log_panel.dart';
import '../widgets/recent_edits_dialog.dart';
import '../widgets/row_editor_panel.dart';
import '../widgets/rows_panel.dart';
import '../widgets/sheet_sidebar.dart';

/// Tabs + missing per field | rows | row editor, with the log below.
class WorkbookPage extends StatefulWidget {
  const WorkbookPage({super.key});

  @override
  State<WorkbookPage> createState() => _WorkbookPageState();
}

class _WorkbookPageState extends State<WorkbookPage> {
  final _searchFocus = FocusNode();

  /// Asks before the WINDOW closes (title-bar ×, Alt+F4, Cmd+Q) when there are unsaved changes - not only
  /// when the in-app Close button is used.
  late final AppLifecycleListener _exitGuard = AppLifecycleListener(onExitRequested: _onExitRequested);

  @override
  void initState() {
    super.initState();
    final sheets = context.read<WorkbookCubit>().state.summary?.sheets ?? const [];
    final sheetCubit = context.read<SheetCubit>();
    if (sheetCubit.state.sheet == null && sheets.isNotEmpty) sheetCubit.selectSheet(sheets.first.name);
    // Columns a newer schema defines (e.g. simpleRatchet) were added on open: say so once the page is up.
    _exitGuard; // start listening
    final summary = context.read<WorkbookCubit>().state.summary;
    if ((summary?.unsavedEntries ?? 0) > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _offerRecovery(summary!));
    }
    final added = summary?.addedColumns ?? const [];
    if (added.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _snack('New columns added to this workbook: ${added.join(', ')} - save to keep');
      });
    }
  }

  Future<void> _offerRecovery(WorkbookSummary s) async {
    if (!mounted) return;
    final wb = context.read<WorkbookCubit>();
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Recover unsaved changes?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Text('${s.unsavedEntries} change(s) made in this workbook were never saved - the app was closed '
              'or stopped${s.unsavedLast != null ? ' (last one ${formatWhen(s.unsavedLast)})' : ''}. They are kept '
              'in a recovery file next to the workbook.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'later'), child: const Text('Ask me next time')),
          TextButton(onPressed: () => Navigator.pop(c, 'discard'), child: const Text('Discard them')),
          FilledButton(onPressed: () => Navigator.pop(c, 'recover'), child: const Text('Recover')),
        ],
      ),
    );
    if (choice == 'recover') await wb.recoverUnsaved();
    if (choice == 'discard') await wb.discardUnsaved();
  }

  /// Save / Don't save / Cancel. Every edit is also in the recovery file, so even a hard kill loses nothing,
  /// but the normal way out should never be a silent discard.
  Future<AppExitResponse> _onExitRequested() async {
    final wb = context.read<WorkbookCubit>();
    if (!(wb.state.summary?.dirty ?? false) || !mounted) return AppExitResponse.exit;
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Unsaved changes'),
        content: const Text('Save before closing?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, 'cancel'), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(c, 'discard'), child: const Text("Don't save")),
          FilledButton(onPressed: () => Navigator.pop(c, 'save'), child: const Text('Save')),
        ],
      ),
    );
    if (choice == 'save') return await wb.save() ? AppExitResponse.exit : AppExitResponse.cancel;
    return choice == 'discard' ? AppExitResponse.exit : AppExitResponse.cancel;
  }

  @override
  void dispose() {
    _exitGuard.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _snack(String text, {bool error = false}) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text),
        backgroundColor: error ? cs.error : null,
        duration: Duration(seconds: error ? 6 : 3),
      ));
  }

  Future<void> _autofill() async {
    final sheet = context.read<SheetCubit>().state.sheet;
    if (sheet == null) return;
    final n = await showAutofillDialog(context, sheet);
    if (n != null && mounted) _snack('Auto-fill: $n cells filled - save to keep (Ctrl+Z undoes)');
  }

  Future<void> _wiki() async {
    final st = context.read<SheetCubit>().state;
    final ids = st.selected.isNotEmpty
        ? st.selected.toList()
        : [if (st.focusedId != null) st.focusedId!];
    if (st.sheet == null || ids.isEmpty) {
      _snack('Tick rows (or click one) first');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Fill from wiki'),
        content: Text('Re-read the wiki pages of ${ids.length} row(s)? Only empty cells are filled. '
            'The workbook is saved first; requests go one at a time (safe for your IP).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Start')),
        ],
      ),
    );
    if (ok == true && mounted) await context.read<WikiCubit>().start(st.sheet!, ids);
  }

  Future<void> _recent() async {
    final e = await showRecentEditsDialog(context);
    if (e == null || !mounted) return;
    final sheet = context.read<SheetCubit>();
    if (sheet.state.sheet != e.sheet) await sheet.selectSheet(e.sheet);
    sheet.focus(e.id);
  }

  Future<void> _addColumn() async {
    final sheet = context.read<SheetCubit>().state.sheet;
    final all = <String>[for (final s in context.read<WorkbookCubit>().state.summary?.sheets ?? const <SheetInfo>[]) s.name];
    if (sheet == null) return;
    final ok = await showAddColumnDialog(context, sheet: sheet, allSheets: all);
    if (ok == true && mounted) _snack('Column added - save to keep (Ctrl+Z undoes). It shows in the field list and editor.');
  }

  Future<void> _changeLog() async {
    final e = await showEditLogDialog(context, sheet: context.read<SheetCubit>().state.sheet);
    if (e == null || e.rowId == null || !mounted) return;
    final sheet = context.read<SheetCubit>();
    if (sheet.state.sheet != e.sheet) await sheet.selectSheet(e.sheet);
    sheet.focus(e.rowId!);
  }

  Future<void> _close() async {
    final dirty = context.read<WorkbookCubit>().state.summary?.dirty ?? false;
    if (dirty) {
      final save = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Unsaved changes'),
          content: const Text('Save before closing the workbook?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Discard')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Save')),
          ],
        ),
      );
      if (save == null || !mounted) return;
      if (save) await context.read<WorkbookCubit>().save();
    }
    if (mounted) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final wb = context.read<WorkbookCubit>();
    return MultiBlocListener(
      listeners: [
        BlocListener<WorkbookCubit, WorkbookState>(
          listenWhen: (a, b) => b.message != null || b.error != null,
          listener: (_, s) => _snack(s.error ?? s.message!, error: s.error != null),
        ),
        BlocListener<SheetCubit, SheetState>(
          listenWhen: (a, b) => a.focusedId != b.focusedId && b.focusedId != null,
          listener: (context, s) => context.read<RowEditorCubit>().load(s.sheet!, s.focusedId!),
        ),
        BlocListener<SheetCubit, SheetState>(
          listenWhen: (a, b) => b.error != null && a.error != b.error,
          listener: (_, s) => _snack(s.error!, error: true),
        ),
        BlocListener<RowEditorCubit, RowEditorState>(
          listenWhen: (a, b) => b.message != null || b.error != null,
          listener: (_, s) => _snack(s.error ?? s.message!, error: s.error != null),
        ),
        BlocListener<WikiCubit, WikiState>(
          listenWhen: (a, b) => b.message != null || b.error != null,
          listener: (_, s) => _snack(s.error ?? s.message!, error: s.error != null),
        ),
      ],
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): wb.save,
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): wb.undo,
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): _searchFocus.requestFocus,
          const SingleActivator(LogicalKeyboardKey.enter, control: true): context.read<SheetCubit>().nextGap,
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            appBar: AppBar(
              leading: IconButton(tooltip: 'Close workbook', icon: const Icon(Icons.close), onPressed: _close),
              title: BlocBuilder<WorkbookCubit, WorkbookState>(
                builder: (context, s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${s.summary?.dirty == true ? '● ' : ''}${s.summary?.fileName ?? ''}'),
                  Text(
                    s.summary == null
                        ? ''
                        : '${s.summary!.dirty ? 'Unsaved changes' : 'All changes saved'} - '
                            'last saved ${ago(s.summary!.lastSaved)} - ${s.summary!.undoSteps} undo step(s)',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ]),
              ),
              actions: [
                BlocBuilder<WorkbookCubit, WorkbookState>(
                  builder: (context, s) => IconButton(
                    tooltip: 'Undo (Ctrl+Z)',
                    onPressed: (s.summary?.undoSteps ?? 0) > 0 ? wb.undo : null,
                    icon: const Icon(Icons.undo),
                  ),
                ),
                const SizedBox(width: 4),
                TextButton.icon(onPressed: _autofill, icon: const Icon(Icons.auto_fix_high), label: const Text('Auto-fill')),
                BlocBuilder<WikiCubit, WikiState>(
                  builder: (context, s) => TextButton.icon(
                    onPressed: s.running ? null : _wiki,
                    icon: const Icon(Icons.travel_explore),
                    label: const Text('Fill from wiki'),
                  ),
                ),
                TextButton.icon(
                    onPressed: _addColumn, icon: const Icon(Icons.view_column_outlined), label: const Text('Add column')),
                TextButton.icon(onPressed: _changeLog, icon: const Icon(Icons.receipt_long), label: const Text('Change log')),
                IconButton(tooltip: 'Recently edited', onPressed: _recent, icon: const Icon(Icons.history)),
                IconButton(
                    tooltip: 'Settings', onPressed: () => context.push(Routes.settings), icon: const Icon(Icons.settings_outlined)),
                const SizedBox(width: 8),
                BlocBuilder<WorkbookCubit, WorkbookState>(
                  builder: (context, s) => FilledButton.icon(
                    onPressed: s.saving || s.summary?.dirty != true ? null : wb.save,
                    icon: s.saving
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save),
                    label: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
            ),
            body: Column(children: [
              Expanded(
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(width: 280, child: SheetSidebar()),
                  const VerticalDivider(width: 1),
                  Expanded(child: RowsPanel(searchFocus: _searchFocus)),
                  const VerticalDivider(width: 1),
                  const SizedBox(width: 400, child: RowEditorPanel()),
                ]),
              ),
              const LogPanel(),
            ]),
          ),
        ),
      ),
    );
  }
}
