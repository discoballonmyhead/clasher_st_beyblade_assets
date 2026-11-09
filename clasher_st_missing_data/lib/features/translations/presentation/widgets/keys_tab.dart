import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/translation_models.dart';
import '../cubits/translation_cubit.dart';
import '../cubits/translation_keys_cubit.dart';
import '../cubits/translation_state.dart';
import 'common.dart';

/// Every key in the app or the sheet, with filters; the selected one opens in the editor.
class KeysTab extends StatelessWidget {
  const KeysTab({super.key});

  @override
  Widget build(BuildContext context) => const Row(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Expanded(flex: 5, child: _KeyList()),
      VerticalDivider(width: 1),
      Expanded(flex: 4, child: KeyEditor()),
    ],
  );
}

class _KeyList extends StatelessWidget {
  const _KeyList();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final keys = context.read<TranslationKeysCubit>();
    final langs = context.select<TranslationCubit, List<TrLanguage>>(
      (c) => c.state.languages,
    );
    return BlocBuilder<TranslationKeysCubit, TranslationKeysState>(
      builder: (context, s) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Key, constant, English or any translation',
                      isDense: true,
                    ),
                    onChanged: keys.search,
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String?>(
                  value: s.missingIn,
                  hint: const Text('Any language'),
                  onChanged: keys.filterMissingIn,
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Any language'),
                    ),
                    for (final l in langs)
                      DropdownMenuItem(
                        value: l.column,
                        child: Text('Missing in ${l.code ?? l.column}'),
                      ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
                  child: ChoiceChip(
                    label: const Text('All'),
                    selected: s.status == null,
                    onSelected: (_) => keys.filterStatus(null),
                  ),
                ),
                for (final e in TrStatus.labels.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: 6, top: 4, bottom: 4),
                    child: ChoiceChip(
                      label: Text(e.value),
                      selected: s.status == e.key,
                      onSelected: (_) =>
                          keys.filterStatus(s.status == e.key ? null : e.key),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Text(
                  '${s.total} keys',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                ),
                const Spacer(),
                if (s.loading)
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
          const Divider(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: s.rows.length,
              itemExtent: 64,
              itemBuilder: (context, i) {
                final r = s.rows[i];
                final done = langs.length - r.missingLanguages.length;
                return ListTile(
                  key: ValueKey(r.key),
                  selected: r.key == s.selected,
                  onTap: () => keys.select(r.key),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          r.key,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          r.english,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Row(
                    children: [
                      for (final st in r.status.where(
                        (x) => x != TrStatus.untranslated,
                      ))
                        StatusChip(st),
                      const Spacer(),
                      if (r.inSheet)
                        Text(
                          '$done/${langs.length}',
                          style: TextStyle(
                            fontSize: 12,
                            color: done == langs.length
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One key: the app's and the sheet's English, every translation (checked as you type), and the fixes its
/// status calls for.
class KeyEditor extends StatefulWidget {
  const KeyEditor({super.key});

  @override
  State<KeyEditor> createState() => _KeyEditorState();
}

class _KeyEditorState extends State<KeyEditor> {
  final Map<String, TextEditingController> _ctl = {};
  String? _for; // key the controllers hold
  TrKeyRow? _loaded; // the row they were filled from

  @override
  void dispose() {
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _load(TrKeyRow r, List<TrLanguage> langs) {
    final same = _for == r.key && _ctl.length == langs.length + 1;
    // the row changed underneath (a fix, undo, recovery): refill, unless there are unapplied edits
    if (same &&
        (_loaded == r || (_loaded != null && _drafts(_loaded!).isNotEmpty))) {
      return;
    }
    for (final c in _ctl.values) {
      c.dispose();
    }
    _ctl
      ..clear()
      ..['English'] = TextEditingController(text: r.sheetEnglish ?? '');
    for (final l in langs) {
      _ctl[l.column] = TextEditingController(
        text: r.translations[l.column] ?? '',
      );
    }
    _for = r.key;
    _loaded = r;
  }

  Map<String, String> _drafts(TrKeyRow r) => {
    for (final e in _ctl.entries)
      if (e.value.text !=
          (e.key == 'English'
              ? (r.sheetEnglish ?? '')
              : (r.translations[e.key] ?? '')))
        e.key: e.value.text,
  };

  /// The same checks as the engine, while typing.
  List<String> _check(String english, String text) {
    if (text.isEmpty) return const [];
    final pe = placeholdersOf(english), pt = placeholdersOf(text);
    return [
      if (pe.any((p) => !pt.contains(p)))
        'missing ${pe.where((p) => !pt.contains(p)).map((p) => '{$p}').join(' ')}',
      if (pt.any((p) => !pe.contains(p)))
        '${pt.where((p) => !pe.contains(p)).map((p) => '{$p}').join(' ')} isn\'t in the English',
      if (RegExp(r'%(?:\d+\$)?[sd]').allMatches(english).length !=
          RegExp(r'%(?:\d+\$)?[sd]').allMatches(text).length)
        '%s count differs from the English',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ws = context.read<TranslationCubit>();
    return BlocBuilder<TranslationKeysCubit, TranslationKeysState>(
      buildWhen: (a, b) => a.selectedRow != b.selectedRow,
      builder: (context, ks) {
        final r = ks.selectedRow;
        if (r == null) return const Center(child: Text('Pick a key'));
        return BlocBuilder<TranslationCubit, TranslationState>(
          builder: (context, s) {
            final langs = s.languages;
            _load(r, langs);
            final drafts = _drafts(r);
            final english = _ctl['English']!.text.isNotEmpty
                ? _ctl['English']!.text
                : r.english;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              r.key,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copy the key',
                            icon: const Icon(Icons.copy, size: 18),
                            onPressed: () =>
                                Clipboard.setData(ClipboardData(text: r.key)),
                          ),
                        ],
                      ),
                      Text(
                        [
                          if (r.inApp)
                            '${s.summary?.project?.className ?? 'TrTokens'}.${r.token}'
                          else
                            'not in the app',
                          if (r.section != null && r.section!.isNotEmpty)
                            r.section!,
                          if (r.subsection != null && r.subsection!.isNotEmpty)
                            r.subsection!,
                          if (r.inApp) 'used ${r.uses}x',
                          if (r.where != null)
                            'sheet ${r.where}'
                          else
                            'not in the sheet',
                        ].join('  ·  '),
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                      if (r.comment.isNotEmpty)
                        Text(
                          'placeholders: ${r.comment}',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Wrap(
                        children: [for (final st in r.status) StatusChip(st)],
                      ),
                      ..._fixes(context, r, s, ws),
                      if (r.inApp) ...[
                        const SectionTitle('English in the app'),
                        SelectableText(
                          r.appEnglish ??
                              '(none - add it to defaultEnglishTranslations)',
                        ),
                      ],
                      if (r.inSheet) ...[
                        const SectionTitle('English in the sheet'),
                        TextField(
                          controller: _ctl['English'],
                          maxLines: null,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(isDense: true),
                        ),
                        const SectionTitle('Translations'),
                        for (final l in langs)
                          _translationField(context, l, english, r),
                      ],
                    ],
                  ),
                ),
                if (r.inSheet) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        FilledButton.icon(
                          onPressed: drafts.isEmpty || s.busy != null
                              ? null
                              : () async {
                                  await ws.setCells([
                                    for (final e in drafts.entries)
                                      (
                                        key: r.key,
                                        column: e.key,
                                        text: e.value,
                                      ),
                                  ]);
                                  _for =
                                      null; // reload from the engine's answer
                                },
                          icon: const Icon(Icons.check),
                          label: Text(
                            drafts.isEmpty ? 'Apply' : 'Apply ${drafts.length}',
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (drafts.isNotEmpty)
                          TextButton(
                            onPressed: () => setState(() => _for = null),
                            child: const Text('Discard'),
                          ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Saved to the sheet with "Save sheet"',
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.end,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        );
      },
    );
  }

  Widget _translationField(
    BuildContext context,
    TrLanguage l,
    String english,
    TrKeyRow r,
  ) {
    final cs = Theme.of(context).colorScheme;
    final problems = _check(english, _ctl[l.column]!.text);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        key: ValueKey('${r.key}-${l.column}'),
        controller: _ctl[l.column],
        maxLines: null,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          isDense: true,
          labelText:
              '${l.column}${l.code != null ? '  (${l.code})' : ''}${l.deprecated ? '  - removed' : ''}',
          errorText: problems.isEmpty ? null : problems.join('; '),
          filled: _ctl[l.column]!.text.isEmpty,
          fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          suffixIcon: IconButton(
            tooltip: 'Start from the English',
            icon: const Icon(Icons.content_paste_go, size: 18),
            onPressed: () => setState(() => _ctl[l.column]!.text = english),
          ),
        ),
      ),
    );
  }

  List<Widget> _fixes(
    BuildContext context,
    TrKeyRow r,
    TranslationState s,
    TranslationCubit ws,
  ) {
    final out = <Widget>[];
    if (!r.inSheet && r.inApp) {
      out.add(
        _Fix(
          text: 'Nobody can translate this key until it is in the sheet.',
          action: 'Add to the sheet',
          onPressed: () => ws.addKeys([
            (key: r.key, english: r.appEnglish ?? '', meta: const {}),
          ]),
        ),
      );
    }
    if (r.inSheet && !r.inApp) {
      final pending = s.addToApp.containsKey(r.key);
      out.add(
        _Fix(
          text: pending
              ? 'Added to the app on the next export, under ${s.addToApp[r.key]}.'
              : 'The app has no constant for this key (unused, or not added yet).',
          action: pending ? 'Don\'t add' : 'Add to the app',
          onPressed: () =>
              pending ? ws.unmarkForApp(r.key) : ws.markForApp(r.key),
          extra: pending
              ? DropdownButton<String>(
                  value: s.addToApp[r.key],
                  onChanged: (v) => ws.markForApp(r.key, section: v),
                  items: [
                    for (final sec in {
                      ...s.sections,
                      'NEW',
                      s.addToApp[r.key]!,
                    })
                      DropdownMenuItem(
                        value: sec,
                        child: Text(sec.isEmpty ? '(top)' : sec),
                      ),
                  ],
                )
              : null,
        ),
      );
    }
    if (r.status.contains(TrStatus.englishMismatch)) {
      final pending = s.updateEnglish.contains(r.key);
      final sameShape =
          placeholdersOf(r.appEnglish ?? '').join() ==
          placeholdersOf(r.sheetEnglish ?? '').join();
      out.add(
        _Fix(
          text: pending
              ? 'The app\'s English becomes the sheet\'s on the next export.'
              : sameShape
              ? 'The app and the sheet have different English.'
              : 'Different English, and different placeholders: fix the sheet (the code fills the placeholders in).',
          action: 'Copy the app\'s English to the sheet',
          onPressed: () => ws.setCells([
            (key: r.key, column: 'English', text: r.appEnglish ?? ''),
          ]),
          secondary: sameShape
              ? (pending ? 'Keep the app\'s' : 'Use the sheet\'s in the app')
              : null,
          onSecondary: () => ws.toggleEnglishUpdate(r.key),
        ),
      );
    }
    return out;
  }
}

class _Fix extends StatelessWidget {
  const _Fix({
    required this.text,
    required this.action,
    required this.onPressed,
    this.secondary,
    this.onSecondary,
    this.extra,
  });

  final String text;
  final String action;
  final VoidCallback onPressed;
  final String? secondary;
  final VoidCallback? onSecondary;
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 10),
      color: cs.secondaryContainer.withValues(alpha: 0.6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonal(onPressed: onPressed, child: Text(action)),
                if (secondary != null)
                  OutlinedButton(
                    onPressed: onSecondary,
                    child: Text(secondary!),
                  ),
                ?extra,
              ],
            ),
          ],
        ),
      ),
    );
  }
}
