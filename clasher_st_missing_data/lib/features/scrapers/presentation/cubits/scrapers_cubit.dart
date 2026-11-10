import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failure.dart';
import '../../../studio/domain/entities/studio_models.dart';
import '../../../studio/domain/job_center.dart';
import '../../../studio/domain/repositories/studio_repository.dart';

class ScrapeOptions extends Equatable {
  const ScrapeOptions({
    this.limit,
    this.maxRequests,
    this.delay,
    this.noImages = false,
    this.overwrite = false,
    this.relist = false,
    this.refreshExisting = false,
    this.listOnly = false,
  });

  /// Max pages per target this run.
  final int? limit;
  final int? maxRequests;
  final double? delay;
  final bool noImages;

  /// Overwrite filled cells (default: fill blanks only).
  final bool overwrite;
  final bool relist;
  final bool refreshExisting;

  /// Only list the pages a target would scrape.
  final bool listOnly;

  ScrapeOptions copyWith({
    int? Function()? limit,
    int? Function()? maxRequests,
    double? Function()? delay,
    bool? noImages,
    bool? overwrite,
    bool? relist,
    bool? refreshExisting,
    bool? listOnly,
  }) => ScrapeOptions(
    limit: limit != null ? limit() : this.limit,
    maxRequests: maxRequests != null ? maxRequests() : this.maxRequests,
    delay: delay != null ? delay() : this.delay,
    noImages: noImages ?? this.noImages,
    overwrite: overwrite ?? this.overwrite,
    relist: relist ?? this.relist,
    refreshExisting: refreshExisting ?? this.refreshExisting,
    listOnly: listOnly ?? this.listOnly,
  );

  Map<String, Object?> toJson() => {
    'limit': limit,
    'maxRequests': maxRequests,
    'delay': delay,
    'noImages': noImages,
    'overwrite': overwrite,
    'relist': relist,
    'refreshExisting': refreshExisting,
    'listOnly': listOnly,
  };

  @override
  List<Object?> get props => [limit, maxRequests, delay, noImages, overwrite, relist, refreshExisting, listOnly];
}

class ScrapersState extends Equatable {
  const ScrapersState({
    this.overview,
    this.hobby,
    this.generation,
    this.picked = const {},
    this.focused,
    this.options = const ScrapeOptions(),
    this.runningJob,
    this.log = const [],
    this.lastRun,
    this.configText,
    this.configOriginal,
    this.configError,
    this.codePath,
    this.codeText,
    this.codeOriginal,
    this.codeExists = false,
    this.codeCheck,
    this.scraperPath,
    this.loading = false,
    this.error,
    this.message,
  });

  final ScraperOverview? overview;
  final String? hobby;
  final String? generation;
  final Set<String> picked;

  /// The target whose settings are open.
  final String? focused;
  final ScrapeOptions options;
  final String? runningJob;
  final List<String> log;
  final String? lastRun;

  final String? configText;
  final String? configOriginal;
  final String? configError;

  final String? codePath;
  final String? codeText;
  final String? codeOriginal;
  final bool codeExists;
  final CodeCheck? codeCheck;
  final String? scraperPath;

  final bool loading;
  final String? error;
  final String? message;

  bool get running => runningJob != null;
  bool get configDirty => configText != null && configText != configOriginal;
  bool get codeDirty => codeText != null && codeText != codeOriginal;

  List<String> get hobbies => [...{for (final t in overview?.targets ?? const <ScraperTarget>[]) t.hobby}];
  List<String> generationsOf(String? hobby) =>
      [...{for (final t in overview?.targets ?? const <ScraperTarget>[]) if (t.hobby == hobby) t.generation}];
  List<ScraperTarget> get visible => [
    for (final t in overview?.targets ?? const <ScraperTarget>[])
      if (t.hobby == hobby && (generation == null || t.generation == generation)) t,
  ];

