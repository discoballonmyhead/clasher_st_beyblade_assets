/// Something that can hold unsaved changes (an open workbook, a translation sheet). The Studio's shell asks
/// before the window closes when any of them is dirty, and can save them all.
class UnsavedSource {
  const UnsavedSource({
    required this.id,
    required this.label,
    required this.isDirty,
    required this.save,
  });

  final String id;

  /// What the prompt lists, e.g. "Data: beyblade_parts.xlsx".
  final String Function() label;
  final bool Function() isDirty;

  /// True when saved.
  final Future<bool> Function() save;
}

class UnsavedWork {
  final _sources = <String, UnsavedSource>{};

  void register(UnsavedSource s) => _sources[s.id] = s;
  void unregister(String id) => _sources.remove(id);

  List<UnsavedSource> get dirty => [
    for (final s in _sources.values)
      if (s.isDirty()) s,
  ];

  /// Saves every dirty source -> true when all saved.
  Future<bool> saveAll() async {
    var ok = true;
    for (final s in dirty) {
      ok = await s.save() && ok;
    }
    return ok;
  }
}
