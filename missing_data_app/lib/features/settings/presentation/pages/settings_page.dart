import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../cubit/settings_cubit.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: BlocBuilder<SettingsCubit, SettingsState>(
        builder: (context, s) {
          final cubit = context.read<SettingsCubit>();
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: ListView(padding: const EdgeInsets.all(24), children: [
                Text('Engine', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'The app runs missing_data_tool.py from the clasher_st_beyblade_assets folder in the background '
                  '(Python 3 with openpyxl, pillow, requests, mwparserfromhell).',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: s.python,
                  decoration: const InputDecoration(labelText: 'Python executable', hintText: 'python3 or C:\\Python312\\python.exe'),
                  onChanged: cubit.setPython,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: s.toolsDir,
                  decoration: const InputDecoration(labelText: 'Tools folder (contains missing_data_tool.py)'),
                  onChanged: cubit.setToolsDir,
                ),
                const SizedBox(height: 16),
                Row(children: [
                  FilledButton.icon(
                    onPressed: s.testing ? null : cubit.saveAndTest,
                    icon: s.testing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.play_arrow),
                    label: const Text('Save and test'),
                  ),
                ]),
                if (s.result != null) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: s.ok == true ? cs.primaryContainer : cs.errorContainer,
                    child: Padding(padding: const EdgeInsets.all(12), child: SelectableText(s.result!)),
                  ),
                ],
              ]),
            ),
          );
        },
      ),
    );
  }
}
