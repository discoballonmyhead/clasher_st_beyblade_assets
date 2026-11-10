import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/settings/app_settings.dart';
import '../../../studio/domain/entities/studio_models.dart';
import '../../../studio/domain/job_center.dart';
import '../../../studio/domain/repositories/studio_repository.dart';

enum StepStatus { idle, running, done, failed }

class DataReleaseState extends Equatable {
  const DataReleaseState({
    this.workspace,
    this.tools,
    this.git,
    this.books = const {},
    this.log = const [],
    this.running,
    this.runningJob,
    this.package = StepStatus.idle,
    this.packageResult,
    this.commit = StepStatus.idle,
    this.commitHead,
    this.build = StepStatus.idle,
    this.release,
    this.publish = StepStatus.idle,
    this.published,
    this.error,
    this.message,
  });

  final StudioWorkspace? workspace;
  final ToolsStatus? tools;
  final GitStatus? git;

  /// Workbook paths ticked for packaging.
  final Set<String> books;
  final List<String> log;

  /// Which step is running (package / commit / build / publish), null when idle.
  final String? running;
  final String? runningJob;
  final StepStatus package;
  final PackageResult? packageResult;
  final StepStatus commit;
  final String? commitHead;
  final StepStatus build;
  final ReleaseBuild? release;
  final StepStatus publish;
  final PublishResult? published;
  final String? error;
  final String? message;

  bool get busy => running != null;

  DataReleaseState copyWith({
    StudioWorkspace? workspace,
    ToolsStatus? tools,
    GitStatus? git,
    Set<String>? books,
    List<String>? log,
    String? Function()? running,
    String? Function()? runningJob,
    StepStatus? package,
    PackageResult? Function()? packageResult,
    StepStatus? commit,
    String? Function()? commitHead,
    StepStatus? build,
    ReleaseBuild? Function()? release,
    StepStatus? publish,
    PublishResult? Function()? published,
    String? Function()? error,
    String? Function()? message,
  }) => DataReleaseState(
    workspace: workspace ?? this.workspace,
    tools: tools ?? this.tools,
    git: git ?? this.git,
    books: books ?? this.books,
    log: log ?? this.log,
    running: running != null ? running() : this.running,
    runningJob: runningJob != null ? runningJob() : this.runningJob,
    package: package ?? this.package,
    packageResult: packageResult != null ? packageResult() : this.packageResult,
    commit: commit ?? this.commit,
    commitHead: commitHead != null ? commitHead() : this.commitHead,
    build: build ?? this.build,
    release: release != null ? release() : this.release,
    publish: publish ?? this.publish,
    published: published != null ? published() : this.published,
    error: error != null ? error() : null,
    message: message != null ? message() : null,
  );

  @override
  List<Object?> get props => [
    workspace, tools, git, books, log, running, runningJob, package, packageResult, commit, commitHead, build,
    release, publish, published, error, message,
  ];
}

/// The data release, step by step: package the workbooks into data/, commit + push data/ (images go live on the
/// CDN), build the release files, create the GitHub release - all in the data repo from Settings -> Publishing.
class DataReleaseCubit extends Cubit<DataReleaseState> {
  DataReleaseCubit({required StudioRepository repository, required JobCenter jobs, required AppSettings settings})
    : _repo = repository,
      _jobs = jobs,
      _settings = settings,
      super(const DataReleaseState());

  final StudioRepository _repo;
  final JobCenter _jobs;
  final AppSettings _settings;

  String get repoDir => _settings.toolsDir;
  String get dataDir => _join(repoDir, 'data');
  String get releaseRoot => _join(repoDir, '_release');
  PublishingConstants get pub => _settings.publishing;

  static String _join(String a, String b) => a.endsWith('/') || a.endsWith('\\') ? '$a$b' : '$a/$b';

  Future<void> load() async {
    final ws = (await _repo.workspace()).valueOrNull;
    final tools = (await _repo.tools()).valueOrNull;
    final git = (await _repo.gitStatus(repoDir)).valueOrNull;
    final books = {
      for (final h in ws?.hobbies ?? const <Hobby>[])
        if (h.packaged)
          for (final w in h.workbooks)
            if (w.exists) w.path,
    };
    emit(state.copyWith(workspace: ws, tools: tools, git: git, books: state.books.isEmpty ? books : null));
  }

  Future<void> refreshGit() async {
    final git = (await _repo.gitStatus(repoDir)).valueOrNull;
    if (git != null) emit(state.copyWith(git: git));
  }

  /// Tells git who commits in the data repo (repo-local) -> an error message, or null.
  Future<String?> setGitIdentity(String name, String email) async {
    final res = await _repo.setGitIdentity(repoDir, name: name, email: email);
    return res.fold((f) => f.message, (g) {
      emit(state.copyWith(git: g));
      return null;
    });
  }

  void toggleBook(String path) {
    final b = {...state.books};
    b.contains(path) ? b.remove(path) : b.add(path);
    emit(state.copyWith(books: b));
  }

  void clearLog() => emit(state.copyWith(log: const []));

