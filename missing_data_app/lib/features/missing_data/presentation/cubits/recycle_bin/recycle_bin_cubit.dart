import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../../core/services/data_change_notifier.dart';
import '../../../domain/entities/row_lifecycle.dart';
import '../../../domain/usecases/row_lifecycle_usecases.dart';

class RecycleBinState extends Equatable {
  const RecycleBinState({this.items = const [], this.loading = false, this.selected = const {}, this.message, this.error});

  final List<DeletedRow> items;
  final bool loading;

  /// Keys of the ticked entries.
  final Set<String> selected;
  final String? message;
  final String? error;

  RecycleBinState copyWith({
    List<DeletedRow>? items,
    bool? loading,
    Set<String>? selected,
    String? Function()? message,
    String? Function()? error,
  }) =>
      RecycleBinState(
        items: items ?? this.items,
        loading: loading ?? this.loading,
        selected: selected ?? this.selected,
        message: message != null ? message() : this.message,
        error: error != null ? error() : this.error,
      );

  @override
  List<Object?> get props => [items, loading, selected, message, error];
}

/// Recently deleted: rows deleted with the tool, kept with their pictures until restored or emptied.
class RecycleBinCubit extends Cubit<RecycleBinState> {
  RecycleBinCubit({
    required GetDeletedRows list,
    required RestoreDeletedRows restore,
    required PurgeDeletedRows purge,
    required DataChangeNotifier changes,
  })  : _list = list,
        _restore = restore,
        _purge = purge,
        _changes = changes,
        super(const RecycleBinState());

  final GetDeletedRows _list;
  final RestoreDeletedRows _restore;
  final PurgeDeletedRows _purge;
  final DataChangeNotifier _changes;

  Future<void> load() async {
    emit(state.copyWith(loading: true, error: () => null));
    final res = await _list();
    res.fold(
      (f) => emit(state.copyWith(loading: false, error: () => f.message)),
      (items) => emit(state.copyWith(
          loading: false, items: items, selected: {...state.selected.where((k) => items.any((i) => i.key == k))})),
    );
  }

  void toggle(String key) {
    final s = {...state.selected};
    s.contains(key) ? s.remove(key) : s.add(key);
    emit(state.copyWith(selected: s));
  }

  Future<void> restoreSelected() async {
    if (state.selected.isEmpty) return;
    final res = await _restore(state.selected.toList());
    await res.fold((f) async => emit(state.copyWith(error: () => f.message)), (rows) async {
      final text = rows
          .map((r) => '${r.sheet} #${r.id}${r.newId ? ' (#${r.oldId} was taken)' : ''}')
          .join(', ');
      emit(state.copyWith(selected: const {}, message: () => 'Restored $text - save to keep', error: () => null));
      _changes.notify(DataChange.idsChanged);
      await load();
    });
  }

  /// [all] empties recently deleted; otherwise only the ticked entries go.
  Future<void> purge({bool all = false}) async {
    if (!all && state.selected.isEmpty) return;
    final res = await _purge(keys: all ? null : state.selected.toList());
    await res.fold((f) async => emit(state.copyWith(error: () => f.message)), (n) async {
      emit(state.copyWith(
          selected: const {}, message: () => '$n removed for good - save to keep', error: () => null));
      _changes.notify(DataChange.structureChanged);
      await load();
    });
  }
}
