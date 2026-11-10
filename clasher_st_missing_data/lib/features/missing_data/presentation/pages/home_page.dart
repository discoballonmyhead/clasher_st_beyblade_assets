import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../cubits/workbook/workbook_cubit.dart';
import '../cubits/workspace/data_workspace_cubit.dart';
import '../widgets/hobbies_dialog.dart';
import '../cubits/workbook/workbook_state.dart';

/// Start page: open a workbook (dialog, typed path, or a recent one).
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _path = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<DataWorkspaceCubit>().load();
  }

  @override
  void dispose() {
    _path.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocConsumer<WorkbookCubit, WorkbookState>(
      listenWhen: (a, b) => a.status != b.status || b.error != null,
      listener: (context, s) {
        if (s.status == WorkbookStatus.ready) context.go(Routes.workbook);
        if (s.error != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.error!), backgroundColor: cs.error),
          );
        }
      },
      builder: (context, s) {
        final cubit = context.read<WorkbookCubit>();
        final busy = s.status == WorkbookStatus.opening;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Data'),
            actions: [
              IconButton(
                tooltip: 'Settings',
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => context.go(Routes.settings),
              ),
            ],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.all(24),
                shrinkWrap: true,
                children: [
                  Text(
                    'Find and fill what is missing',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Open beyblade_parts.xlsx, beyblade_products.xlsx or beyblade_tcg.xlsx. Edits stay in memory '
                    'until you save (Ctrl+S); every save keeps a .bak copy.',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          FilledButton.icon(
                            onPressed: busy ? null : cubit.pickAndOpen,
                            icon: const Icon(Icons.folder_open),
                            label: const Text('Open workbook...'),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _path,
                                  decoration: const InputDecoration(
                                    labelText: 'or paste a path',
                                  ),
                                  onSubmitted: (p) => p.trim().isEmpty
                                      ? null
                                      : cubit.open(p.trim()),
                                ),
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: busy
                                    ? null
                                    : () => _path.text.trim().isEmpty
                                          ? null
                                          : cubit.open(_path.text.trim()),
                                child: const Text('Open'),
                              ),
                            ],
                          ),
                          if (busy) ...[
                            const SizedBox(height: 16),
                            const LinearProgressIndicator(),
                            const SizedBox(height: 6),
                            Text(
                              'Opening - big workbooks with many images take a few seconds',
                              style: TextStyle(color: cs.onSurfaceVariant),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _Hobbies(busy: busy),
                  if (s.recent.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Recent',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Card(
                      child: Column(
                        children: [
                          for (final p in s.recent)
                            ListTile(
                              leading: const Icon(Icons.table_view_outlined),
                              title: Text(p.split(RegExp(r'[\\/]')).last),
                              subtitle: Text(
                                p,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: busy ? null : () => cubit.open(p),
                            ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}


/// Each hobby with its generations and workbooks, to open in one click.
class _Hobbies extends StatelessWidget {
  const _Hobbies({required this.busy});
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocBuilder<DataWorkspaceCubit, DataWorkspaceState>(
      builder: (context, ws) {
        final hobbies = ws.workspace?.hobbies ?? const [];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('Hobbies', style: Theme.of(context).textTheme.titleMedium)),
            TextButton.icon(
              onPressed: ws.workspace == null ? null : () => showHobbiesDialog(context),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit hobbies'),
            ),
          ]),
          if (ws.error != null) Text(ws.error!, style: TextStyle(color: cs.error, fontSize: 12)),
          for (final h in hobbies)
            Card(
              margin: const EdgeInsets.only(top: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(h.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${h.kind == 'cards' ? 'Card game' : 'Parts'} · ${h.generations.join(', ')}',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    for (final w in h.workbooks)
                      Tooltip(
                        message: w.exists ? w.path : 'Not found: ${w.path}',
                        child: OutlinedButton.icon(
                          onPressed: busy || !w.exists
                              ? null
                              : () {
                                  context.read<DataWorkspaceCubit>().selectHobby(h.name);
                                  context.read<WorkbookCubit>().open(w.path);
                                },
                          icon: Icon(w.exists ? Icons.table_chart_outlined : Icons.help_outline, size: 18),
                          label: Text(w.file),
                        ),
                      ),
                  ]),
                ]),
              ),
            ),
        ]);
      },
    );
  }
}
