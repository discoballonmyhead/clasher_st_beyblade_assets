import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/services/system_open.dart';
import '../../../translations/presentation/cubits/translation_cubit.dart';
import '../../../translations/presentation/cubits/translation_state.dart';
import '../cubits/translations_release_cubit.dart';
import 'job_log.dart';

/// Language packs -> the translations repo's release. Packs come from the Translations section's sheet; this tab
/// builds them (if needed) and uploads the changed ones.
class TranslationsReleaseTab extends StatefulWidget {
  const TranslationsReleaseTab({super.key});

  @override
  State<TranslationsReleaseTab> createState() => _TranslationsReleaseTabState();
}

class _TranslationsReleaseTabState extends State<TranslationsReleaseTab> {
  bool _onlyChanged = true;
  bool _strict = true;

  @override
  void initState() {
    super.initState();
    context.read<TranslationCubit>().ensureStarted();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rel = context.read<TranslationsReleaseCubit>();
    return BlocBuilder<TranslationCubit, TranslationState>(
      builder: (context, tr) => BlocConsumer<TranslationsReleaseCubit, TranslationsReleaseState>(
        listenWhen: (a, b) => b.error != null && a.error != b.error,
        listener: (context, s) => ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.error!), backgroundColor: cs.error, duration: const Duration(seconds: 8)),
        ),
        builder: (context, s) {
          final pub = rel.pub;
          final packs = tr.packs;
          final done = s.uploadedOf(packs);
          final files = packs == null
              ? <String>[]
              : [for (final f in TranslationsReleaseCubit.packFiles(packs, onlyChanged: _onlyChanged)) if (!done.contains(f)) f];
          final withProblems = packs == null
              ? 0
              : packs.packs.where((p) => p.errors > 0 && files.contains('${packs.out}/${p.file}')).length;
          return Column(children: [
            Expanded(
              child: ListView(padding: const EdgeInsets.all(20), children: [
                Text(
                  'Publishes language packs to ${pub.translationsRepoSlug}, release "${pub.translationsTag}" '
                  '(${s.releaseExists == null ? 'checking ...' : s.releaseExists! ? 'exists' : 'created on the first upload'}). '
                  'The app lists the lang_*.zip files on that release, so a language is live as soon as it\'s up.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                if (tr.projects.isEmpty)
                  const Text('Add an app in the Translations section first.')
                else
                  Row(children: [
                    const Text('App: '),
                    DropdownButton<String>(
                      value: tr.active?.id,
                      onChanged: tr.busy == null ? (id) => id == null ? null : context.read<TranslationCubit>().select(id) : null,
                      items: [for (final p in tr.projects) DropdownMenuItem(value: p.id, child: Text(p.name))],
                    ),
                    const SizedBox(width: 12),
                    if (tr.summary?.sheet != null) Text(tr.summary!.sheet!.fileName, style: TextStyle(color: cs.onSurfaceVariant)),
                  ]),
                if (tr.dirty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('The sheet has unsaved changes: save it in Translations so the sheet and the packs match.',
                        style: TextStyle(color: Colors.orange.shade800)),
                  ),
                const SizedBox(height: 12),
                Row(children: [
                  FilledButton.tonalIcon(
                    onPressed: tr.summary?.sheet == null || tr.busy != null
                        ? null
                        : () => context.read<TranslationCubit>().buildPacks(strict: _strict),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: Text(packs == null ? 'Build packs' : 'Build again'),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: const Text('Strict (skip packs with broken placeholders)'),
                    selected: _strict,
                    onSelected: (v) => setState(() => _strict = v),
                  ),
                ]),
                if (packs != null) ...[
                  const SizedBox(height: 12),
                  for (final p in packs.packs)
                    ListTile(
                      dense: true,
                      leading: done.contains('${packs.out}/${p.file}')
                          ? Icon(Icons.cloud_done_outlined, color: cs.primary)
                          : Icon(p.changed ? Icons.fiber_new_outlined : Icons.check, color: p.changed ? cs.primary : cs.outline),
                      title: Text('${p.file}  (${p.column})'),
                      subtitle: Text('${p.keys} keys, ${(p.bytes / 1024).toStringAsFixed(1)} KB - '
                          '${done.contains('${packs.out}/${p.file}') ? 'uploaded' : p.changed ? 'changed since the last build' : 'same as last build'}'
                          '${p.errors > 0 ? ' - ${p.errors} key(s) with problems' : ''}'),
                    ),
                  for (final sk in packs.skipped)
                    Text('Skipped ${sk.column}: ${sk.reason}', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _onlyChanged,
                    onChanged: (v) => setState(() => _onlyChanged = v),
                    title: const Text('Only the packs that changed'),
                  ),
                  Row(children: [
                    FilledButton.icon(
                      onPressed: s.uploading || files.isEmpty || !(s.tools?.canPublish ?? false)
                          ? null
                          : () async {
                              final ok = await confirmAction(
                                context,
                                title: 'Upload ${files.length} language pack(s)?',
                                action: 'Upload',
                                facts: [
                                  'Repository: ${pub.translationsRepoSlug} (as ${s.tools!.ghUser ?? 'you'})',
                                  'Release: ${pub.translationsTag}${s.releaseExists == true ? '' : ' (created now)'}',
                                  'Files: ${files.map((f) => f.split('/').last).join(', ')} - same names are replaced',
                                  if (withProblems > 0)
                                    '$withProblems pack(s) have keys with problems (broken placeholders) - turn on Strict and build again to leave them out.',
                                  'People get the new texts the next time the app checks.',
                                ],
                              );
                              if (ok) await rel.upload(files, from: packs);
                            },
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: Text(files.isEmpty
                          ? (done.isNotEmpty ? 'All uploaded' : 'Nothing changed to upload')
                          : 'Upload ${files.length} pack(s)'),
                    ),
                    TextButton.icon(onPressed: () => openInSystem(packs.out), icon: const Icon(Icons.folder_open_outlined), label: const Text('Open folder')),
                  ]),
                  if (s.tools != null && !s.tools!.canPublish)
                    Text(!s.tools!.gh ? 'Install the GitHub CLI (gh) to upload: cli.github.com' : 'Sign gh in once: "gh auth login" in a terminal',
                        style: TextStyle(color: cs.error)),
                  if (s.published != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Uploaded. The release has ${s.published!.assets.length} file(s).', style: TextStyle(color: cs.primary)),
                    ),
                  const SizedBox(height: 8),
                  Text(
                    'New languages also need app_language_constants.dart (in ${packs.out}) in the app\'s next build, so the picker '
                    'shows their name and flag.',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: JobLog(lines: s.log, running: s.uploading, height: 160),
            ),
          ]);
        },
      ),
    );
  }
}
