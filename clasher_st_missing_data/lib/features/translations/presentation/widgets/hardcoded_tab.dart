import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../domain/entities/translation_models.dart';
import '../../domain/repositories/translation_repository.dart';
import '../cubits/translation_cubit.dart';
import '../cubits/translation_state.dart';
import 'common.dart';

/// Strings still written in the code: pick them, adjust their keys, add them to the sheet (and to the app's
/// constants on the next export). The code itself is yours to change - each row gives the constant to use.
class HardcodedTab extends StatefulWidget {
  const HardcodedTab({super.key});

  @override
  State<HardcodedTab> createState() => _HardcodedTabState();
}

class _HardcodedTabState extends State<HardcodedTab> {
  List<HardcodedString> _items = const [];
  final Map<String, String> _keys = {}; // text -> edited key
  final Set<String> _picked = {}; // texts
  bool _showMaybe = false;
  bool _loading = false;
  int _revision = -1;
  String _section = 'NEW';

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await sl<TranslationRepository>().hardcoded();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _items = res.valueOrNull ?? const [];
      _picked.removeWhere(
        (t) => !_items.any((i) => i.text == t && i.existingKey == null),
      );
    });
  }

  String _keyFor(HardcodedString h) => _keys[h.text] ?? h.key;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocBuilder<TranslationCubit, TranslationState>(
      builder: (context, s) {
        if (_revision != s.revision) {
          _revision = s.revision;
          WidgetsBinding.instance.addPostFrameCallback((_) => _load());
        }
        final cls = s.summary?.project?.className ?? 'TrTokens';
        final visible = [
          for (final h in _items)
            if (_showMaybe || h.confidence == 'high') h,
        ];
        // one row per distinct text: the same string in five files is one key
        final byText = <String, List<HardcodedString>>{};
        for (final h in visible) {
          byText.putIfAbsent(h.text, () => []).add(h);
        }
        final groups = byText.entries.toList();
        final newOnes = groups
            .where((g) => g.value.first.existingKey == null)
            .length;
        final problems = <String, String>{};
        final seen = <String, String>{};
        for (final g in groups) {
          if (g.value.first.existingKey != null) continue;
          final k = _keyFor(g.value.first);
          if (!keyPattern.hasMatch(k)) {
            problems[g.key] = 'lower_snake_case only';
          } else if (seen.containsKey(k)) {
            problems[g.key] = 'same key as "${seen[k]}"';
          }
          seen[k] = g.key;
        }
        final pickable = _picked
            .where((t) => !problems.containsKey(t))
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                '${groups.length} string(s) in ${{for (final h in visible) h.file}.length} file(s); $newOnes need a key. '
                'Ones the sheet already has only need the code changed. The Studio never edits your code.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChip(
                    label: const Text('Also show less certain ones'),
                    selected: _showMaybe,
                    onSelected: (v) => setState(() => _showMaybe = v),
                  ),
                  TextButton(
                    onPressed: () => setState(
                      () => _picked
                        ..clear()
                        ..addAll([
                          for (final g in groups)
                            if (g.value.first.existingKey == null) g.key,
                        ]),
                    ),
                    child: const Text('Pick all new'),
                  ),
                  TextButton(
                    onPressed: () => setState(_picked.clear),
                    child: const Text('None'),
                  ),
                  const SizedBox(width: 12),
                  const Text('Section in the app:'),
                  DropdownButton<String>(
                    value: _section,
                    onChanged: (v) => setState(() => _section = v ?? 'NEW'),
                    items: [
                      for (final sec in {
                        ...s.sections.where((x) => x.isNotEmpty),
                        'NEW',
                      })
                        DropdownMenuItem(value: sec, child: Text(sec)),
                    ],
                  ),
                  FilledButton.icon(
                    onPressed: pickable.isEmpty || s.busy != null
                        ? null
                        : () async {
                            final items = [
                              for (final t in pickable)
                                (
                                  key: _keyFor(byText[t]!.first),
                                  english: t,
                                  meta: {
                                    'Filepath': byText[t]!
                                        .map((h) => h.location)
                                        .take(5)
                                        .join(', '),
                                  },
                                ),
                            ];
                            final added = await context
                                .read<TranslationCubit>()
                                .addKeys(items, toApp: true, section: _section);
                            if (mounted) {
                              setState(
                                () => _picked.removeWhere(
                                  (t) =>
                                      added.contains(_keyFor(byText[t]!.first)),
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.playlist_add),
                    label: Text(
                      'Add ${pickable.length} to the sheet and the app',
                    ),
                  ),
                  if (_loading)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: groups.isEmpty
                  ? Center(
                      child: Text(
                        _loading
                            ? 'Scanning ...'
                            : 'Nothing written in the code. Everything goes through $cls.',
                      ),
                    )
                  : ListView.separated(
                      itemCount: groups.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final g = groups[i];
                        final h = g.value.first;
                        final existing = h.existingKey;
                        final key = existing ?? _keyFor(h);
                        final ref = '$cls.${tokenNameFor(key)}';
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Checkbox(
                                value:
                                    existing == null && _picked.contains(g.key),
                                onChanged: existing != null
                                    ? null
                                    : (v) => setState(
                                        () => v == true
                                            ? _picked.add(g.key)
                                            : _picked.remove(g.key),
                                      ),
                              ),
                              Expanded(
                                flex: 4,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '"${g.key}"',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    Text(
                                      [
                                        for (final x in g.value.take(3))
                                          '${x.location} (${x.context})',
                                        if (g.value.length > 3)
                                          '+${g.value.length - 3} more',
                                      ].join('   '),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                    if (h.placeholders.isNotEmpty)
                                      Text(
                                        'placeholders: ${h.placeholders.map((p) => '{$p}').join(' ')} - the code passes these in',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                    if (h.confidence != 'high')
                                      Text(
                                        'less certain: may not be shown to people',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: cs.onSurfaceVariant,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 3,
                                child: existing != null
                                    ? Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: Text(
                                          'already $existing',
                                          style: TextStyle(color: cs.primary),
                                        ),
                                      )
                                    : TextFormField(
                                        key: ValueKey('hc-${g.key}'),
                                        initialValue: key,
                                        decoration: InputDecoration(
                                          isDense: true,
                                          labelText: 'key',
                                          errorText: problems[g.key],
                                        ),
                                        onChanged: (v) => setState(
                                          () => _keys[g.key] = v.trim(),
                                        ),
                                      ),
                              ),
                              IconButton(
                                tooltip:
                                    'Copy $ref (use it in place of the text)',
                                icon: const Icon(Icons.copy, size: 18),
                                onPressed: () =>
                                    Clipboard.setData(ClipboardData(text: ref)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            if (s.addToApp.isNotEmpty)
              Container(
                color: cs.secondaryContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: SectionTitle(
                  '${s.addToApp.length} key(s) wait for the next export to reach the app\'s constants',
                  trailing: Text(
                    'Export & packs tab',
                    style: TextStyle(color: cs.onSecondaryContainer),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
