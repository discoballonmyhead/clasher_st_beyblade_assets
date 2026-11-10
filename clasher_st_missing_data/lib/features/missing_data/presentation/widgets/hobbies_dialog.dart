import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../studio/domain/entities/studio_models.dart';
import '../cubits/workspace/data_workspace_cubit.dart';

Future<void> showHobbiesDialog(BuildContext context) => showDialog<void>(
  context: context,
  builder: (_) => BlocProvider.value(value: context.read<DataWorkspaceCubit>(), child: const _HobbiesDialog()),
);

/// Hobbies, their generations (series - or years for card games) and workbooks. Saved in studio_workspace.json.
class _HobbiesDialog extends StatefulWidget {
  const _HobbiesDialog();

  @override
  State<_HobbiesDialog> createState() => _HobbiesDialogState();
}

class _Draft {
  _Draft(Hobby h)
    : name = TextEditingController(text: h.name),
      gens = TextEditingController(text: h.generations.join(', ')),
      books = TextEditingController(text: [for (final w in h.workbooks) '${w.role}: ${w.file}'].join('\n')),
      kind = h.kind,
      packaged = h.packaged,
      scraped = h.scraped;

  final TextEditingController name, gens, books;
  String kind;
  final bool packaged, scraped;

  Hobby toHobby() => Hobby(
    name: name.text.trim(),
    kind: kind,
    generations: [for (final g in gens.text.split(',')) if (g.trim().isNotEmpty) g.trim()],
    workbooks: [
      for (final line in books.text.split('\n'))
        if (line.trim().isNotEmpty)
          WorkbookRef(
            role: line.contains(':') ? line.split(':').first.trim() : 'workbook',
            file: (line.contains(':') ? line.substring(line.indexOf(':') + 1) : line).trim(),
            path: '',
          ),
    ],
    packaged: packaged,
    scraped: scraped,
  );

  void dispose() {
    name.dispose();
    gens.dispose();
    books.dispose();
  }
}

class _HobbiesDialogState extends State<_HobbiesDialog> {
  late final List<_Draft> _drafts = [
    for (final h in context.read<DataWorkspaceCubit>().state.workspace?.hobbies ?? const <Hobby>[]) _Draft(h),
  ];
  String? _error;

  @override
  void dispose() {
    for (final d in _drafts) {
      d.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Hobbies'),
      content: SizedBox(
        width: 640,
        height: 520,
        child: ListView(children: [
          Text(
            'Generations are the series (Burst, X ...) or, for card games, years. Workbooks: one per line as '
            '"role: file.xlsx", next to the tools (or a full path). Packaging and scraping are set up for Beyblade and '
            'Beyblade TCG; a new hobby can be edited in Data now and gets its own packager later.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
          for (final (i, d) in _drafts.indexed)
            Card(
              margin: const EdgeInsets.only(top: 10),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(children: [
                  Row(children: [
                    Expanded(child: TextField(controller: d.name, decoration: const InputDecoration(labelText: 'Name', isDense: true))),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: d.kind,
                      onChanged: (v) => setState(() => d.kind = v ?? 'parts'),
                      items: const [
                        DropdownMenuItem(value: 'parts', child: Text('Parts')),
                        DropdownMenuItem(value: 'cards', child: Text('Card game')),
                      ],
                    ),
                    IconButton(
                      tooltip: d.packaged ? "Packaged and scraped today - can't be removed here" : 'Remove',
                      onPressed: d.packaged ? null : () => setState(() => _drafts.removeAt(i).dispose()),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ]),
                  TextField(controller: d.gens, decoration: const InputDecoration(labelText: 'Generations (comma separated)', isDense: true)),
                  TextField(
                    controller: d.books,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(labelText: 'Workbooks (role: file.xlsx, one per line)', isDense: true),
                  ),
                ]),
              ),
            ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _drafts.add(_Draft(const Hobby(name: '', kind: 'cards', generations: [])))),
              icon: const Icon(Icons.add),
              label: const Text('Add a hobby'),
            ),
          ),
          if (_error != null) Text(_error!, style: TextStyle(color: cs.error)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            final err = await context.read<DataWorkspaceCubit>().saveHobbies([for (final d in _drafts) d.toHobby()]);
            if (!context.mounted) return;
            if (err != null) {
              setState(() => _error = err);
            } else {
              Navigator.pop(context);
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
