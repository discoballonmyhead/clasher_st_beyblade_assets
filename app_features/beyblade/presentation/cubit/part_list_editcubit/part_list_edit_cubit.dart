import 'package:clasher_st/features/beyblade/parts_list.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/parts_list_cubit/parts_list_cubit.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum PartListEditStatus {
  /// Fetching the list named in the URL.
  loading,

  /// The form is showing (a new list, or a loaded one).
  ready,

  /// The id doesn't exist or isn't the caller's.
  notFound,

  /// Couldn't load and there is nothing to show.
  failure,

  /// One-shot outcomes: the page leaves.
  saved,
  deleted,
}

class PartListEditState extends Equatable {
  const PartListEditState({
    this.status = PartListEditStatus.loading,
    this.original,
    this.draft = const PartList(kind: PartListKind.ban),
    this.saving = false,
    this.deleting = false,
    this.error,
  });

  final PartListEditStatus status;

  /// The stored version; null for a new list.
  final PartList? original;

  /// What the form shows, including unsaved edits.
  final PartList draft;
  final bool saving;
  final bool deleting;

  /// The last failure, for a snackbar. Cleared by the next change.
  final String? error;

  bool get busy => saving || deleting;
  bool get isNew => !draft.isSaved;
  bool get dirty => original == null ? !draft.isEmpty : draft != original;
  bool get canSave =>
      status == PartListEditStatus.ready && !busy && !draft.isEmpty;

  /// [error] is not kept: leave it out to clear it.
  PartListEditState copyWith({
    PartListEditStatus? status,
    PartList? original,
    PartList? draft,
    bool? saving,
    bool? deleting,
    String? error,
  }) =>
      PartListEditState(
        status: status ?? this.status,
        original: original ?? this.original,
        draft: draft ?? this.draft,
        saving: saving ?? this.saving,
        deleting: deleting ?? this.deleting,
        error: error,
      );

  @override
  List<Object?> get props => [status, original, draft, saving, deleting, error];
}

/// The create / edit page for one saved part list. Scoped to that page's
/// route and opened by id, so the page works from a tap, a link or a web
/// refresh alike. The list page updates itself through
/// [PartListsRepository.changes]; nothing is passed back.
class PartListEditCubit extends Cubit<PartListEditState> {
  PartListEditCubit(this._repo) : super(const PartListEditState());

  final PartListsRepository _repo;
  String? _id;

  static final _uuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false);

  /// [id] null starts a new kit, of [kind] (ban list by default).
  Future<void> open(String? id, {PartListKind kind = PartListKind.ban}) async {
    _id = id;
    if (id == null) {
      emit(PartListEditState(
          status: PartListEditStatus.ready, draft: PartList(kind: kind)));
      return;
    }
    if (!_uuid.hasMatch(id)) {
      emit(const PartListEditState(status: PartListEditStatus.notFound));
      return;
    }

    // Opened from the list page: show the copy we have right away, then
    // refresh it in the background.
    final known = _repo.cached(id);
    emit(known == null
        ? const PartListEditState()
        : PartListEditState(
            status: PartListEditStatus.ready, original: known, draft: known));

    try {
      final fresh = await _repo.fetchById(id);
      if (isClosed) return;
      if (fresh == null) {
        emit(const PartListEditState(status: PartListEditStatus.notFound));
        return;
      }
      // Don't throw away edits the user already started on the cached copy.
      final keepDraft = state.status == PartListEditStatus.ready && state.dirty;
      emit(state.copyWith(
        status: PartListEditStatus.ready,
        original: fresh,
        draft: keepDraft ? state.draft : fresh,
      ));
    } catch (e) {
      if (isClosed) return;
      // Already showing the cached copy: saving will report any problem.
      if (state.status == PartListEditStatus.ready) return;
      emit(state.copyWith(
          status: PartListEditStatus.failure, error: partListsErrorMessage(e)));
    }
  }

  Future<void> retry() => open(_id);

  void rename(String name) {
    if (name == state.draft.name) return;
    emit(state.copyWith(draft: state.draft.copyWith(name: name)));
  }

  /// From the part editor (kind and parts). The name stays the field's.
  void edit(PartList list) =>
      emit(state.copyWith(draft: list.copyWith(name: state.draft.name)));

  Future<void> save() async {
    if (!state.canSave) return;
    emit(state.copyWith(saving: true));
    try {
      final saved =
          await _repo.save(state.draft.copyWith(name: state.draft.name.trim()));
      if (isClosed) return;
      emit(state.copyWith(
        status: PartListEditStatus.saved,
        original: saved,
        draft: saved,
        saving: false,
      ));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(saving: false, error: partListsErrorMessage(e)));
    }
  }

  Future<void> delete() async {
    final id = state.draft.id;
    if (id == null || state.busy) return;
    emit(state.copyWith(deleting: true));
    try {
      await _repo.delete(id);
      if (isClosed) return;
      emit(state.copyWith(status: PartListEditStatus.deleted, deleting: false));
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(deleting: false, error: partListsErrorMessage(e)));
    }
  }
}
