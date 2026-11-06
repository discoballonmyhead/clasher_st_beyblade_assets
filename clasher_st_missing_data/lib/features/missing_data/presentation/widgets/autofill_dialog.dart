import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../cubits/autofill/autofill_cubit.dart';
import '../cubits/autofill/autofill_state.dart';

/// Shows every value the engine can fill, lets the user untick some, applies the rest.
Future<int?> showAutofillDialog(BuildContext context, String sheet) =>
    showDialog<int>(
      context: context,
      builder: (_) => BlocProvider(
        create: (_) => sl<AutofillCubit>()..load(sheet),
        child: _AutofillDialog(sheet: sheet),
      ),
    );

class _AutofillDialog extends StatelessWidget {
  const _AutofillDialog({required this.sheet});

  final String sheet;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocBuilder<AutofillCubit, AutofillState>(
      builder: (context, s) {
        final cubit = context.read<AutofillCubit>();
        final visible = s.visible.toList();
        return AlertDialog(
          title: Text('Auto-fill $sheet'),
          content: SizedBox(
            width: 860,
            height: 520,
            child: s.loading
                ? const Center(child: CircularProgressIndicator())
                : s.proposals.isEmpty
                ? Center(
                    child: Text(
                      s.error ??
                          'Nothing can be filled automatically in this tab.',
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'From a variant\'s parent row, from rows with the same name that all agree, '
                        'or derived from the row itself. Only empty cells are filled; undo with Ctrl+Z.',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final k in s.sourceKinds)
                            FilterChip(
                              label: Text(k),
                              selected: !s.hiddenSources.contains(k),
                              onSelected: (_) => cubit.toggleSource(k),
                            ),
                          TextButton(
                            onPressed: () => cubit.selectAll(true),
                            child: const Text('Tick all'),
                          ),
                          TextButton(
                            onPressed: () => cubit.selectAll(false),
                            child: const Text('Untick all'),
                          ),
                        ],
                      ),
                      const Divider(),
                      Expanded(
                        child: ListView.builder(
                          itemCount: visible.length,
                          itemExtent: 40,
                          itemBuilder: (context, i) {
                            final idx = visible[i];
                            final p = s.proposals[idx];
                            return CheckboxListTile(
                              dense: true,
                              value: s.selected.contains(idx),
                              onChanged: (_) => cubit.toggle(idx),
                              title: Text(
                                '#${p.id}  ${p.field} = ${p.value}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              secondary: Text(
                                p.source,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: s.applying || s.selectedVisible == 0
                  ? null
                  : () async {
                      final n = await cubit.apply(sheet);
                      if (context.mounted && n != null)
                        Navigator.pop(context, n);
                    },
              child: Text('Apply ${s.selectedVisible}'),
            ),
          ],
        );
      },
    );
  }
}
