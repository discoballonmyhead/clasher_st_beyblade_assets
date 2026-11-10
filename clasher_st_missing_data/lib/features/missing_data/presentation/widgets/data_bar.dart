import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/sheet/sheet_cubit.dart';
import '../cubits/workbook/workbook_cubit.dart';
import '../cubits/workbook/workbook_state.dart';
import '../cubits/workspace/data_workspace_cubit.dart';

/// The open workbook's tabs that belong to [gen] (all of them for null).
List<String> tabsOf(WorkbookState wb, String? gen) => [
  for (final s in wb.summary?.sheets ?? const [])
    if (s.belongsTo(gen)) s.name,
];

/// Hobby -> generation, and the workbooks open as tabs.
class DataBar extends StatelessWidget {
  const DataBar({super.key, required this.onClose});

  /// Close a workbook tab (asks first when it has unsaved changes).
  final Future<void> Function(String path) onClose;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocBuilder<DataWorkspaceCubit, DataWorkspaceState>(
      builder: (context, ws) => BlocBuilder<WorkbookCubit, WorkbookState>(
        buildWhen: (a, b) =>
            a.docs != b.docs ||
            a.summary?.path != b.summary?.path ||
            a.dirtyDocs != b.dirtyDocs,
        builder: (context, wb) {
          final hobby = ws.current;
          return Container(
            color: cs.surfaceContainerLow,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            height: 40,
            child: Theme(
              data: Theme.of(context).copyWith(
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              child: Row(
                children: [
                  if (ws.workspace != null &&
                      ws.workspace!.hobbies.isNotEmpty) ...[
                    DropdownButton<String>(
                      value: ws.hobby,
                      isDense: true,
                      underline: const SizedBox.shrink(),
                      onChanged: (h) {
                        if (h == null) return;
                        final path = context
                            .read<DataWorkspaceCubit>()
                            .selectHobby(h);
                        context.read<SheetCubit>().setGeneration(null);
                        if (path != null) {
                          context.read<WorkbookCubit>().switchTo(path);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '$h has no workbook yet - add its file on the Data home page (Edit hobbies).',
                              ),
                            ),
                          );
                        }
                      },
                      items: [
                        for (final h in ws.workspace!.hobbies)
                          DropdownMenuItem(value: h.name, child: Text(h.name)),
                      ],
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('All'),
                      selected: ws.generation == null,
                      onSelected: (_) {
                        context.read<DataWorkspaceCubit>().selectGeneration(
                          null,
                        );
                        context.read<SheetCubit>().setGeneration(
                          null,
                          tabs: tabsOf(wb, null),
                        );
                      },
                    ),
                    for (final g in hobby?.generations ?? const <String>[])
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text(g),
                          selected: ws.generation == g,
                          onSelected: (_) {
                            context.read<DataWorkspaceCubit>().selectGeneration(
                              g,
                            );
                            context.read<SheetCubit>().setGeneration(
                              g,
                              tabs: tabsOf(wb, g),
                            );
                          },
                        ),
                      ),
                    const SizedBox(width: 12),
                  ],
                  const VerticalDivider(width: 1, indent: 8, endIndent: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final p in wb.docs)
                            Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: InputChip(
                                key: ValueKey('doc-$p'),
                                selected: wb.summary?.path == p,
                                avatar: Icon(
                                  Icons.table_chart_outlined,
                                  size: 16,
                                  color: cs.primary,
                                ),
                                label: Text(
                                  '${wb.dirtyDocs.contains(p) ? '● ' : ''}${p.split(RegExp(r'[\\/]')).last}',
                                ),
                                onPressed: () =>
                                    context.read<WorkbookCubit>().switchTo(p),
                                onDeleted: () => onClose(p),
                                deleteButtonTooltipMessage: 'Close',
                              ),
                            ),
                          if (hobby != null)
                            for (final w in hobby.workbooks)
                              if (w.exists &&
                                  !wb.docs.any(
                                    (d) =>
                                        d.replaceAll('\\', '/') ==
                                        w.path.replaceAll('\\', '/'),
                                  ))
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: ActionChip(
                                    avatar: const Icon(Icons.add, size: 16),
                                    label: Text(w.file),
                                    tooltip: 'Open ${w.path}',
                                    onPressed: () => context
                                        .read<WorkbookCubit>()
                                        .open(w.path),
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
