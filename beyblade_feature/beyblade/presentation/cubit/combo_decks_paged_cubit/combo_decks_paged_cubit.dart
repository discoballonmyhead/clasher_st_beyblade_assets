import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// State of a paged, searchable list.
class PagedState<T> extends Equatable {
  const PagedState({
    this.items = const [],
    this.loading = false,
    this.loaded = false,
    this.loadingMore = false,
    this.failed = false,
    this.moreFailed = false,
    this.nextCursor,
    this.query = '',
    this.total = 0,
    this.fromDevice = false,
  });

  final List<T> items;

  /// First page (or a new search) is on its way.
  final bool loading;

  /// At least one load finished (so an empty list means "none").
  final bool loaded;
  final bool loadingMore;

  /// The first page failed and nothing could be shown.
  final bool failed;

  /// The last "load more" failed; the list keeps what it has.
  final bool moreFailed;
  final String? nextCursor;
  final String query;
  final int total;
  final bool fromDevice;

  bool get hasMore => nextCursor != null;

  PagedState<T> copyWith({
    List<T>? items,
    bool? loading,
    bool? loaded,
    bool? loadingMore,
    bool? failed,
    bool? moreFailed,
    String? nextCursor,
    bool clearCursor = false,
    String? query,
    int? total,
    bool? fromDevice,
  }) =>
      PagedState<T>(
        items: items ?? this.items,
        loading: loading ?? this.loading,
        loaded: loaded ?? this.loaded,
        loadingMore: loadingMore ?? this.loadingMore,
        failed: failed ?? this.failed,
        moreFailed: moreFailed ?? this.moreFailed,
        nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
        query: query ?? this.query,
        total: total ?? this.total,
        fromDevice: fromDevice ?? this.fromDevice,
      );

  @override
  List<Object?> get props => [
        items,
        loading,
        loaded,
        loadingMore,
        failed,
        moreFailed,
        nextCursor,
        query,
        total,
        fromDevice,
      ];
}

/// Loads a list a page at a time: [load] (first page / new search),
/// [loadMore] (next page), [search]. A newer load always wins over an
/// older one still in flight.
abstract class PagedCubit<T> extends Cubit<PagedState<T>> {
  PagedCubit({this.pageSize = 20}) : super(PagedState<T>());

  final int pageSize;
  int _token = 0;

  Future<ItemsPage<T>> fetch(String? cursor, String query, int limit);

  String idOf(T item);

  Future<void> load({String? query}) async {
    final q = (query ?? state.query).trim();
    final token = ++_token;
    emit(state.copyWith(
        loading: true, failed: false, moreFailed: false, query: q));
    try {
      final page = await fetch(null, q, pageSize);
      if (isClosed || token != _token) return;
      emit(PagedState<T>(
        items: page.items,
        loaded: true,
        nextCursor: page.nextCursor,
        query: q,
        total: page.total,
        fromDevice: page.fromDevice,
      ));
    } catch (_) {
      if (isClosed || token != _token) return;
      emit(state.copyWith(loading: false, loaded: true, failed: true));
    }
  }

  Future<void> loadMore() async {
    final cursor = state.nextCursor;
    if (state.loading || state.loadingMore || cursor == null) return;
    final token = _token;
    emit(state.copyWith(loadingMore: true, moreFailed: false));
    try {
      final page = await fetch(cursor, state.query, pageSize);
      if (isClosed || token != _token) return;
      final seen = {for (final i in state.items) idOf(i)};
      emit(state.copyWith(
        items: [
          ...state.items,
          ...page.items.where((i) => !seen.contains(idOf(i))),
        ],
        loadingMore: false,
        nextCursor: page.nextCursor,
        clearCursor: page.nextCursor == null,
        total: page.total,
      ));
    } catch (_) {
      if (isClosed || token != _token) return;
      emit(state.copyWith(loadingMore: false, moreFailed: true));
    }
  }

  void search(String query) {
    if (query.trim() == state.query) return;
    load(query: query);
  }

  /// Puts a new item on top right away (it's the newest).
  void addFirst(T item) {
    final id = idOf(item);
    emit(state.copyWith(
      items: [item, ...state.items.where((i) => idOf(i) != id)],
      total: state.total + 1,
    ));
  }

  /// Takes an item out right away; returns it (for putting it back).
  T? removeById(String id) {
    T? removed;
    final kept = <T>[];
    for (final i in state.items) {
      if (idOf(i) == id) {
        removed = i;
      } else {
        kept.add(i);
      }
    }
    if (removed == null) return null;
    emit(state.copyWith(
        items: kept, total: state.total > 0 ? state.total - 1 : 0));
    return removed;
  }
}

// ── Combos tab ───────────────────────────────────────────────────────────────

class CombosPageCubit extends PagedCubit<Combo> {
  CombosPageCubit(this._repo);

  final CombosDecksRepository _repo;

  @override
  Future<ItemsPage<Combo>> fetch(String? cursor, String query, int limit) =>
      _repo.combos(cursor: cursor, query: query, limit: limit);

  @override
  String idOf(Combo item) => item.id;

  Future<Combo> create(String name, BeybladeLoadout loadout) async {
    final combo = await _repo.createCombo(name, loadout);
    if (state.query.isEmpty ||
        combo.name.toLowerCase().contains(state.query.toLowerCase())) {
      addFirst(combo);
    }
    return combo;
  }

  /// Removed from the list at once; put back if the delete fails.
  Future<bool> delete(String id) async {
    final removed = removeById(id);
    try {
      await _repo.deleteCombo(id);
      return true;
    } catch (_) {
      if (removed != null) await load();
      return false;
    }
  }
}

// ── Decks tab ────────────────────────────────────────────────────────────────

class DecksPageCubit extends PagedCubit<DeckEntry> {
  DecksPageCubit(this._repo);

  final CombosDecksRepository _repo;

  @override
  Future<ItemsPage<DeckEntry>> fetch(String? cursor, String query, int limit) =>
      _repo.decks(cursor: cursor, query: query, limit: limit);

  @override
  String idOf(DeckEntry item) => item.deck.id;

  /// [combos] in the order they were picked; that order is the deck's.
  Future<DeckEntry> create(String name, List<Combo> combos) async {
    final deck = await _repo.createDeck(name, [for (final c in combos) c.id]);
    final entry = DeckEntry(deck: deck, combos: combos);
    if (state.query.isEmpty ||
        deck.name.toLowerCase().contains(state.query.toLowerCase())) {
      addFirst(entry);
    }
    return entry;
  }

  Future<bool> delete(String id) async {
    final removed = removeById(id);
    try {
      await _repo.deleteDeck(id);
      return true;
    } catch (_) {
      if (removed != null) await load();
      return false;
    }
  }

  /// A combo was deleted on the Combos tab: decks drop it, as the server
  /// and the phone do.
  void comboDeleted(String comboId) {
    emit(state.copyWith(
        items: [for (final e in state.items) e.withoutCombo(comboId)]));
  }
}

// ── Combo picker ─────────────────────────────────────────────────────────────

/// Its own instance per picker page: nothing shared with the page behind.
class ComboPickerCubit extends PagedCubit<Combo> {
  ComboPickerCubit(this._repo);

  final CombosDecksRepository _repo;

  @override
  Future<ItemsPage<Combo>> fetch(String? cursor, String query, int limit) =>
      _repo.combos(cursor: cursor, query: query, limit: limit);

  @override
  String idOf(Combo item) => item.id;
}
