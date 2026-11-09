import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/translation_models.dart';
import '../cubits/translation_cubit.dart';
import '../cubits/translation_state.dart';
import 'common.dart';

/// Where the app and the sheet stand: key counts, problems by kind, coverage per language, the files found.
class OverviewTab extends StatelessWidget {
  const OverviewTab({
    super.key,
    required this.onShowKey,
    required this.onOpenTab,
  });

  final void Function(String key) onShowKey;
  final void Function(int tab) onOpenTab;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocBuilder<TranslationCubit, TranslationState>(
      builder: (context, s) {
        final r = s.report;
        final p = s.summary?.project;
        final sheet = s.summary?.sheet;
        if (r == null) return const Center(child: CircularProgressIndicator());
        final byKind = <String, List<TrIssue>>{};
        for (final i in r.issues) {
          byKind.putIfAbsent(i.kind, () => []).add(i);
        }
        final kinds = byKind.entries.toList()
          ..sort(
            (a, b) => a.value.first.severity.index.compareTo(
              b.value.first.severity.index,
            ),
          );
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Stat(
                  label: 'Keys in the app',
                  value: '${r.keysInApp}',
                  hint: p == null ? 'no project' : p.className,
                ),
                _Stat(
                  label: 'Keys in the sheet',
                  value: '${r.keysInSheet}',
                  hint: sheet?.fileName ?? 'no sheet',
                ),
                _Stat(label: 'In both', value: '${r.keysInBoth}'),
                _Stat(
                  label: 'Errors',
                  value: '${r.count(TrSeverity.error)}',
                  color: cs.error,
                  onTap: () => onOpenTab(4),
                ),
                _Stat(
                  label: 'Warnings',
                  value: '${r.count(TrSeverity.warning)}',
                  color: Colors.orange.shade700,
                  onTap: () => onOpenTab(4),
                ),
                _Stat(
                  label: 'Pending for the app',
                  value: '${s.addToApp.length + s.updateEnglish.length}',
                  hint: 'next export',
                  onTap: () => onOpenTab(5),
                ),
              ],
            ),
            const SectionTitle('Languages'),
            if (r.coverage.isEmpty)
              Text(
                'Open a sheet to see the languages.',
                style: TextStyle(color: cs.onSurfaceVariant),
              )
            else
              for (final c in r.coverage) _CoverageRow(c: c),
            const SectionTitle('What needs a look'),
            if (kinds.isEmpty)
              Row(
                children: [
                  Icon(Icons.check_circle, color: cs.primary),
                  const SizedBox(width: 8),
                  const Text('Everything is in step.'),
                ],
              )
            else
              for (final e in kinds)
                Builder(
                  builder: (context) {
                    final (icon, color) = severityLook(
                      context,
                      e.value.first.severity,
                    );
                    final first = e.value.firstWhere(
                      (i) => i.key != null,
                      orElse: () => e.value.first,
                    );
                    return ListTile(
                      dense: true,
                      leading: Icon(icon, color: color),
                      title: Text(
                        '${issueKindLabels[e.key] ?? e.key}  (${e.value.length})',
                      ),
                      subtitle: Text(
                        first.message,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: first.key != null && e.key != 'hardcoded'
                          ? TextButton(
                              onPressed: () => onShowKey(first.key!),
                              child: const Text('Show'),
                            )
                          : TextButton(
                              onPressed: () =>
                                  onOpenTab(e.key == 'hardcoded' ? 2 : 4),
                              child: const Text('Open'),
                            ),
                    );
                  },
                ),
            const SectionTitle('Files'),
            _FileRow(
              label: 'TrTokens',
              path: p?.tokensFile,
              missing: 'not found - an export creates it',
            ),
            _FileRow(
              label: 'Default English',
              path: p?.defaultsFile,
              missing: 'not found - an export creates it',
            ),
            _FileRow(
              label: 'Language registry',
              path: p?.languagesFile,
              missing: 'not found - an export creates it',
            ),
            _FileRow(label: 'Sheet', path: sheet?.path, missing: 'none'),
            _FileRow(
              label: 'Export folder',
              path: s.active?.exportDir,
              missing: 'none',
            ),
            const SizedBox(height: 8),
            Text(
              s.active?.writeIntoProject == true
                  ? 'The project is read; after an export you can copy the three constants files in (each backed up first).'
                  : 'The project is only read. Generated files go to the export folder.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ],
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.hint,
    this.color,
    this.onTap,
  });
  final String label;
  final String value;
  final String? hint;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 180,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(color: color),
                ),
                Text(label),
                if (hint != null)
                  Text(
                    hint!,
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverageRow extends StatelessWidget {
  const _CoverageRow({required this.c});
  final TrCoverage c;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = c.language;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 230,
            child: Text(l.column, overflow: TextOverflow.ellipsis),
          ),
          SizedBox(
            width: 90,
            child: Text(
              l.code ?? 'no code',
              style: TextStyle(
                color: l.code == null ? cs.error : cs.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: LinearProgressIndicator(
              value: c.total == 0 ? 0 : c.translated / c.total,
              minHeight: 6,
              borderRadius: BorderRadius.circular(3),
              backgroundColor: cs.surfaceContainerHighest,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 170,
            child: Text(
              '${c.percent.toStringAsFixed(c.percent == 100 ? 0 : 1)}%  (${c.translated}/${c.total})'
              '${l.deprecated ? '  removed' : ''}',
            ),
          ),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.label,
    required this.path,
    required this.missing,
  });
  final String label;
  final String? path;
  final String missing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 160,
            child: Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
          ),
          Expanded(
            child: SelectableText(
              path ?? missing,
              style: TextStyle(
                fontSize: 13,
                color: path == null ? cs.onSurfaceVariant : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
