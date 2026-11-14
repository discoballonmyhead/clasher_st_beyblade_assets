import 'dart:async';
import 'dart:developer' as dev;
import 'dart:math' as math;

import 'package:clasher_st/core/init_injection/injection.dart';
import 'package:clasher_st/features/beyblade/data/dsrces/beyblade_ldsrc.dart';
import 'package:clasher_st/features/beyblade/data/dsrces/combo_decks_remote.dart';
import 'package:clasher_st/features/beyblade/data/models/models.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/domain/repositories/beyblade_data_repo.dart';

/// Pages of combos and decks for the Combos & Decks page and the picker.
///
/// Reads:
///   * From the account, a page at a time, when everything made on this
///     phone has been uploaded (the outbox is empty after a quick flush).
///     Each page is also saved on the phone, so deck registration and
///     offline use see it.
///   * From the phone otherwise (offline, or changes still waiting to
///     upload): the phone's copy is then the complete one. Same paging,
///     same search, marked [ItemsPage.fromDevice].
///   The first page decides; later pages follow the same source (the
///   cursor says which).
///
/// Writes go through [BeybladeDataRepo] (saved on the phone, queued for
/// the account), then a flush is started without waiting for it.
class CombosDecksRepositoryImpl implements CombosDecksRepository {
  CombosDecksRepositoryImpl({
    required CombosDecksRemoteDataSource remote,
    required BeybladeDataLocalDatasource local,
    required BeybladeDataRepo data,
  })  : _remote = remote,
        _local = local,
        _data = data;

  final CombosDecksRemoteDataSource _remote;
  final BeybladeDataLocalDatasource _local;
  final BeybladeDataRepo _data;

  static const String _devicePrefix = 'device:';
  static const Duration _flushWait = Duration(seconds: 6);

  ComboSyncOutbox? get _outbox =>
      sl.isRegistered<ComboSyncOutbox>() ? sl<ComboSyncOutbox>() : null;

  /// True when the account already has everything this phone has.
  Future<bool> _accountIsCurrent() async {
    final outbox = _outbox;
    if (outbox == null) return false; // sync not set up: the phone is it
    try {
      return await outbox.flush().timeout(_flushWait) == 0;
    } catch (_) {
      return false;
    }
  }

  void _flushLater() {
    final outbox = _outbox;
    if (outbox == null) return;
    unawaited(outbox.flush().then((_) {}, onError: (Object e) {
      dev.log('Flush after write failed (will retry): $e',
          name: 'CombosDecksRepo');
    }));
  }

  // ── COMBOS ─────────────────────────────────────────────────────────────────

  @override
  Future<ItemsPage<Combo>> combos(
      {String? cursor, String query = '', int limit = 20}) async {
    if (cursor != null && cursor.startsWith(_devicePrefix)) {
      return _deviceCombos(cursor, query, limit);
    }
    if (cursor == null && !await _accountIsCurrent()) {
      return _deviceCombos(null, query, limit);
    }
    try {
      final page =
          await _remote.combos(cursor: cursor, query: query, limit: limit);
      for (final c in page.items) {
        await _local.saveCombo(_comboModel(c));
      }
      return page;
    } catch (e) {
      // Offline on the first page: the phone's copy. On a later page the
      // caller shows "couldn't load more" and lets the user retry.
      if (cursor == null) return _deviceCombos(null, query, limit);
      rethrow;
    }
  }

  ItemsPage<Combo> _deviceCombos(String? cursor, String query, int limit) {
    final q = query.trim().toLowerCase();
    final all = _local
        .getAllSavedCombos()
        .where((m) => q.isEmpty || m.name.toLowerCase().contains(q))
        .toList()
      ..sort(_newestFirst<ComboModel>((m) => m.createdAtMillis, (m) => m.id));
    return _slice<ComboModel, Combo>(all, cursor, limit, (m) => m.toEntity());
  }

  // ── DECKS ──────────────────────────────────────────────────────────────────

  @override
  Future<ItemsPage<DeckEntry>> decks(
      {String? cursor, String query = '', int limit = 20}) async {
    if (cursor != null && cursor.startsWith(_devicePrefix)) {
      return _deviceDecks(cursor, query, limit);
    }
    if (cursor == null && !await _accountIsCurrent()) {
      return _deviceDecks(null, query, limit);
    }
    try {
      final page =
          await _remote.decks(cursor: cursor, query: query, limit: limit);
      for (final e in page.items) {
        await _local.saveDeck(DeckModel(
          id: e.deck.id,
          name: e.deck.name,
          comboIds: e.deck.comboIds,
          createdAtMillis: e.deck.createdAt.millisecondsSinceEpoch,
        ));
        for (final c in e.combos) {
          await _local.saveCombo(_comboModel(c));
        }
      }
      return page;
    } catch (e) {
      if (cursor == null) return _deviceDecks(null, query, limit);
      rethrow;
    }
  }

  ItemsPage<DeckEntry> _deviceDecks(String? cursor, String query, int limit) {
    final q = query.trim().toLowerCase();
    final combos = {
      for (final m in _local.getAllSavedCombos()) m.id: m,
    };
    final all = _local
        .getAllDecks()
        .where((m) => q.isEmpty || m.name.toLowerCase().contains(q))
        .toList()
      ..sort(_newestFirst<DeckModel>((m) => m.createdAtMillis, (m) => m.id));
    return _slice<DeckModel, DeckEntry>(all, cursor, limit, (m) {
      final live = [
        for (final id in m.comboIds)
          if (combos[id] != null) combos[id]!.toEntity(),
      ];
      return DeckEntry(
        deck: m.toEntity(),
        combos: live,
        missing: m.comboIds.length - live.length,
      );
    });
  }

  // ── WRITES ─────────────────────────────────────────────────────────────────

  @override
  Future<Combo> createCombo(String name, BeybladeLoadout loadout) async {
    final combo = await _data.createCombo(name, loadout);
    _flushLater();
    return combo;
  }

  @override
  Future<void> deleteCombo(String id) async {
    await _data.deleteCombo(id);
    _flushLater();
  }

  @override
  Future<Deck> createDeck(String name, List<String> comboIds) async {
    final deck = await _data.createDeck(name, comboIds);
    _flushLater();
    return deck;
  }

  @override
  Future<void> deleteDeck(String id) async {
    await _data.deleteDeck(id);
    _flushLater();
  }

  // ── HELPERS ────────────────────────────────────────────────────────────────

  static ComboModel _comboModel(Combo c) => ComboModel(
        id: c.id,
        name: c.name,
        loadout: c.loadout,
        createdAtMillis: c.createdAt.millisecondsSinceEpoch,
      );

  static int Function(T a, T b) _newestFirst<T>(
          int Function(T) at, String Function(T) id) =>
      (a, b) {
        final byTime = at(b).compareTo(at(a));
        return byTime != 0 ? byTime : id(b).compareTo(id(a));
      };

  /// Device paging: the cursor is the offset into the sorted list.
  static ItemsPage<R> _slice<T, R>(
      List<T> all, String? cursor, int limit, R Function(T) map) {
    final asked = cursor == null
        ? 0
        : int.tryParse(cursor.substring(_devicePrefix.length)) ?? 0;
    final start = math.max(0, math.min(asked, all.length));
    final end = math.min(start + limit, all.length);
    return ItemsPage<R>(
      items: [for (var i = start; i < end; i++) map(all[i])],
      nextCursor: end < all.length ? '$_devicePrefix$end' : null,
      total: all.length,
      fromDevice: true,
    );
  }
}
