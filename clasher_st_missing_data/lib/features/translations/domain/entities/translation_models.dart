import 'package:equatable/equatable.dart';

/// A language column of the sheet and the code its pack is published under.
class TrLanguage extends Equatable {
  const TrLanguage({
    required this.column,
    this.code,
    this.name = '',
    this.country = '',
    this.how,
    this.status = 'active',
  });

  final String column;

  /// null when the column can't be resolved to a code (packs refuse to build).
  final String? code;
  final String name;
  final String country;

  /// How the code was found: Languages tab, languages.json, brackets, header is a code, known name.
  final String? how;

  /// active / deprecated (not packed; the app's registry rejects it) / unresolved.
  final String status;

  bool get deprecated => status == 'deprecated';

  TrLanguage copyWith({
    String? code,
    String? name,
    String? country,
    String? status,
  }) => TrLanguage(
    column: column,
    code: code ?? this.code,
    name: name ?? this.name,
    country: country ?? this.country,
    how: how,
    status: status ?? this.status,
  );

  Map<String, String> toRow() => {
    'column': column,
    'code': code ?? '',
    'name': name,
    'country': country,
    'status': status == 'unresolved' ? 'active' : status,
  };

  @override
  List<Object?> get props => [column, code, name, country, how, status];
}

class RegistryLanguage extends Equatable {
  const RegistryLanguage({
    required this.code,
    required this.name,
    required this.country,
  });
  final String code;
  final String name;
  final String country;
  @override
  List<Object?> get props => [code, name, country];
}

/// An Excel / LibreOffice lock file next to the sheet: it may be open elsewhere.
class LockInfo extends Equatable {
  const LockInfo({
    required this.file,
    this.user,
    this.machine,
    this.modified,
    this.stale = false,
  });
  final String file;
  final String? user;
  final String? machine;
  final String? modified;
  final bool stale;
  @override
  List<Object?> get props => [file, user, machine, modified, stale];
}

class TrProjectInfo extends Equatable {
  const TrProjectInfo({
    required this.root,
    this.tokensFile,
    this.defaultsFile,
    this.languagesFile,
    this.tokens = 0,
    this.sections = const [],
    this.className = 'TrTokens',
    this.registry,
    this.rejected = const [],
  });

  final String root;
  final String? tokensFile;
  final String? defaultsFile;
  final String? languagesFile;
  final int tokens;
  final List<String> sections;
  final String className;

  /// null when the project has no LanguageRegistry.
  final List<RegistryLanguage>? registry;
  final List<String> rejected;

  @override
  List<Object?> get props => [
    root,
    tokensFile,
    defaultsFile,
    languagesFile,
    tokens,
    sections,
    className,
    registry,
    rejected,
  ];
}

class TrSheetInfo extends Equatable {
  const TrSheetInfo({
    required this.path,
    this.tabs = const [],
    this.keys = 0,
    this.languages = const [],
    this.meta = const [],
    this.dirty = false,
    this.undo = 0,
    this.locks = const [],
    this.unsupported = const [],
    this.hasLanguagesTab = false,
    this.unsavedFromLastTime = 0,
  });

  final String path;
  final List<String> tabs;
  final int keys;
  final List<TrLanguage> languages;
  final List<String> meta;
  final bool dirty;
  final int undo;
  final List<LockInfo> locks;

  /// Parts of the workbook that can't be kept (charts, macros ...): saving is refused.
  final List<String> unsupported;
  final bool hasLanguagesTab;

  /// Edits left by a session that closed without saving.
  final int unsavedFromLastTime;

  String get fileName => path.split(RegExp(r'[\\/]')).last;

  @override
  List<Object?> get props => [
    path,
    tabs,
    keys,
    languages,
    meta,
    dirty,
    undo,
    locks,
    unsupported,
    hasLanguagesTab,
    unsavedFromLastTime,
  ];
}

