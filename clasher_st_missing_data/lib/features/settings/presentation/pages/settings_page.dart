import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/services/file_picker_service.dart';
import '../../../../core/settings/app_settings.dart';
import '../cubit/settings_cubit.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: BlocConsumer<SettingsCubit, SettingsState>(
        listenWhen: (a, b) => b.message != null && a.message != b.message,
        listener: (context, s) =>
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(s.message!))),
        builder: (context, s) {
          final cubit = context.read<SettingsCubit>();
          final p = s.publishing;
          final saved = sl<AppSettings>().publishing;
          Widget field(
            String label,
            String value,
            PublishingConstants Function(PublishingConstants, String) set, {
            String? hint,
            String? help,
          }) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextFormField(
              initialValue: value,
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                helperText: help,
              ),
              onChanged: (v) => cubit.editPublishing((x) => set(x, v)),
            ),
          );
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text('Engine', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'The Studio runs Python scripts from the clasher_st_beyblade_assets folder in the background: '
                    'missing_data_tool.py for the data, translation_tool.py for translations (Python 3 with openpyxl, '
                    'pillow, requests, mwparserfromhell).',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    initialValue: s.python,
                    decoration: const InputDecoration(
                      labelText: 'Python executable',
                      hintText: 'python3 or C:\\Python312\\python.exe',
                    ),
                    onChanged: cubit.setPython,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: s.toolsDir,
                    decoration: const InputDecoration(
                      labelText: 'Tools folder (contains missing_data_tool.py)',
                    ),
                    onChanged: cubit.setToolsDir,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed: s.testing ? null : cubit.saveAndTest,
                        icon: s.testing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.play_arrow),
                        label: const Text('Save and test'),
                      ),
                    ],
                  ),
                  if (s.result != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      color: s.ok == true
                          ? cs.primaryContainer
                          : cs.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(s.result!),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  Text(
                    'Publishing',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Names that stay the same from release to release. The Studio fills them into release commands, CDN '
                    'links and checks.',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  field(
                    'GitHub owner',
                    p.owner,
                    (x, v) => x.copyWith(owner: v.trim()),
                  ),
                  field(
                    'Data repo',
                    p.dataRepo,
                    (x, v) => x.copyWith(dataRepo: v.trim()),
                    help: 'Images are served from ${p.cdnImagesBase}',
                  ),
                  field(
                    'Data branch',
                    p.dataBranch,
                    (x, v) => x.copyWith(dataBranch: v.trim()),
                  ),
                  field(
                    'Catalog release tag format',
                    p.catalogTagFormat,
                    (x, v) => x.copyWith(catalogTagFormat: v.trim()),
                    help:
                        'Today: ${p.catalogTag(DateTime.now())}  (yyyy, MM, dd are replaced)',
                  ),
                  field(
                    'Image packs release tag',
                    p.imagePacksTag,
                    (x, v) => x.copyWith(imagePacksTag: v.trim()),
                    help: 'AppEnv.githubReleaseTag in the app',
                  ),
                  field(
                    'Translations repo',
                    p.translationsRepo,
                    (x, v) => x.copyWith(translationsRepo: v.trim()),
                  ),
                  field(
                    'Translations release tag',
                    p.translationsTag,
                    (x, v) => x.copyWith(translationsTag: v.trim()),
                    help:
                        'Language packs go to ${p.translationsRepoSlug} @ ${p.translationsTag}',
                  ),
                  Row(
                    children: [
                      FilledButton.icon(
                        onPressed:
                            p.toJson().toString() == saved.toJson().toString()
                            ? null
                            : cubit.savePublishing,
                        icon: const Icon(Icons.check),
                        label: const Text('Save publishing settings'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  Text('Backup', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text(
                    'Settings live with your user account on this computer. Export them to a file to keep a copy or move '
                    'them to another computer (paths, apps, publishing names, recent workbooks).',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final folder = await sl<FilePickerService>()
                              .pickFolder(title: 'Save the settings file in');
                          if (folder != null) await cubit.exportTo(folder);
                        },
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Export settings ...'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final file = await sl<FilePickerService>().pickFile(
                            extensions: const ['json'],
                            title: 'Settings file',
                          );
                          if (file != null) await cubit.importFrom(file);
                        },
                        icon: const Icon(Icons.download),
                        label: const Text('Import settings ...'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
