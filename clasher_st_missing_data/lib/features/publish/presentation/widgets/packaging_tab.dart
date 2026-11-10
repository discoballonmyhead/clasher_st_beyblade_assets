import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../studio/domain/entities/studio_models.dart';
import '../cubits/packaging_cubit.dart';

/// Per JSON sheet: which columns go into the JSON and how critical each one is. Saved in packaging_profiles.json;
/// the packager, the release check and the missing data counts all follow it.
class PackagingTab extends StatelessWidget {
  const PackagingTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cubit = context.read<PackagingCubit>();
    return BlocConsumer<PackagingCubit, PackagingState>(
      listenWhen: (a, b) => (b.error != null && a.error != b.error) || (b.message != null && a.message != b.message),
      listener: (context, s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(s.error ?? s.message!),
        backgroundColor: s.error != null ? cs.error : null,
      )),
      builder: (context, s) {
        if (s.loading && s.sheets.isEmpty) return const Center(child: CircularProgressIndicator());
        final groups = <String, List<SheetProfile>>{};
        for (final p in s.sheets) {
          groups.putIfAbsent('${p.workbook}${p.generation != null ? ' - ${p.generation}' : ''}', () => []).add(p);
        }
        final d = s.draft;
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 280,
            child: ListView(children: [
              for (final g in groups.entries) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text(g.key, style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                ),
                for (final p in g.value)
                  ListTile(
                    dense: true,
                    selected: p.sheet == s.selected,
                    title: Text('${p.sheet}.json'),
                    subtitle: Text(p.tab),
                    trailing: p.columns.any((c) => c.changed) ? const Icon(Icons.tune, size: 16) : null,
                    onTap: () => cubit.select(p.sheet),
                  ),
              ],
            ]),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: d == null
                ? const Center(child: Text('Pick a sheet'))
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                      child: Text('${d.sheet}.json  ·  ${d.tab}${d.source == 'schema' ? '  (tab not in the workbook yet - schema columns)' : ''}',
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'Required: an empty cell blocks the release. Recommended: counted as missing in Data. Optional: never '
                        'counted. Unticked: left out of the JSON. Locked rows are ids, images and fields the app reads as '
                        'required. A new column added in Data shows up here once it\'s in the workbook.',
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ),
                    Expanded(
                      child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                        for (final c in d.columns)
                          ListTile(
                            dense: true,
                            leading: Checkbox(
                              value: c.include,
                              onChanged: c.locked ? null : (v) => cubit.edit(c.name, include: v ?? true),
                            ),
                            title: Row(children: [
                              Text(c.name, style: TextStyle(
                                fontWeight: c.changed ? FontWeight.w700 : null,
                                decoration: c.include ? null : TextDecoration.lineThrough,
                              )),
                              if (c.locked) ...[
                                const SizedBox(width: 6),
                                Tooltip(
                                  message: c.appRequired ? 'The app reads this as required' : 'Id / image column',
                                  child: Icon(Icons.lock_outline, size: 14, color: cs.outline),
                                ),
                              ],
                            ]),
                            subtitle: c.changed ? Text('default: ${c.defaultCriticality.name}') : null,
                            trailing: SizedBox(
                              width: 170,
                              child: DropdownButton<Criticality>(
                                isExpanded: true,
                                value: c.criticality,
                                onChanged: c.locked || !c.include ? null : (v) => cubit.edit(c.name, criticality: v),
                                items: const [
                                  DropdownMenuItem(value: Criticality.required, child: Text('required')),
                                  DropdownMenuItem(value: Criticality.recommended, child: Text('recommended')),
                                  DropdownMenuItem(value: Criticality.optional, child: Text('optional')),
                                ],
                              ),
                            ),
                          ),
                      ]),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        FilledButton.icon(
                          onPressed: s.dirty && !s.saving ? cubit.save : null,
                          icon: const Icon(Icons.check),
                          label: const Text('Save'),
                        ),
                        const SizedBox(width: 8),
                        if (s.dirty) TextButton(onPressed: cubit.discard, child: const Text('Discard')),
                        const Spacer(),
                        TextButton.icon(onPressed: cubit.load, icon: const Icon(Icons.refresh), label: const Text('Reload columns')),
                      ]),
                    ),
                  ]),
          ),
        ]);
      },
    );
  }
}