  ScrapersState copyWith({
    ScraperOverview? overview,
    String? Function()? hobby,
    String? Function()? generation,
    Set<String>? picked,
    String? Function()? focused,
    ScrapeOptions? options,
    String? Function()? runningJob,
    List<String>? log,
    String? Function()? lastRun,
    String? Function()? configText,
    String? Function()? configOriginal,
    String? Function()? configError,
    String? Function()? codePath,
    String? Function()? codeText,
    String? Function()? codeOriginal,
    bool? codeExists,
    CodeCheck? Function()? codeCheck,
    String? Function()? scraperPath,
    bool? loading,
    String? Function()? error,
    String? Function()? message,
  }) => ScrapersState(
    overview: overview ?? this.overview,
    hobby: hobby != null ? hobby() : this.hobby,
    generation: generation != null ? generation() : this.generation,
    picked: picked ?? this.picked,
    focused: focused != null ? focused() : this.focused,
    options: options ?? this.options,
    runningJob: runningJob != null ? runningJob() : this.runningJob,
    log: log ?? this.log,
    lastRun: lastRun != null ? lastRun() : this.lastRun,
    configText: configText != null ? configText() : this.configText,
    configOriginal: configOriginal != null ? configOriginal() : this.configOriginal,
    configError: configError != null ? configError() : this.configError,
    codePath: codePath != null ? codePath() : this.codePath,
    codeText: codeText != null ? codeText() : this.codeText,
    codeOriginal: codeOriginal != null ? codeOriginal() : this.codeOriginal,
    codeExists: codeExists ?? this.codeExists,
    codeCheck: codeCheck != null ? codeCheck() : this.codeCheck,
    scraperPath: scraperPath != null ? scraperPath() : this.scraperPath,
    loading: loading ?? this.loading,
    error: error != null ? error() : null,
    message: message != null ? message() : null,
  );

  @override
  List<Object?> get props => [
    overview, hobby, generation, picked, focused, options, runningJob, log, lastRun, configText, configOriginal,
    configError, codePath, codeText, codeOriginal, codeExists, codeCheck, scraperPath, loading, error, message,
  ];
}

/// The wiki scraper per hobby and generation: pick targets, run them (live log, safe stop), edit each target's
/// settings and the hobby + generation's own code.
class ScrapersCubit extends Cubit<ScrapersState> {
  ScrapersCubit({required StudioRepository repository, required JobCenter jobs})
    : _repo = repository,
      _jobs = jobs,
      super(const ScrapersState());

  final StudioRepository _repo;
  final JobCenter _jobs;
  static const _json = JsonEncoder.withIndent('  ');

  Future<void> load() async {
    emit(state.copyWith(loading: true));
    final res = await _repo.scraperTargets();
    await res.fold(
      (f) async => emit(state.copyWith(loading: false, error: () => f.message)),
      (o) async {
        final hobby = state.hobby ?? o.targets.firstOrNull?.hobby;
        final gens = [...{for (final t in o.targets) if (t.hobby == hobby) t.generation}];
        final gen = state.generation != null && gens.contains(state.generation) ? state.generation : (gens.isEmpty ? null : gens.last);
        emit(state.copyWith(loading: false, overview: o, hobby: () => hobby, generation: () => gen));
        if (state.codeText == null && hobby != null && gen != null) await loadCode();
      },
    );
  }

  Future<void> selectHobby(String hobby) async {
    final gens = state.generationsOf(hobby);
    emit(state.copyWith(hobby: () => hobby, generation: () => gens.isEmpty ? null : gens.last, picked: const {}, focused: () => null));
    await loadCode();
  }

  Future<void> selectGeneration(String? gen) async {
    if (state.codeDirty) {
      emit(state.copyWith(error: () => 'Save or discard the code changes first'));
      return;
    }
    emit(state.copyWith(generation: () => gen, picked: const {}));
    if (gen != null) await loadCode();
  }

  void togglePick(String target) {
    final p = {...state.picked};
    p.contains(target) ? p.remove(target) : p.add(target);
    emit(state.copyWith(picked: p));
  }

  void pickAllVisible() => emit(state.copyWith(picked: {for (final t in state.visible) t.target}));
  void clearPicks() => emit(state.copyWith(picked: const {}));
  void setOptions(ScrapeOptions o) => emit(state.copyWith(options: o));
  void clearLog() => emit(state.copyWith(log: const []));

  Future<void> run() async {
    if (state.running || state.picked.isEmpty) return;
    final targets = [for (final t in state.visible) if (state.picked.contains(t.target)) t.target];
    emit(state.copyWith(runningJob: () => 'starting', log: [...state.log, '', '── Scrape ${targets.join(', ')} ──']));
    final lines = <String>[];
    var flushed = 0;
    final res = await _jobs.run(() async {
      final r = await _repo.scrape(targets: targets, options: state.options.toJson());
      if (r case Ok(:final value)) emit(state.copyWith(runningJob: () => value));
      return r;
    }, (l) {
      lines.add(l);
      if (lines.length - flushed >= 3) {
        emit(state.copyWith(log: [...state.log, ...lines.sublist(flushed)]));
        flushed = lines.length;
      }
    });
    final log = [...state.log, ...lines.sublist(flushed)];
    switch (res) {
      case Err(:final failure):
        emit(state.copyWith(runningJob: () => null, log: log, error: () => failure.message));
      case Ok(value: final e):
        final msg = e.ok ? '${(e.result as Map?)?['message'] ?? 'finished'}' : (e.error ?? 'failed');
        emit(state.copyWith(runningJob: () => null, log: log, lastRun: () => msg, message: () => 'Scrape: $msg'));
        await load(); // progress changed
    }
  }

