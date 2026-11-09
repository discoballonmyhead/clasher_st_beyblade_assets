import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/translation_models.dart';
import '../cubits/translation_cubit.dart';
import '../cubits/translation_state.dart';
import 'common.dart';

/// Every problem, filterable by severity and kind; tap one to open its key.
class IssuesTab extends StatefulWidget {
  const IssuesTab({super.key, required this.onShowKey});
  final void Function(String key) onShowKey;

  @override
  State<IssuesTab> createState() => _IssuesTabState();
}

class _IssuesTabState extends State<IssuesTab> {
  final Set<TrSeverity> _severities = {TrSeverity.error, TrSeverity.warning};
  String? _kind;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocBuilder<TranslationCubit, TranslationState>(
      builder: (context, s) {
        final all = s.report?.issues ?? const <TrIssue>[];
        final kinds = {for (final i in all) i.kind}.toList()..sort();
        final q = _query.toLowerCase();
        final list = [
          for (final i in all)
            if (_severities.contains(i.severity) &&
                (_kind == null || i.kind == _kind) &&
                (q.isEmpty ||
                    '${i.key} ${i.language} ${i.message} ${i.where}'
                        .toLowerCase()
                        .contains(q)))
              i,
        ];
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  for (final sev in TrSeverity.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(
                          '${sev.name} (${all.where((i) => i.severity == sev).length})',
                        ),
                        selected: _severities.contains(sev),
                        onSelected: (v) => setState(
                          () => v
                              ? _severities.add(sev)
                              : _severities.remove(sev),
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  DropdownButton<String?>(
                    value: _kind,
                    hint: const Text('All kinds'),
                    onChanged: (v) => setState(() => _kind = v),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All kinds'),
                      ),
                      for (final k in kinds)
                        DropdownMenuItem(
                          value: k,
                          child: Text(issueKindLabels[k] ?? k),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Filter',
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${list.length} shown',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: list.length,
                itemBuilder: (context, n) {
                  final i = list[n];
                  final (icon, color) = severityLook(context, i.severity);
                  return ListTile(
                    dense: true,
                    leading: Icon(icon, color: color, size: 20),
                    title: Text(
                      [
                        issueKindLabels[i.kind] ?? i.kind,
                        if (i.key != null) i.key!,
                        if (i.language != null) i.language!,
                      ].join('  ·  '),
                    ),
                    subtitle: Text(
                      '${i.message}${i.where != null ? '   [${i.where}]' : ''}',
                    ),
                    onTap: i.key != null && i.kind != 'hardcoded'
                        ? () => widget.onShowKey(i.key!)
                        : null,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
