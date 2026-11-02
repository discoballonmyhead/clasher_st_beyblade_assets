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

  String get python => _prefs.getString(_python) ?? (Platform.isWindows ? 'python' : 'python3');
  set python(String v) => _prefs.setString(_python, v);

  /// The folder with missing_data_tool.py. Default: the repo this app lives in.
  String get toolsDir => _prefs.getString(_tools) ?? _guessToolsDir();
  set toolsDir(String v) => _prefs.setString(_tools, v);

  EngineConfig get engineConfig => EngineConfig(python: python, toolsDir: toolsDir);

  List<String> get recentWorkbooks => _prefs.getStringList(_recent) ?? const [];

  Future<void> addRecent(String path) async {
    final list = [path, ...recentWorkbooks.where((p) => p != path)].take(8).toList();
    await _prefs.setStringList(_recent, list);
  }

  String get rowSort => _prefs.getString(_sort) ?? 'sheet';
  set rowSort(String v) => _prefs.setString(_sort, v);

  static String _guessToolsDir() {
    var dir = Directory.current;
    for (var i = 0; i < 4; i++) {
      if (File('${dir.path}${Platform.pathSeparator}missing_data_tool.py').existsSync()) return dir.path;
      dir = dir.parent;
    }
    return Directory.current.parent.path;
  }
}
