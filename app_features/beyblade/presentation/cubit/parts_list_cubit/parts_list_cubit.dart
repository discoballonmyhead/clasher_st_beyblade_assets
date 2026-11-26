import 'dart:async';

import 'package:clasher_st/core/network/rpc_parser.dart';
import 'package:clasher_st/features/beyblade/parts_list.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// GetIt registration (wherever the other repositories/cubits are):
//
//   sl.registerLazySingleton(() => PartListsRepository(Supabase.instance.client));
//   sl.registerFactory(() => PartListsCubit(sl()));
//   sl.registerFactory(() => PartListEditCubit(sl()));

class PartListsException implements Exception {
  const PartListsException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The message to show for a failed part-list call.
String partListsErrorMessage(Object e) => switch (e) {
      PartListsException(:final message) => message,
      PostgrestException(:final message) => message,
      _ => "Couldn't reach the server. Try again.",
    };

/// A saved list was created, changed or deleted. Every cubit showing lists
/// (this page, the create-tournament "My lists") listens, so no screen has
/// to hand results back to another.
sealed class PartListChange {
  const PartListChange();
}

class PartListSaved extends PartListChange {
  const PartListSaved(this.list);
  final PartList list;
}

class PartListDeleted extends PartListChange {
  const PartListDeleted(this.id);
  final String id;
}

/// RPCs from 20_part_lists.sql. They answer with `{status, error}` like
/// the rest of the app, so anything but 200 becomes a [PartListsException]
/// carrying the server's message.
class PartListsRepository {
  PartListsRepository(this._client);

  final SupabaseClient _client;

  /// The source of truth for "a list changed". Registered as a lazy
  /// singleton, so it lives as long as the app.
  final _changes = StreamController<PartListChange>.broadcast();
  Stream<PartListChange> get changes => _changes.stream;

  /// Last known copy of each list this session, so opening one from the
  /// list page shows instantly while the fresh copy loads.
  final Map<String, PartList> _known = {};

  PartList? cached(String id) => _known[id];

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
    final lists = [
      for (final item in res['items'] as List)
        PartList.fromJson(Map<String, dynamic>.from(item as Map)),
    ];
    for (final l in lists) {
      if (l.id != null) _known[l.id!] = l;
    }
    return lists;
  }

  /// One of the caller's lists (SQL 84), or null when it doesn't exist or
  /// isn't theirs.
  Future<PartList?> fetchById(String id) async {
    final res = await RpcParser.call(_client, 'inventory_get_part_list',
        params: {'p_id': id}, locatious: 'PartListsRepository.fetchById');
    if (res.isNotFound) {
      _known.remove(id);
      return null;
    }
    if (!res.isSuccess) {
      throw PartListsException(res.message ?? 'Something went wrong.');
    }
    final item = res.raw['item'];
    if (item is! Map) return null;
    final list = PartList.fromJson(Map<String, dynamic>.from(item));
    _known[id] = list;
    return list;
  }

  /// Creates the list when [PartList.id] is null, otherwise updates it.
  /// Returns the stored version (canonical ids, server timestamps).
  Future<PartList> save(PartList list) async {
    final res = _ok(await _client.rpc('inventory_save_part_list', params: {
      'p_name': list.name,
      'p_kind': list.kind.toJson(),
      'p_parts': list.partsJson,
      'p_id': list.id,
      // Deck kits (sql/93); ignored for the other kinds.
      if (list.kind == PartListKind.deck) 'p_decks': list.decksJson,
    }));
    final saved =
        PartList.fromJson(Map<String, dynamic>.from(res['item'] as Map));
    if (saved.id != null) _known[saved.id!] = saved;
    _changes.add(PartListSaved(saved));
    return saved;
  }

