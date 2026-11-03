import 'package:supabase_flutter/supabase_flutter.dart';

class TournamentStadiumException implements Exception {
  const TournamentStadiumException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The optional stadium of a tournament: an Accessory dataId from the parts
/// catalog (accessoryType Stadium), or null for "not specified".
///
/// RPCs from flutter_integration/sql/21_tournament_stadium.sql. They answer
/// `{status, error}` like the rest of the app. Kept apart from
/// CreateTournamentRequest so the create RPC doesn't change: the page sets
/// the stadium right after the tournament is created, like the prizes.
class TournamentStadiumRepository {
  TournamentStadiumRepository(this._client);

  final SupabaseClient _client;

  /// Tournament id -> stadium dataId (null = none). The detail page asks on
  /// every rebuild; this answers from memory after the first time.
  final Map<String, String?> _cache = {};

  Map<String, dynamic> _ok(dynamic response) {
    final map = Map<String, dynamic>.from(response as Map);
    if (map['status'] != 200) {
      throw TournamentStadiumException(
          map['error']?.toString() ?? 'Something went wrong.');
    }
    return map;
  }

  /// Sets or clears (null) the stadium. Host only.
  Future<void> setStadium(String tournamentId, String? stadiumDataId) async {
    _ok(await _client.rpc('tournaments_set_stadium', params: {
      'p_tournament_id': tournamentId,
      'p_stadium_data_id': stadiumDataId,
    }));
    _cache[tournamentId] = stadiumDataId;
  }

  Future<String?> getStadium(String tournamentId, {bool refresh = false}) async {
    if (!refresh && _cache.containsKey(tournamentId)) {
      return _cache[tournamentId];
    }
    final res = _ok(await _client.rpc('tournaments_get_stadium',
        params: {'p_tournament_id': tournamentId}));
    final id = (res['stadium_data_id'] as String?)?.trim();
    return _cache[tournamentId] = (id == null || id.isEmpty) ? null : id;
  }
}
