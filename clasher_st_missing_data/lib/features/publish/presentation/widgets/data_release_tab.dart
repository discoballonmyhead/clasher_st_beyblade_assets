import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/services/system_open.dart';
import '../../../../core/settings/app_settings.dart';
import '../../../studio/domain/entities/studio_models.dart';
import '../cubits/data_release_cubit.dart';
import 'job_log.dart';
import '../../../../core/theme/app_theme.dart';

/// Package -> commit + push data/ -> build release files -> create the GitHub release, then the values for the
/// Supabase manifest. Each step can be run on its own; each says what it needs.
class DataReleaseTab extends StatefulWidget {
  const DataReleaseTab({super.key});

  @override
  State<DataReleaseTab> createState() => _DataReleaseTabState();
}

class _DataReleaseTabState extends State<DataReleaseTab> {
  late final _message = TextEditingController(text: 'Data update ${_today()}');
  late final _tag = TextEditingController(text: sl<AppSettings>().publishing.catalogTag(DateTime.now()));
  final _assets = TextEditingController();
  final _gitName = TextEditingController();
  final _gitEmail = TextEditingController();
  String? _identityError;
  bool _push = true;
  bool _dropInvalid = false;
  bool _latest = true;

  static String _today() => DateTime.now().toIso8601String().substring(0, 10);

