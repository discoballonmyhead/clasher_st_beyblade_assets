import 'package:equatable/equatable.dart';

/// One app whose strings the Studio manages: its Flutter project (read-only), its translation sheet, and where
/// generated files go. Any number of them; the Studio isn't tied to one app.
class TranslationProject extends Equatable {
  const TranslationProject({
    required this.id,
    required this.name,
    required this.projectDir,
    required this.sheetPath,
    required this.exportDir,
    this.tokensFile = '',
    this.defaultsFile = '',
    this.languagesFile = '',
    this.writeIntoProject = false,
  });

  final String id;
  final String name;

  /// The Flutter project root (has lib/). Read, never written - unless [writeIntoProject].
  final String projectDir;

  /// The translation workbook (.xlsx).
  final String sheetPath;

  /// Where generated Dart, language packs and reports go.
  final String exportDir;

  /// Overrides when the constants files can't be found by their class names (paths relative to the project).
  final String tokensFile;
  final String defaultsFile;
  final String languagesFile;

  /// Off by default: generated constants files are only written to [exportDir]. On: "Copy into project" is
  /// offered after an export (the three constants files only, each backed up first).
  final bool writeIntoProject;

  Map<String, String> get overrides => {
    if (tokensFile.trim().isNotEmpty) 'tokens': tokensFile.trim(),
    if (defaultsFile.trim().isNotEmpty) 'defaults': defaultsFile.trim(),
    if (languagesFile.trim().isNotEmpty) 'languages': languagesFile.trim(),
  };

  TranslationProject copyWith({
    String? name,
    String? projectDir,
    String? sheetPath,
    String? exportDir,
    String? tokensFile,
    String? defaultsFile,
    String? languagesFile,
    bool? writeIntoProject,
  }) => TranslationProject(
    id: id,
    name: name ?? this.name,
    projectDir: projectDir ?? this.projectDir,
    sheetPath: sheetPath ?? this.sheetPath,
    exportDir: exportDir ?? this.exportDir,
    tokensFile: tokensFile ?? this.tokensFile,
    defaultsFile: defaultsFile ?? this.defaultsFile,
    languagesFile: languagesFile ?? this.languagesFile,
    writeIntoProject: writeIntoProject ?? this.writeIntoProject,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'projectDir': projectDir,
    'sheetPath': sheetPath,
    'exportDir': exportDir,
    'tokensFile': tokensFile,
    'defaultsFile': defaultsFile,
    'languagesFile': languagesFile,
    'writeIntoProject': writeIntoProject,
  };

  factory TranslationProject.fromJson(Map<String, dynamic> j) =>
      TranslationProject(
        id: '${j['id']}',
        name: '${j['name'] ?? ''}',
        projectDir: '${j['projectDir'] ?? ''}',
        sheetPath: '${j['sheetPath'] ?? ''}',
        exportDir: '${j['exportDir'] ?? ''}',
        tokensFile: '${j['tokensFile'] ?? ''}',
        defaultsFile: '${j['defaultsFile'] ?? ''}',
        languagesFile: '${j['languagesFile'] ?? ''}',
        writeIntoProject: j['writeIntoProject'] == true,
      );

  @override
  List<Object?> get props => [
    id,
    name,
    projectDir,
    sheetPath,
    exportDir,
    tokensFile,
    defaultsFile,
    languagesFile,
    writeIntoProject,
  ];
}
