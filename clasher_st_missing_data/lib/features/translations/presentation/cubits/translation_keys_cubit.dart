import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/translation_models.dart';
import '../../domain/repositories/translation_repository.dart';
import 'translation_cubit.dart';

class TranslationKeysState extends Equatable {
  const TranslationKeysState({
    this.rows = const [],
    this.total = 0,
    this.query = '',
    this.status,
    this.missingIn,
    this.selected,
    this.loading = false,
    this.error,
  });

  final List<TrKeyRow> rows;
  final int total;
  final String query;

  /// One of TrStatus, or null for all.
  final String? status;

  /// Only keys not yet translated into this language column.
  final String? missingIn;
  final String? selected;
  final bool loading;
  final String? error;

  TrKeyRow? get selectedRow => rows.where((r) => r.key == selected).firstOrNull;

  TranslationKeysState copyWith({
    List<TrKeyRow>? rows,
    int? total,
    String? query,
    String? Function()? status,
    String? Function()? missingIn,
    String? Function()? selected,
    bool? loading,
    String? Function()? error,
  }) => TranslationKeysState(
    rows: rows ?? this.rows,
    total: total ?? this.total,
    query: query ?? this.query,
    status: status != null ? status() : this.status,
    missingIn: missingIn != null ? missingIn() : this.missingIn,
    selected: selected != null ? selected() : this.selected,
    loading: loading ?? this.loading,
    error: error != null ? error() : this.error,
  );

  @override
  List<Object?> get props => [
    rows,
    total,
    query,
    status,
    missingIn,
    selected,
    loading,
    error,
  ];
}

/// The keys table: search, filters, the selected key. Reloads whenever the translation project changes.
class TranslationKeysCubit extends Cubit<TranslationKeysState> {
  TranslationKeysCubit({
    required TranslationRepository repository,
    required TranslationCubit workspace,
  }) : _repo = repository,
       super(const TranslationKeysState()) {
    _sub = workspace.stream
        .map((s) => s.revision)
        .distinct()
        .listen((_) => load());
    if (workspace.state.isOpen) load();
  }

  final TranslationRepository _repo;
  late final StreamSubscription<int> _sub;
  Timer? _debounce;

  Future<void> load() async {
    emit(state.copyWith(loading: true));
    final res = await _repo.keys(
      query: state.query,
      status: state.status,
      missingIn: state.missingIn,
    );
    res.fold(
      (f) => emit(state.copyWith(loading: false, error: () => f.message)),
      (p) => emit(
        state.copyWith(
          loading: false,
          rows: p.rows,
          total: p.total,
          error: () => null,
        ),
      ),
    );
  }

  void search(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      emit(state.copyWith(query: q));
      load();
    });
  }

  void filterStatus(String? s) {
    emit(state.copyWith(status: () => s));
    load();
  }

  void filterMissingIn(String? column) {
    emit(state.copyWith(missingIn: () => column));
    load();
  }

  void select(String? key) => emit(state.copyWith(selected: () => key));

  /// Shows one key (from the issues list), clearing filters that would hide it.
  Future<void> show(String key) async {
    emit(
      state.copyWith(
        query: '',
        status: () => null,
        missingIn: () => null,
        selected: () => key,
      ),
    );
    await load();
  }

  @override
  Future<void> close() async {
    _debounce?.cancel();
    await _sub.cancel();
    return super.close();
  }
}
