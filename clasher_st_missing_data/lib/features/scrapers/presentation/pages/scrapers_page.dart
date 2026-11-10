import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../publish/presentation/widgets/job_log.dart';
import '../cubits/scrapers_cubit.dart';
import '../widgets/code_editor.dart';

/// The wiki scraper per hobby and generation.
class ScrapersPage extends StatelessWidget {
  const ScrapersPage({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider.value(
    value: sl<ScrapersCubit>()..load(),
    child: BlocConsumer<ScrapersCubit, ScrapersState>(
      listenWhen: (a, b) => (b.error != null && a.error != b.error) || (b.message != null && a.message != b.message),
      listener: (context, s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(s.error ?? s.message!),
        backgroundColor: s.error != null ? Theme.of(context).colorScheme.error : null,
      )),
      builder: (context, s) {
        final cubit = context.read<ScrapersCubit>();
        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              titleSpacing: 16,
              title: Row(children: [
                const Text('Scrapers'),
                const SizedBox(width: 24),
                if (s.hobbies.isNotEmpty)
                  DropdownButton<String>(
                    value: s.hobby,
                    underline: const SizedBox.shrink(),
                    onChanged: s.running ? null : (h) => h == null ? null : cubit.selectHobby(h),
                    items: [for (final h in s.hobbies) DropdownMenuItem(value: h, child: Text(h))],
                  ),
                const SizedBox(width: 12),
                for (final g in s.generationsOf(s.hobby))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(g),
                      selected: s.generation == g,
                      onSelected: s.running ? null : (_) => cubit.selectGeneration(g),
                    ),
                  ),
              ]),
              actions: [
                IconButton(tooltip: 'Reload', onPressed: s.running ? null : cubit.load, icon: const Icon(Icons.refresh)),
                const SizedBox(width: 8),
              ],
              bottom: const TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [Tab(text: 'Run'), Tab(text: 'Target settings'), Tab(text: 'Code'), Tab(text: 'Scraper settings')],
              ),
            ),
            body: s.overview == null
                ? Center(child: s.loading ? const CircularProgressIndicator() : const Text('The scraper isn\'t available - check Settings'))
                : TabBarView(children: [_RunTab(s: s), _TargetTab(s: s), _CodeTab(s: s), _SettingsTab(s: s)]),
          ),
        );
      },
    ),
  );
}

class _TargetList extends StatelessWidget {
  const _TargetList({required this.s, this.pick = true});
  final ScrapersState s;
  final bool pick;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cubit = context.read<ScrapersCubit>();
    return ListView(children: [
      if (pick)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(children: [
            TextButton(onPressed: s.running ? null : cubit.pickAllVisible, child: const Text('All')),
            TextButton(onPressed: s.running ? null : cubit.clearPicks, child: const Text('None')),
          ]),
        ),
      for (final t in s.visible)
        ListTile(
          dense: true,
          selected: !pick && s.focused == t.target,
          leading: pick
              ? Checkbox(value: s.picked.contains(t.target), onChanged: s.running ? null : (_) => cubit.togglePick(t.target))
              : null,
          title: Text(t.label),
          subtitle: Text([
            t.target,
            if (t.categories.isNotEmpty) 'Category: ${t.categories.join(', ')}',
            if (t.progress != null) _progress(t.progress!),
          ].join('\n'), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          isThreeLine: t.progress != null || t.categories.isNotEmpty,
          trailing: t.hasPlugin ? Tooltip(message: 'Has its own code', child: Icon(Icons.code, size: 16, color: cs.primary)) : null,
          onTap: pick ? () => cubit.togglePick(t.target) : () => cubit.focus(t.target),
        ),
    ]);
  }

  static String _progress(Map<String, dynamic> p) {
    final done = p['done'] ?? p['done_count'] ?? (p['done_titles'] is List ? (p['done_titles'] as List).length : null);
    final total = p['total'] ?? (p['titles'] is List ? (p['titles'] as List).length : null);
    final complete = p['complete'] == true;
    if (complete) return 'complete';
    if (done != null && total != null) return '$done / $total pages';
    return 'started';
  }
}

