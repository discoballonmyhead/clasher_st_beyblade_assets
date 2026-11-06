import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubits/sheet/sheet_cubit.dart';
import '../cubits/sheet/sheet_state.dart';
import '../cubits/workbook/workbook_cubit.dart';
import '../cubits/workbook/workbook_state.dart';

/// Tabs of the workbook, then "missing per field" for the selected tab (click to filter rows).
class SheetSidebar extends StatelessWidget {
  const SheetSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 4), child: Text('Tabs', style: text.titleSmall)),
      BlocBuilder<WorkbookCubit, WorkbookState>(
        buildWhen: (a, b) => a.summary?.sheets != b.summary?.sheets,
        builder: (context, wb) => BlocBuilder<SheetCubit, SheetState>(
          buildWhen: (a, b) => a.sheet != b.sheet,
          builder: (context, st) => Flexible(
            child: ListView(shrinkWrap: true, children: [
              for (final s in wb.summary?.sheets ?? const [])
                ListTile(
                  selected: s.name == st.sheet,
                  title: Text(s.name.replaceFirst('Parts_', ''), maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: _Badge(gaps: s.rowsWithMissing, total: s.rows),
                  onTap: () => context.read<SheetCubit>().selectSheet(s.name),
                ),
            ]),
          ),
        ),
      ),
      const Divider(height: 16),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        child: Row(children: [
          Expanded(child: Text('Missing per field', style: text.titleSmall)),
          BlocBuilder<SheetCubit, SheetState>(
            buildWhen: (a, b) => a.includeOptional != b.includeOptional,
            builder: (context, st) => Tooltip(
              message: 'Also count optional columns (variantLabel, description ...)',
              child: FilterChip(
                label: const Text('optional'),
                selected: st.includeOptional,
                onSelected: (_) => context.read<SheetCubit>().toggleOptional(),
              ),
            ),
          ),
        ]),
      ),
      Expanded(
        child: BlocBuilder<SheetCubit, SheetState>(
          buildWhen: (a, b) => a.analysis != b.analysis || a.field != b.field,
          builder: (context, st) {
            final a = st.analysis;
            if (a == null) return const SizedBox.shrink();
            final gaps = a.withGaps;
            final cubit = context.read<SheetCubit>();
            return ListView(children: [
              ListTile(
                selected: st.field == null,
                title: const Text('All rows'),
                trailing: Text('${a.total}'),
                onTap: () => cubit.selectField(null),
              ),
              if (gaps.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    Icon(Icons.check_circle, color: cs.primary, size: 18),
                    const SizedBox(width: 6),
                    const Expanded(child: Text('Nothing missing in this tab')),
                  ]),
                ),
              for (final f in gaps)
                ListTile(
                  selected: st.field == f.field,
                  title: Text(f.field + (f.custom ? '  +' : '') + (f.never ? '  (never filled)' : ''),
                      style: f.custom
                          ? TextStyle(color: cs.tertiary)
                          : f.never
                              ? TextStyle(color: cs.onSurfaceVariant)
                              : null),
                  subtitle: LinearProgressIndicator(
                    value: a.total == 0 ? 0 : f.missing / a.total,
                    minHeight: 3,
                    backgroundColor: cs.surfaceContainerHighest,
                  ),
                  trailing: Text('${f.missing}'),
                  onTap: () => cubit.selectField(f.field),
                ),
            ]);
          },
        ),
      ),
    ]);
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.gaps, required this.total});

  final int gaps;
  final int total;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: '$gaps of $total rows have something missing',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: gaps == 0 ? cs.primaryContainer : cs.tertiaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(gaps == 0 ? '$total' : '$gaps/$total', style: const TextStyle(fontSize: 12)),
      ),
    );
  }
}
