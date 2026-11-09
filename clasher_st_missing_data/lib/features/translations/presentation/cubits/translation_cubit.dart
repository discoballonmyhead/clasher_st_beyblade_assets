import 'dart:convert';
import 'dart:math';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/error/failure.dart';
import '../../data/translation_project_store.dart';
import '../../domain/entities/translation_models.dart';
import '../../domain/entities/translation_project.dart';
import '../../domain/repositories/translation_repository.dart';
import '../../domain/usecases/translation_usecases.dart';
import 'translation_state.dart';

/// The translation project that's open: its summary and report, edits to the sheet, what the next export adds
/// to the app, and the export / pack results. One for the whole app.
class TranslationCubit extends Cubit<TranslationState> {
  TranslationCubit({
    required TranslationRepository repository,
    required TranslationProjectStore store,
    required SharedPreferences prefs,
  }) : _repo = repository,
       _store = store,
       _prefs = prefs,
       _open = OpenTranslationProject(repository),
       _refresh = RefreshTranslations(repository),
       _edit = EditTranslations(repository),
       _add = AddTranslationKeys(repository),
       _export = ExportAppConstants(repository),
       _packs = BuildLanguagePacks(repository),
       super(const TranslationState());

  final TranslationRepository _repo;
  final TranslationProjectStore _store;
  final SharedPreferences _prefs;
  final OpenTranslationProject _open;
  final RefreshTranslations _refresh;
  final EditTranslations _edit;
  final AddTranslationKeys _add;
  final ExportAppConstants _export;
  final BuildLanguagePacks _packs;

  bool _started = false;

  /// Loads the saved apps and opens the last one - once, the first time the section is shown.
  Future<void> ensureStarted() async {
    if (_started) return;
    _started = true;
    await init();
  }

  // ── projects ──
  Future<void> init() async {
    final projects = _store.load();
    final active =
        projects.where((p) => p.id == _store.activeId).firstOrNull ??
        projects.firstOrNull;
    emit(state.copyWith(projects: projects, active: () => active));
    if (active != null) await open();
  }

  static String newId() =>
      '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}${Random().nextInt(1 << 20).toRadixString(36)}';

