import 'package:flutter/material.dart';

import '../../domain/entities/translation_models.dart';

/// Severity colour + icon, shared by the overview, issues and the key editor.
(IconData, Color) severityLook(BuildContext context, TrSeverity s) {
  final cs = Theme.of(context).colorScheme;
  return switch (s) {
    TrSeverity.error => (Icons.error_outline, cs.error),
    TrSeverity.warning => (Icons.warning_amber_rounded, Colors.orange.shade700),
    TrSeverity.info => (Icons.info_outline, cs.onSurfaceVariant),
  };
}

/// Plain-words names for the engine's issue kinds.
const issueKindLabels = {
  'missing_in_sheet': 'In the app, not in the sheet',
  'missing_in_app': 'In the sheet, not in the app',
  'english_mismatch': 'English differs (app / sheet)',
  'no_default_english': 'No default English',
  'default_without_token': 'Default English for a missing constant',
  'duplicate_default': 'Default English twice',
  'duplicate_token': 'Constant declared twice',
  'duplicate_key_value': 'Two constants, same key',
  'duplicate_key': 'Key twice in the sheet',
  'duplicate_code': 'Two columns, same language code',
  'bad_key': 'Key not lower_snake_case',
  'empty_english': 'No English in the sheet',
  'placeholder_missing': 'Placeholder missing',
  'placeholder_unknown': 'Unknown placeholder',
  'percent_mismatch': '%s count differs',
  'stray_brace': 'Stray { or }',
  'whitespace': 'Extra spaces',
  'untranslated': 'Untranslated',
  'unused_token': 'Constant unused in code',
  'language_unresolved': 'Column without a language code',
  'registry_missing': 'Language not in the registry',
  'registry_name': 'Registry name differs',
  'hardcoded': 'Written in the code',
  'no_tokens_file': 'No TrTokens file',
  'no_defaults_file': 'No default English file',
};

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = switch (status) {
      TrStatus.problem => (cs.errorContainer, cs.onErrorContainer),
      TrStatus.missingInSheet || TrStatus.englishMismatch => (
        cs.tertiaryContainer,
        cs.onTertiaryContainer,
      ),
      _ => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
    };
    return Container(
      margin: const EdgeInsets.only(right: 4, top: 2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        TrStatus.labels[status] ?? status,
        style: TextStyle(fontSize: 11, color: fg),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleMedium),
        ),
        ?trailing,
      ],
    ),
  );
}
