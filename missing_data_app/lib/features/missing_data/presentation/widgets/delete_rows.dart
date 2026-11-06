import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../cubits/structure/structure_cubit.dart';

/// Asks, then deletes [ids] from [sheet] (they go to Recently deleted). True when deleted.
Future<bool> deleteRowsWithConfirm(BuildContext context, String sheet, List<String> ids) async {
  if (ids.isEmpty) return false;
  final list = ids.take(8).map((i) => '#$i').join(', ') + (ids.length > 8 ? ' ...' : '');
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text('Delete ${ids.length} row(s)?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Text('$list from $sheet.\n\nThe rows below move up together with their pictures. Deleted rows '
            'stay in Recently deleted (with their pictures) until you empty it, and Undo brings them back.'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(c).colorScheme.error),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  final cubit = sl<StructureCubit>();
  final res = await cubit.deleteRows(sheet, ids);
  if (context.mounted) {
    final s = cubit.state;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(s.error ?? s.message ?? ''),
        backgroundColor: s.error != null ? Theme.of(context).colorScheme.error : null,
      ));
  }
  await cubit.close();
  return res != null;
}
