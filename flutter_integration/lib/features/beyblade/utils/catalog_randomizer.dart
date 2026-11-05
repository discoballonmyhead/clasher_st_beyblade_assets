import 'dart:math';

import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/domain/repositories/beyblade_data_repo.dart';
import 'package:equatable/equatable.dart';

// =============================================================================
// CATALOG RANDOMIZER
// -----------------------------------------------------------------------------
// Random, valid builds drawn from the part catalog instead of only from the
// user's saved combos, so a host with nothing saved can still roll decks
// for walk-ins.
//
// Rules every random build follows:
//  * One generation per build. Parts carry hobbyGeneration ("X", "Burst",
//    ...); mixing generations inside one bey makes no physical sense.
//  * Ratchet only when needed: none when the blade or the bit has an
//    integrated ratchet, otherwise one is required (same rule as the
//    builder).
//  * Separated tops (Lock Chip + Over/Metal or Main + Assist) only when the
//    generation actually has every piece for them.
//  * Optionally no part repeated across a deck (tournament rule). Variants
//    count as the same part: a recolour or a Hasbro release of a blade is
//    still that blade, so identity is parentPartId ?? dataId.
// =============================================================================

/// Which parts a random build may use. Empty sets mean "any".
class RandomBuildFilter extends Equatable {
  const RandomBuildFilter({
    this.generations = const {},
    this.manufacturers = const {},
    this.excludeIllegal = true,
    this.allowSeparated = true,
  });

  final Set<String> generations;
  final Set<String> manufacturers;

  /// Leaves out parts marked illegal. Parts with unknown legality stay in:
  /// much of the catalog is unrated, and excluding it would leave little.
  final bool excludeIllegal;

  /// Allows Lock Chip builds where the generation has them.
  final bool allowSeparated;

  bool accepts(BeybladePart p) =>
      (generations.isEmpty || generations.contains(p.hobbyGeneration)) &&
      (manufacturers.isEmpty || manufacturers.contains(p.manufacturer)) &&
      (!excludeIllegal || p.legality != WboLegality.illegal);

  RandomBuildFilter copyWith({
    Set<String>? generations,
    Set<String>? manufacturers,
    bool? excludeIllegal,
    bool? allowSeparated,
  }) =>
      RandomBuildFilter(
        generations: generations ?? this.generations,
        manufacturers: manufacturers ?? this.manufacturers,
        excludeIllegal: excludeIllegal ?? this.excludeIllegal,
        allowSeparated: allowSeparated ?? this.allowSeparated,
      );

  @override
  List<Object?> get props =>
      [generations, manufacturers, excludeIllegal, allowSeparated];
}

/// What the loaded catalog contains, for building filter chips.
class CatalogFacets extends Equatable {
  const CatalogFacets({required this.generations, required this.manufacturers});

  /// Generations that can produce at least one complete build.
  final List<String> generations;
  final List<String> manufacturers;

  @override
  List<Object?> get props => [generations, manufacturers];
}

/// Opens [RandomizerSession]s. Register as a lazy singleton; it holds no
/// catalog data itself, so it never goes stale after a catalog update.
class CatalogRandomizer {
  CatalogRandomizer(this._repo, {Random? random}) : _random = random;

  final BeybladeDataRepo _repo;
  final Random? _random;

  /// Loads every part type once (in parallel). Keep the session for as long
  /// as a screen is rolling decks; open a new one on the next screen.
  Future<RandomizerSession> openSession() async {
    final results = await Future.wait<List<BeybladePart>>([
      _repo.getAllBlades(),
      _repo.getAllRatchets(),
      _repo.getAllBits(),
      _repo.getAllLockChips(),
      _repo.getAllOverBlades(),
      _repo.getAllMetalBlades(),
      _repo.getAllMainBlades(),
      _repo.getAllAssistBlades(),
    ]);
    return RandomizerSession._(
      blades: results[0].cast<Blade>(),
      ratchets: results[1].cast<Ratchet>(),
      bits: results[2].cast<Bit>(),
      lockChips: results[3].cast<LockChip>(),
      overBlades: results[4].cast<OverBlade>(),
      metalBlades: results[5].cast<MetalBlade>(),
      mainBlades: results[6].cast<MainBlade>(),
      assistBlades: results[7].cast<AssistBlade>(),
      random: _random ?? Random(),
    );
  }
}

/// A loaded catalog that rolls builds synchronously.
class RandomizerSession {
  RandomizerSession._({
    required this.blades,
    required this.ratchets,
    required this.bits,
    required this.lockChips,
    required this.overBlades,
    required this.metalBlades,
    required this.mainBlades,
    required this.assistBlades,
    required Random random,
  }) : _random = random;

  final List<Blade> blades;
  final List<Ratchet> ratchets;
  final List<Bit> bits;
  final List<LockChip> lockChips;
  final List<OverBlade> overBlades;
  final List<MetalBlade> metalBlades;
  final List<MainBlade> mainBlades;
  final List<AssistBlade> assistBlades;
  final Random _random;