  Future<void> delete(String id) async {
    _ok(await _client.rpc('inventory_delete_part_list', params: {'p_id': id}));
    _known.remove(id);
    _changes.add(PartListDeleted(id));
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

  /// Copies an organiser kit (parts pool or deck kit) onto the tournament,
  /// or clears it when null (sql/93). Call after the format is saved: a
  /// deck kit must match the tournament's combos per blader.
  Future<void> applyOrganizerKit(String tournamentId, PartList? kit) async {
    final name = kit?.name.trim() ?? '';
    _ok(await _client.rpc('tournaments_set_organizer_kit', params: {
      'p_tournament_id': tournamentId,
      'p_kind': kit?.kind.toJson(),
      'p_parts':
          kit == null || kit.kind == PartListKind.deck ? null : kit.partsJson,
      'p_decks': kit?.kind == PartListKind.deck ? kit!.decksJson : null,
      'p_name': name.isEmpty ? null : name,
      'p_source_list_id': kit?.id,
    }));
  }

  /// The tournament's part rules and organiser kit (sql/93).
  Future<TournamentKits> kitsOf(String tournamentId) async {
    final res = _ok(await _client.rpc('tournaments_get_kits',
        params: {'p_tournament_id': tournamentId}));
    final d = Map<String, dynamic>.from((res['data'] as Map?) ?? const {});
    PartList? read(Object? v) =>
        v is Map ? PartList.fromJson(Map<String, dynamic>.from(v)) : null;
    return TournamentKits(
      partRules: read(d['part_rules']),
      organizerKit: read(d['organizer_kit']),
      combosPerPlayer: (d['combos_per_player'] as num?)?.toInt() ?? 3,
      organizerDecks: d['deck_source'] == 'organizer',
    );
  }

  /// The most-winning parts (for a ban list or a pool) from real results.
  Future<List<MetaPart>> metaParts(
      {bool yearly = false, int limit = 20}) async {
    final res = _ok(await _client.rpc('inventory_meta_picks', params: {
      'p_what': 'parts',
      'p_period': yearly ? 'yearly' : 'monthly',
      'p_limit': limit,
    }));
    return [
      for (final r in (res['data'] as List? ?? const []))
        if (r is Map)
          MetaPart(
            PartRef('${r['part_type']}', '${r['data_id']}'),
            wins: (r['wins'] as num?)?.toInt() ?? 0,
            games: (r['games'] as num?)?.toInt() ?? 0,
            winRate: (r['win_rate_pct'] as num?)?.toDouble() ?? 0,
          ),
    ];
  }

  /// The most-winning combos (to start a deck kit) from real results.
  Future<List<MetaCombo>> metaCombos(
      {bool yearly = false, int limit = 20}) async {
    final res = _ok(await _client.rpc('inventory_meta_picks', params: {
      'p_what': 'combos',
      'p_period': yearly ? 'yearly' : 'monthly',
      'p_limit': limit,
    }));
    return [
      for (final r in (res['data'] as List? ?? const []))
        if (r is Map && r['combo'] is Map)
          MetaCombo(
            KitDeck.cleanCombo(Map<String, dynamic>.from(r['combo'] as Map)),
            wins: (r['wins'] as num?)?.toInt() ?? 0,
            games: (r['games'] as num?)?.toInt() ?? 0,
            winRate: (r['win_rate_pct'] as num?)?.toDouble() ?? 0,
          ),
    ];
  }
}

/// A tournament's kits as stored on it (snapshots, not the saved kits).
class TournamentKits extends Equatable {
  const TournamentKits({
    this.partRules,
    this.organizerKit,
    this.combosPerPlayer = 3,
    this.organizerDecks = false,
  });

  final PartList? partRules;
  final PartList? organizerKit;
  final int combosPerPlayer;

  /// The format has the organiser hand out decks (Mirror Match).
  final bool organizerDecks;

  @override
  List<Object?> get props =>
      [partRules, organizerKit, combosPerPlayer, organizerDecks];
}

/// A part that wins a lot this month / year.
class MetaPart extends Equatable {
  const MetaPart(this.ref,
      {required this.wins, required this.games, required this.winRate});

  final PartRef ref;
  final int wins;
  final int games;
  final double winRate;

  @override
  List<Object?> get props => [ref, wins, games, winRate];
}

/// A combo that wins a lot this month / year.
class MetaCombo extends Equatable {
  const MetaCombo(this.combo,
      {required this.wins, required this.games, required this.winRate});

  final Map<String, String> combo;
  final int wins;
  final int games;
  final double winRate;

  @override
  List<Object?> get props => [combo, wins, games, winRate];
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
  PartListsCubit(this._repo) : super(const PartListsState()) {
    _sub = _repo.changes.listen(_apply);
  }

  final PartListsRepository _repo;
  late final StreamSubscription<PartListChange> _sub;

  static String _message(Object e) => partListsErrorMessage(e);

  /// Saved or deleted anywhere (e.g. on the edit page): update in place.
  /// Same result as this cubit's own save/delete, so applying both is safe.
  void _apply(PartListChange change) {
    final lists = switch (change) {
      PartListSaved(:final list) => [
          list,
          ...state.lists.where((l) => l.id != list.id),
        ],
      PartListDeleted(:final id) =>
        state.lists.where((l) => l.id != id).toList(),
    };
    emit(PartListsState(
      loading: state.loading,
      saving: state.saving,
      lists: lists,
      error: state.error,
    ));
  }

  @override
  Future<void> close() async {
    await _sub.cancel();
    return super.close();
  }

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
