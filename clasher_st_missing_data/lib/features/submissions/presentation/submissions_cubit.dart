import 'dart:typed_data';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failure.dart';
import '../../../core/services/data_change_notifier.dart';
import '../../missing_data/domain/entities/workbook.dart';
import '../../missing_data/domain/repositories/missing_data_repository.dart';
import '../domain/submission.dart';

class SubmissionsState extends Equatable {
  const SubmissionsState({
    this.loading = false,
    this.configured = true,
    this.items = const [],
    this.images = const {},
    this.busy = const {},
    this.error,
    this.message,
  });

  final bool loading;
  final bool configured;
  final List<Submission> items;

  /// Pictures fetched so far (id -> bytes).
  final Map<String, Uint8List> images;

  /// Submissions being applied / rejected.
  final Set<String> busy;
  final String? error;
  final String? message;

  SubmissionsState copyWith({
    bool? loading,
    bool? configured,
    List<Submission>? items,
    Map<String, Uint8List>? images,
    Set<String>? busy,
    String? Function()? error,
    String? Function()? message,
  }) =>
      SubmissionsState(
        loading: loading ?? this.loading,
        configured: configured ?? this.configured,
        items: items ?? this.items,
        images: images ?? this.images,
        busy: busy ?? this.busy,
        error: error != null ? error() : null,
        message: message != null ? message() : null,
      );

  @override
  List<Object?> get props => [loading, configured, items, images.keys.toList(), busy, error, message];
}

/// Data -> Submissions: pictures sent from the app, put on their rows (with the credit) in the open workbook.
class SubmissionsCubit extends Cubit<SubmissionsState> {
  SubmissionsCubit({
    required SubmissionsRepository repository,
    required MissingDataRepository data,
    required DataChangeNotifier changes,
  })  : _repo = repository,
        _data = data,
        _changes = changes,
        super(const SubmissionsState());

  final SubmissionsRepository _repo;
  final MissingDataRepository _data;
  final DataChangeNotifier _changes;

  Future<void> load() async {
    if (!_repo.isConfigured) {
      emit(state.copyWith(configured: false, loading: false));
      return;
    }
    emit(state.copyWith(loading: true, configured: true));
    final res = await _repo.list();
    switch (res) {
      case Err(:final failure):
        emit(state.copyWith(loading: false, error: () => failure.message));
      case Ok(value: final items):
        emit(state.copyWith(loading: false, items: items));
        for (final s in items) {
          if (isClosed) return;
          await _loadImage(s.id);
        }
    }
  }

  Future<Uint8List?> _loadImage(String id) async {
    final have = state.images[id];
    if (have != null) return have;
    final res = await _repo.image(id);
    if (isClosed) return null;
    return res.fold((_) => null, (b) {
      emit(state.copyWith(images: {...state.images, id: b}));
      return b;
    });
  }

  /// The tab of the open workbook a submission goes to (by its catalog key), or null.
  static SheetInfo? tabFor(Submission s, List<SheetInfo> sheets) {
    for (final t in sheets) {
      if (t.json == s.targetType) return t;
    }
    return null;
  }

  /// Puts the picture on its row and adds the credit to the row's credits; marks the submission applied.
  Future<void> apply(Submission s, List<SheetInfo> sheets) async {
    final tab = tabFor(s, sheets);
    if (tab == null || s.isOther) return;
    emit(state.copyWith(busy: {...state.busy, s.id}));
    void done({String? error, String? message, bool remove = false}) => emit(state.copyWith(
          busy: {...state.busy}..remove(s.id),
          items: remove ? [for (final x in state.items) if (x.id != s.id) x] : null,
          error: error == null ? null : () => error,
          message: message == null ? null : () => message,
        ));

    final bytes = await _loadImage(s.id);
    if (bytes == null) return done(error: 'Couldn\'t download the picture of ${s.targetName}.');
    final put = await _data.setImage(tab.name, s.targetId, bytes, field: s.pictureField);
    if (put case Err(:final failure)) return done(error: '${tab.name} #${s.targetId}: ${failure.message}');

    final row = (await _data.row(tab.name, s.targetId)).valueOrNull;
    final before = row?.values['credits']?.toString() ?? '';
    final after = mergeCredits(before, s.creditText);
    if (after != before) {
      final upd = await _data.updateRow(tab.name, s.targetId, {'credits': after});
      if (upd case Err(:final failure)) {
        return done(error: 'Picture put on ${tab.name} #${s.targetId}, but the credit wasn\'t: ${failure.message}');
      }
    }
    _changes.notify(DataChange.rowsEdited);

    final marked = await _repo.setStatus(s.id, 'applied', note: '${tab.name} #${s.targetId}');
    final where = '${tab.name} #${s.targetId}';
    return marked.fold(
      (f) => done(
        remove: true,
        error: 'Put on $where - save the workbook to keep it. It couldn\'t be marked applied in the sheet: '
            '${f.message}',
      ),
      (_) => done(remove: true, message: 'Put on $where with credit "${s.creditText}" - save the workbook to keep it.'),
    );
  }

  /// Not used (blurry, wrong part, not theirs ...).
  Future<void> reject(Submission s, {String note = ''}) => _mark(s, 'rejected', note, 'Rejected');

  /// For "other" submissions handled by hand.
  Future<void> markApplied(Submission s) => _mark(s, 'applied', 'by hand', 'Marked applied');

  Future<void> _mark(Submission s, String status, String note, String verb) async {
    emit(state.copyWith(busy: {...state.busy, s.id}));
    final res = await _repo.setStatus(s.id, status, note: note);
    emit(res.fold(
      (f) => state.copyWith(busy: {...state.busy}..remove(s.id), error: () => f.message),
      (_) => state.copyWith(
        busy: {...state.busy}..remove(s.id),
        items: [for (final x in state.items) if (x.id != s.id) x],
        message: () => '$verb: ${s.targetName.isEmpty ? s.note : s.targetName}',
      ),
    ));
  }
}
