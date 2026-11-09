import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/entities/translation_project.dart';

/// The apps the Studio manages translations for, kept with the app's settings (and in Settings -> Export).
class TranslationProjectStore {
  TranslationProjectStore(this._prefs);

  final SharedPreferences _prefs;
  static const _list = 'translationProjects';
  static const _active = 'activeTranslationProject';

  List<TranslationProject> load() {
    final raw = _prefs.getString(_list);
    if (raw == null) return const [];
    try {
      return [
        for (final p in jsonDecode(raw) as List)
          TranslationProject.fromJson(Map<String, dynamic>.from(p as Map)),
      ];
    } on FormatException {
      return const [];
    }
  }

  Future<void> saveAll(List<TranslationProject> projects) => _prefs.setString(
    _list,
    jsonEncode([for (final p in projects) p.toJson()]),
  );

  String? get activeId => _prefs.getString(_active);
  Future<void> setActive(String? id) =>
      id == null ? _prefs.remove(_active) : _prefs.setString(_active, id);
}
