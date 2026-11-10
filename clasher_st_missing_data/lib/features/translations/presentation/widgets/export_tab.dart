import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/services/system_open.dart';
import '../../../../core/settings/app_settings.dart';
import '../../domain/entities/translation_models.dart';
import '../cubits/translation_cubit.dart';
import '../cubits/translation_state.dart';
import 'common.dart';
import '../../../../core/theme/app_theme.dart';

/// The app's constants (TrTokens, default English, the language registry) generated into the export folder with
/// a diff against the project's files, and the language packs with the command to publish them.
class ExportTab extends StatefulWidget {
  const ExportTab({super.key});

  @override
  State<ExportTab> createState() => _ExportTabState();
}

class _ExportTabState extends State<ExportTab> {
  bool _strict = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cubit = context.read<TranslationCubit>();
    final pub = sl<AppSettings>().publishing;
    return BlocBuilder<TranslationCubit, TranslationState>(
      builder: (context, s) {
        final ex = s.export;
        final packs = s.packs;
        final project = s.summary?.project;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SectionTitle(
              'App constants',
              trailing: Text(
                s.active?.exportDir ?? '',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ),
            Text(
              project == null
                  ? 'Add the Flutter project to this app to export its constants.'
                  : 'Writes ${project.className}, the default English and the language registry to the export folder: '
                        'your files exactly as they are, plus what\'s listed below (added at the end of their section). '
                        'Nothing is removed or reordered.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            if (s.addToApp.isEmpty && s.updateEnglish.isEmpty)
              Text(
                'Nothing pending: the export only adds languages the registry lacks.',
                style: TextStyle(color: cs.onSurfaceVariant),
              )
            else ...[
              for (final e in s.addToApp.entries)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.add_circle_outline),
                  title: Text(
                    '${e.key}  ->  ${project?.className ?? 'TrTokens'}.${tokenNameFor(e.key)}',
                  ),
                  subtitle: Text('new constant, section ${e.value}'),
                  trailing: IconButton(
                    tooltip: 'Don\'t add',
                    icon: const Icon(Icons.close),
                    onPressed: () => cubit.unmarkForApp(e.key),
                  ),
                ),
              for (final k in s.updateEnglish)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.edit_note),
                  title: Text(k),
                  subtitle: const Text(
                    'the app\'s English becomes the sheet\'s',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => cubit.toggleEnglishUpdate(k),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: project != null && s.busy == null
                      ? cubit.exportDart
                      : null,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Export to the export folder'),
                ),
                if (ex != null && s.active?.writeIntoProject == true)
                  OutlinedButton.icon(
                    onPressed: s.busy == null
                        ? () => _confirmApply(context, ex)
                        : null,
                    icon: const Icon(Icons.drive_file_move_outline),
                    label: const Text('Copy into the project ...'),
                  ),
                if (ex != null)
                  TextButton.icon(
                    onPressed: () => openInSystem(ex.out),
                    icon: const Icon(Icons.folder_open_outlined),
                    label: const Text('Open folder'),
                  ),
              ],
            ),
            if (ex != null) ...[
              for (final p in ex.problems)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('!  $p', style: TextStyle(color: cs.error)),
                ),
              for (final f in ex.files) _ExportFileCard(f: f),
              if (s.active?.writeIntoProject != true)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'The project wasn\'t changed. Copy these files into it yourself, or turn on "Offer to copy generated '
                    'constants into the project" in this app\'s settings (pencil icon at the top).',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
            ],
            const Divider(height: 40),
            SectionTitle(
              'Language packs',
              trailing: Text(
                pub.translationsRepoSlug,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ),
            Text(
              'One lang_<code>.zip per published language, holding translations.json with every non-empty translation. '
              'English isn\'t packed (it ships in the app). The same sheet always gives the same zip, so only changed '
              'packs need uploading.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _strict,
              onChanged: (v) => setState(() => _strict = v),
              title: const Text(
                'Strict: don\'t write a pack with broken placeholders or %s',
              ),
              subtitle: const Text(
                'Off: such packs are written and the problems listed (the app shows those keys oddly).',
              ),
            ),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: s.summary?.sheet != null && s.busy == null
                      ? () => cubit.buildPacks(strict: _strict)
                      : null,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Build packs'),
                ),
                const SizedBox(width: 8),
                if (s.dirty)
                  Text(
                    'The sheet has unsaved changes - packs use them; save the sheet too.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.orange.shade800,
                    ),
                  ),
              ],
            ),
            if (packs != null) ...[
              const SizedBox(height: 12),
              Table(
                columnWidths: const {
                  0: FlexColumnWidth(2),
                  1: FixedColumnWidth(90),
                  2: FixedColumnWidth(90),
                  3: FixedColumnWidth(110),
                  4: FlexColumnWidth(2),
                },
                children: [
                  const TableRow(
                    children: [
                      Text(
                        'Pack',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Keys',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Size',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Since last build',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Problems',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  for (final p in packs.packs)
                    TableRow(
                      children: [
                        Text('${p.file}  (${p.column})'),
                        Text('${p.keys}'),
                        Text('${(p.bytes / 1024).toStringAsFixed(1)} KB'),
                        Text(
                          p.changed ? 'changed' : 'same',
                          style: TextStyle(
                            color: p.changed ? cs.primary : cs.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          p.errors == 0
                              ? '-'
                              : '${p.errors} key(s): see Issues',
                          style: TextStyle(
                            color: p.errors == 0 ? null : cs.error,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              for (final sk in packs.skipped)
                Text(
                  'Skipped ${sk.column}${sk.code != null ? ' (${sk.code})' : ''}: ${sk.reason}',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              const SizedBox(height: 12),
              const Text('Publish the changed packs (from the export folder):'),
              _Command(
                text:
                    'gh release upload ${pub.translationsTag} '
                    '${packs.packs.where((p) => p.changed).map((p) => p.file).join(' ').ifEmpty('lang_*.zip')} '
                    '--clobber -R ${pub.translationsRepoSlug}',
              ),
              Text(
                'Repo and tag come from Settings -> Publishing. app_language_constants.dart in the export folder is the '
                'registry for your next app build.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              TextButton.icon(
                onPressed: () => openInSystem(packs.out),
                icon: const Icon(Icons.folder_open_outlined),
                label: const Text('Open folder'),
              ),
            ],
          ],
        );
      },
    );
  }

  Future<void> _confirmApply(BuildContext context, ExportResult ex) async {
    final cubit = context.read<TranslationCubit>();
    final changing = ex.files.where((f) => !f.identical).toList();
    if (changing.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('The project already has these files.')),
      );
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Copy into the project?'),
        content: Text(
          'These files in the project are replaced by the exported ones:\n\n'
          '${changing.map((f) => '•  ${f.relative} (${f.created ? 'new' : '+${f.added} lines${f.updated > 0 ? ', ${f.updated} English updated' : ''}'})').join('\n')}'
          '\n\nEach is backed up first (export folder / project-backups). No other file is touched.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Copy'),
          ),
        ],
      ),
    );
    if (ok == true) await cubit.applyExport();
  }
}