  Future<T?> _job<T>(
    String step,
    Future<Result<String>> Function() start,
    T Function(Object? result) parse,
    DataReleaseState Function(StepStatus s, T? v) apply,
  ) async {
    if (state.busy) return null;
    emit(apply(StepStatus.running, null).copyWith(
      running: () => step,
      log: [...state.log, '', '── $step ──'],
    ));
    final lines = <String>[];
    var flushed = 0;
    final res = await _jobs.run(start, (l) {
      lines.add(l);
      // keep the UI responsive: emit in batches
      if (lines.length - flushed >= 5 || l.startsWith('ERROR')) {
        emit(state.copyWith(log: [...state.log, ...lines.sublist(flushed)]));
        flushed = lines.length;
      }
    });
    emit(state.copyWith(log: [...state.log, ...lines.sublist(flushed)]));
    switch (res) {
      case Err(:final failure):
        emit(apply(StepStatus.failed, null).copyWith(running: () => null, error: () => failure.message));
        return null;
      case Ok(value: final e):
        if (!e.ok) {
          emit(apply(StepStatus.failed, null).copyWith(running: () => null, error: () => e.error ?? '$step failed'));
          return null;
        }
        final v = parse(e.result);
        emit(apply(StepStatus.done, v).copyWith(running: () => null));
        return v;
    }
  }

  Future<PackageResult?> package() => _job<PackageResult>(
    'Package',
    () => _repo.package(
      books: state.books.toList(),
      out: dataDir,
      owner: pub.owner,
      repo: pub.dataRepo,
      branch: pub.dataBranch,
    ),
    _packageFrom,
    (s, v) => state.copyWith(package: s, packageResult: () => v ?? (s == StepStatus.running ? null : state.packageResult)),
  ).then((v) async {
    await refreshGit();
    return v;
  });

  Future<String?> commitPush(String message, {bool push = true}) => _job<String>(
    push ? 'Commit and push data/' : 'Commit data/',
    () => _repo.commitPush(repo: repoDir, message: message, push: push),
    (r) => '${(r as Map?)?['head'] ?? ''}',
    (s, v) => state.copyWith(commit: s, commitHead: () => v ?? state.commitHead),
  ).then((v) async {
    await refreshGit();
    return v;
  });

  Future<ReleaseBuild?> buildRelease(String tag, {bool dropInvalid = false, String? appAssets}) => _job<ReleaseBuild>(
    'Build release files',
    () => _repo.buildRelease(
      data: dataDir,
      out: releaseRoot,
      tag: tag,
      owner: pub.owner,
      repo: pub.dataRepo,
      dropInvalid: dropInvalid,
      appAssets: appAssets,
    ),
    _releaseFrom,
    (s, v) => state.copyWith(build: s, release: () => v ?? (s == StepStatus.running ? null : state.release)),
  );

  Future<PublishResult?> publish({String? title, String? notes, bool latest = true}) async {
    final r = state.release;
    if (r == null) return null;
    return _job<PublishResult>(
      'Create the GitHub release',
      () => _repo.publishRelease(
        slug: pub.dataRepoSlug,
        tag: r.tag,
        files: r.files,
        title: title,
        notes: notes,
        latest: latest,
      ),
      publishFrom,
      (s, v) => state.copyWith(publish: s, published: () => v ?? state.published),
    );
  }

  Future<void> stop() async {
    final id = _jobs.running.lastOrNull;
    if (id != null) await _jobs.stop(id);
  }

  static PackageResult _packageFrom(Object? r) {
    final j = Map<String, dynamic>.from(r as Map);
    List<CheckItem> items(Object? v) => [
      for (final e in (v as List? ?? const []))
        CheckItem(sheet: '${(e as Map)['sheet']}', id: e['id'] as String?, message: '${e['message']}'),
    ];
    return PackageResult(
      out: '${j['out']}',
      ok: j['ok'] == true,
      errors: items(j['errors']),
      warnings: items(j['warnings']),
      errorCount: (j['errorCount'] as num? ?? 0).toInt(),
      warningCount: (j['warningCount'] as num? ?? 0).toInt(),
      rowsPerSheet: {
        for (final e in Map<String, dynamic>.from(j['sheets'] as Map? ?? {}).entries)
          e.key: ((e.value as Map?)?['rowCount'] as num? ?? 0).toInt(),
      },
      changes: Map<String, dynamic>.from(j['changes'] as Map? ?? {}),
    );
  }

  static ReleaseBuild _releaseFrom(Object? r) {
    final j = Map<String, dynamic>.from(r as Map);
    return ReleaseBuild(
      folder: '${j['folder']}',
      manifest: Map<String, dynamic>.from(j['manifest'] as Map? ?? {}),
      files: [for (final f in (j['files'] as List? ?? const [])) '$f'],
      packs: [for (final p in (j['packs'] as List? ?? const [])) Map<String, dynamic>.from(p as Map)],
    );
  }

  static PublishResult publishFrom(Object? r) {
    final j = Map<String, dynamic>.from(r as Map);
    return PublishResult(
      created: j['created'] == true,
      url: j['url'] as String?,
      assets: [for (final a in (j['assets'] as List? ?? const [])) '$a'],
    );
  }
}
