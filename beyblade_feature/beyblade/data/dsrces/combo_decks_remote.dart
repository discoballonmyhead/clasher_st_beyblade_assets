import 'dart:developer' as dev;

import 'package:clasher_st/core/network/rpc_parser.dart';
import 'package:clasher_st/features/beyblade/data/models/models.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The account's combos and decks, a page at a time (SQL 82).
abstract class CombosDecksRemoteDataSource {
  Future<ItemsPage<Combo>> combos(
      {String? cursor, String query = '', int limit = 20});

  Future<ItemsPage<DeckEntry>> decks(
      {String? cursor, String query = '', int limit = 20});
}

class CombosDecksRemoteDataSourceImpl implements CombosDecksRemoteDataSource {
  const CombosDecksRemoteDataSourceImpl(this._client);

  final SupabaseClient _client;

  static Map<String, dynamic> _params(
          String? cursor, String query, int limit) =>
      {
        'p_limit': limit,
        'p_cursor': cursor,
        'p_search': query.trim().isEmpty ? null : query.trim(),
      };

  /// A row that doesn't parse (e.g. a combo saved with an empty loadout) is
  /// skipped rather than failing the whole page.
  static Combo? _combo(Object? raw) {
    if (raw is! Map) return null;
    try {
      return ComboModel.fromJson(Map<String, dynamic>.from(raw)).toEntity();
    } catch (e) {
      dev.log('Skipped a combo row: $e', name: 'CombosDecksRemote');
      return null;
    }
  }

  @override
  Future<ItemsPage<Combo>> combos(
      {String? cursor, String query = '', int limit = 20}) async {
    final res = await RpcParser.call(
      _client,
      'beyblade_combos_page',
      params: _params(cursor, query, limit),
      locatious: 'CombosDecksRemote.combos',
    );
    res.throwIfError();
    final raw = res.raw;
    return ItemsPage<Combo>(
      items: (raw['items'] as List? ?? const [])
          .map(_combo)
          .whereType<Combo>()
          .toList(growable: false),
      nextCursor: raw['next_cursor'] as String?,
      total: (raw['total'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<ItemsPage<DeckEntry>> decks(
      {String? cursor, String query = '', int limit = 20}) async {
    final res = await RpcParser.call(
      _client,
      'beyblade_decks_page',
      params: _params(cursor, query, limit),
      locatious: 'CombosDecksRemote.decks',
    );
    res.throwIfError();
    final raw = res.raw;
    final items = <DeckEntry>[];
    for (final r in (raw['items'] as List? ?? const [])) {
      if (r is! Map) continue;
      final row = Map<String, dynamic>.from(r);
      try {
        items.add(DeckEntry(
          deck: DeckModel.fromJson(row).toEntity(),
          combos: (row['combos'] as List? ?? const [])
              .map(_combo)
              .whereType<Combo>()
              .toList(growable: false),
          missing: (row['missing'] as num?)?.toInt() ?? 0,
        ));
      } catch (e) {
        dev.log('Skipped a deck row: $e', name: 'CombosDecksRemote');
      }
    }
    return ItemsPage<DeckEntry>(
      items: items,
      nextCursor: raw['next_cursor'] as String?,
      total: (raw['total'] as num?)?.toInt() ?? 0,
    );
  }
}
