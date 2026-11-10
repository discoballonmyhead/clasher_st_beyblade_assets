import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/settings/app_settings.dart';
import '../../../../studio/domain/entities/studio_models.dart';
import '../../../../studio/domain/repositories/studio_repository.dart';

class DataWorkspaceState extends Equatable {
  const DataWorkspaceState({this.workspace, this.hobby, this.generation, this.error});

  final StudioWorkspace? workspace;
  final String? hobby;

  /// null = every generation.
  final String? generation;
  final String? error;

  Hobby? get current => workspace?.hobby(hobby);

  DataWorkspaceState copyWith({
    StudioWorkspace? workspace,
    String? Function()? hobby,
    String? Function()? generation,
    String? Function()? error,
  }) => DataWorkspaceState(
    workspace: workspace ?? this.workspace,
    hobby: hobby != null ? hobby() : this.hobby,
    generation: generation != null ? generation() : this.generation,
    error: error != null ? error() : this.error,
  );

  @override
  List<Object?> get props => [workspace, hobby, generation, error];
}

/// Which hobby and generation the Data section shows; the workbooks each hobby has.
class DataWorkspaceCubit extends Cubit<DataWorkspaceState> {
  DataWorkspaceCubit({required StudioRepository repository, required AppSettings settings})
    : _repo = repository,
      _settings = settings,
      super(DataWorkspaceState(hobby: settings.dataHobby, generation: settings.dataGeneration));

  final StudioRepository _repo;
  final AppSettings _settings;

  Future<void> load() async {
    final res = await _repo.workspace();
    res.fold(
      (f) => emit(state.copyWith(error: () => f.message)),
      (ws) {
        final hobby = ws.hobby(state.hobby)?.name ?? ws.hobbies.firstOrNull?.name;
        final gens = ws.hobby(hobby)?.generations ?? const [];
        emit(state.copyWith(
          workspace: ws,
          hobby: () => hobby,
          generation: () => gens.contains(state.generation) ? state.generation : null,
          error: () => null,
        ));
      },
    );
  }

  /// -> the hobby's first workbook that exists (to open), or null.
  String? selectHobby(String name) {
    final h = state.workspace?.hobby(name);
    if (h == null) return null;
    _settings
      ..dataHobby = name
      ..dataGeneration = null;
    emit(state.copyWith(hobby: () => name, generation: () => null));
    return h.workbooks.where((w) => w.exists).firstOrNull?.path;
  }

  void selectGeneration(String? gen) {
    _settings.dataGeneration = gen;
    emit(state.copyWith(generation: () => gen));
  }

  /// When a workbook is opened from elsewhere (recent list, typed path), follow its hobby.
  void followWorkbook(String path) {
    final h = state.workspace?.hobbyOfWorkbook(path);
    if (h != null && h.name != state.hobby) {
      _settings.dataHobby = h.name;
      emit(state.copyWith(hobby: () => h.name, generation: () => h.generations.contains(state.generation) ? state.generation : null));
    }
  }

  Future<String?> saveHobbies(List<Hobby> hobbies) async {
    final res = await _repo.saveWorkspace(hobbies);
    return res.fold((f) => f.message, (ws) {
      emit(state.copyWith(workspace: ws));
      return null;
    });
  }
}