extension on String {
  String ifEmpty(String other) => trim().isEmpty ? other : this;
}

class _Command extends StatelessWidget {
  const _Command({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(
              text,
              style: const TextStyle(fontFamily: monoFamily, fontFamilyFallback: monoFallback, fontSize: 13),
            ),
          ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy, size: 18),
            onPressed: () => Clipboard.setData(ClipboardData(text: text)),
          ),
        ],
      ),
    );
  }
}

class _ExportFileCard extends StatelessWidget {
  const _ExportFileCard({required this.f});
  final ExportFile f;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lines = f.diff.split('\n');
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: ExpansionTile(
        title: Text(f.relative),
        subtitle: Text(
          f.identical
              ? 'same as the project\'s'
              : f.created
              ? 'new file (the project has none)'
              : '+${f.added} added${f.updated > 0 ? ', ${f.updated} English updated' : ''}',
        ),
        children: [
          if (!f.identical)
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 360),
              color: cs.surfaceContainerLowest,
              padding: const EdgeInsets.all(8),
              child: SingleChildScrollView(
                child: SelectableText.rich(
                  TextSpan(
                    children: [
                      for (final l in lines)
                        TextSpan(
                          text: '$l\n',
                          style: TextStyle(
                            fontFamily: monoFamily, fontFamilyFallback: monoFallback,
                            fontSize: 12,
                            color: l.startsWith('+') && !l.startsWith('+++')
                                ? Colors.green.shade700
                                : l.startsWith('-') && !l.startsWith('---')
                                ? cs.error
                                : l.startsWith('@@')
                                ? cs.primary
                                : null,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    f.exportPath,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
