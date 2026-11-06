import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:missing_data_app/features/missing_data/presentation/cubits/recycle_bin/recycle_bin_cubit.dart';

import '../../../../core/di/service_locator.dart';
import 'formatting.dart';

Future<void> showRecycleBin(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => BlocProvider(
    create: (_) => sl<RecycleBinCubit>()..load(),
    child: const RecycleBinDialog(),
  ),
);

/// Rows deleted with the tool: restore them (with their pictures) or remove them for good.
class RecycleBinDialog extends StatelessWidget {
  const RecycleBinDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocConsumer<RecycleBinCubit, RecycleBinState>(
      listenWhen: (a, b) =>
          b.message != null && a.message != b.message ||
          b.error != null && a.error != b.error,
      listener: (context, s) => ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(s.error ?? s.message!),
            backgroundColor: s.error != null ? cs.error : null,
          ),
        ),
      builder: (context, s) {
        final cubit = context.read<RecycleBinCubit>();
        return AlertDialog(
          title: const Text('Recently deleted'),
          content: SizedBox(
            width: 640,
            height: 420,
            child: s.loading && s.items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : s.items.isEmpty
                ? const Center(
                    child: Text(
                      'Nothing deleted. Rows you delete stay here until you empty it.',
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ListView.builder(
                          itemCount: s.items.length,
                          itemBuilder: (context, i) {
                            final d = s.items[i];
                            return CheckboxListTile(
                              key: ValueKey(d.key),
                              value: s.selected.contains(d.key),
                              onChanged: (_) => cubit.toggle(d.key),
                              dense: true,
                              secondary: Icon(
                                d.hasImage
                                    ? Icons.image_outlined
                                    : Icons.hide_image_outlined,
                                color: cs.onSurfaceVariant,
                              ),
                              title: Text('#${d.rowId}  ${d.name}'),
                              subtitle: Text(
                                '${d.sheet}  -  deleted ${formatWhen(d.deletedAt)}'
                                '${d.source.isEmpty ? '' : ' with ${d.source}'}',
                              ),
                            );
                          },
                        ),
                      ),
                      Text(
                        'Restored rows go to the end of their tab, with their old id when it is free.',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: s.items.isEmpty
                  ? null
                  : () => _confirmPurge(context, cubit, all: true),
              child: const Text('Empty'),
            ),
            TextButton(
              onPressed: s.selected.isEmpty
                  ? null
                  : () => _confirmPurge(context, cubit),
              child: const Text('Delete for good'),
            ),
            FilledButton.icon(
              onPressed: s.selected.isEmpty ? null : cubit.restoreSelected,
              icon: const Icon(Icons.restore),
              label: Text(
                s.selected.isEmpty ? 'Restore' : 'Restore ${s.selected.length}',
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _confirmPurge(
    BuildContext context,
    RecycleBinCubit cubit, {
    bool all = false,
  }) async {
    final n = all ? cubit.state.items.length : cubit.state.selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove $n row(s) for good?'),
        content: const Text(
          'With their pictures. Undo (Ctrl+Z) still brings them back until you close the workbook.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) await cubit.purge(all: all);
  }
}
