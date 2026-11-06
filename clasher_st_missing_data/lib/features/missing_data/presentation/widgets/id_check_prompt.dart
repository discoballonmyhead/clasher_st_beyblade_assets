import 'package:flutter/material.dart';

import '../../domain/entities/row_lifecycle.dart';

enum IdChoice { renumber, notNow }

/// "Ids aren't serial": shift them to 1..N, or not now (asked again once the tab's ids change).
Future<IdChoice> askAboutIds(BuildContext context, IdIssue i) async {
  final cs = Theme.of(context).colorScheme;
  final what = [
    if (i.gapCount > 0)
      'missing ${i.gapCount} id(s): ${i.gaps.take(8).join(', ')}${i.gaps.length > 8 ? ' ...' : ''}',
    if (i.duplicates.isNotEmpty)
      'duplicated: ${i.duplicates.take(8).join(', ')}',
  ].join('; ');
  final choice = await showDialog<IdChoice>(
    context: context,
    barrierDismissible: false,
    builder: (c) => AlertDialog(
      title: const Text("Ids aren't serial"),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${i.sheet}: ${i.rows} rows, ids up to ${i.max} ($what).'),
            const SizedBox(height: 12),
            Text(
              'Shift them to 1..${i.rows}? Their order stays the same. Parent ids, ProductContents and TCG card '
              'links are updated too (in the other workbooks when you save). Links to deleted rows are cleared.',
            ),
            if (i.released > 0) ...[
              const SizedBox(height: 12),
              Text(
                '${i.released} of the ids that would change are already in data/ (released to the app): saved builds '
                'and collections there would point at other parts.',
                style: TextStyle(color: cs.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, IdChoice.notNow),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, IdChoice.renumber),
          child: const Text('Shift ids'),
        ),
      ],
    ),
  );
  return choice ?? IdChoice.notNow;
}
