import 'package:clasher_st/features/beyblade/parts_list.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// GetIt registration (wherever the other repositories/cubits are):
//
//   sl.registerLazySingleton(() => PartListsRepository(Supabase.instance.client));
//   sl.registerFactory(() => PartListsCubit(sl()));

class PartListsException implements Exception {
  const PartListsException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// RPCs from 20_part_lists.sql. They answer with `{status, error}` like
/// the rest of the app, so anything but 200 becomes a [PartListsException]
/// carrying the server's message.
class PartListsRepository {
  PartListsRepository(this._client);

  final SupabaseClient _client;

  Map<String, dynamic> _ok(dynamic response) {
    final map = Map<String, dynamic>.from(response as Map);
    if (map['status'] != 200) {
      throw PartListsException(
          map['error']?.toString() ?? 'Something went wrong.');
    }
    return map;
  }

  Future<List<PartList>> fetchMine() async {
    final res = _ok(await _client.rpc('inventory_get_part_lists'));
    return [
      for (final item in res['items'] as List)
        PartList.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
  }

  /// Creates the list when [PartList.id] is null, otherwise updates it.
  /// Returns the stored version (canonical ids, server timestamps).
  Future<PartList> save(PartList list) async {
    final res = _ok(await _client.rpc('inventory_save_part_list', params: {
      'p_name': list.name,
      'p_kind': list.kind.toJson(),
      'p_parts': list.partsJson,
      'p_id': list.id,
    }));
    return PartList.fromJson(Map<String, dynamic>.from(res['item'] as Map));
  }

  Future<void> delete(String id) async {
    _ok(await _client.rpc('inventory_delete_part_list', params: {'p_id': id}));
  }

  /// Copies [rules] onto the tournament as a snapshot, or clears them when
  /// null. Call right after the tournament is created, next to the
  /// entry-fee call.
  Future<void> applyToTournament(String tournamentId, PartList? rules) async {
    final name = rules?.name.trim() ?? '';
    _ok(await _client.rpc('tournaments_set_part_rules', params: {
      'p_tournament_id': tournamentId,
      'p_kind': rules?.kind.toJson(),
      'p_parts': rules?.partsJson,
      'p_name': name.isEmpty ? null : name,
      'p_source_list_id': rules?.id,
    }));
  }
}

class PartListsState extends Equatable {
  const PartListsState({
    this.loading = false,
    this.saving = false,
    this.lists = const [],
    this.error,
  });

  final bool loading;
  final bool saving;
  final List<PartList> lists;
  final String? error;

  @override
  List<Object?> get props => [loading, saving, lists, error];
}

class PartListsCubit extends Cubit<PartListsState> {
  PartListsCubit(this._repo) : super(const PartListsState());

  final PartListsRepository _repo;

  static String _message(Object e) => switch (e) {
        PartListsException(:final message) => message,
        PostgrestException(:final message) => message,
        _ => "Couldn't reach the server. Try again.",
      };

  Future<void> load() async {
    emit(PartListsState(loading: true, lists: state.lists));
    try {
      emit(PartListsState(lists: await _repo.fetchMine()));
    } catch (e) {
      emit(PartListsState(lists: state.lists, error: _message(e)));
    }
  }

  /// The saved list on success; null on failure, with the reason in
  /// [PartListsState.error].
  Future<PartList?> save(PartList list) async {
    emit(PartListsState(saving: true, lists: state.lists));
    try {
      final saved = await _repo.save(list);
      emit(PartListsState(lists: [
        saved,
        ...state.lists.where((l) => l.id != saved.id),
      ]));
      return saved;
    } catch (e) {
      emit(PartListsState(lists: state.lists, error: _message(e)));
      return null;
    }
  }

  Future<bool> delete(String id) async {
    try {
      await _repo.delete(id);
      emit(
          PartListsState(lists: state.lists.where((l) => l.id != id).toList()));
      return true;
    } catch (e) {
      emit(PartListsState(lists: state.lists, error: _message(e)));
      return false;
    }
  }
}
