import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/services/data_change_notifier.dart';
import '../../../../../core/services/file_picker_service.dart';
import '../../../../../core/settings/app_settings.dart';
import '../../../domain/usecases/workbook_usecases.dart';
import 'workbook_state.dart';

/// The open workbook: opening, saving (edits stay in memory until saved), undo, recent files.
class WorkbookCubit extends Cubit<WorkbookState> {
  WorkbookCubit({
    required OpenWorkbook open,
    required GetWorkbookSummary summary,
    required SaveWorkbook save,
    required UndoLastChange undo,
    RecoverUnsaved? recover,
    DiscardUnsaved? discard,
    required AppSettings settings,
    required FilePickerService picker,
    required DataChangeNotifier changes,
  }) : _open = open,
       _summary = summary,
       _save = save,
       _undo = undo,
       _recover = recover,
       _discard = discard,
       _settings = settings,
       _picker = picker,
       _changes = changes,
       super(WorkbookState(recent: settings.recentWorkbooks)) {
    _sub = changes.stream
        .where((c) => c != DataChange.workbookOpened && c != DataChange.saved)
        .listen((_) => refresh());
  }

  final OpenWorkbook _open;
  final GetWorkbookSummary _summary;
  final SaveWorkbook _save;
  final UndoLastChange _undo;
  final RecoverUnsaved? _recover;
  final DiscardUnsaved? _discard;
  final AppSettings _settings;
  final FilePickerService _picker;
  final DataChangeNotifier _changes;
  late final StreamSubscription<DataChange> _sub;

  Future<void> pickAndOpen() async {
    final path = await _picker.pickWorkbook();
    if (path != null) await open(path);
  }

  Future<void> open(String path) async {
    emit(state.copyWith(status: WorkbookStatus.opening));
    final res = await _open(path);
    await res.fold(
      (f) async =>
          emit(state.copyWith(status: WorkbookStatus.failed, error: f.message)),
      (summary) async {
        await _settings.addRecent(path);
        emit(
          state.copyWith(
            status: WorkbookStatus.ready,
            summary: summary,
            recent: _settings.recentWorkbooks,
          ),
        );
        _changes.notify(DataChange.workbookOpened);
      },
    );
  }

  Future<void> refresh() async {
    final res = await _summary();
    res.fold(
      (f) => emit(state.copyWith(error: f.message)),
      (s) => emit(state.copyWith(summary: s)),
    );
  }

  /// True when the workbook is saved (the close-window guard waits for this).
  Future<bool> save() async {
    if (state.summary == null || state.saving) return false;
    emit(state.copyWith(saving: true));
    final res = await _save();
    return res.fold(
      (f) {
        emit(state.copyWith(saving: false, error: f.message));
        return false;
      },
      (_) async {
        final s = (await _summary()).valueOrNull;
        emit(
          state.copyWith(
            saving: false,
            summary: s,
            message: 'Saved (a backup copy was kept)',
          ),
        );
        _changes.notify(DataChange.saved);
        return true;
      },
    );
  }

  /// Replays the edits of a session that was closed without saving.
  Future<void> recoverUnsaved() async {
    final recover = _recover;
    if (recover == null) return;
    final res = await recover();
    await res.fold((f) async => emit(state.copyWith(error: f.message)), (
      n,
    ) async {
      final s = (await _summary()).valueOrNull;
      emit(
        state.copyWith(
          summary: s,
          message: 'Recovered $n unsaved change(s) - save to keep them',
        ),
      );
      _changes.notify(DataChange.structureChanged);
    });
  }

  /// Drops them (the engine keeps the file in backups/).
  Future<void> discardUnsaved() async {
    final discard = _discard;
    if (discard == null) return;
    final res = await discard();
    await res.fold((f) async => emit(state.copyWith(error: f.message)), (
      _,
    ) async {
      final s = (await _summary()).valueOrNull;
      emit(
        state.copyWith(
          summary: s,
          message: 'Unsaved changes discarded (a copy is in backups/)',
        ),
      );
    });
  }

  /// Undo labels of steps that delete, restore or renumber rows (see the engine's undo labels).
  static final _movesIds = RegExp(
    r'^(delete \d+ row|restore \d+ deleted|empty \d+ from|renumber )',
  );

  Future<void> undo() async {
    if (state.summary == null) return;
    final res = await _undo();
    res.fold((f) => emit(state.copyWith(error: f.message)), (label) {
      emit(
        state.copyWith(
          message: label == null ? 'Nothing to undo' : 'Undid: $label',
        ),
      );
      if (label != null)
        _changes.notify(
          _movesIds.hasMatch(label) ? DataChange.idsChanged : DataChange.undone,
        );
    });
  }

  @override
  Future<void> close() async {
    await _sub.cancel();
    return super.close();
  }
}