class _RunTab extends StatelessWidget {
  const _RunTab({required this.s});
  final ScrapersState s;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cubit = context.read<ScrapersCubit>();
    final o = s.options;
    Widget number(String label, String? value, void Function(String) set) => SizedBox(
      width: 220,
      child: TextFormField(
        initialValue: value ?? '',
        enabled: !s.running,
        decoration: InputDecoration(labelText: label, isDense: true),
        keyboardType: TextInputType.number,
        onChanged: set,
      ),
    );
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 340, child: _TargetList(s: s)),
      const VerticalDivider(width: 1),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (s.overview!.userAgentNeedsContact)
              Card(
                color: cs.tertiaryContainer,
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Text('Put a way to contact you in the user agent (Scraper settings): Fandom asks bots to identify themselves.'),
                ),
              ),
            Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              number('Pages per target', o.limit?.toString(), (v) => cubit.setOptions(o.copyWith(limit: () => int.tryParse(v)))),
              number('Request budget', o.maxRequests?.toString(), (v) => cubit.setOptions(o.copyWith(maxRequests: () => int.tryParse(v)))),
              number('Seconds between requests', o.delay?.toString(), (v) => cubit.setOptions(o.copyWith(delay: () => double.tryParse(v)))),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              FilterChip(label: const Text('Skip images'), selected: o.noImages, onSelected: s.running ? null : (v) => cubit.setOptions(o.copyWith(noImages: v))),
              FilterChip(label: const Text('Overwrite filled cells'), selected: o.overwrite, onSelected: s.running ? null : (v) => cubit.setOptions(o.copyWith(overwrite: v))),
              FilterChip(label: const Text('Find new pages (relist)'), selected: o.relist, onSelected: s.running ? null : (v) => cubit.setOptions(o.copyWith(relist: v))),
              FilterChip(label: const Text('Refetch pages already in the workbook'), selected: o.refreshExisting, onSelected: s.running ? null : (v) => cubit.setOptions(o.copyWith(refreshExisting: v))),
              FilterChip(label: const Text('Only list the pages'), selected: o.listOnly, onSelected: s.running ? null : (v) => cubit.setOptions(o.copyWith(listOnly: v))),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              FilledButton.icon(
                onPressed: s.running || s.picked.isEmpty
                    ? null
                    : () async {
                        if (o.overwrite) {
                          final ok = await confirmAction(context,
                              title: 'Overwrite filled cells?',
                              action: 'Run and overwrite',
                              facts: [
                                'Cells you filled by hand are replaced by what the wiki says, for ${s.picked.length} target(s).',
                                'Save your workbook in Data first; the scraper writes the workbook file directly.',
                              ]);
                          if (!ok) return;
                        }
                        await cubit.run();
                      },
                icon: const Icon(Icons.play_arrow),
                label: Text(s.picked.isEmpty ? 'Pick targets' : 'Run ${s.picked.length} target(s)'),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Polite and resumable: one request at a time, progress saved as it goes. Stop finishes the current step '
                  'and saves; run again to continue. Close the workbook in Data and Excel while it runs - it writes the file.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
            ]),
            if (s.lastRun != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Last run: ${s.lastRun}')),
            const SizedBox(height: 12),
            Expanded(child: JobLog(lines: s.log, running: s.running, onStop: cubit.stop, onClear: cubit.clearLog, height: double.infinity)),
          ]),
        ),
      ),
    ]);
  }
}

class _TargetTab extends StatelessWidget {
  const _TargetTab({required this.s});
  final ScrapersState s;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cubit = context.read<ScrapersCubit>();
    return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 340, child: _TargetList(s: s, pick: false)),
      const VerticalDivider(width: 1),
      Expanded(
        child: s.focused == null
            ? const Center(child: Text('Pick a target to see its settings'))
            : Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(s.focused!, style: Theme.of(context).textTheme.titleMedium),
                  Text(
                    'categories: wiki categories to read · title_prefixes: stripped from page titles · exclude_title_regex: '
                    'pages to skip · aliases: {"wiki field": "our column"} · extra_titles: pages to always include · '
                    'list_pages (products): the product list pages.',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: CodeEditor(text: s.configText ?? '', onChanged: cubit.editConfig)),
                  if (s.configError != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(s.configError!, style: TextStyle(color: cs.error))),
                  const SizedBox(height: 8),
                  Row(children: [
                    FilledButton.icon(
                      onPressed: s.configDirty && s.configError == null ? cubit.saveConfig : null,
                      icon: const Icon(Icons.check),
                      label: const Text('Save'),
                    ),
                    const SizedBox(width: 8),
                    if (s.configDirty) TextButton(onPressed: cubit.discardConfig, child: const Text('Discard')),
                    const Spacer(),
                    Text(s.overview!.configPath, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  ]),
                ]),
              ),
      ),
    ]);
  }
}

