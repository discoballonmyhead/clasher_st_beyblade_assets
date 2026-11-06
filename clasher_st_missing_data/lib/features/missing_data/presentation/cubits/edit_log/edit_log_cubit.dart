import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/usecases/structure_usecases.dart';
import 'edit_log_state.dart';

/// The workbook's change log: everything changed with the missing data tool (this app, the Python GUI
/// or the CLI), newest first. Search and "this tab only" filter it.
class EditLogCubit extends Cubit<EditLogState> {
  EditLogCubit({required GetEditLog getLog, this.sheet})
      : _getLog = getLog,
        super(const EditLogState());

  final GetEditLog _getLog;

  /// The open tab, for "this tab only".
  final String? sheet;
  Timer? _debounce;

  Future<void> load() async {
    emit(state.copyWith(loading: true));
    final res = await _getLog(sheet: state.thisTabOnly ? sheet : null, query: state.query);
    res.fold(
      (f) => emit(state.copyWith(loading: false, error: f.message)),
      (page) => emit(state.copyWith(loading: false, entries: page.entries, total: page.total)),
    );
  }

  void search(String q) {
    emit(state.copyWith(query: q));
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), load);
  }

  void toggleThisTab() {
    emit(state.copyWith(thisTabOnly: !state.thisTabOnly));
    load();
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
