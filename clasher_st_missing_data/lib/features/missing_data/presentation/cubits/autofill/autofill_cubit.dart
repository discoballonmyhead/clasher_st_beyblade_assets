import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/services/data_change_notifier.dart';
import '../../../domain/usecases/fill_usecases.dart';
import 'autofill_state.dart';

/// Preview of everything the engine can fill (parent rows, agreeing same-name rows, derived values);
/// the user deselects what they don't want and applies the rest.
class AutofillCubit extends Cubit<AutofillState> {
  AutofillCubit({
    required GetFillProposals proposals,
    required ApplyFillProposals apply,
    required DataChangeNotifier changes,
  })  : _proposals = proposals,
        _apply = apply,
        _changes = changes,
        super(const AutofillState());

  final GetFillProposals _proposals;
  final ApplyFillProposals _apply;
  final DataChangeNotifier _changes;

  Future<void> load(String sheet) async {
    emit(const AutofillState(loading: true));
    final res = await _proposals(sheet);
    res.fold(
      (f) => emit(AutofillState(error: f.message)),
      (list) => emit(AutofillState(proposals: list, selected: {for (var i = 0; i < list.length; i++) i})),
    );
  }

  void toggle(int index) {
    final s = {...state.selected};
    s.contains(index) ? s.remove(index) : s.add(index);
    emit(state.copyWith(selected: s));
  }

  void toggleSource(String kind) {
    final h = {...state.hiddenSources};
    h.contains(kind) ? h.remove(kind) : h.add(kind);
    emit(state.copyWith(hiddenSources: h));
  }

  void selectAll(bool on) => emit(state.copyWith(selected: on ? state.visible.toSet() : <int>{}));

  Future<int?> apply(String sheet) async {
    final items = [for (final i in state.visible) if (state.selected.contains(i)) state.proposals[i]];
    if (items.isEmpty) return 0;
    emit(state.copyWith(applying: true));
    final res = await _apply(sheet, items);
    return res.fold((f) {
      emit(state.copyWith(applying: false, error: f.message));
      return null;
    }, (n) {
      emit(state.copyWith(applying: false, applied: n));
      _changes.notify(DataChange.filled);
      return n;
    });
  }
}