  Future<void> stop() async {
    final id = state.runningJob;
    if (id != null && id != 'starting') await _jobs.stop(id);
  }

  // ── target settings ──
  Future<void> focus(String target) async {
    if (state.configDirty) {
      emit(state.copyWith(error: () => 'Save or discard the target settings first'));
      return;
    }
    final res = await _repo.scraperTargetConfig(target);
    res.fold(
      (f) => emit(state.copyWith(error: () => f.message)),
      (c) {
        final text = _json.convert(c);
        emit(state.copyWith(focused: () => target, configText: () => text, configOriginal: () => text, configError: () => null));
      },
    );
  }

  void editConfig(String text) {
    String? err;
    try {
      final v = jsonDecode(text);
      if (v is! Map) err = 'The settings must be a JSON object { ... }';
    } on FormatException catch (e) {
      err = e.message;
    }
    emit(state.copyWith(configText: () => text, configError: () => err));
  }

  void discardConfig() => emit(state.copyWith(configText: () => state.configOriginal, configError: () => null));

  Future<void> saveConfig() async {
    final t = state.focused;
    if (t == null || state.configError != null || !state.configDirty) return;
    final res = await _repo.saveScraperTargetConfig(t, Map<String, dynamic>.from(jsonDecode(state.configText!) as Map));
    res.fold(
      (f) => emit(state.copyWith(error: () => f.message)),
      (_) => emit(state.copyWith(configOriginal: () => state.configText, message: () => '$t saved (previous version in scrapers/backups)')),
    );
  }

  // ── code ──
  Future<void> loadCode() async {
    final h = state.hobby, g = state.generation;
    if (h == null || g == null) return;
    final res = await _repo.codeFiles(h, g);
    res.fold(
      (f) => emit(state.copyWith(error: () => f.message)),
      (c) => emit(state.copyWith(
        codePath: () => c.path,
        codeText: () => c.text,
        codeOriginal: () => c.exists ? c.text : '',
        codeExists: c.exists,
        codeCheck: () => null,
        scraperPath: () => c.scraperPath,
      )),
    );
  }

  /// Opens the scraper's own source (advanced) in the editor.
  Future<void> openScraperSource() async {
    final p = state.scraperPath;
    if (p == null) return;
    if (state.codeDirty) {
      emit(state.copyWith(error: () => 'Save or discard the code changes first'));
      return;
    }
    final res = await _repo.readCode(p);
    res.fold(
      (f) => emit(state.copyWith(error: () => f.message)),
      (c) => emit(state.copyWith(codePath: () => c.path, codeText: () => c.text, codeOriginal: () => c.text, codeExists: true, codeCheck: () => null)),
    );
  }

  void editCode(String text) => emit(state.copyWith(codeText: () => text, codeCheck: () => null));
  void discardCode() => emit(state.copyWith(codeText: () => state.codeExists ? state.codeOriginal : state.codeText, codeCheck: () => null));

  Future<CodeCheck?> checkCode() async {
    final p = state.codePath, t = state.codeText;
    if (p == null || t == null) return null;
    final res = await _repo.checkCode(p, t);
    return res.fold((f) {
      emit(state.copyWith(error: () => f.message));
      return null;
    }, (c) {
      emit(state.copyWith(codeCheck: () => c));
      return c;
    });
  }

  Future<void> saveCode() async {
    final p = state.codePath, t = state.codeText;
    if (p == null || t == null) return;
    final chk = await checkCode();
    if (chk == null || !chk.ok) return;
    final res = await _repo.saveCode(p, t);
    await res.fold(
      (f) async => emit(state.copyWith(error: () => f.message)),
      (_) async {
        emit(state.copyWith(codeOriginal: () => t, codeExists: true, message: () => 'Saved ${p.split(RegExp(r'[\\/]')).last} (previous version in scrapers/backups)'));
        await load();
      },
    );
  }

  Future<void> saveSettings({required String userAgent, double? delay, int? maxRequests}) async {
    final res = await _repo.saveScraperSettings(userAgent: userAgent, politeness: {
      'delay_seconds': ?delay,
      'max_requests_per_run': ?maxRequests,
    });
    await res.fold(
      (f) async => emit(state.copyWith(error: () => f.message)),
      (_) async {
        emit(state.copyWith(message: () => 'Scraper settings saved'));
        await load();
      },
    );
  }
}
