import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../bridge/engine_bridge.dart';

/// Where Python and the tools are, recent workbooks, and UI preferences.
class AppSettings {
  AppSettings(this._prefs);

  final SharedPreferences _prefs;

  static const _python = 'python';
  static const _tools = 'toolsDir';
  static const _recent = 'recentWorkbooks';
  static const _sort = 'rowSort';

  String get python =>
      _prefs.getString(_python) ?? (Platform.isWindows ? 'python' : 'python3');
  set python(String v) => _prefs.setString(_python, v);

  /// The folder with missing_data_tool.py. Default: the repo this app lives in.
  String get toolsDir => _prefs.getString(_tools) ?? _guessToolsDir();
  set toolsDir(String v) => _prefs.setString(_tools, v);

  EngineConfig get engineConfig =>
      EngineConfig(python: python, toolsDir: toolsDir);

  /// The translation engine (translation_tool.py, same folder and interpreter).
  EngineConfig get translationEngineConfig => EngineConfig(
    python: python,
    toolsDir: toolsDir,
    scriptName: 'translation_tool.py',
  );

  static const _publishing = 'publishing';

  /// Repo names, branches and release tags: set once, used everywhere.
  PublishingConstants get publishing {
    final raw = _prefs.getString(_publishing);
    if (raw == null) return const PublishingConstants();
    try {
      return PublishingConstants.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map),
      );
    } on FormatException {
      return const PublishingConstants();
    }
  }

  Future<void> setPublishing(PublishingConstants v) =>
      _prefs.setString(_publishing, jsonEncode(v.toJson()));

  /// Every setting, for a backup file (Settings -> Export).
  Map<String, Object?> exportAll() => {
    for (final k in _prefs.getKeys()) k: _prefs.get(k),
  };

  /// Restores a backup made by [exportAll]. Unknown value types are skipped.
  Future<int> importAll(Map<String, Object?> data) async {
    var n = 0;
    for (final e in data.entries) {
      final v = e.value;
      final done = switch (v) {
        String() => await _prefs.setString(e.key, v),
        bool() => await _prefs.setBool(e.key, v),
        int() => await _prefs.setInt(e.key, v),
        double() => await _prefs.setDouble(e.key, v),
        List() => await _prefs.setStringList(e.key, [for (final x in v) '$x']),
        _ => false,
      };
      if (done) n++;
    }
    return n;
  }

  List<String> get recentWorkbooks => _prefs.getStringList(_recent) ?? const [];

  Future<void> addRecent(String path) async {
    final list = [
      path,
      ...recentWorkbooks.where((p) => p != path),
    ].take(8).toList();
    await _prefs.setStringList(_recent, list);
  }

  String get rowSort => _prefs.getString(_sort) ?? 'sheet';
  set rowSort(String v) => _prefs.setString(_sort, v);

  static String _guessToolsDir() {
    var dir = Directory.current;
    for (var i = 0; i < 4; i++) {
      if (File('${dir.path}${Platform.pathSeparator}missing_data_tool.py')
          .existsSync()) {
        return dir.path;
      }
      dir = dir.parent;
    }
    return Directory.current.parent.path;
  }
}

/// Names that stay the same release after release. Defaults are this project's.
class PublishingConstants {
  const PublishingConstants({
    this.owner = 'discoballonmyhead',
    this.dataRepo = 'clasher_st_beyblade_assets',
    this.dataBranch = 'main',
    this.catalogTagFormat = 'yyyy-MM-dd',
    this.imagePacksTag = '',
    this.translationsRepo = 'clasher_st_translations',
    this.translationsTag = 'latest',
  });

  /// GitHub user or organisation that owns the repos.
  final String owner;
  final String dataRepo;
  final String dataBranch;

  /// How catalog release tags are named (yyyy, MM, dd are replaced).
  final String catalogTagFormat;

  /// The release the image packs live on (AppEnv.githubReleaseTag in the app).
  final String imagePacksTag;
  final String translationsRepo;

  /// The release the language packs are uploaded to.
  final String translationsTag;

  String catalogTag(DateTime d) => catalogTagFormat
      .replaceAll('yyyy', d.year.toString().padLeft(4, '0'))
      .replaceAll('MM', d.month.toString().padLeft(2, '0'))
      .replaceAll('dd', d.day.toString().padLeft(2, '0'));

  String get dataRepoSlug => '$owner/$dataRepo';
  String get translationsRepoSlug => '$owner/$translationsRepo';
  String get cdnImagesBase =>
      'https://cdn.jsdelivr.net/gh/$owner/$dataRepo@$dataBranch/data/images/';

  PublishingConstants copyWith({
    String? owner,
    String? dataRepo,
    String? dataBranch,
    String? catalogTagFormat,
    String? imagePacksTag,
    String? translationsRepo,
    String? translationsTag,
  }) => PublishingConstants(
    owner: owner ?? this.owner,
    dataRepo: dataRepo ?? this.dataRepo,
    dataBranch: dataBranch ?? this.dataBranch,
    catalogTagFormat: catalogTagFormat ?? this.catalogTagFormat,
    imagePacksTag: imagePacksTag ?? this.imagePacksTag,
    translationsRepo: translationsRepo ?? this.translationsRepo,
    translationsTag: translationsTag ?? this.translationsTag,
  );

  Map<String, String> toJson() => {
    'owner': owner,
    'dataRepo': dataRepo,
    'dataBranch': dataBranch,
    'catalogTagFormat': catalogTagFormat,
    'imagePacksTag': imagePacksTag,
    'translationsRepo': translationsRepo,
    'translationsTag': translationsTag,
  };

  factory PublishingConstants.fromJson(Map<String, dynamic> j) {
    const d = PublishingConstants();
    String s(String k, String fallback) =>
        (j[k] is String && (j[k] as String).trim().isNotEmpty)
        ? (j[k] as String).trim()
        : fallback;
    return PublishingConstants(
      owner: s('owner', d.owner),
      dataRepo: s('dataRepo', d.dataRepo),
      dataBranch: s('dataBranch', d.dataBranch),
      catalogTagFormat: s('catalogTagFormat', d.catalogTagFormat),
      imagePacksTag: j['imagePacksTag'] is String
          ? (j['imagePacksTag'] as String).trim()
          : d.imagePacksTag,
      translationsRepo: s('translationsRepo', d.translationsRepo),
      translationsTag: s('translationsTag', d.translationsTag),
    );
  }
}