  /// How many fresh attempts a single build or a whole deck gets before
  /// giving up. Attempts are cheap (list filtering on a few hundred rows).
  static const _maxAttempts = 40;

  /// Same part for deck-uniqueness purposes: variants share their parent.
  /// Prefixed with the part type, because dataIds are only unique within
  /// a type (a blade and a bit may both be "12").
  static String familyOf(BeybladePart p) =>
      '${_typeKey(p)}:${p.parentPartId ?? p.dataId}';

  static String _typeKey(BeybladePart p) => switch (p) {
        Blade() => 'blade',
        Ratchet() => 'ratchet',
        Bit() => 'bit',
        LockChip() => 'lockChip',
        OverBlade() => 'overBlade',
        MetalBlade() => 'metalBlade',
        MainBlade() => 'mainBlade',
        AssistBlade() => 'assistBlade',
        _ => 'part',
      };

  /// The part families a saved loadout uses, so a single re-rolled slot can
  /// avoid what the deck's other slots already contain. Ids missing from
  /// the catalog still count (by id), so they're never reused either.
  Set<String> familiesOf(BeybladeLoadout l) {
    String? fam<T extends BeybladePart>(List<T> list, String type, String? id) {
      if (id == null || id.isEmpty) return null;
      for (final p in list) {
        if (p.dataId == id) return familyOf(p);
      }
      return '$type:$id';
    }

    return {
      fam(blades, 'blade', l.bladeDataId),
      fam(ratchets, 'ratchet', l.ratchetDataId),
      fam(bits, 'bit', l.bitDataId),
      fam(lockChips, 'lockChip', l.lockChipDataId),
      fam(overBlades, 'overBlade', l.overBladeDataId),
      fam(metalBlades, 'metalBlade', l.metalBladeDataId),
      fam(mainBlades, 'mainBlade', l.mainBladeDataId),
      fam(assistBlades, 'assistBlade', l.assistBladeDataId),
    }.whereType<String>().toSet();
  }

  CatalogFacets get facets {
    const any = RandomBuildFilter(excludeIllegal: false);
    final gens = <String>{
      for (final g in {for (final b in bits) b.hobbyGeneration})
        if (_canBuildIn(g, any)) g,
    };
    final makers = <String>{
      for (final list in _allLists)
        for (final p in list) p.manufacturer,
    }..removeWhere((m) => m.trim().isEmpty);
    return CatalogFacets(
      generations: gens.toList()..sort(),
      manufacturers: makers.toList()..sort(),
    );
  }

  List<List<BeybladePart>> get _allLists => [
        blades,
        ratchets,
        bits,
        lockChips,
        overBlades,
        metalBlades,
        mainBlades,
        assistBlades,
      ];