class _CodeTab extends StatelessWidget {
  const _CodeTab({required this.s});
  final ScrapersState s;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cubit = context.read<ScrapersCubit>();
    final isScraper = s.codePath != null && s.codePath == s.scraperPath;
    final chk = s.codeCheck;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(
              isScraper
                  ? 'The scraper itself (fandom_scraper.py) - changes here affect every hobby and generation.'
                  : '${s.hobby} - ${s.generation}: code that runs after the built-in mapping for every page of this '
                      'hobby and generation${s.codeExists ? '' : ' (not created yet - this is a starting point)'}.',
              style: TextStyle(color: isScraper ? cs.error : cs.onSurfaceVariant),
            ),
          ),
          if (!isScraper)
            TextButton.icon(onPressed: cubit.openScraperSource, icon: const Icon(Icons.description_outlined), label: const Text('Scraper source (advanced)'))
          else
            TextButton.icon(onPressed: cubit.loadCode, icon: const Icon(Icons.arrow_back), label: Text('Back to ${s.hobby} - ${s.generation}')),
        ]),
        const SizedBox(height: 8),
        Expanded(child: CodeEditor(text: s.codeText ?? '', onChanged: cubit.editCode, errorLine: chk?.ok == false ? chk!.line : null)),
        const SizedBox(height: 8),
        if (chk != null)
          Text(chk.ok ? 'No syntax errors' : 'Line ${chk.line ?? '?'}: ${chk.message}', style: TextStyle(color: chk.ok ? cs.primary : cs.error)),
        Row(children: [
          OutlinedButton.icon(onPressed: cubit.checkCode, icon: const Icon(Icons.spellcheck), label: const Text('Check syntax')),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: s.codeDirty || !s.codeExists ? cubit.saveCode : null,
            icon: const Icon(Icons.check),
            label: Text(s.codeExists ? 'Save' : 'Create'),
          ),
          const SizedBox(width: 8),
          if (s.codeDirty && s.codeExists) TextButton(onPressed: cubit.discardCode, child: const Text('Discard')),
          const Spacer(),
          Flexible(child: Text(s.codePath ?? '', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant))),
        ]),
        Text('Saving checks the syntax first and keeps the previous version in scrapers/backups. A file that fails to load '
            'is skipped by the scraper (reported in the log), so a mistake can\'t stop a run.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

class _SettingsTab extends StatefulWidget {
  const _SettingsTab({required this.s});
  final ScrapersState s;

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  late final _ua = TextEditingController(text: widget.s.overview?.userAgent ?? '');
  late final _delay = TextEditingController(text: '${widget.s.overview?.politeness['delay_seconds'] ?? 2.0}');
  late final _budget = TextEditingController(text: '${widget.s.overview?.politeness['max_requests_per_run'] ?? 1500}');

  @override
  void dispose() {
    _ua.dispose();
    _delay.dispose();
    _budget.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(20), children: [
      Text('Being polite to the wiki', style: Theme.of(context).textTheme.titleMedium),
      Text('The scraper waits between requests, backs off when the wiki is busy, and stops on HTTP 403 to protect your IP.',
          style: TextStyle(color: cs.onSurfaceVariant)),
      const SizedBox(height: 12),
      TextField(controller: _ua, decoration: const InputDecoration(labelText: 'User agent (include a way to contact you)')),
      const SizedBox(height: 8),
      Row(children: [
        SizedBox(width: 220, child: TextField(controller: _delay, decoration: const InputDecoration(labelText: 'Seconds between requests (>= 0.5)'))),
        const SizedBox(width: 12),
        SizedBox(width: 220, child: TextField(controller: _budget, decoration: const InputDecoration(labelText: 'Requests per run'))),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        FilledButton.icon(
          onPressed: () => context.read<ScrapersCubit>().saveSettings(
            userAgent: _ua.text,
            delay: double.tryParse(_delay.text.trim()),
            maxRequests: int.tryParse(_budget.text.trim()),
          ),
          icon: const Icon(Icons.check),
          label: const Text('Save'),
        ),
      ]),
      const SizedBox(height: 16),
      Text('Progress and the full request log: ${widget.s.overview?.stateDir}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      Text('Settings file: ${widget.s.overview?.configPath}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
    ]);
  }
}