class TrSummary extends Equatable {
  const TrSummary({this.project, this.sheet});
  final TrProjectInfo? project;
  final TrSheetInfo? sheet;
  @override
  List<Object?> get props => [project, sheet];
}

enum TrSeverity { error, warning, info }

class TrIssue extends Equatable {
  const TrIssue({
    required this.kind,
    required this.severity,
    required this.message,
    this.key,
    this.language,
    this.where,
  });

  final String kind;
  final TrSeverity severity;
  final String message;
  final String? key;
  final String? language;
  final String? where;

  @override
  List<Object?> get props => [kind, severity, message, key, language, where];
}

class TrCoverage extends Equatable {
  const TrCoverage({
    required this.language,
    required this.translated,
    required this.total,
    required this.percent,
    this.sameAsEnglish = 0,
  });

  final TrLanguage language;
  final int translated;
  final int total;
  final double percent;
  final int sameAsEnglish;

  @override
  List<Object?> get props => [
    language,
    translated,
    total,
    percent,
    sameAsEnglish,
  ];
}

class TrReport extends Equatable {
  const TrReport({
    this.issues = const [],
    this.coverage = const [],
    this.keysInApp = 0,
    this.keysInSheet = 0,
    this.keysInBoth = 0,
  });

  final List<TrIssue> issues;
  final List<TrCoverage> coverage;
  final int keysInApp;
  final int keysInSheet;
  final int keysInBoth;

  int count(TrSeverity s) => issues.where((i) => i.severity == s).length;

  @override
  List<Object?> get props => [
    issues,
    coverage,
    keysInApp,
    keysInSheet,
    keysInBoth,
  ];
}

/// What's wrong with one translation.
class TrProblem extends Equatable {
  const TrProblem({
    required this.language,
    required this.kind,
    required this.severity,
    required this.message,
  });
  final String language;
  final String kind;
  final TrSeverity severity;
  final String message;
  @override
  List<Object?> get props => [language, kind, severity, message];
}

/// Statuses a key can have in the keys table.
abstract final class TrStatus {
  static const missingInSheet = 'missing_in_sheet';
  static const missingInApp = 'missing_in_app';
  static const englishMismatch = 'english_mismatch';
  static const unused = 'unused';
  static const problem = 'problem';
  static const untranslated = 'untranslated';

  static const labels = {
    missingInSheet: 'Not in the sheet',
    missingInApp: 'Not in the app',
    englishMismatch: 'English differs',
    untranslated: 'Untranslated',
    problem: 'Problems',
    unused: 'Unused in code',
  };
}

class TrKeyRow extends Equatable {
  const TrKeyRow({
    required this.key,
    this.token,
    this.section,
    this.subsection,
    this.comment = '',
    this.appEnglish,
    this.sheetEnglish,
    this.where,
    this.translations = const {},
    this.missingLanguages = const [],
    this.status = const [],
    this.problems = const [],
    this.uses = 0,
  });

  final String key;

  /// TrTokens constant name, null when the app doesn't have the key.
  final String? token;
  final String? section;
  final String? subsection;
  final String comment;
  final String? appEnglish;

  /// null when the key isn't in the sheet.
  final String? sheetEnglish;
  final String? where;
  final Map<String, String> translations;
  final List<String> missingLanguages;
  final List<String> status;
  final List<TrProblem> problems;
  final int uses;

  bool get inSheet => sheetEnglish != null;
  bool get inApp => token != null;
  String get english => sheetEnglish ?? appEnglish ?? '';

  @override
  List<Object?> get props => [
    key,
    token,
    section,
    subsection,
    comment,
    appEnglish,
    sheetEnglish,
    where,
    translations,
    missingLanguages,
    status,
    problems,
    uses,
  ];
}

class TrKeysPage extends Equatable {
  const TrKeysPage({required this.total, required this.rows});
  final int total;
  final List<TrKeyRow> rows;
  @override
  List<Object?> get props => [total, rows];
}

