import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/services/data_change_notifier.dart';
import '../../../../../core/settings/app_settings.dart';
import '../../../domain/entities/row.dart';
import '../../../domain/usecases/sheet_usecases.dart';
import 'sheet_state.dart';

/// One tab: what's missing per field, the filtered/sorted rows, selection and the focused row.
class SheetCubit extends Cubit<SheetState> {
  SheetCubit({
    required AnalyzeSheet analyze,
    required ListRows listRows,
    required DataChangeNotifier changes,
    required AppSettings settings,
  }) : _analyze = analyze,
       _listRows = listRows,
       _settings = settings,
       super(
         SheetState(
           sort: RowSort.values.asNameOr(settings.rowSort, RowSort.sheet),
         ),
       ) {
    _sub = changes.stream.listen((c) {
      if (c == DataChange.workbookOpened) {
        emit(const SheetState().copyWith(sort: state.sort, generation: () => state.generation));
      } else if (c == DataChange.idsChanged && state.sheet != null) {
        emit(state.copyWith(selected: const {}, focusedId: () => null));
        refresh();
      } else if (c != DataChange.saved && state.sheet != null) {
        refresh();
      }
    });
  }

  final AnalyzeSheet _analyze;
  final ListRows _listRows;
  final AppSettings _settings;
  late final StreamSubscription<DataChange> _sub;
  Timer? _debounce;

  Future<void> selectSheet(String sheet) async {
    emit(
      SheetState(
        sheet: sheet,
        sort: state.sort,
        includeOptional: state.includeOptional,
        loading: true,
        generation: state.generation,
      ),
    );
    await refresh();
  }

  Future<void> refresh() async {
    final sheet = state.sheet;
    if (sheet == null) return;
    emit(state.copyWith(loading: true));
    final a = await _analyze(sheet, includeOptional: state.includeOptional);
    final r = await _listRows(
      sheet,
      field: state.field,
      query: state.query,
      sort: state.sort,
      includeOptional: state.includeOptional,
      generation: state.generation,
    );
    if (sheet != state.sheet) return; // tab changed meanwhile
    emit(
      state.copyWith(
        loading: false,
        analysis: a.valueOrNull,
        rows: r.valueOrNull?.rows,
        total: r.valueOrNull?.total,
        error: a.fold(
          (f) => f.message,
          (_) => r.fold((f) => f.message, (_) => null),
        ),
      ),
    );
  }

  Future<void> selectField(String? field) async {
    emit(state.copyWith(field: () => field, selected: const {}));
    await refresh();
  }

  /// Typing in the search box: waits 250 ms after the last key.
  void search(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      emit(state.copyWith(query: query));
      await refresh();
    });
  }

  Future<void> sortBy(RowSort sort) async {
    _settings.rowSort = sort.name;
    emit(state.copyWith(sort: sort));
    await refresh();
  }

  /// Shared tabs (Products, Accessories ...) list only this generation's rows; null = all.
  /// Shows [generation] only. [tabs] are the workbook's tabs of that generation: when the open tab isn't one of
  /// them, the first one opens (or none, when the workbook has no tab of that generation).
  Future<void> setGeneration(String? generation, {List<String>? tabs}) async {
    final keep = tabs == null || (state.sheet != null && tabs.contains(state.sheet));
    if (generation == state.generation && keep) return;
    if (!keep) {
      if (tabs.isEmpty) {
        emit(SheetState(sort: state.sort, includeOptional: state.includeOptional, generation: generation));
        return;
      }
      emit(state.copyWith(generation: () => generation, selected: const {}));
      await selectSheet(tabs.first);
      return;
    }
    emit(state.copyWith(generation: () => generation, selected: const {}));
    await refresh();
  }

  Future<void> toggleOptional() async {
    emit(state.copyWith(includeOptional: !state.includeOptional));
    await refresh();
  }

  void toggleSelected(String id) {
    final s = {...state.selected};
    s.contains(id) ? s.remove(id) : s.add(id);
    emit(state.copyWith(selected: s));
  }

  void selectAllListed() =>
      emit(state.copyWith(selected: {for (final r in state.rows) r.id}));

  void clearSelection() => emit(state.copyWith(selected: const {}));

  void focus(String id) => emit(state.copyWith(focusedId: () => id));

  /// Focus the next row (after the focused one) that still misses something.
  void nextGap() {
    if (state.rows.isEmpty) return;
    final start = state.rows.indexWhere((r) => r.id == state.focusedId) + 1;
    for (var i = 0; i < state.rows.length; i++) {
      final r = state.rows[(start + i) % state.rows.length];
      if (r.missing.isNotEmpty && r.id != state.focusedId) {
        focus(r.id);
        return;
      }
    }
  }

  @override
  Future<void> close() async {
    _debounce?.cancel();
    await _sub.cancel();
    return super.close();
  }
}

extension on List<RowSort> {
  RowSort asNameOr(String name, RowSort fallback) =>
      firstWhere((e) => e.name == name, orElse: () => fallback);
}
