import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../../domain/entities/structure.dart';
import '../cubits/structure/structure_cubit.dart';

/// Adds a row and returns its id (null when cancelled or refused; refusals show a snack).
/// [NewRowMode.empty] asks for a name first; variant / copy start from [copyFrom] straight away.
Future<String?> addRowWithPrompt(BuildContext context, String sheet,
    {NewRowMode mode = NewRowMode.empty, String? copyFrom}) async {
  Map<String, String>? values;
  if (mode == NewRowMode.empty) {
    final name = await showDialog<String>(context: context, builder: (_) => _NameDialog(sheet: sheet));
    if (name == null) return null;
    if (name.trim().isNotEmpty) values = {'name': name.trim()};
  }
  final cubit = sl<StructureCubit>();
  final id = await cubit.addRow(sheet, mode: mode, copyFrom: copyFrom, values: values);
  if (context.mounted) {
    final cs = Theme.of(context).colorScheme;
    final s = cubit.state;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(s.error ?? s.message ?? ''),
        backgroundColor: s.error != null ? cs.error : null,
      ));
  }
  await cubit.close();
  return id;
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.sheet});

  final String sheet;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('New row in ${widget.sheet}'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Dran Sword'),
              onSubmitted: (v) => Navigator.pop(context, v),
            ),
            const SizedBox(height: 8),
            Text('It gets the next free id; fill in the rest in the editor. For a recolor of an existing part, '
                'use "Duplicate as variant" on that part instead.',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, _name.text), child: const Text('Add row')),
        ],
      );
}
