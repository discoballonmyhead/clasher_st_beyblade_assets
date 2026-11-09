import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/translation_models.dart';
import '../cubits/translation_cubit.dart';
import '../cubits/translation_state.dart';
import 'common.dart';

/// The sheet's language columns, the code each pack is published under, and the app's registry. Edits go to the
/// sheet's Languages tab (the place codes are decided).
class LanguagesTab extends StatefulWidget {
  const LanguagesTab({super.key});

  @override
  State<LanguagesTab> createState() => _LanguagesTabState();
}

class _LanguagesTabState extends State<LanguagesTab> {
  List<TrLanguage>? _draft;
  List<TrLanguage>? _source;

  static final _code = RegExp(r'^[a-zA-Z]{2,3}(-[A-Za-z0-9]{2,8})*$');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocBuilder<TranslationCubit, TranslationState>(
      builder: (context, s) {
        if (!identical(_source, s.languages)) {
          _source = s.languages;
          _draft = [...s.languages];
        }
        final draft = _draft!;
        final changed = draft.indexed.any((e) => e.$2 != s.languages[e.$1]);
        final cover = {
          for (final c in s.report?.coverage ?? const <TrCoverage>[])
            c.language.column: c,
        };
        final registry = {
          for (final r
              in s.summary?.project?.registry ?? const <RegistryLanguage>[])
            r.code: r,
        };
        final rejected = {
          for (final r in s.summary?.project?.rejected ?? const <String>[])
            r.toLowerCase(),
        };
        final codes = <String, int>{};
        for (final l in draft.where((l) => !l.deprecated && l.code != null)) {
          codes[l.code!] = (codes[l.code!] ?? 0) + 1;
        }
        final hasSheetTab = s.summary?.sheet?.hasLanguagesTab ?? false;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'A pack is published as lang_<code>.zip and the app stores it under that code: changing a code after '
              'release orphans what people downloaded. Mark a language "removed" to stop publishing it; the app\'s '
              'registry then rejects its code.${hasSheetTab ? '' : ' The sheet has no Languages tab yet: saving here '
                        'creates one, so codes no longer depend on column names.'}',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(3),
                1: FixedColumnWidth(110),
                2: FlexColumnWidth(3),
                3: FixedColumnWidth(80),
                4: FixedColumnWidth(130),
                5: FixedColumnWidth(110),
                6: FlexColumnWidth(2),
              },
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  children: [
                    for (final h in [
                      'Sheet column',
                      'Code',
                      'Native name (picker)',
                      'Country',
                      'Status',
                      'Translated',
                      'In the app',
                    ])
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          h,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
                for (final (i, l) in draft.indexed)
                  TableRow(
                    children: [
                      Text(l.column),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: TextFormField(
                          key: ValueKey('code-${l.column}-${_source.hashCode}'),
                          initialValue: l.code ?? '',
                          decoration: InputDecoration(
                            isDense: true,
                            errorText: (l.code ?? '').isEmpty
                                ? 'needed'
                                : !_code.hasMatch(l.code!)
                                ? 'not a code'
                                : (codes[l.code!] ?? 0) > 1
                                ? 'twice'
                                : null,
                          ),
                          onChanged: (v) => setState(
                            () => draft[i] = l.copyWith(code: v.trim()),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: TextFormField(
                          key: ValueKey('name-${l.column}-${_source.hashCode}'),
                          initialValue: l.name,
                          decoration: const InputDecoration(isDense: true),
                          onChanged: (v) => setState(
                            () => draft[i] = l.copyWith(name: v.trim()),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: TextFormField(
                          key: ValueKey(
                            'country-${l.column}-${_source.hashCode}',
                          ),
                          initialValue: l.country,
                          decoration: const InputDecoration(isDense: true),
                          onChanged: (v) => setState(
                            () => draft[i] = l.copyWith(
                              country: v.trim().toUpperCase(),
                            ),
                          ),
                        ),
                      ),
                      DropdownButton<String>(
                        isExpanded: true,
                        isDense: true,
                        value: l.deprecated ? 'deprecated' : 'active',
                        onChanged: (v) =>
                            setState(() => draft[i] = l.copyWith(status: v)),
                        items: const [
                          DropdownMenuItem(
                            value: 'active',
                            child: Text('published'),
                          ),
                          DropdownMenuItem(
                            value: 'deprecated',
                            child: Text('removed'),
                          ),
                        ],
                      ),
                      Text(
                        cover[l.column] == null
                            ? '-'
                            : '${cover[l.column]!.percent.toStringAsFixed(0)}%  (${cover[l.column]!.translated})',
                      ),
                      Text(
                        l.code == null
                            ? '-'
                            : rejected.contains(l.code!.toLowerCase())
                            ? 'rejected (removed)'
                            : registry.containsKey(l.code)
                            ? registry[l.code]!.name
                            : 'missing - export adds it',
                        style: TextStyle(
                          color:
                              l.code != null &&
                                  !registry.containsKey(l.code) &&
                                  !rejected.contains(l.code!.toLowerCase()) &&
                                  !l.deprecated
                              ? Colors.orange.shade700
                              : null,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton.icon(
                  onPressed:
                      changed &&
                          codes.values.every((n) => n == 1) &&
                          draft.every((l) => _code.hasMatch(l.code ?? '')) &&
                          s.busy == null
                      ? () => _confirmAndSave(context, s.languages, draft)
                      : null,
                  icon: const Icon(Icons.check),
                  label: const Text('Save to the Languages tab'),
                ),
                const SizedBox(width: 8),
                if (changed)
                  TextButton(
                    onPressed: () => setState(() => _draft = [...s.languages]),
                    child: const Text('Discard'),
                  ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: s.busy == null
                      ? () => _addLanguage(context, draft)
                      : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Add a language'),
                ),
              ],
            ),
            const SectionTitle('How codes are found'),
            Text(
              'In this order: the Languages tab; languages.json beside the sheet; a code in brackets in the header '
              '("Korean (ko)"); a header that is a code ("th"); the Studio\'s list of language names. A column that '
              'matches none stops the pack build - a made-up code ships a pack the app can never match.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            for (final l in s.languages)
              Text(
                '  ${l.column}: ${l.code ?? 'no code'}${l.how != null ? '  (${l.how})' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  color: l.code == null ? cs.error : cs.onSurfaceVariant,
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _confirmAndSave(
    BuildContext context,
    List<TrLanguage> before,
    List<TrLanguage> after,
  ) async {
    final renamed = [
      for (final (i, l) in after.indexed)
        if (before[i].code != null && before[i].code != l.code)
          '${l.column}: ${before[i].code} -> ${l.code}',
    ];
    final cubit = context.read<TranslationCubit>();
    if (renamed.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Change language codes?'),
          content: Text(
            '${renamed.join('\n')}\n\nPeople who downloaded the old pack keep it under the old code, and '
            'the app won\'t match the new one to it. Only change a code before its first release.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Change'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await cubit.setLanguages(after);
  }

  Future<void> _addLanguage(
    BuildContext context,
    List<TrLanguage> current,
  ) async {
    final cubit = context.read<TranslationCubit>();
    final column = TextEditingController(),
        code = TextEditingController(),
        name = TextEditingController(),
        country = TextEditingController();
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Add a language'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: column,
                  decoration: const InputDecoration(
                    labelText: 'Sheet column header',
                    hintText: 'Thai',
                  ),
                ),
                TextField(
                  controller: code,
                  decoration: const InputDecoration(
                    labelText: 'Code (pack name)',
                    hintText: 'th',
                  ),
                ),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Native name',
                    hintText: 'ไทย',
                  ),
                ),
                TextField(
                  controller: country,
                  decoration: const InputDecoration(
                    labelText: 'Country (flag)',
                    hintText: 'TH',
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: TextStyle(color: Theme.of(c).colorScheme.error),
                    ),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Adds an empty column to the sheet. Empty cells fall back to English in the app, so a half-done '
                  'language is fine.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final col = column.text.trim(), cd = code.text.trim();
                final e = col.isEmpty
                    ? 'Give the column a header'
                    : current.any(
                        (l) => l.column.toLowerCase() == col.toLowerCase(),
                      )
                    ? 'The sheet already has that column'
                    : !_code.hasMatch(cd)
                    ? 'The code must look like ko, zh-TW or vi-south'
                    : current.any((l) => l.code == cd && !l.deprecated)
                    ? '$cd is already ${current.firstWhere((l) => l.code == cd).column}'
                    : null;
                if (e != null) {
                  set(() => error = e);
                  return;
                }
                Navigator.pop(c, true);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await cubit.addLanguage(
        column: column.text.trim(),
        code: code.text.trim(),
        name: name.text.trim().isEmpty ? code.text.trim() : name.text.trim(),
        country: country.text.trim().toUpperCase(),
      );
    }
    for (final c in [column, code, name, country]) {
      c.dispose();
    }
  }
}
