import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/service_locator.dart';
import '../../missing_data/domain/entities/workbook.dart';
import '../../missing_data/presentation/cubits/workbook/workbook_cubit.dart';
import '../domain/submission.dart';
import 'submissions_cubit.dart';

/// Pictures and typed-in values sent from the app (Settings -> Help complete the catalog), waiting for review.
Future<void> showSubmissionsDialog(BuildContext context) {
  final sheets = context.read<WorkbookCubit>().state.summary?.sheets ?? const <SheetInfo>[];
  return showDialog<void>(
    context: context,
    builder: (_) => BlocProvider(
      create: (_) => sl<SubmissionsCubit>()..load(),
      child: _SubmissionsDialog(sheets: sheets),
    ),
  );
}

class _SubmissionsDialog extends StatelessWidget {
  const _SubmissionsDialog({required this.sheets});
  final List<SheetInfo> sheets;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocConsumer<SubmissionsCubit, SubmissionsState>(
      listenWhen: (a, b) => (b.error != null && a.error != b.error) || (b.message != null && a.message != b.message),
      listener: (context, s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(s.error ?? s.message!),
        backgroundColor: s.error != null ? cs.error : null,
        duration: const Duration(seconds: 6),
      )),
      builder: (context, s) {
        final cubit = context.read<SubmissionsCubit>();
        return AlertDialog(
          title: Row(children: [
            Expanded(child: Text(s.loading ? 'Submissions' : 'Submissions (${s.items.length} new)')),
            IconButton(tooltip: 'Reload', onPressed: s.loading ? null : cubit.load, icon: const Icon(Icons.refresh)),
          ]),
          content: SizedBox(
            width: 760,
            height: 560,
            child: !s.configured
                ? const Center(
                    child: Text('Set the submissions web app URL and admin key in Settings -> Publishing.\n'
                        'How to set up the sheet and the script: submissions/README.md',
                        textAlign: TextAlign.center))
                : s.loading
                    ? const Center(child: CircularProgressIndicator())
                    : s.items.isEmpty
                        ? const Center(child: Text('Nothing new.'))
                        : ListView(children: [
                            for (final sub in s.items) _SubmissionCard(sub: sub, state: s, sheets: sheets),
                          ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        );
      },
    );
  }
}

class _SubmissionCard extends StatelessWidget {
  const _SubmissionCard({required this.sub, required this.state, required this.sheets});
  final Submission sub;
  final SubmissionsState state;
  final List<SheetInfo> sheets;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final cubit = context.read<SubmissionsCubit>();
    final img = state.images[sub.id];
    final tab = SubmissionsCubit.tabFor(sub, sheets);
    final busy = state.busy.contains(sub.id);
    final what = sub.isOther
        ? 'Something else'
        : '${sub.targetName.isEmpty ? sub.targetType : sub.targetName}  (${sub.targetType} #${sub.targetId})';
    return Card(
      key: ValueKey('submission-${sub.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              border: Border.all(color: cs.outlineVariant),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: sub.isValue
                ? Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.edit_note, color: cs.primary),
                      Text(sub.field, style: tt.labelSmall, textAlign: TextAlign.center, maxLines: 2),
                    ]),
                  )
                : img == null
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Image.memory(img,
                        fit: BoxFit.contain, errorBuilder: (_, _, _) => const Icon(Icons.broken_image)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(what, style: tt.titleSmall),
              if (sub.isValue)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: SelectableText.rich(
                    key: ValueKey('value-${sub.id}'),
                    TextSpan(children: [
                      TextSpan(text: '${sub.field} = ', style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                      TextSpan(text: sub.value, style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              Text(
                [
                  if (sub.isValue)
                    'value'
                  else if (sub.kind == 'fullBodyImage')
                    'full-body picture'
                  else if (!sub.isOther)
                    'picture',
                  'from ${sub.username}',
                  if (sub.credit.isNotEmpty && sub.credit != sub.username) 'credit "${sub.credit}"',
                  if (sub.submittedAt != null) sub.submittedAt!.toLocal().toString().substring(0, 16),
                ].join(' · '),
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              if (sub.note.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(sub.note, style: tt.bodySmall),
              ],
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (sub.isOther)
                  OutlinedButton(
                    onPressed: busy ? null : () => cubit.markApplied(sub),
                    child: const Text('Mark done'),
                  )
                else
                  Tooltip(
                    message: tab == null
                        ? 'Open the workbook that has the ${sub.targetType} tab'
                        : sub.isValue
                            ? 'Set ${sub.field} on ${tab.name} #${sub.targetId} and add the credit'
                            : 'Put it on ${tab.name} #${sub.targetId} and add the credit',
                    child: FilledButton.icon(
                      key: ValueKey('apply-${sub.id}'),
                      onPressed: busy || tab == null || (img == null && !sub.isValue) ? null : () => cubit.apply(sub, sheets),
                      icon: busy
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.check, size: 18),
                      label: Text(tab == null ? 'Apply (open its workbook)' : 'Apply'),
                    ),
                  ),
                TextButton(
                  key: ValueKey('reject-${sub.id}'),
                  style: TextButton.styleFrom(foregroundColor: cs.error),
                  onPressed: busy ? null : () => cubit.reject(sub),
                  child: const Text('Reject'),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}