  /// Adds or replaces a project, makes it active and opens it.
  Future<void> saveProject(TranslationProject p) async {
    final list = [
      for (final x in state.projects)
        if (x.id != p.id) x,
      p,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    await _store.saveAll(list);
    await _store.setActive(p.id);
    emit(state.copyWith(projects: list, active: () => p));
    await open();
  }

  Future<void> deleteProject(String id) async {
    final list = [
      for (final x in state.projects)
        if (x.id != id) x,
    ];
    await _store.saveAll(list);
    final active = state.active?.id == id ? list.firstOrNull : state.active;
    await _store.setActive(active?.id);
    emit(
      state.copyWith(
        projects: list,
        active: () => active,
        summary: () => null,
        report: () => null,
      ),
    );
    if (active != null) await open();
  }

  Future<void> select(String id) async {
    final p = state.projects.where((x) => x.id == id).firstOrNull;
    if (p == null || p.id == state.active?.id) return;
    await _store.setActive(p.id);
    emit(
      state.copyWith(active: () => p, export: () => null, packs: () => null),
    );
    await open();
  }

  // ── opening / refreshing ──
  Future<void> open() async {
    final p = state.active;
    if (p == null) return;
    emit(state.copyWith(loading: true, busy: () => 'Reading ${p.name} ...'));
    final res = await _open(p);
    if (res case Err(:final failure)) {
      emit(
        state.copyWith(
          loading: false,
          busy: () => null,
          summary: () => null,
          report: () => null,
          error: () => failure.message,
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        addToApp: _loadPending(p.id).$1,
        updateEnglish: _loadPending(p.id).$2,
      ),
    );
    await _reload(rescan: false);
  }

  /// Re-reads the project from disk (after you changed the code) and the report.
  Future<void> refresh() =>
      _reload(rescan: true, label: 'Scanning the project ...');

  Future<void> _reload({
    required bool rescan,
    String? label,
    String? message,
  }) async {
    emit(state.copyWith(loading: true, busy: () => label ?? state.busy));
    final res = await _refresh(rescan: rescan);
    res.fold(
      (f) => emit(
        state.copyWith(
          loading: false,
          busy: () => null,
          error: () => f.message,
        ),
      ),
      (v) {
        // keys that reached the app's constants (copied in) are no longer pending - only knowable when the
        // project with its TrTokens is open
        var pending = state.addToApp;
        if (state.addToApp.isNotEmpty && (v.$1.project?.tokensFile != null)) {
          final stillMissing = {
            for (final i in v.$2.issues)
              if (i.kind == 'missing_in_app' && i.key != null) i.key!,
          };
          pending = {
            for (final e in state.addToApp.entries)
              if (stillMissing.contains(e.key)) e.key: e.value,
          };
        }
        emit(
          state.copyWith(
            loading: false,
            busy: () => null,
            summary: () => v.$1,
            report: () => v.$2,
            revision: state.revision + 1,
            addToApp: pending,
            message: () => message,
          ),
        );
        if (state.addToApp.length != pending.length) _savePending();
      },
    );
  }

  Future<T?> _run<T>(
    String label,
    Future<Result<T>> Function() action, {
    bool reload = true,
    bool rescan = false,
    String Function(T value)? done,
  }) async {
    emit(state.copyWith(busy: () => label));
    final res = await action();
    return switch (res) {
      Ok(:final value) => () async {
        if (reload) {
          await _reload(rescan: rescan, message: done?.call(value));
        } else {
          emit(
            state.copyWith(busy: () => null, message: () => done?.call(value)),
          );
        }
        return value;
      }(),
      Err(:final failure) => () {
        emit(
          state.copyWith(
            busy: () => null,
            error: () => failure.message,
            conflict: failure.message.contains('changed on disk'),
          ),
        );
        return Future<T?>.value();
      }(),
    };
  }

  // ── sheet edits (journaled by the engine; saved with save()) ──
  Future<List<TrProblem>> setCells(
    List<({String key, String column, String text})> items,
  ) async =>
      await _run(
        'Saving the texts ...',
        () => _edit(items),
        done: (p) => p.isEmpty
            ? 'Updated - save to keep'
            : '${p.length} problem(s): see the editor',
      ) ??
      const [];

  /// Adds keys to the sheet. [toApp]: also add them to the app's constants on the next export, under [section].
  Future<List<String>> addKeys(
    List<({String key, String english, Map<String, String> meta})> items, {
    bool toApp = false,
    String? section,
  }) async {
    final r = await _run(
      'Adding ${items.length} key(s) ...',
      () => _add(items),
      rescan: true,
      done: (v) =>
          'Added ${v.added.length} key(s) to the sheet${v.skipped.isEmpty ? '' : ', skipped ${v.skipped.length}: ${v.skipped.first}'}'
          ' - save to keep',
    );
    if (r != null && toApp && r.added.isNotEmpty) {
      emit(
        state.copyWith(
          addToApp: {
            ...state.addToApp,
            for (final k in r.added) k: section ?? 'NEW',
          },
        ),
      );
      _savePending();
    }
    return r?.added ?? const [];
  }

  void markForApp(String key, {String? section}) {
    emit(
      state.copyWith(
        addToApp: {
          ...state.addToApp,
          key: section ?? state.addToApp[key] ?? 'NEW',
        },
      ),
    );
    _savePending();
  }

  void unmarkForApp(String key) {
    emit(state.copyWith(addToApp: {...state.addToApp}..remove(key)));
    _savePending();
  }

  void toggleEnglishUpdate(String key) {
    final s = {...state.updateEnglish};
    s.contains(key) ? s.remove(key) : s.add(key);
    emit(state.copyWith(updateEnglish: s));
    _savePending();
  }

  Future<void> setLanguages(List<TrLanguage> langs) => _run<bool>(
    'Saving languages ...',
    () => _ok(_repo.setLanguages(langs)),
    done: (_) => 'Languages tab updated - save to keep',
  );

  Future<void> addLanguage({
    required String column,
    String? code,
    String? name,
    String? country,
  }) => _run<bool>(
    'Adding $column ...',
    () => _ok(
      _repo.addLanguage(
        column: column,
        code: code,
        name: name,
        country: country,
      ),
    ),
    done: (_) => 'Column $column added to the sheet - save to keep',
  );

  Future<void> undo() => _run<String?>(
    'Undoing ...',
    _repo.undo,
    rescan: true,
    done: (l) => l == null ? 'Nothing to undo' : 'Undid: $l',
  );

  Future<bool> save({bool force = false}) async {
    final r = await _run(
      'Saving the sheet ...',
      () => _repo.save(force: force),
      done: (b) =>
          'Saved (previous version: ${b.split(RegExp(r'[\\/]')).last})',
    );
    return r != null;
  }

  Future<void> recoverUnsaved() => _run<int>(
    'Recovering ...',
    _repo.recoverUnsaved,
    rescan: true,
    done: (n) => 'Recovered $n unsaved change(s) - save to keep',
  );

  Future<void> discardUnsaved() => _run<bool>(
    'Discarding ...',
    () => _ok(_repo.discardUnsaved()),
    done: (_) => 'Discarded (a copy is in backups/)',
  );

  // ── exports ──
  Future<void> exportDart() async {
    final p = state.active;
    if (p == null) return;
    final r = await _run(
      'Exporting the app constants ...',
      () => _export(
        p.exportDir,
        addKeys: state.addToApp.keys.toList(),
        updateEnglish: state.updateEnglish.toList(),
        sections: state.addToApp,
      ),
      reload: false,
      done: (v) => 'Written to ${v.out} - the project wasn\'t touched',
    );
    if (r != null) emit(state.copyWith(export: () => r));
  }

  /// Only when the project allows it (TranslationProject.writeIntoProject) - the page asks first.
  Future<void> applyExport() async {
    final p = state.active;
    if (p == null || !p.writeIntoProject || state.export == null) return;
    final r = await _run(
      'Copying into the project ...',
      () => _repo.applyExport(p.exportDir),
      rescan: true,
      done: (files) =>
          'Copied ${files.length} file(s) into the project (backups in the export folder)',
    );
    if (r != null) {
      emit(state.copyWith(export: () => null));
    }
  }

  Future<void> buildPacks({bool strict = false}) async {
    final p = state.active;
    if (p == null) return;
    final r = await _run(
      'Building language packs ...',
      () => _packs(p.exportDir, strict: strict),
      reload: false,
      done: (v) =>
          'Built ${v.packs.length} pack(s)${v.skipped.isEmpty ? '' : ', skipped ${v.skipped.length}'}',
    );
    if (r != null) emit(state.copyWith(packs: () => r));
  }

  /// `Result<void>` -> `Result<bool>`, so _run can hand the value to its message.
  static Future<Result<bool>> _ok(Future<Result<void>> r) async =>
      switch (await r) {
        Ok() => const Ok(true),
        Err(:final failure) => Err(failure),
      };

  // ── pending export choices survive restarts ──
  String _pendingKey(String id) => 'trPending:$id';

  (Map<String, String>, Set<String>) _loadPending(String id) {
    final raw = _prefs.getString(_pendingKey(id));
    if (raw == null) return (const {}, const {});
    try {
      final j = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return (
        {
          for (final e in Map<String, dynamic>.from(
            j['addToApp'] as Map? ?? {},
          ).entries)
            e.key: '${e.value}',
        },
        {for (final k in (j['updateEnglish'] as List? ?? const [])) '$k'},
      );
    } on FormatException {
      return (const {}, const {});
    }
  }

  void _savePending() {
    final id = state.active?.id;
    if (id == null) return;
    _prefs.setString(
      _pendingKey(id),
      jsonEncode({
        'addToApp': state.addToApp,
        'updateEnglish': state.updateEnglish.toList(),
      }),
    );
  }
}