  @override
  void dispose() {
    _message.dispose();
    _tag.dispose();
    _assets.dispose();
    _gitName.dispose();
    _gitEmail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cubit = context.read<DataReleaseCubit>();
    return BlocConsumer<DataReleaseCubit, DataReleaseState>(
      listenWhen: (a, b) => b.error != null && a.error != b.error,
      listener: (context, s) => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.error!), backgroundColor: cs.error, duration: const Duration(seconds: 8)),
      ),
      builder: (context, s) {
        final pub = cubit.pub;
        final tools = s.tools;
        final pr = s.packageResult;
        return Column(children: [
          Expanded(
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Text(
                'Releases the catalog from ${pub.dataRepoSlug} (branch ${pub.dataBranch}). Repo, branch and tag format '
                'are in Settings -> Publishing.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
              if (tools != null && (!tools.git || !tools.canPublish))
                _Warn(
                  !tools.git
                      ? 'git isn\'t installed - steps 2 and 4 need it (git-scm.com).'
                      : !tools.gh
                          ? 'The GitHub CLI (gh) isn\'t installed - step 4 needs it: cli.github.com, then "gh auth login".'
                          : 'gh isn\'t signed in - run "gh auth login" once in a terminal, then reload.',
                ),
              // 1
              _Step(
                n: 1,
                title: 'Package the workbooks into data/',
                status: s.package,
                subtitle: pr == null
                    ? 'JSON per sheet + WebP images, checked against what the app accepts'
                    : pr.ok
                        ? 'Catalog check passed${pr.warningCount > 0 ? ' (${pr.warningCount} warnings)' : ''}'
                        : '${pr.errorCount} row(s) the app would reject - fix them in Data, or leave them out in step 3',
                children: [
                  for (final h in s.workspace?.hobbies ?? const <Hobby>[])
                    if (h.packaged)
                      for (final w in h.workbooks)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: s.books.contains(w.path),
                          onChanged: w.exists ? (_) => cubit.toggleBook(w.path) : null,
                          title: Text('${h.name}: ${w.file}'),
                          subtitle: Text(w.exists ? w.path : 'not found: ${w.path}'),
                        ),
                  Row(children: [
                    FilledButton.icon(
                      onPressed: s.busy || s.books.isEmpty ? null : cubit.package,
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('Package'),
                    ),
                    const SizedBox(width: 12),
                    Text('-> ${cubit.dataDir}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ]),
                  if (pr != null) ...[
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      for (final e in pr.rowsPerSheet.entries)
                        if (e.value > 0) Chip(label: Text('${e.key} ${e.value}')),
                    ]),
                    if (pr.rowsPerSheet.values.any((v) => v == 0))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Empty (written as []): ${[for (final e in pr.rowsPerSheet.entries) if (e.value == 0) e.key].join(', ')}',
                          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        ),
                      ),
                    for (final e in pr.errors.take(12))
                      Text('!  ${e.sheet}${e.id != null ? ' #${e.id}' : ''}: ${e.message}', style: TextStyle(color: cs.error, fontSize: 12)),
                    if (pr.errorCount > 12) Text('... and ${pr.errorCount - 12} more (in the log)', style: TextStyle(color: cs.error, fontSize: 12)),
                  ],
                ],
              ),
              // 2
              _Step(
                n: 2,
                title: 'Commit and push data/',
                status: s.commit,
                subtitle: s.git == null
                    ? 'Checking git ...'
                    : !s.git!.isRepo
                        ? 'The tools folder isn\'t a git repository'
                        : '${s.git!.changed} changed file(s) in data/ (${s.git!.changedImages} images) on ${s.git!.branch}'
                              '${(s.git!.ahead ?? 0) > 0 ? ' - ${s.git!.ahead} commit(s) not pushed yet' : ''}'
                              '${(s.git!.behind ?? 0) > 0 ? ' - ${s.git!.behind} commit(s) behind: pull first' : ''}',
                children: [
                  Text('Images are served from the CDN off ${pub.dataBranch}, so they must be pushed before the app gets the release.',
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  if (s.git != null && s.git!.isRepo && !s.git!.hasIdentity) ...[
                    const SizedBox(height: 8),
                    Text('git doesn\'t know who you are yet, so it can\'t commit. Saved for this repository only.',
                        style: TextStyle(color: cs.error)),
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(child: TextField(controller: _gitName, decoration: const InputDecoration(labelText: 'Your name', isDense: true))),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: _gitEmail, decoration: const InputDecoration(labelText: 'Email (e.g. your GitHub email)', isDense: true))),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () async {
                          final err = await cubit.setGitIdentity(_gitName.text, _gitEmail.text);
                          if (mounted) setState(() => _identityError = err);
                        },
                        child: const Text('Save'),
                      ),
                    ]),
                    if (_identityError != null) Text(_identityError!, style: TextStyle(color: cs.error, fontSize: 12)),
                  ],
                  const SizedBox(height: 12),
                  TextField(controller: _message, decoration: const InputDecoration(labelText: 'Commit message', isDense: true)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: _push,
                    onChanged: (v) => setState(() => _push = v),
                    title: const Text('Push to GitHub after committing'),
                  ),
                  Row(children: [
                    FilledButton.icon(
                      onPressed: s.busy ||
                              !(s.git?.isRepo ?? false) ||
                              !(tools?.git ?? false) ||
                              !s.git!.hasIdentity ||
                              (s.git!.changed == 0 && !(_push && (s.git!.ahead ?? 0) > 0))
                          ? null
                          : () async {
                              final g = s.git!;
                              final ok = await confirmAction(
                                context,
                                title: _push ? 'Commit and push data/?' : 'Commit data/?',
                                action: _push ? 'Commit and push' : 'Commit',
                                facts: [
                                  'Repository: ${cubit.repoDir}',
                                  'Branch: ${g.branch}${g.remote.isNotEmpty ? '  ->  ${g.remote}' : ''}',
                                  '${g.changed} changed file(s) under data/ (${g.changedImages} images); nothing else is staged',
                                  'Message: "${_message.text.trim()}"',
                                  if (_push) 'Pushing makes the images public on the CDN.',
                                ],
                              );
                              if (ok) await cubit.commitPush(_message.text.trim(), push: _push);
                            },
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: Text(_push ? 'Commit and push' : 'Commit'),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(onPressed: cubit.refreshGit, icon: const Icon(Icons.refresh), label: const Text('Check again')),
                    if (s.commitHead != null) Text('  committed ${s.commitHead}', style: TextStyle(color: cs.primary)),
                  ]),
                ],
              ),
              // 3
              _Step(
                n: 3,
                title: 'Build the release files',
                status: s.build,
                subtitle: s.release == null
                    ? 'catalog.zip, catalog_manifest.json, image and data packs, in _release/<tag>/'
                    : '${s.release!.files.length} file(s) in ${s.release!.folder}',
                children: [
                  Row(children: [
                    SizedBox(
                      width: 220,
                      child: TextField(controller: _tag, decoration: const InputDecoration(labelText: 'Release tag', isDense: true)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _assets,
                        decoration: const InputDecoration(
                          labelText: 'App assets folder (optional - only when you build a new app version)',
                          isDense: true,
                        ),
                      ),
                    ),
                  ]),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: _dropInvalid,
                    onChanged: (v) => setState(() => _dropInvalid = v),
                    title: const Text('Leave out rows the app can\'t read (instead of stopping)'),
                    subtitle: pr != null && !pr.ok ? Text('${pr.errorCount} row(s) would be left out this time') : null,
                  ),
                  Row(children: [
                    FilledButton.icon(
                      onPressed: s.busy
                          ? null
                          : () => cubit.buildRelease(_tag.text.trim(), dropInvalid: _dropInvalid, appAssets: _assets.text.trim()),
                      icon: const Icon(Icons.archive_outlined),
                      label: const Text('Build release files'),
                    ),
                    if (s.release != null)
                      TextButton.icon(
                        onPressed: () => openInSystem(s.release!.folder),
                        icon: const Icon(Icons.folder_open_outlined),
                        label: const Text('Open folder'),
                      ),
                  ]),
                  if (s.release != null)
                    for (final p in s.release!.packs)
                      Text('  ${p['file']}  ${((p['bytes'] as num? ?? 0) / 1024 / 1024).toStringAsFixed(2)} MB',
                          style: const TextStyle(fontFamily: monoFamily, fontFamilyFallback: monoFallback, fontSize: 12)),
                ],
              ),
              // 4
              _Step(
                n: 4,
                title: 'Create the GitHub release',
                status: s.publish,
                subtitle: s.published?.url ??
                    (s.release == null ? 'Build the release files first' : 'Uploads the ${s.release!.files.length} files to ${pub.dataRepoSlug} @ ${s.release!.tag}'),
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    value: _latest,
                    onChanged: (v) => setState(() => _latest = v),
                    title: const Text('Mark as the latest release'),
                  ),
                  Row(children: [
                    FilledButton.icon(
                      onPressed: s.busy || s.release == null || !(tools?.canPublish ?? false)
                          ? null
                          : () async {
                              final r = s.release!;
                              final ok = await confirmAction(
                                context,
                                title: 'Create release ${r.tag}?',
                                action: 'Create and upload',
                                facts: [
                                  'Repository: ${pub.dataRepoSlug} (as ${tools!.ghUser ?? 'you'})',
                                  'Tag: ${r.tag} - if it exists, its files with the same names are replaced',
                                  '${r.files.length} file(s): ${r.files.map((f) => f.split(RegExp(r'[\\/]')).last).join(', ')}',
                                  'Installed apps pick it up once the Supabase manifest points at it (below).',
                                ],
                              );
                              if (ok) await cubit.publish(title: 'Catalog ${r.tag}', latest: _latest);
                            },
                      icon: const Icon(Icons.rocket_launch_outlined),
                      label: const Text('Create release'),
                    ),
                    if (s.published?.url != null)
                      TextButton.icon(
                        onPressed: () => openInSystem(s.published!.url!),
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Open on GitHub'),
                      ),
                  ]),
                ],
              ),
              if (s.release != null) ...[
                const SizedBox(height: 12),
                Text('Supabase: make beyblade_catalog_manifest return', style: Theme.of(context).textTheme.titleSmall),
                _CopyBox(text: const JsonEncoder.withIndent('  ').convert(s.release!.manifest)),
                if (pub.imagePacksTag.isNotEmpty && pub.imagePacksTag != s.release!.tag)
                  Text(
                    'Image packs are on this release too. The app reads packs from ${pub.imagePacksTag} '
                    '(AppEnv.githubReleaseTag) - change that in the app (and in Settings) if you want it to use ${s.release!.tag}.',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
              ],
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: JobLog(lines: s.log, running: s.busy, onStop: cubit.stop, onClear: cubit.clearLog),
          ),
        ]);
      },
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.title, required this.status, required this.subtitle, required this.children});
  final int n;
  final String title;
  final StepStatus status;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (icon, color) = switch (status) {
      StepStatus.done => (Icons.check_circle, cs.primary),
      StepStatus.failed => (Icons.error, cs.error),
      StepStatus.running => (Icons.timelapse, cs.tertiary),
      StepStatus.idle => (Icons.radio_button_unchecked, cs.outline),
    };
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 10),
            Text('$n.  $title', style: Theme.of(context).textTheme.titleMedium),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: 34, top: 2, bottom: 6),
            child: Text(subtitle, style: TextStyle(color: status == StepStatus.failed ? cs.error : cs.onSurfaceVariant)),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 34),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
          ),
        ]),
      ),
    );
  }
}

class _Warn extends StatelessWidget {
  const _Warn(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      color: cs.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Icon(Icons.info_outline, color: cs.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: cs.onTertiaryContainer))),
        ]),
      ),
    );
  }
}

class _CopyBox extends StatelessWidget {
  const _CopyBox({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: SelectableText(text, style: const TextStyle(fontFamily: monoFamily, fontFamilyFallback: monoFallback, fontSize: 12))),
        IconButton(
          tooltip: 'Copy',
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () => Clipboard.setData(ClipboardData(text: text)),
        ),
      ]),
    );
  }
}