  /// One random build, or null when the filter leaves nothing buildable.
  /// [usedFamilies] (deck uniqueness) is read, and updated on success.
  BeybladeLoadout? build(RandomBuildFilter filter,
      {Set<String>? usedFamilies}) {
    final gens = _buildableGenerations(filter);
    if (gens.isEmpty) return null;
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      final gen = gens[_random.nextInt(gens.length)];
      final result = _tryBuild(gen, filter, usedFamilies ?? const {});
      if (result != null) {
        usedFamilies?.addAll(result.families);
        return result.loadout;
      }
    }
    return null;
  }

  /// [count] builds. With [uniqueParts], no part (variants included) appears
  /// twice in the deck. Null when no such deck can be found.
  List<BeybladeLoadout>? deck(
    int count,
    RandomBuildFilter filter, {
    bool uniqueParts = true,
  }) {
    if (count <= 0) return const [];
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      final used = uniqueParts ? <String>{} : null;
      final out = <BeybladeLoadout>[];
      for (var i = 0; i < count; i++) {
        final b = build(filter, usedFamilies: used);
        if (b == null) break;
        out.add(b);
      }
      if (out.length == count) return out;
    }
    return null;
  }

  /// One random part of type [T] that passes [filter] and isn't in [used],
  /// for filling a single builder slot. Null when none qualifies.
  T? randomPart<T extends BeybladePart>(
    List<T> pool,
    RandomBuildFilter filter, {
    String? generation,
    Set<String> used = const {},
  }) {
    final ok = [
      for (final p in pool)
        if (filter.accepts(p) &&
            (generation == null || p.hobbyGeneration == generation) &&
            !used.contains(familyOf(p)))
          p,
    ];
    return ok.isEmpty ? null : ok[_random.nextInt(ok.length)];
  }

  // ── internals ───────────────────────────────────────────────────────────

  List<String> _buildableGenerations(RandomBuildFilter filter) {
    final gens = <String>{
      for (final b in bits)
        if (filter.accepts(b)) b.hobbyGeneration,
    };
    return [
      for (final g in gens)
        if (_canBuildIn(g, filter)) g,
    ];
  }

  bool _canBuildIn(String gen, RandomBuildFilter f) {
    bool any<T extends BeybladePart>(List<T> l) =>
        l.any((p) => p.hobbyGeneration == gen && f.accepts(p));
    if (!any(bits)) return false;
    final hasUnibody = any(blades);
    if (!hasUnibody && !_separatedPossible(gen, f)) return false;
    // A build needs a ratchet unless something integrates one.
    final hasRatchets = any(ratchets);
    final integrated = bits.any((b) =>
            b.hobbyGeneration == gen &&
            f.accepts(b) &&
            b.hasIntegratedRatchet) ||
        blades.any((b) =>
            b.hobbyGeneration == gen && f.accepts(b) && b.hasIntegratedRatchet);
    return hasRatchets || integrated;
  }

  bool _has<T extends BeybladePart>(
          List<T> l, String gen, RandomBuildFilter f) =>
      l.any((p) => p.hobbyGeneration == gen && f.accepts(p));

  bool _mainPossible(String gen, RandomBuildFilter f) =>
      _has(mainBlades, gen, f);

  bool _overMetalPossible(String gen, RandomBuildFilter f) =>
      _has(overBlades, gen, f) && _has(metalBlades, gen, f);

  bool _separatedPossible(String gen, RandomBuildFilter f) =>
      f.allowSeparated &&
      _has(lockChips, gen, f) &&
      _has(assistBlades, gen, f) &&
      (_mainPossible(gen, f) || _overMetalPossible(gen, f));

  _Rolled? _tryBuild(String gen, RandomBuildFilter f, Set<String> used) {
    final families = <String>{};
    bool fresh(BeybladePart p) =>
        !used.contains(familyOf(p)) && !families.contains(familyOf(p));
    T? pick<T extends BeybladePart>(List<T> pool,
        [bool Function(T part)? allowed]) {
      final ok = [
        for (final p in pool)
          if (p.hobbyGeneration == gen &&
              f.accepts(p) &&
              fresh(p) &&
              (allowed == null || allowed(p)))
            p,
      ];
      if (ok.isEmpty) return null;
      final chosen = ok[_random.nextInt(ok.length)];
      families.add(familyOf(chosen));
      return chosen;
    }

    // Choose the top shape, weighted by how many tops of each shape exist.
    final uniCount =
        blades.where((b) => b.hobbyGeneration == gen && f.accepts(b)).length;
    // Only counts separated tops when a complete one can actually be made.
    final sepCount = _separatedPossible(gen, f)
        ? lockChips
            .where((b) => b.hobbyGeneration == gen && f.accepts(b))
            .length
        : 0;
    if (uniCount + sepCount == 0) return null;
    final separated = _random.nextInt(uniCount + sepCount) >= uniCount;

    final bit = pick(bits);
    if (bit == null) return null;

    String? bladeId, lockId, overId, metalId, mainId, assistId;
    var integrated = bit.hasIntegratedRatchet;
    // The blade (single) or assist blade (lock chip build) may only fit a
    // simple ratchet; then only simple ratchets are rolled.
    var needsSimple = false;

    if (!separated) {
      // Never two built-in ratchets on one bey (blade + bit).
      final blade =
          pick(blades, (Blade b) => !integratedRatchetConflict(b, bit));
      if (blade == null) return null;
      bladeId = blade.dataId;
      integrated = integrated || blade.hasIntegratedRatchet;
      needsSimple = blade.requiresSimpleRatchet;
    } else {
      final lock = pick(lockChips);
      final assist = pick(assistBlades);
      if (lock == null || assist == null) return null;
      lockId = lock.dataId;
      assistId = assist.dataId;
      needsSimple = assist.requiresSimpleRatchet;
      final mainOk = _mainPossible(gen, f);
      final overMetalOk = _overMetalPossible(gen, f);
      final useMain = mainOk && (!overMetalOk || _random.nextBool());
      if (useMain) {
        final main = pick(mainBlades);
        if (main == null) return null;
        mainId = main.dataId;
      } else {
        final over = pick(overBlades);
        final metal = pick(metalBlades);
        if (over == null || metal == null) return null;
        overId = over.dataId;
        metalId = metal.dataId;
      }
    }

    String? ratchetId;
    if (!integrated) {
      final ratchet =
          pick(ratchets, (Ratchet r) => !needsSimple || r.isSimple);
      if (ratchet == null) return null; // no simple ratchet left: next try
      ratchetId = ratchet.dataId;
    }

    return _Rolled(
      BeybladeLoadout(
        bladeDataId: bladeId,
        ratchetDataId: ratchetId,
        bitDataId: bit.dataId,
        lockChipDataId: lockId,
        overBladeDataId: overId,
        metalBladeDataId: metalId,
        mainBladeDataId: mainId,
        assistBladeDataId: assistId,
      ),
      families,
    );
  }
}

class _Rolled {
  const _Rolled(this.loadout, this.families);
  final BeybladeLoadout loadout;
  final Set<String> families;
}
