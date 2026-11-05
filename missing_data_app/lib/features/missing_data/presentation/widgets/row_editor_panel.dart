import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../cubits/row_editor/row_editor_cubit.dart';
import '../cubits/row_editor/row_editor_state.dart';
import '../../domain/entities/structure.dart';
import '../cubits/sheet/sheet_cubit.dart';
import 'new_row_dialog.dart';
import 'formatting.dart';

const _optional = {
  'parentPartId', 'variantLabel', 'updated_at', 'deleted', 'incompleteData', 'integratedRatchet', 'twoStat',
  'parentProductId', 'parentCardId', 'parentSetId', 'linkedPartType', 'linkedPartDataID', 'illustrator',
  'legality', 'description', 'subType',
};

/// The focused row: every field (missing ones highlighted), apply, next gap, and its image.
class RowEditorPanel extends StatelessWidget {
  const RowEditorPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<RowEditorCubit, RowEditorState>(
      builder: (context, s) {
        final d = s.detail;
        if (s.loading && d == null) return const Center(child: CircularProgressIndicator());
        if (d == null) {
          return const Center(child: Text('Click a row to edit it', textAlign: TextAlign.center));
        }
        final cs = Theme.of(context).colorScheme;
        final cubit = context.read<RowEditorCubit>();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Text('#${d.id}  ${d.display('name').isEmpty ? d.display('productName') : d.display('name')}',
                style: Theme.of(context).textTheme.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
            child: Text(
              'last edited ${formatWhen(d.updatedAt)}${d.parentId != null ? '  -  variant of #${d.parentId}' : ''}'
              '${d.missing.isEmpty ? '  -  complete' : '  -  ${d.missing.length} missing'}',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ),
          Expanded(
            child: ListView(padding: const EdgeInsets.symmetric(horizontal: 12), children: [
              _ImageBox(state: s),
              const SizedBox(height: 12),
              for (final f in d.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: TextFormField(
                    key: ValueKey('${d.id}-$f'),
                    initialValue: s.valueOf(f),
                    onChanged: (v) => cubit.edit(f, v),
                    onFieldSubmitted: (_) => cubit.apply(),
                    decoration: InputDecoration(
                      // + marks a column added with the tool (purple header in the workbook)
                      labelText: d.customFields.contains(f) ? '$f  +' : f,
                      filled: d.missing.contains(f),
                      fillColor: Theme.of(context).brightness == Brightness.light ? AppTheme.missing : cs.tertiaryContainer,
                      labelStyle: d.customFields.contains(f)
                          ? TextStyle(color: cs.tertiary)
                          : _optional.contains(f)
                              ? TextStyle(color: cs.outline)
                              : null,
                      suffixIcon: s.drafts.containsKey(f) ? Icon(Icons.edit, size: 16, color: cs.primary) : null,
                    ),
                  ),
                ),
            ]),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              FilledButton.icon(
                onPressed: s.hasDrafts && !s.saving ? cubit.apply : null,
                icon: const Icon(Icons.check),
                label: Text(s.hasDrafts ? 'Apply ${s.drafts.length}' : 'Apply'),
              ),
              if (s.hasDrafts) TextButton(onPressed: cubit.discard, child: const Text('Discard')),
              Tooltip(
                message: 'Next row with gaps (Ctrl+Enter)',
                child: OutlinedButton.icon(
                  onPressed: () => context.read<SheetCubit>().nextGap(),
                  icon: const Icon(Icons.skip_next),
                  label: const Text('Next gap'),
                ),
              ),
              Tooltip(
                message: 'New row with the shared fields of this one (type, spin, stats ...) and parent #${d.parentId ?? d.id}',
                child: TextButton.icon(
                  onPressed: () => _newFrom(context, s.sheet!, d.id, NewRowMode.variant),
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                  label: const Text('Duplicate as variant'),
                ),
              ),
              TextButton.icon(
                onPressed: () => _newFrom(context, s.sheet!, d.id, NewRowMode.copy),
                icon: const Icon(Icons.content_copy, size: 18),
                label: const Text('Copy row'),
              ),
            ]),
          ),
        ]);
      },
    );
  }
}

Future<void> _newFrom(BuildContext context, String sheet, String id, NewRowMode mode) async {
  final sheetCubit = context.read<SheetCubit>();
  final newId = await addRowWithPrompt(context, sheet, mode: mode, copyFrom: id);
  if (newId != null) sheetCubit.focus(newId);
}

class _ImageBox extends StatefulWidget {
  const _ImageBox({required this.state});

  final RowEditorState state;

  @override
  State<_ImageBox> createState() => _ImageBoxState();
}

class _ImageBoxState extends State<_ImageBox> {
  final _url = TextEditingController();

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Widget _pic(Uint8List? bytes, String label) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(children: [
        Text(label, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        const SizedBox(height: 4),
        Container(
          height: 120,
          decoration: BoxDecoration(
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(8),
            color: cs.surfaceContainerLowest,
          ),
          alignment: Alignment.center,
          child: bytes == null
              ? Icon(Icons.image_not_supported_outlined, color: cs.outline)
              : Padding(
                  padding: const EdgeInsets.all(4),
                  child: Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true,
                      errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined))),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final cubit = context.read<RowEditorCubit>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            _pic(s.detail?.image, 'current'),
            const SizedBox(width: 8),
            _pic(s.newImage, 'new'),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            OutlinedButton.icon(onPressed: cubit.pickImage, icon: const Icon(Icons.upload_file, size: 18), label: const Text('File')),
            OutlinedButton.icon(
                onPressed: s.detail?.parentId == null ? null : cubit.useParentImage,
                icon: const Icon(Icons.family_restroom, size: 18),
                label: const Text('Parent image')),
            if (s.newImage != null)
              FilledButton.icon(
                  onPressed: s.saving ? null : () => cubit.putImage(),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Put on row')),
            if (s.newImage != null) TextButton(onPressed: cubit.clearNewImage, child: const Text('Clear')),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: TextField(controller: _url, decoration: const InputDecoration(hintText: 'Image URL'))),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: 'Download and put on row',
              onPressed: () {
                final u = _url.text.trim();
                if (u.isNotEmpty) cubit.putImage(url: u);
              },
              icon: const Icon(Icons.download),
            ),
          ]),
          const SizedBox(height: 4),
          Text('Images are trimmed, fitted in 600 px + a 128 px copy, stored as WebP.',
              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ]),
      ),
    );
  }
}
