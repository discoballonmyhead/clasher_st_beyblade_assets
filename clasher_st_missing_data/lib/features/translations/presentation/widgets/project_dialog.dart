import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/services/file_picker_service.dart';
import '../../domain/entities/translation_project.dart';
import '../cubits/translation_cubit.dart';

Future<void> showTranslationProjectDialog(
  BuildContext context, {
  TranslationProject? existing,
}) => showDialog<void>(
  context: context,
  builder: (_) => BlocProvider.value(
    value: context.read<TranslationCubit>(),
    child: _ProjectDialog(existing: existing),
  ),
);

/// Checks a project's paths -> problems (empty = fine). [exists] is overridable for tests.
List<String> validateTranslationProject(
  TranslationProject p, {
  bool Function(String path)? dirExists,
  bool Function(String path)? fileExists,
}) {
  final isDir = dirExists ?? (path) => Directory(path).existsSync();
  final isFile = fileExists ?? (path) => File(path).existsSync();
  final out = <String>[];
  String sep(String path) =>
      path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  if (p.name.trim().isEmpty) out.add('Give the app a name');
  if (p.projectDir.trim().isEmpty && p.sheetPath.trim().isEmpty) {
    out.add('Pick the Flutter project, the sheet, or both');
  }
  if (p.projectDir.trim().isNotEmpty && !isDir('${p.projectDir}/lib')) {
    out.add('The Flutter project folder has no lib/ - pick the project root');
  }
  if (p.sheetPath.trim().isNotEmpty) {
    if (!p.sheetPath.toLowerCase().endsWith('.xlsx')) {
      out.add('The sheet must be an .xlsx file');
    } else if (!isFile(p.sheetPath)) {
      out.add('The sheet doesn\'t exist');
    }
  }
  if (p.exportDir.trim().isEmpty) {
    out.add('Pick an export folder (generated files go there)');
  }
  if (p.projectDir.trim().isNotEmpty && p.exportDir.trim().isNotEmpty) {
    final lib = sep('${p.projectDir}/lib');
    final out0 = sep(p.exportDir);
    if (out0 == lib || out0.startsWith('$lib/') || out0 == sep(p.projectDir)) {
      out.add(
        'The export folder can\'t be the project or inside its lib/ - the project is never written by an '
        'export',
      );
    }
  }
  return out;
}

class _ProjectDialog extends StatefulWidget {
  const _ProjectDialog({this.existing});
  final TranslationProject? existing;

  @override
  State<_ProjectDialog> createState() => _ProjectDialogState();
}

class _ProjectDialogState extends State<_ProjectDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _project = TextEditingController(
    text: widget.existing?.projectDir ?? '',
  );
  late final _sheet = TextEditingController(
    text: widget.existing?.sheetPath ?? '',
  );
  late final _export = TextEditingController(
    text: widget.existing?.exportDir ?? '',
  );
  late final _tokens = TextEditingController(
    text: widget.existing?.tokensFile ?? '',
  );
  late final _defaults = TextEditingController(
    text: widget.existing?.defaultsFile ?? '',
  );
  late final _languages = TextEditingController(
    text: widget.existing?.languagesFile ?? '',
  );
  late bool _write = widget.existing?.writeIntoProject ?? false;
  bool _advanced = false;
  List<String> _problems = const [];

  @override
  void dispose() {
    for (final c in [
      _name,
      _project,
      _sheet,
      _export,
      _tokens,
      _defaults,
      _languages,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  TranslationProject get _value => TranslationProject(
    id: widget.existing?.id ?? TranslationCubit.newId(),
    name: _name.text.trim(),
    projectDir: _project.text.trim(),
    sheetPath: _sheet.text.trim(),
    exportDir: _export.text.trim(),
    tokensFile: _tokens.text.trim(),
    defaultsFile: _defaults.text.trim(),
    languagesFile: _languages.text.trim(),
    writeIntoProject: _write,
  );

  Future<void> _pickFolder(TextEditingController c, String title) async {
    final p = await sl<FilePickerService>().pickFolder(title: title);
    if (p == null) return;
    setState(() => c.text = p);
    if (c == _project) {
      if (_name.text.trim().isEmpty) {
        _name.text = p.split(RegExp(r'[\\/]')).where((x) => x.isNotEmpty).last;
      }
      if (_export.text.trim().isEmpty) {
        _export.text =
            '${Directory(p).parent.path}${Platform.pathSeparator}translations_export';
      }
    }
  }

  Future<void> _pickSheet() async {
    final p = await sl<FilePickerService>().pickWorkbook();
    if (p != null) setState(() => _sheet.text = p);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove ${widget.existing!.name}?'),
        content: const Text(
          'Only the Studio forgets it. The project, the sheet and the export folder stay as they are.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      final cubit = context.read<TranslationCubit>();
      Navigator.pop(context);
      await cubit.deleteProject(widget.existing!.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget path(
      TextEditingController c,
      String label,
      VoidCallback pick, {
      String? hint,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: c,
              decoration: InputDecoration(
                labelText: label,
                hintText: hint,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton(onPressed: pick, child: const Text('Browse')),
        ],
      ),
    );
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'Add an app'
            : 'Edit ${widget.existing!.name}',
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'clasher_st',
                ),
              ),
              const SizedBox(height: 10),
              path(
                _project,
                'Flutter project (the folder with lib/)',
                () => _pickFolder(_project, 'Flutter project'),
              ),
              path(_sheet, 'Translation sheet (.xlsx)', _pickSheet),
              path(
                _export,
                'Export folder (generated Dart, language packs)',
                () => _pickFolder(_export, 'Export folder'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _write,
                onChanged: (v) => setState(() => _write = v),
                title: const Text(
                  'Offer to copy generated constants into the project',
                ),
                subtitle: Text(
                  'Off: the project is never written; you copy the files from the export folder. On: after an export '
                  'you can copy the three constants files in (each backed up first, after you confirm). Your other '
                  'code is never touched either way.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ),
              TextButton.icon(
                onPressed: () => setState(() => _advanced = !_advanced),
                icon: Icon(_advanced ? Icons.expand_less : Icons.expand_more),
                label: const Text(
                  'Constants files (when they can\'t be found by their class names)',
                ),
              ),
              if (_advanced) ...[
                TextField(
                  controller: _tokens,
                  decoration: const InputDecoration(
                    labelText: 'TrTokens file',
                    hintText: 'lib/core/constants/trc_constant_tokens.dart',
                  ),
                ),
                TextField(
                  controller: _defaults,
                  decoration: const InputDecoration(
                    labelText: 'Default English file',
                    hintText: 'lib/core/constants/default_english_tr.dart',
                  ),
                ),
                TextField(
                  controller: _languages,
                  decoration: const InputDecoration(
                    labelText: 'Language registry file',
                    hintText: 'lib/core/constants/app_language_constants.dart',
                  ),
                ),
              ],
              for (final p in _problems)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('•  $p', style: TextStyle(color: cs.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            onPressed: _delete,
            style: TextButton.styleFrom(foregroundColor: cs.error),
            child: const Text('Remove'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            final v = _value;
            final problems = validateTranslationProject(v);
            setState(() => _problems = problems);
            if (problems.isNotEmpty) return;
            final cubit = context.read<TranslationCubit>();
            Navigator.pop(context);
            await cubit.saveProject(v);
          },
          child: Text(widget.existing == null ? 'Add and open' : 'Save'),
        ),
      ],
    );
  }
}
