import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../domain/entities/structure.dart';
import '../../domain/usecases/structure_usecases.dart';
import '../cubits/edit_log/edit_log_cubit.dart';
import '../cubits/edit_log/edit_log_state.dart';
import 'formatting.dart';

/// Everything changed with the missing data tool, from the workbook's _edit_log tab.
/// Returns the entry picked (to jump to its row).
Future<EditLogEntry?> showEditLogDialog(BuildContext context, {String? sheet}) => showDialog<EditLogEntry>(
      context: context,
      builder: (_) => BlocProvider(
        create: (_) => EditLogCubit(getLog: sl<GetEditLog>(), sheet: sheet)..load(),
        child: const _EditLogDialog(),
      ),
    );

IconData _icon(String action) => switch (action) {
      'add_column' => Icons.view_column_outlined,
      'add_row' => Icons.playlist_add,
      'auto-fill' => Icons.auto_fix_high,
      'image' => Icons.image_outlined,
      'wiki' => Icons.travel_explore,
      _ => Icons.edit_outlined,
    };

class _EditLogDialog extends StatelessWidget {
  const _EditLogDialog();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cubit = context.read<EditLogCubit>();
    return AlertDialog(
      title: const Text('Change log'),
      content: SizedBox(
        width: 860,
        height: 540,
        child: BlocBuilder<EditLogCubit, EditLogState>(
          builder: (context, s) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search tab, id, field, value'),
                  onChanged: cubit.search,
                ),
              ),
              const SizedBox(width: 12),
              if (cubit.sheet != null)
                FilterChip(
                  label: Text('Only ${cubit.sheet}'),
                  selected: s.thisTabOnly,
                  onSelected: (_) => cubit.toggleThisTab(),
                ),
            ]),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                '${s.total} change(s) made with the missing data tool${s.total > s.entries.length ? ' - newest ${s.entries.length} shown' : ''}. '
                'Kept in the workbook (_edit_log); the packager exports it to data/_edit_log.json.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
            Expanded(
              child: s.loading && s.entries.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : s.error != null
                      ? Center(child: Text(s.error!))
                      : s.entries.isEmpty
                          ? const Center(child: Text('No changes yet.'))
                          : ListView.separated(
                              itemCount: s.entries.length,
                              separatorBuilder: (_, _) => const Divider(height: 1),
                              itemBuilder: (context, i) => _EntryTile(entry: s.entries[i]),
                            ),
            ),
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});

  final EditLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final e = entry;
    final what = switch (e.action) {
      'set' || 'auto-fill' || 'image' => '${e.field}: ${e.oldValue ?? '(empty)'} → ${e.newValue ?? '(empty)'}',
      'add_column' => 'new column ${e.field}',
      'add_row' => 'new row',
      _ => e.action,
    };
    return ListTile(
      dense: true,
      leading: Icon(_icon(e.action), color: e.action.startsWith('add_') ? cs.tertiary : cs.primary),
      title: Text('${e.sheet}${e.rowId != null ? '  #${e.rowId}' : ''}  -  $what',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
          [e.action, e.source, if (e.note != null) e.note!].join('  ·  '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis),
      trailing: Text(formatWhen(e.at), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      onTap: e.rowId == null || e.rowId!.contains(',') ? null : () => Navigator.pop(context, e),
    );
  }
}
