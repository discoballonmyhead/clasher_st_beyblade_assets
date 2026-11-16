import 'package:clasher_st/features/contributions/domain/entities.dart';
import 'package:clasher_st/features/contributions/presentation/cubit/missing_cubits.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// One entry's missing fields and pictures, the credit and the consent; sends them to the submissions sheet.
class FillMissingPage extends StatelessWidget {
  const FillMissingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<FillMissingCubit, FillMissingState>(
      listenWhen: (a, b) => b.error != null && a.error != b.error,
      listener: (context, s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.error!))),
      builder: (context, s) {
        final cubit = context.read<FillMissingCubit>();
        return Scaffold(
          appBar: AppBar(title: Text(cubit.item.name, overflow: TextOverflow.ellipsis)),
          body: SafeArea(
            child: s.loading
                ? const Center(child: CircularProgressIndicator())
                : s.receipt != null
                    ? _Thanks(onDone: () => Navigator.of(context).maybePop())
                    : s.contributor == null
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text('Sign in to send what you know. You\'re credited in the app.',
                                  textAlign: TextAlign.center),
                            ),
                          )
                        : _Form(s: s, cubit: cubit),
          ),
        );
      },
    );
  }
}

class _Form extends StatelessWidget {
  const _Form({required this.s, required this.cubit});
  final FillMissingState s;
  final FillMissingCubit cubit;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final item = cubit.item;
    final details = cubit.detailFields;
    final pictures = cubit.pictureFields;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(
          [cubit.sheet?.label ?? item.sheet, if (item.code.isNotEmpty) item.code, if (item.variant != null) item.variant!]
              .join(' · '),
          style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
        Text('Sending as ${s.contributor!.username}', style: tt.labelMedium),
        const SizedBox(height: 16),
        if (details.isNotEmpty) ...[
          Text('Fill in what you know', style: tt.titleSmall),
          const SizedBox(height: 8),
          for (final f in details) _FieldInput(field: f, value: s.values[f.name] ?? '', cubit: cubit),
          const SizedBox(height: 8),
        ],
        if (pictures.isNotEmpty) ...[
          Text(pictures.length == 1 ? 'Missing: ${pictures.first.label.toLowerCase()}' : 'Missing pictures',
              style: tt.titleSmall),
          const SizedBox(height: 8),
          if (pictures.length > 1)
            SegmentedButton<String>(
              key: const ValueKey('fill-picture-field'),
              segments: [for (final p in pictures) ButtonSegment(value: p.name, label: Text(p.label))],
              selected: {s.pictureField ?? pictures.first.name},
              onSelectionChanged: (v) => cubit.setPictureField(v.first),
            ),
          if (s.picture != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(s.picture!.bytes, height: 200, width: double.infinity, fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox(height: 200, child: Icon(Icons.broken_image))),
                ),
                Positioned(
                  right: 4,
                  top: 4,
                  child: IconButton.filledTonal(
                      tooltip: 'Remove', onPressed: cubit.clearPicture, icon: const Icon(Icons.close)),
                ),
              ]),
            ),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
              key: const ValueKey('fill-gallery'),
              onPressed: () => cubit.pickPicture(),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(s.picture == null ? 'Choose a picture' : 'Choose another'),
            ),
            OutlinedButton.icon(
              onPressed: () => cubit.pickPicture(camera: true),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Take a photo'),
            ),
          ]),
          const SizedBox(height: 16),
        ],
        TextFormField(
          key: const ValueKey('fill-credit'),
          initialValue: s.credit,
          maxLength: 120,
          decoration: InputDecoration(
            labelText: 'Credit (optional)',
            helperText: 'How you\'re credited in the app. Empty: ${s.contributor!.username}.',
          ),
          onChanged: cubit.setCredit,
        ),
        TextFormField(
          key: const ValueKey('fill-note'),
          initialValue: s.note,
          maxLength: 500,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Source or note (optional)',
            helperText: 'Where it\'s from helps us check it (e.g. "weighed my own", a link).',
          ),
          onChanged: cubit.setNote,
        ),
        CheckboxListTile(
          key: const ValueKey('fill-consent'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: s.consent,
          onChanged: (v) => cubit.setConsent(v ?? false),
          title: const Text('This is correct to the best of my knowledge, any picture is mine to share, and it '
              'can be shown in the app.'),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          key: const ValueKey('fill-send'),
          onPressed: cubit.canSubmit ? cubit.send : null,
          icon: s.submitting
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send),
          label: Text(s.submitting ? 'Sending...' : 'Send'),
        ),
      ],
    );
  }
}

/// One missing field, with the input its type needs.
class _FieldInput extends StatelessWidget {
  const _FieldInput({required this.field, required this.value, required this.cubit});
  final WantedField field;
  final String value;
  final FillMissingCubit cubit;

  @override
  Widget build(BuildContext context) {
    final problem = field.check(value);
    final key = ValueKey('fill-field-${field.name}');
    final decoration = InputDecoration(
      labelText: field.label,
      helperText: field.hint,
      suffixText: field.unit,
      errorText: problem,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: switch (field.type) {
        WantedFieldType.choice => DropdownButtonFormField<String>(
            key: key,
            initialValue: field.choices.contains(value) ? value : null,
            decoration: decoration,
            items: [for (final c in field.choices) DropdownMenuItem(value: c, child: Text(c))],
            onChanged: (v) => cubit.setValue(field.name, v ?? ''),
          ),
        WantedFieldType.number => TextFormField(
            key: key,
            initialValue: value,
            decoration: decoration,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            onChanged: (v) => cubit.setValue(field.name, v),
          ),
        WantedFieldType.date => TextFormField(
            key: key,
            initialValue: value,
            decoration: decoration.copyWith(hintText: 'YYYY-MM-DD'),
            keyboardType: TextInputType.datetime,
            onChanged: (v) => cubit.setValue(field.name, v),
          ),
        _ => TextFormField(
            key: key,
            initialValue: value,
            decoration: decoration,
            maxLength: 300,
            onChanged: (v) => cubit.setValue(field.name, v),
          ),
      },
    );
  }
}

class _Thanks extends StatelessWidget {
  const _Thanks({required this.onDone});
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.favorite, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            Text('Thanks!', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 6),
            const Text('We\'ll check it and add it with your credit.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(key: const ValueKey('fill-done'), onPressed: onDone, child: const Text('Back to the list')),
          ]),
        ),
      );
}
