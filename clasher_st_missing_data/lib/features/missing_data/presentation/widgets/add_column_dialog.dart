import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../cubits/structure/structure_cubit.dart';
import '../cubits/structure/structure_state.dart';

/// Add a column to this tab or to every data tab. True when it was added.
Future<bool?> showAddColumnDialog(
  BuildContext context, {
  required String sheet,
  required List<String> allSheets,
}) => showDialog<bool>(
  context: context,
  builder: (_) => BlocProvider(
    create: (_) => sl<StructureCubit>(),
    child: _AddColumnDialog(sheet: sheet, allSheets: allSheets),
  ),
);

class _AddColumnDialog extends StatefulWidget {
  const _AddColumnDialog({required this.sheet, required this.allSheets});

  final String sheet;
  final List<String> allSheets;

  @override
  State<_AddColumnDialog> createState() => _AddColumnDialogState();
}

class _AddColumnDialogState extends State<_AddColumnDialog> {
  final _name = TextEditingController();
  final _default = TextEditingController();
  final _note = TextEditingController();
  bool _allTabs = false;
  bool _inherit = true;
  bool _optional = false;

  @override
  void dispose() {
    _name.dispose();
    _default.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final ok = await context.read<StructureCubit>().addColumn(
      sheets: _allTabs ? widget.allSheets : [widget.sheet],
      name: _name.text,
      optional: _optional,
      inherit: _inherit,
      defaultValue: _default.text,
      note: _note.text.trim(),
    );
    if (ok && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocBuilder<StructureCubit, StructureState>(
      builder: (context, s) => AlertDialog(
        title: const Text('Add a column'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _name,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Column name',
                    hintText: 'e.g. tipShape',
                    errorText: s.error,
                    helperText: 'Letters, digits and _ - it becomes the field name in the JSON',
                  ),
                  onSubmitted: (_) => _add(),
                ),
                const SizedBox(height: 12),
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text('This tab (${widget.sheet})'),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text('All ${widget.allSheets.length} tabs'),
                    ),
                  ],
                  selected: {_allTabs},
                  onSelectionChanged: (v) => setState(() => _allTabs = v.first),
                ),
                CheckboxListTile(
                  value: _inherit,
                  onChanged: (v) => setState(() => _inherit = v ?? false),
                  title: const Text('Variants copy it from their parent'),
                  subtitle: const Text(
                    'Auto-fill and "Duplicate as variant" carry it over',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  value: _optional,
                  onChanged: (v) => setState(() => _optional = v ?? false),
                  title: const Text('Optional'),
                  subtitle: const Text("Don't count it as missing"),
                  contentPadding: EdgeInsets.zero,
                ),
                TextField(
                  controller: _default,
                  decoration: const InputDecoration(
                    labelText: 'Value for every existing row (optional)',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _note,
                  decoration: const InputDecoration(
                    labelText: "Note: what it's for",
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Added after the last column (purple header) and listed in the workbook\'s _columns tab. '
                  'The packager writes it into the JSON; the app ignores fields it doesn\'t read yet.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: s.busy ? null : _add,
            icon: s.busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.view_column_outlined),
            label: const Text('Add column'),
          ),
        ],
      ),
    );
  }
}
