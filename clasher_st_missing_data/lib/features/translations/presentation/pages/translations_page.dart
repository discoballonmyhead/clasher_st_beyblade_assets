import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/services/system_open.dart';
import '../cubits/translation_cubit.dart';
import '../cubits/translation_keys_cubit.dart';
import '../cubits/translation_state.dart';
import '../widgets/export_tab.dart';
import '../widgets/hardcoded_tab.dart';
import '../widgets/issues_tab.dart';
import '../widgets/keys_tab.dart';
import '../widgets/languages_tab.dart';
import '../widgets/overview_tab.dart';
import '../widgets/project_dialog.dart';

/// Strings of an app: the sheet and the app's constants side by side, what's untranslated or broken, strings
/// still written in the code, the languages, and the exports (Dart constants, language packs).
class TranslationsPage extends StatefulWidget {
  const TranslationsPage({super.key});

  static const tabs = [
    'Overview',
    'Keys',
    'In the code',
    'Languages',
    'Issues',
    'Export & packs',
  ];

  @override
  State<TranslationsPage> createState() => _TranslationsPageState();
}

class _TranslationsPageState extends State<TranslationsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: TranslationsPage.tabs.length,
    vsync: this,
  );
  late final TranslationKeysCubit _keys = TranslationKeysCubit(
    repository: sl(),
    workspace: sl<TranslationCubit>(),
  );
  String? _offeredFor; // the sheet the recovery prompt was shown for

  @override
  void initState() {
    super.initState();
    sl<TranslationCubit>().ensureStarted();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _keys.close();
    super.dispose();
  }

  void _snack(String text, {bool error = false}) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: error ? cs.error : null,
          duration: Duration(seconds: error ? 8 : 3),
        ),
      );
  }

  /// Jump from an issue / the overview to one key in the Keys tab.
  void showKey(String key) {
    _keys.show(key);
    _tabs.animateTo(1);
  }

  Future<void> _offerRecovery(TranslationState s) async {
    final n = s.summary?.sheet?.unsavedFromLastTime ?? 0;
    final path = s.summary?.sheet?.path;
    if (n == 0 || path == null || _offeredFor == path) return;
    _offeredFor = path;
    final cubit = context.read<TranslationCubit>();
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: const Text('Recover unsaved translations?'),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Text(
            '$n change(s) made to ${s.summary!.sheet!.fileName} were never saved - the Studio was closed '
            'or stopped. They are kept in a recovery file next to the sheet.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, 'later'),
            child: const Text('Ask me next time'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'discard'),
            child: const Text('Discard them'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, 'recover'),
            child: const Text('Recover'),
          ),
        ],
      ),
    );
    if (choice == 'recover') await cubit.recoverUnsaved();
    if (choice == 'discard') await cubit.discardUnsaved();
  }

  Future<void> _saveForced(TranslationCubit cubit) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Overwrite the newer file?'),
        content: const Text(
          'The sheet was saved by something else (Excel, another tool) after the Studio opened '
          'it. Overwriting replaces those changes with yours; a copy of the newer file goes to backups/ first. '
          'To keep both, reopen the project instead and redo your changes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Overwrite'),
          ),
        ],
      ),
    );
    if (ok == true) await cubit.save(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TranslationCubit>();
    return BlocProvider.value(
      value: _keys,
      child: BlocConsumer<TranslationCubit, TranslationState>(
        listenWhen: (a, b) =>
            b.message != null ||
            b.error != null ||
            (a.summary?.sheet?.path != b.summary?.sheet?.path) ||
            (a.summary?.sheet?.unsavedFromLastTime !=
                b.summary?.sheet?.unsavedFromLastTime),
        listener: (context, s) {
          if (s.error != null || s.message != null) {
            _snack(s.error ?? s.message!, error: s.error != null);
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _offerRecovery(s);
          });
        },
        builder: (context, s) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
                cubit.save(),
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                cubit.undo,
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              appBar: AppBar(
                titleSpacing: 16,
                title: _ProjectPicker(state: s),
                actions: [
                  if (s.isOpen) ...[
                    IconButton(
                      tooltip: 'Undo (Ctrl+Z)',
                      onPressed: s.undoSteps > 0 && s.busy == null
                          ? cubit.undo
                          : null,
                      icon: const Icon(Icons.undo),
                    ),
                    IconButton(
                      tooltip:
                          'Scan the project again (after you changed the code)',
                      onPressed: s.busy == null ? cubit.refresh : null,
                      icon: const Icon(Icons.refresh),
                    ),
                    if (s.active != null)
                      IconButton(
                        tooltip: 'Open the export folder',
                        onPressed: () => openInSystem(s.active!.exportDir),
                        icon: const Icon(Icons.folder_open_outlined),
                      ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: s.dirty && s.busy == null
                          ? () => cubit.save()
                          : null,
                      icon: const Icon(Icons.save),
                      label: const Text('Save sheet'),
                    ),
                    const SizedBox(width: 12),
                  ],
                ],
                bottom: s.isOpen
                    ? TabBar(
                        controller: _tabs,
                        isScrollable: true,
                        tabAlignment: TabAlignment.start,
                        tabs: [
                          for (final (i, t) in TranslationsPage.tabs.indexed)
                            Tab(
                              child: _TabLabel(text: t, badge: _badge(s, i)),
                            ),
                        ],
                      )
                    : null,
              ),
              body: Column(
                children: [
                  if (s.busy != null)
                    const LinearProgressIndicator(minHeight: 2),
                  ..._banners(context, s, cubit),
                  Expanded(
                    child: !s.isOpen
                        ? _EmptyState(state: s)
                        : TabBarView(
                            controller: _tabs,
                            children: [
                              OverviewTab(
                                onShowKey: showKey,
                                onOpenTab: _tabs.animateTo,
                              ),
                              const KeysTab(),
                              const HardcodedTab(),
                              const LanguagesTab(),
                              IssuesTab(onShowKey: showKey),
                              const ExportTab(),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  int? _badge(TranslationState s, int tab) {
    final r = s.report;
    if (r == null) return null;
    return switch (tab) {
      2 => r.issues.where((i) => i.kind == 'hardcoded' && i.key != null).length,
      4 =>
        r.issues
            .where((i) => i.severity.index < 2 && i.kind != 'hardcoded')
            .length,
      5 => s.addToApp.length + s.updateEnglish.length,
      _ => null,
    };
  }

  List<Widget> _banners(
    BuildContext context,
    TranslationState s,
    TranslationCubit cubit,
  ) {
    final cs = Theme.of(context).colorScheme;
    final sheet = s.summary?.sheet;
    final out = <Widget>[];
    Widget banner(
      IconData icon,
      Color bg,
      Color fg,
      String text, [
      List<Widget> actions = const [],
    ]) => MaterialBanner(
      backgroundColor: bg,
      leading: Icon(icon, color: fg),
      content: Text(text, style: TextStyle(color: fg)),
      actions: actions.isEmpty ? [const SizedBox.shrink()] : actions,
    );
    if (s.conflict) {
      out.add(
        banner(
          Icons.sync_problem,
          cs.errorContainer,
          cs.onErrorContainer,
          'Not saved: the sheet changed on disk after it was opened. Reopen the project to see those changes, or '
          'overwrite them with yours.',
          [
            TextButton(onPressed: cubit.open, child: const Text('Reopen')),
            TextButton(
              onPressed: () => _saveForced(cubit),
              child: const Text('Overwrite'),
            ),
          ],
        ),
      );
    }
    if (sheet != null && sheet.unsupported.isNotEmpty) {
      out.add(
        banner(
          Icons.block,
          cs.errorContainer,
          cs.onErrorContainer,
          'This sheet has ${sheet.unsupported.join(', ')}, which would be lost on save - so the Studio won\'t save '
          'it. Keep those in another workbook.',
        ),
      );
    }
    for (final l in sheet?.locks ?? const []) {
      out.add(
        banner(
          Icons.lock_outline,
          cs.tertiaryContainer,
          cs.onTertiaryContainer,
          '${sheet!.fileName} may be open in ${l.file.startsWith('.~lock') ? 'LibreOffice' : 'Excel'}'
          '${l.user != null ? ' (${l.user}'
                    '${l.modified != null ? ', since ${l.modified}' : ''})' : ''}'
          '${l.stale ? ' - the lock looks stale' : ''}. Whichever saves last wins: close it there before saving '
          'here.',
        ),
      );
    }
    return out;
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.text, this.badge});
  final String text;
  final int? badge;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(text),
      if ((badge ?? 0) > 0) ...[
        const SizedBox(width: 6),
        Badge(label: Text('$badge')),
      ],
    ],
  );
}

class _ProjectPicker extends StatelessWidget {
  const _ProjectPicker({required this.state});
  final TranslationState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TranslationCubit>();
    final s = state;
    final sheet = s.summary?.sheet;
    return Row(
      children: [
        if (s.projects.isNotEmpty)
          DropdownButton<String>(
            value: s.active?.id,
            underline: const SizedBox.shrink(),
            onChanged: s.busy == null
                ? (id) => id == null ? null : cubit.select(id)
                : null,
            items: [
              for (final p in s.projects)
                DropdownMenuItem(value: p.id, child: Text(p.name)),
            ],
          ),
        if (s.active != null)
          IconButton(
            tooltip: 'Edit this project',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () =>
                showTranslationProjectDialog(context, existing: s.active),
          ),
        IconButton(
          tooltip: 'Add an app',
          icon: const Icon(Icons.add, size: 20),
          onPressed: () => showTranslationProjectDialog(context),
        ),
        const SizedBox(width: 12),
        if (sheet != null)
          Flexible(
            child: Text(
              '${sheet.dirty ? '● ' : ''}${sheet.fileName} - ${sheet.keys} keys, ${sheet.languages.length} languages'
              '${sheet.undo > 0 ? ' - ${sheet.undo} undo step(s)' : ''}',
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.state});
  final TranslationState state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (state.loading) return const Center(child: CircularProgressIndicator());
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Translations',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Add an app: its Flutter project folder and its translation sheet. The Studio reads the project\'s '
              'TrTokens, default English and language registry, finds strings still written in the code, and keeps '
              'the sheet in step. It never changes the project: generated Dart goes to an export folder.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => showTranslationProjectDialog(context),
              icon: const Icon(Icons.add),
              label: Text(
                state.projects.isEmpty ? 'Add an app' : 'Add another app',
              ),
            ),
            if (state.active != null && state.summary == null) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: context.read<TranslationCubit>().open,
                icon: const Icon(Icons.refresh),
                label: Text('Try opening ${state.active!.name} again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
