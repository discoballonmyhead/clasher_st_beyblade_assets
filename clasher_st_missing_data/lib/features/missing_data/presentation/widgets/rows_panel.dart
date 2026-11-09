import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/row.dart';
import 'delete_rows.dart';
import 'new_row_dialog.dart';
import '../cubits/sheet/sheet_cubit.dart';
import '../cubits/sheet/sheet_state.dart';
import 'formatting.dart';

/// Search, sort and the rows of the tab. Tick rows for bulk actions; click a row to edit it.
class RowsPanel extends StatelessWidget {
  const RowsPanel({super.key, required this.searchFocus});

  final FocusNode searchFocus;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cubit = context.read<SheetCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  focusNode: searchFocus,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search id, name, code (Ctrl+F)',
                  ),
                  onChanged: cubit.search,
                ),
              ),
              const SizedBox(width: 8),
              BlocBuilder<SheetCubit, SheetState>(
                buildWhen: (a, b) => a.sort != b.sort,
                builder: (context, st) => SegmentedButton<RowSort>(
                  segments: const [
                    ButtonSegment(
                      value: RowSort.sheet,
                      label: Text('Sheet order'),
                    ),
                    ButtonSegment(
                      value: RowSort.missing,
                      label: Text('Most gaps'),
                    ),
                    ButtonSegment(
                      value: RowSort.updated,
                      label: Text('Last edited'),
                    ),
                  ],
                  selected: {st.sort},
                  onSelectionChanged: (s) => cubit.sortBy(s.first),
                ),
              ),
            ],
          ),
        ),
        BlocBuilder<SheetCubit, SheetState>(
          buildWhen: (a, b) =>
              a.total != b.total ||
              a.field != b.field ||
              a.selected != b.selected ||
              a.loading != b.loading,
          builder: (context, st) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            // the left group wraps onto a second line on narrow windows instead of overflowing
            child: Row(
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    children: [
                      Text(
                        '${st.total} rows${st.field != null ? ' missing ${st.field}' : ''}',
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                      if (st.selected.isNotEmpty) ...[
                        Chip(
                          label: Text('${st.selected.length} ticked'),
                          onDeleted: cubit.clearSelection,
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            foregroundColor: cs.error,
                          ),
                          onPressed: st.sheet == null
                              ? null
                              : () => deleteRowsWithConfirm(
                                  context,
                                  st.sheet!,
                                  st.selected.toList(),
                                ),
                          icon: const Icon(Icons.delete_outline, size: 18),
                          label: const Text('Delete ticked'),
                        ),
                      ],
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: st.sheet == null
                      ? null
                      : () async {
                          final id = await addRowWithPrompt(context, st.sheet!);
                          if (id != null) cubit.focus(id);
                        },
                  icon: const Icon(Icons.playlist_add, size: 18),
                  label: const Text('New row'),
                ),
                TextButton(
                  onPressed: cubit.selectAllListed,
                  child: const Text('Tick all listed'),
                ),
                if (st.loading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
        ),
        const _Header(),
        const Divider(height: 1),
        Expanded(
          child: BlocBuilder<SheetCubit, SheetState>(
            buildWhen: (a, b) =>
                a.rows != b.rows ||
                a.selected != b.selected ||
                a.focusedId != b.focusedId,
            builder: (context, st) {
              if (st.sheet == null) {
                return const Center(child: Text('Pick a tab on the left'));
              }
              if (st.rows.isEmpty && !st.loading) {
                return const Center(child: Text('No rows match'));
              }
              return ListView.builder(
                itemCount: st.rows.length,
                itemExtent: 44,
                itemBuilder: (context, i) => _RowTile(
                  row: st.rows[i],
                  odd: i.isOdd,
                  ticked: st.selected.contains(st.rows[i].id),
                  focused: st.focusedId == st.rows[i].id,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium
        ?.copyWith(fontWeight: FontWeight.bold);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 6),
      child: Row(
        children: [
          const SizedBox(width: 40),
          SizedBox(width: 56, child: Text('id', style: style)),
          Expanded(flex: 3, child: Text('name', style: style)),
          Expanded(flex: 2, child: Text('code', style: style)),
          Expanded(flex: 3, child: Text('edition / label', style: style)),
          SizedBox(width: 130, child: Text('last edited', style: style)),
          Expanded(flex: 4, child: Text('missing', style: style)),
        ],
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.row,
    required this.odd,
    required this.ticked,
    required this.focused,
  });

  final RowSummary row;
  final bool odd;
  final bool ticked;
  final bool focused;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cubit = context.read<SheetCubit>();
    final bg = focused
        ? cs.primaryContainer
        : (odd ? cs.surfaceContainerLow : null);
    return Material(
      color: bg,
      child: InkWell(
        onTap: () => cubit.focus(row.id),
        child: Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Checkbox(
                  value: ticked,
                  onChanged: (_) => cubit.toggleSelected(row.id),
                ),
              ),
              SizedBox(width: 56, child: Text(row.id, maxLines: 1)),
              Expanded(
                flex: 3,
                child: Text(
                  row.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  row.code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  row.edition,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 130,
                child: Text(
                  formatWhen(row.updatedAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: row.updatedAt == null ? cs.outline : null,
                  ),
                ),
              ),
              Expanded(
                flex: 4,
                child: row.missing.isEmpty
                    ? Icon(Icons.check, size: 16, color: cs.primary)
                    : Text(
                        row.missing.join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: cs.tertiary, fontSize: 12),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
