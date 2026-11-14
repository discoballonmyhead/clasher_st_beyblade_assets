import 'dart:math';

/// Random picks for decks. Generic so it has no project imports: callers
/// hand it a list of whatever they're choosing from (saved combos, combo
/// ids, saved decks) and get the same type back.
///
/// The pool for random beys is the user's saved combos. Those are real,
/// already-built loadouts both screens can load today through
/// CombosCubit. Drawing from the full parts catalog instead would only
/// change what list gets passed in here, not this class or its callers.
class DeckRandomizer {
  DeckRandomizer._();

  static final Random _rng = Random();

  /// [count] different items from [pool] in random order, or null when
  /// the pool doesn't have that many. Never repeats an item, so a random
  /// deck never holds the same combo twice.
  ///
  /// Samples indices rather than shuffling a copy of the pool: constant
  /// expected work for deck-sized counts (3 or 5) and no allocation that
  /// grows with the pool, which matters when the bulk page rolls a deck
  /// for every name in a long pasted list.
  static List<T>? pickDistinct<T>(List<T> pool, int count, {Random? rng}) {
    if (count <= 0 || pool.length < count) return null;
    final r = rng ?? _rng;
    final picked = <int>{}; // insertion-ordered, so the result is too
    while (picked.length < count) {
      picked.add(r.nextInt(pool.length));
    }
    return [for (final i in picked) pool[i]];
  }

  /// One random item, or null for an empty list.
  static T? pickOne<T>(List<T> items, {Random? rng}) =>
      items.isEmpty ? null : items[(rng ?? _rng).nextInt(items.length)];
}
