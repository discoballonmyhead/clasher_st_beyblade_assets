import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/settings/app_settings.dart';
import '../../../studio/domain/entities/studio_models.dart';
import '../../../studio/domain/repositories/studio_repository.dart';

class HistoryState extends Equatable {
  const HistoryState({
    this.data = const [],
    this.translations = const [],
    this.assets = const {},
    this.loading = false,
    this.error,
  });

  final List<ReleaseInfo> data;
  final List<ReleaseInfo> translations;

  /// "slug@tag" -> assets, loaded when a release is opened.
  final Map<String, List<ReleaseAsset>> assets;
  final bool loading;
  final String? error;

  HistoryState copyWith({
    List<ReleaseInfo>? data,
    List<ReleaseInfo>? translations,
    Map<String, List<ReleaseAsset>>? assets,
    bool? loading,
    String? Function()? error,
  }) => HistoryState(
    data: data ?? this.data,
    translations: translations ?? this.translations,
    assets: assets ?? this.assets,
    loading: loading ?? this.loading,
    error: error != null ? error() : this.error,
  );

  @override
  List<Object?> get props => [data, translations, assets, loading, error];
}

/// The releases on the data repo and the translations repo.
class HistoryCubit extends Cubit<HistoryState> {
  HistoryCubit({required StudioRepository repository, required AppSettings settings})
    : _repo = repository,
      _settings = settings,
      super(const HistoryState());

  final StudioRepository _repo;
  final AppSettings _settings;

  Future<void> load() async {
    emit(state.copyWith(loading: true, error: () => null, assets: const {})); // files of a tag may have changed
    final pub = _settings.publishing;
    final d = await _repo.releases(pub.dataRepoSlug);
    final t = await _repo.releases(pub.translationsRepoSlug);
    emit(state.copyWith(
      loading: false,
      data: d.valueOrNull ?? const [],
      translations: t.valueOrNull ?? const [],
      error: () => d.fold((f) => f.message, (_) => t.fold((f) => f.message, (_) => null)),
    ));
  }

  Future<void> loadAssets(String slug, String tag) async {
    final key = '$slug@$tag';
    if (state.assets.containsKey(key)) return;
    final res = await _repo.releaseAssets(slug, tag);
    res.fold(
      (f) => emit(state.copyWith(error: () => f.message)),
      (a) => emit(state.copyWith(assets: {...state.assets, key: a})),
    );
  }
}
