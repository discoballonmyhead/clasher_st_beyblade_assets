import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../studio/domain/entities/studio_models.dart';
import '../../../studio/domain/repositories/studio_repository.dart';

class PackagingState extends Equatable {
  const PackagingState({
    this.sheets = const [],
    this.selected,
    this.draft,
    this.loading = false,
    this.saving = false,
    this.error,
    this.message,
  });

  final List<SheetProfile> sheets;
  final String? selected;

  /// Unsaved edits of the selected sheet.
  final SheetProfile? draft;
  final bool loading;
  final bool saving;
  final String? error;
  final String? message;

  SheetProfile? get current => sheets.where((s) => s.sheet == selected).firstOrNull;
  bool get dirty => draft != null && draft != current;

  PackagingState copyWith({
    List<SheetProfile>? sheets,
    String? Function()? selected,
    SheetProfile? Function()? draft,
    bool? loading,
    bool? saving,
    String? Function()? error,
    String? Function()? message,
  }) => PackagingState(
    sheets: sheets ?? this.sheets,
    selected: selected != null ? selected() : this.selected,
    draft: draft != null ? draft() : this.draft,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    error: error != null ? error() : null,
    message: message != null ? message() : null,
  );

  @override
  List<Object?> get props => [sheets, selected, draft, loading, saving, error, message];
}

/// packaging_profiles.json: per JSON sheet, which columns go into the JSON and how critical each one is.
class PackagingCubit extends Cubit<PackagingState> {
  PackagingCubit(this._repo) : super(const PackagingState());

  final StudioRepository _repo;

  Future<void> load() async {
    emit(state.copyWith(loading: true));
    final res = await _repo.profiles();
    res.fold(
      (f) => emit(state.copyWith(loading: false, error: () => f.message)),
      (sheets) {
        final sel = state.selected ?? sheets.firstOrNull?.sheet;
        emit(state.copyWith(
          loading: false,
          sheets: sheets,
          selected: () => sel,
          draft: () => sheets.where((s) => s.sheet == sel).firstOrNull,
        ));
      },
    );
  }

  void select(String sheet) => emit(state.copyWith(
    selected: () => sheet,
    draft: () => state.sheets.where((s) => s.sheet == sheet).firstOrNull,
  ));

  void edit(String column, {bool? include, Criticality? criticality}) {
    final d = state.draft;
    if (d == null) return;
    emit(state.copyWith(
      draft: () => d.withColumns([
        for (final c in d.columns)
          if (c.name == column && !c.locked) c.copyWith(include: include, criticality: criticality) else c,
      ]),
    ));
  }

  void discard() => emit(state.copyWith(draft: () => state.current));

  Future<bool> save() async {
    final d = state.draft;
    if (d == null || state.saving) return false;
    emit(state.copyWith(saving: true));
    final res = await _repo.saveProfile(d.sheet, d.columns);
    return res.fold(
      (f) {
        emit(state.copyWith(saving: false, error: () => f.message));
        return false;
      },
      (saved) {
        final sheets = [for (final s in state.sheets) if (s.sheet == saved.sheet) saved else s];
        emit(state.copyWith(
          saving: false,
          sheets: sheets,
          draft: () => saved,
          message: () => '${saved.sheet}: saved - the next package uses it',
        ));
        return true;
      },
    );
  }
}