/// A string written straight into the code, and the key it would get.
class HardcodedString extends Equatable {
  const HardcodedString({
    required this.file,
    required this.line,
    required this.text,
    required this.key,
    this.col = 0,
    this.context = '',
    this.confidence = 'high',
    this.placeholders = const [],
    this.existingKey,
    this.snippet = '',
  });

  final String file;
  final int line;
  final int col;
  final String text;

  /// Suggested (or existing) key.
  final String key;
  final String context;

  /// high (Text(...), hintText: ...) or maybe.
  final String confidence;
  final List<String> placeholders;

  /// Set when the sheet / app already has this exact English: only the code needs changing.
  final String? existingKey;
  final String snippet;

  String get location => '$file:$line';

  @override
  List<Object?> get props => [
    file,
    line,
    col,
    text,
    key,
    context,
    confidence,
    placeholders,
    existingKey,
    snippet,
  ];
}

class ExportFile extends Equatable {
  const ExportFile({
    required this.kind,
    required this.relative,
    required this.projectPath,
    required this.exportPath,
    this.created = false,
    this.added = 0,
    this.updated = 0,
    this.identical = false,
    this.diff = '',
  });

  /// tokens / defaults / languages
  final String kind;
  final String relative;
  final String projectPath;
  final String exportPath;
  final bool created;
  final int added;
  final int updated;
  final bool identical;
  final String diff;

  @override
  List<Object?> get props => [
    kind,
    relative,
    projectPath,
    exportPath,
    created,
    added,
    updated,
    identical,
    diff,
  ];
}

class ExportResult extends Equatable {
  const ExportResult({
    required this.files,
    required this.out,
    this.problems = const [],
  });
  final List<ExportFile> files;
  final String out;
  final List<String> problems;
  @override
  List<Object?> get props => [files, out, problems];
}

class PackInfo extends Equatable {
  const PackInfo({
    required this.code,
    required this.column,
    required this.file,
    required this.keys,
    required this.bytes,
    required this.sha256,
    this.changed = true,
    this.errors = 0,
  });

  final String code;
  final String column;
  final String file;
  final int keys;
  final int bytes;
  final String sha256;

  /// False when the pack is byte-for-byte the one built last time (no need to upload it again).
  final bool changed;
  final int errors;

  @override
  List<Object?> get props => [
    code,
    column,
    file,
    keys,
    bytes,
    sha256,
    changed,
    errors,
  ];
}

class PackSkip extends Equatable {
  const PackSkip({required this.column, required this.reason, this.code});
  final String? code;
  final String column;
  final String reason;
  @override
  List<Object?> get props => [code, column, reason];
}

class PackReport extends Equatable {
  const PackReport({
    required this.packs,
    this.skipped = const [],
    this.totalKeys = 0,
    this.out = '',
  });
  final List<PackInfo> packs;
  final List<PackSkip> skipped;
  final int totalKeys;
  final String out;
  @override
  List<Object?> get props => [packs, skipped, totalKeys, out];
}

/// The TrTokens constant name for a key (same rule as the engine: email_txt -> emailTxt).
String tokenNameFor(String key) {
  final parts = key
      .split(RegExp('[^A-Za-z0-9]+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'emptyKey';
  final out =
      parts.first.toLowerCase() +
      parts
          .skip(1)
          .map((p) => p[0].toUpperCase() + p.substring(1).toLowerCase())
          .join();
  return RegExp(r'^\d').hasMatch(out) ? 'k$out' : out;
}

final keyPattern = RegExp(r'^[a-z][a-z0-9]*(_[a-z0-9]+)*$');
final placeholderPattern = RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)\}');

/// Placeholders of a text, sorted and unique.
List<String> placeholdersOf(String text) =>
    (placeholderPattern
        .allMatches(text)
        .map((m) => m.group(1)!)
        .toSet()
        .toList()
      ..sort());
