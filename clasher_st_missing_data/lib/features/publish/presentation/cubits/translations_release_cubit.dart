import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/settings/app_settings.dart';
import '../../../studio/domain/entities/studio_models.dart';
import '../../../studio/domain/job_center.dart';
import '../../../studio/domain/repositories/studio_repository.dart';
import '../../../translations/domain/entities/translation_models.dart';
import 'data_release_cubit.dart' show DataReleaseCubit;

class TranslationsReleaseState extends Equatable {
  const TranslationsReleaseState({
    this.tools,
    this.releaseExists,
    this.log = const [],
    this.uploading = false,
    this.published,
    this.error,
  });

  final ToolsStatus? tools;

  /// Whether the translations repo already has the release tag (created on the first upload otherwise).
  final bool? releaseExists;
  final List<String> log;
  final bool uploading;
  final PublishResult? published;
  final String? error;

  TranslationsReleaseState copyWith({
    ToolsStatus? tools,
    bool? Function()? releaseExists,
    List<String>? log,
    bool? uploading,
    PublishResult? Function()? published,
    String? Function()? error,
  }) => TranslationsReleaseState(
    tools: tools ?? this.tools,
    releaseExists: releaseExists != null ? releaseExists() : this.releaseExists,
    log: log ?? this.log,
    uploading: uploading ?? this.uploading,
    published: published != null ? published() : this.published,
    error: error != null ? error() : null,
  );

  @override
  List<Object?> get props => [tools, releaseExists, log, uploading, published, error];
}

/// Uploads language packs to the translations repo's release (Settings -> Publishing: repo + tag). Packs are
/// built in the Translations section; this only publishes them.
class TranslationsReleaseCubit extends Cubit<TranslationsReleaseState> {
  TranslationsReleaseCubit({required StudioRepository repository, required JobCenter jobs, required AppSettings settings})
    : _repo = repository,
      _jobs = jobs,
      _settings = settings,
      super(const TranslationsReleaseState());

  final StudioRepository _repo;
  final JobCenter _jobs;
  final AppSettings _settings;

  PublishingConstants get pub => _settings.publishing;

  Future<void> load() async {
    final tools = (await _repo.tools()).valueOrNull;
    emit(state.copyWith(tools: tools));
    if (tools?.canPublish ?? false) {
      final rel = (await _repo.releases(pub.translationsRepoSlug)).valueOrNull;
      emit(state.copyWith(releaseExists: () => rel?.any((r) => r.tag == pub.translationsTag)));
    }
  }

  /// [packs] the files to upload (full paths).
  Future<PublishResult?> upload(List<String> packs) async {
    if (packs.isEmpty || state.uploading) return null;
    emit(state.copyWith(uploading: true, log: [...state.log, '', '── Upload ${packs.length} pack(s) ──']));
    final lines = <String>[];
    final res = await _jobs.run(
      () => _repo.publishRelease(
        slug: pub.translationsRepoSlug,
        tag: pub.translationsTag,
        files: packs,
        title: 'Language packs',
        notes: 'Language packs (lang_<code>.zip). Uploaded with Clasher Studio.',
        latest: true,
      ),
      lines.add,
    );
    final log = [...state.log, ...lines];
    switch (res) {
      case Err(:final failure):
        emit(state.copyWith(uploading: false, log: log, error: () => failure.message));
        return null;
      case Ok(value: final e):
        if (!e.ok) {
          emit(state.copyWith(uploading: false, log: log, error: () => e.error ?? 'Upload failed'));
          return null;
        }
        final r = DataReleaseCubit.publishFrom(e.result);
        emit(state.copyWith(uploading: false, log: log, published: () => r, releaseExists: () => true));
        return r;
    }
  }

  /// The packs a report says changed since the last build (or all of them).
  static List<String> packFiles(PackReport report, {bool onlyChanged = true}) => [
    for (final p in report.packs)
      if (!onlyChanged || p.changed) '${report.out}/${p.file}',
  ];
}
