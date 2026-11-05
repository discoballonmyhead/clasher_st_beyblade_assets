import 'dart:convert';

import 'package:equatable/equatable.dart';

// Consolidated domain entities — one file on request. Sectioned with
// banners. Comments kept minimal by request; see prior turns in this
// project's history for the fuller reasoning behind each design choice.

// ── SPIN DIRECTION ──────────────────────────────────────────────
enum SpinDirection {
  left,
  right,
  unknown;

  static SpinDirection parse(dynamic raw) {
    if (raw == null) return SpinDirection.unknown;
    final s = raw.toString().trim().toLowerCase();
    if (s == 'left' || s == 'l') return SpinDirection.left;
    if (s == 'right' || s == 'r') return SpinDirection.right;
    return SpinDirection.unknown;
  }
}

// ── WBO LEGALITY ────────────────────────────────────────────────
enum WboLegality {
  legal,
  illegal,
  unknown;

  static WboLegality parse(dynamic raw) {
    if (raw == null) return WboLegality.unknown;
    final s = raw.toString().trim().toLowerCase();
    if (s.isEmpty) return WboLegality.unknown;
    if (s == 'true' || s == '1' || s == 'yes' || s == 'legal') {
      return WboLegality.legal;
    }

    if (s == 'false' || s == '0' || s == 'no' || s == 'illegal') {
      return WboLegality.illegal;
    }

    return WboLegality.unknown;
  }
}

// ── BEYBLADE ARCHETYPE ──────────────────────────────────────────
/// Shared vocabulary across every `type`/`movementStyle` column
/// (Blade.archetype, Bit.movementStyle, and the over/metal/main/assist
/// blade `type` columns — all Beyblade X part-type columns use the same
/// attack/defense/stamina/balance set).
enum BeybladeArchetype {
  attack,
  defense,
  stamina,
  balance,
  unknown;

  static BeybladeArchetype parse(dynamic raw) {
    if (raw == null) return BeybladeArchetype.unknown;
    final s = raw.toString().trim().toLowerCase();
    return switch (s) {
      'attack' || 'a' => BeybladeArchetype.attack,
      'defense' || 'd' => BeybladeArchetype.defense,
      'stamina' || 's' => BeybladeArchetype.stamina,
      'balance' || 'b' => BeybladeArchetype.balance,
      _ => BeybladeArchetype.unknown,
    };
  }
}

// ── STAT KEY / SPREAD / BLOCK ───────────────────────────────────
enum StatKey { attack, defense, stamina, dash, burstResistance }

/// A single stat's value(s) — most parts report one number, two-stat
/// bits report a pair (e.g. "30-55").
class StatSpread extends Equatable {
  const StatSpread._(this.primary, this.secondary);

  static const StatSpread notProvided = StatSpread._(null, null);
  factory StatSpread.single(double value) => StatSpread._(value, null);
  factory StatSpread.dual(double a, double b) => StatSpread._(a, b);

  final double? primary;
  final double? secondary;

  bool get isProvided => primary != null;
  bool get isTwoStat => isProvided && secondary != null;
  List<double> get values =>
      isProvided ? [primary!, if (secondary != null) secondary!] : const [];

  static StatSpread parse(dynamic raw) {
    if (raw == null) return notProvided;
    final s = raw.toString().trim();
    if (s.isEmpty) return notProvided;
    if (s.contains('-')) {
      final parts = s.split('-');
      if (parts.length == 2) {
        final a = double.tryParse(parts[0].trim());
        final b = double.tryParse(parts[1].trim());
        if (a != null && b != null) return StatSpread.dual(a, b);
      }
    }
    final v = double.tryParse(s);
    return v == null ? notProvided : StatSpread.single(v);
  }

  @override
  List<Object?> get props => [primary, secondary];
}

class StatBlock extends Equatable {
  const StatBlock(Map<StatKey, StatSpread> values) : _values = values;
  const StatBlock.empty() : _values = const {};

  final Map<StatKey, StatSpread> _values;

  StatSpread operator [](StatKey key) => _values[key] ?? StatSpread.notProvided;

  StatBlock copyWithStat(StatKey key, StatSpread value) {
    final next = Map<StatKey, StatSpread>.from(_values);
    next[key] = value;
    return StatBlock(next);
  }

  /// Merges blocks key-by-key using [combine] (defaulting absent sides
  /// to notProvided). Used to sum an arbitrary number of stat-bearing
  /// parts — see BeybladeStatsCalculator.
  static StatBlock combineAll(Iterable<StatBlock> blocks,
      StatSpread Function(StatSpread a, StatSpread b) combine) {
    var result = const StatBlock.empty();
    for (final block in blocks) {
      final merged = <StatKey, StatSpread>{};
      for (final key in StatKey.values) {
        merged[key] = combine(result[key], block[key]);
      }
      result = StatBlock(merged);
    }
    return result;
  }

  Iterable<StatKey> get providedKeys =>
      StatKey.values.where((k) => this[k].isProvided);

  @override
  List<Object?> get props => [_values];
}

// ── BEYBLADE PART (base) ────────────────────────────────────────
/// Fields every physical part shares. [stats] and [isIncomplete] are
/// abstract so any code holding a plain [BeybladePart] — search results,
/// the stats calculator, a legality badge — can read them without a type
/// switch. Parts with no real stat columns (LockChip) just report
/// [StatBlock.empty].
abstract class BeybladePart extends Equatable {
  const BeybladePart({
    required this.dataId,
    this.parentPartId,
    this.variantLabel,
    required this.manufacturer,
    required this.hobbyName,
    required this.hobbyGeneration,
    required this.code,
    required this.name,
    this.edition,
    this.imageUrl,
    this.imageHash,
    this.minifiedImageUrl,
    this.minifiedImageHash,
    required this.mass,
    required this.legality,
    required this.isIncomplete,
  });

  final String dataId;

  /// Null means this row IS the original -- the "element" in the
  /// element/isotope model. Non-null points at another row's dataId
  /// (within this same part type's collection) that this one is a
  /// variant of -- a different color, a Hasbro release, a reprint.
  final String? parentPartId;

  /// Pure display text describing what makes a variant different (e.g.
  /// "Gold Edition") -- not the relationship itself, parentPartId is.
  /// Null on an original.
  final String? variantLabel;

  /// "Takara-Tomy" or "Hasbro". Always set, on originals and variants alike.
  final String manufacturer;

  /// The overall franchise ("Beyblade") and the specific era/line within
  /// it ("X", "Burst", "Metal Fight") -- plain categorical fields, not a
  /// separate lookup entity.
  final String hobbyName;
  final String hobbyGeneration;

  final String code;
  final String name;
  final String? edition;

  final String? imageUrl;

  /// Short content hash of the image file at packaging time -- lets a
  /// consumer detect "this specific image actually changed" without
  /// comparing bytes, purely for download/cache decisions.
  final String? imageHash;

  /// A smaller, more compressed rendering of the same image, generated
  /// alongside the full one -- meant for list/thumbnail views where full
  /// resolution is wasted space. Same hash-tracking idea as imageUrl/imageHash.
  final String? minifiedImageUrl;
  final String? minifiedImageHash;

  final double mass;
  final WboLegality legality;

  /// Sheet's `incompleteData` column — true means this row's data isn't
  /// fully verified yet. Surfaced in the UI as a caution marker, not
  /// hidden or excluded.
  final bool isIncomplete;

  StatBlock get stats;

  List<Object?> get baseProps => [
        dataId,
        parentPartId,
        variantLabel,
        manufacturer,
        hobbyName,
        hobbyGeneration,
        code,
        name,
        edition,
        imageUrl,
        imageHash,
        minifiedImageUrl,
        minifiedImageHash,
        mass,
        legality,
        isIncomplete,
      ];
}

// ── BLADE (unibody) ──────────────────────────────────────────────
class Blade extends BeybladePart {
  const Blade({
    required super.dataId,
    super.parentPartId,
    super.variantLabel,
    required super.manufacturer,
    required super.hobbyName,
    required super.hobbyGeneration,
    required super.code,
    required super.name,
    super.edition,
    super.imageUrl,
    super.imageHash,
    super.minifiedImageUrl,
    super.minifiedImageHash,
    required super.mass,
    required super.legality,
    required super.isIncomplete,
    required this.archetype,
    required this.spinDirection,
    required this.stats,
    required this.hasIntegratedRatchet,
    this.requiresSimpleRatchet = false,
  });

  final BeybladeArchetype archetype;
  final SpinDirection spinDirection;
  @override
  final StatBlock stats;
  final bool hasIntegratedRatchet;

  /// Only fits a simple ratchet ([Ratchet.isSimple]): the builder and the
  /// randomizer offer nothing else. Sheet column `requiresSimpleRatchet`.
  final bool requiresSimpleRatchet;

  @override
  List<Object?> get props => [
        ...baseProps,
        archetype,
        spinDirection,
        stats,
        hasIntegratedRatchet,
        requiresSimpleRatchet,
      ];
}

// ── RATCHET ─────────────────────────────────────────────────────
class Ratchet extends BeybladePart {
  const Ratchet({
    required super.dataId,
    super.parentPartId,
    super.variantLabel,
    required super.manufacturer,
    required super.hobbyName,
    required super.hobbyGeneration,
    required super.code,
    required super.name,
    super.edition,
    super.imageUrl,
    super.imageHash,
    super.minifiedImageUrl,
    super.minifiedImageHash,
    required super.mass,
    required super.legality,
    required super.isIncomplete,
    this.protrusions,
    this.heightMm,
    required this.stats,
    this.isSimple = false,
  });

  final int? protrusions;
  final double? heightMm;
  @override
  final StatBlock stats;

  /// A simple ratchet: the only kind a blade / assist blade with
  /// `requiresSimpleRatchet` accepts. Sheet column `simpleRatchet`.
  final bool isSimple;

  @override
  List<Object?> get props =>
      [...baseProps, protrusions, heightMm, stats, isSimple];
}

// ── BIT ─────────────────────────────────────────────────────────
class Bit extends BeybladePart {
  const Bit({
    required super.dataId,
    super.parentPartId,
    super.variantLabel,
    required super.manufacturer,
    required super.hobbyName,
    required super.hobbyGeneration,
    required super.code,
    required super.name,
    required this.baseName,
    super.edition,
    super.imageUrl,
    super.imageHash,
    super.minifiedImageUrl,
    super.minifiedImageHash,
    required super.mass,
    required super.legality,
    required super.isIncomplete,
    required this.movementStyle,
    required this.stats,
    required this.isTwoStat,
    required this.hasIntegratedRatchet,
  });

  final String baseName;
  final BeybladeArchetype movementStyle;
  @override
  final StatBlock stats;
  final bool isTwoStat;
  final bool hasIntegratedRatchet;

  @override
  List<Object?> get props => [
        ...baseProps,
        baseName,
        movementStyle,
        stats,
        isTwoStat,
        hasIntegratedRatchet
      ];
}

// ── LOCK CHIP ───────────────────────────────────────────────────
/// No stat columns on this sheet — [stats] is always empty. Sits at the
/// top of a separated build, above whichever [BladeCore] was chosen.
class LockChip extends BeybladePart {
  const LockChip({
    required super.dataId,
    super.parentPartId,
    super.variantLabel,
    required super.manufacturer,
    required super.hobbyName,
    required super.hobbyGeneration,
    required super.code,
    required super.name,
    super.edition,
    super.imageUrl,
    super.imageHash,
    super.minifiedImageUrl,
    super.minifiedImageHash,
    required super.mass,
    required super.legality,
    required super.isIncomplete,
  });

  @override
  StatBlock get stats => const StatBlock.empty();

  @override
  List<Object?> get props => baseProps;
}

/// Shared shape for OverBlade/MetalBlade/MainBlade/AssistBlade — same
/// columns (type, spinDir, mass, attack/defense/stamina), kept as
/// separate classes rather than one parameterized type so call sites
/// stay type-safe about which slot a value came from.
abstract class _TypedStatPart extends BeybladePart {
  const _TypedStatPart({
    required super.dataId,
    super.parentPartId,
    super.variantLabel,
    required super.manufacturer,
    required super.hobbyName,
    required super.hobbyGeneration,
    required super.code,
    required super.name,
    super.edition,
    super.imageUrl,
    super.imageHash,
    super.minifiedImageUrl,
    super.minifiedImageHash,
    required super.mass,
    required super.legality,
    required super.isIncomplete,
    required this.type,
    required this.spinDirection,
    required this.stats,
  });

  final BeybladeArchetype type;
  final SpinDirection spinDirection;
  @override
  final StatBlock stats;

  List<Object?> get typedProps => [...baseProps, type, spinDirection, stats];
}

// ── OVER BLADE ──────────────────────────────────────────────────
/// Paired with [MetalBlade] as one alternative for the middle of a
/// separated build — mutually exclusive with [MainBlade], never both.
class OverBlade extends _TypedStatPart {
  const OverBlade({
    required super.dataId,
    super.parentPartId,
    super.variantLabel,
    required super.manufacturer,
    required super.hobbyName,
    required super.hobbyGeneration,
    required super.code,
    required super.name,
    super.edition,
    super.imageUrl,
    super.imageHash,
    super.minifiedImageUrl,
    super.minifiedImageHash,
    required super.mass,
    required super.legality,
    required super.isIncomplete,
    required super.type,
    required super.spinDirection,
    required super.stats,
  });

  @override
  List<Object?> get props => typedProps;
}

// ── METAL BLADE ─────────────────────────────────────────────────
class MetalBlade extends _TypedStatPart {
  const MetalBlade({
    required super.dataId,
    super.parentPartId,
    super.variantLabel,
    required super.manufacturer,
    required super.hobbyName,
    required super.hobbyGeneration,
    required super.code,
    required super.name,
    super.edition,
    super.imageUrl,
    super.imageHash,
    super.minifiedImageUrl,
    super.minifiedImageHash,
    required super.mass,
    required super.legality,
    required super.isIncomplete,
    required super.type,
    required super.spinDirection,
    required super.stats,
  });

  @override
  List<Object?> get props => typedProps;
}

// ── MAIN BLADE ──────────────────────────────────────────────────
/// The other alternative for the middle of a separated build — mutually
/// exclusive with OverBlade+MetalBlade. See [BladeCore].
class MainBlade extends _TypedStatPart {
  const MainBlade({
    required super.dataId,
    super.parentPartId,
    super.variantLabel,
    required super.manufacturer,
    required super.hobbyName,
    required super.hobbyGeneration,
    required super.code,
    required super.name,
    super.edition,
    super.imageUrl,
    super.imageHash,
    super.minifiedImageUrl,
    super.minifiedImageHash,
    required super.mass,
    required super.legality,
    required super.isIncomplete,
    required super.type,
    required super.spinDirection,
    required super.stats,
  });

  @override
  List<Object?> get props => typedProps;
}

// ── ASSIST BLADE ────────────────────────────────────────────────
/// Always present in a separated build regardless of which [BladeCore]
/// was chosen — sits below the core, above the ratchet.
class AssistBlade extends _TypedStatPart {
  const AssistBlade({
    required super.dataId,
    super.parentPartId,
    super.variantLabel,
    required super.manufacturer,
    required super.hobbyName,
    required super.hobbyGeneration,
    required super.code,
    required super.name,
    super.edition,
    super.imageUrl,
    super.imageHash,
    super.minifiedImageUrl,
    super.minifiedImageHash,
    required super.mass,
    required super.legality,
    required super.isIncomplete,
    required super.type,
    required super.spinDirection,
    required super.stats,
    this.requiresSimpleRatchet = false,
  });

  /// Only fits a simple ratchet ([Ratchet.isSimple]). Sheet column
  /// `requiresSimpleRatchet`.
  final bool requiresSimpleRatchet;

  @override
  List<Object?> get props => [...typedProps, requiresSimpleRatchet];
}

// ── BLADE CORE (sealed) ─────────────────────────────────────────
/// The middle section of a separated build — exactly one of these two
/// shapes, enforced at the type level so "both set at once" can't be
/// constructed at all, not just checked at runtime.
sealed class BladeCore extends Equatable {
  const BladeCore();
  List<BeybladePart> get parts;
}

class OverMetalCore extends BladeCore {
  const OverMetalCore({required this.overBlade, required this.metalBlade});
  final OverBlade overBlade;
  final MetalBlade metalBlade;

  @override
  List<BeybladePart> get parts => [overBlade, metalBlade];
  @override
  List<Object?> get props => [overBlade, metalBlade];
}

class MainCore extends BladeCore {
  const MainCore(this.mainBlade);
  final MainBlade mainBlade;

  @override
  List<BeybladePart> get parts => [mainBlade];
  @override
  List<Object?> get props => [mainBlade];
}

// ── BLADE ASSEMBLY (sealed) ─────────────────────────────────────
/// The whole top section of a build — either a single unibody [Blade]
/// (the basic/original case) or a separated stack (lockChip + core +
/// assistBlade). Beyblade.stackedParts switches on this exhaustively,
/// so a new variant here is a compile error everywhere it's not handled
/// yet, not a silent gap.
sealed class BladeAssembly extends Equatable {
  const BladeAssembly();
  List<BeybladePart> get parts;
  double get mass => parts.fold(0, (sum, p) => sum + p.mass);
}

class UnibodyAssembly extends BladeAssembly {
  const UnibodyAssembly(this.blade);
  final Blade blade;

  @override
  List<BeybladePart> get parts => [blade];
  @override
  List<Object?> get props => [blade];
}

class SeparatedAssembly extends BladeAssembly {
  const SeparatedAssembly(
      {required this.lockChip, required this.core, required this.assistBlade});
  final LockChip lockChip;
  final BladeCore core;
  final AssistBlade assistBlade;

  @override
  List<BeybladePart> get parts => [lockChip, ...core.parts, assistBlade];
  @override
  List<Object?> get props => [lockChip, core, assistBlade];
}

// ── BEYBLADE LOADOUT ────────────────────────────────────────────
/// Minimal persisted/shared reference: just dataIds. Flat and nullable
/// rather than mirroring [BladeAssembly]'s sealed shape on purpose — this
/// is a JSON-friendly bag of ids for storage/share-codes, not a place to
/// enforce the mutual-exclusion rule. That rule is enforced procedurally
/// where it actually matters: BeyBuilderCubit (can't populate both paths
/// from the UI) and ResolveBeybladeUseCase (ignores an inconsistent mix
/// rather than guessing).
class BeybladeLoadout extends Equatable {
  const BeybladeLoadout({
    this.bladeDataId,
    this.ratchetDataId,
    required this.bitDataId,
    this.lockChipDataId,
    this.overBladeDataId,
    this.metalBladeDataId,
    this.mainBladeDataId,
    this.assistBladeDataId,
  });

  /// Set for a unibody build; null for a separated one.
  final String? bladeDataId;

  /// Null when the ratchet slot is disabled (integrated ratchet).
  final String? ratchetDataId;

  final String bitDataId;

  /// Separated-build fields — lockChipDataId set alongside either
  /// (overBladeDataId + metalBladeDataId) or mainBladeDataId, never both
  /// pairs at once.
  final String? lockChipDataId;
  final String? overBladeDataId;
  final String? metalBladeDataId;
  final String? mainBladeDataId;
  final String? assistBladeDataId;

  Map<String, dynamic> toJson() => {
        'bladeDataId': bladeDataId,
        'ratchetDataId': ratchetDataId,
        'bitDataId': bitDataId,
        'lockChipDataId': lockChipDataId,
        'overBladeDataId': overBladeDataId,
        'metalBladeDataId': metalBladeDataId,
        'mainBladeDataId': mainBladeDataId,
        'assistBladeDataId': assistBladeDataId,
      };

  factory BeybladeLoadout.fromJson(Map<String, dynamic> json) =>
      BeybladeLoadout(
        bladeDataId: json['bladeDataId'] as String?,
        ratchetDataId: json['ratchetDataId'] as String?,
        bitDataId: json['bitDataId'] as String,
        lockChipDataId: json['lockChipDataId'] as String?,
        overBladeDataId: json['overBladeDataId'] as String?,
        metalBladeDataId: json['metalBladeDataId'] as String?,
        mainBladeDataId: json['mainBladeDataId'] as String?,
        assistBladeDataId: json['assistBladeDataId'] as String?,
      );

  String toShareCode() => base64Url.encode(utf8.encode(jsonEncode(toJson())));

  factory BeybladeLoadout.fromShareCode(String code) {
    try {
      final json = jsonDecode(utf8.decode(base64Url.decode(code.trim())))
          as Map<String, dynamic>;
      return BeybladeLoadout.fromJson(json);
    } catch (e) {
      throw FormatException('Not a valid build code: $e');
    }
  }

  @override
  List<Object?> get props => [
        bladeDataId,
        ratchetDataId,
        bitDataId,
        lockChipDataId,
        overBladeDataId,
        metalBladeDataId,
        mainBladeDataId,
        assistBladeDataId,
      ];
}

// ── BEYBLADE (resolved) ─────────────────────────────────────────
/// Fully-resolved, display-ready build. Never persisted directly —
/// re-derived from a [BeybladeLoadout] + current part data every time,
/// so a data update is instantly reflected anywhere a saved loadout is
/// shown.
class Beyblade extends Equatable {
  const Beyblade({
    required this.loadout,
    required this.assembly,
    this.ratchet,
    required this.bit,
    required this.combinedStats,
    required this.totalMass,
    required this.archetype,
    required this.spinDirection,
    required this.legality,
  });

  final BeybladeLoadout loadout;
  final BladeAssembly assembly;
  final Ratchet? ratchet;
  final Bit bit;

  /// Every stat-bearing part's contribution summed key-by-key; a part
  /// with nothing for a given key contributes 0 to that key. See
  /// BeybladeStatsCalculator.
  final StatBlock combinedStats;

  final double totalMass;

  /// = bit.movementStyle.
  final BeybladeArchetype archetype;

  /// = the unibody blade's spin, or the lock chip core's — whichever
  /// assembly is active.
  final SpinDirection spinDirection;

  /// Worst-of across every part actually in the build.
  final WboLegality legality;

  /// Ordered top-to-bottom for rendering: assembly parts (already in the
  /// right internal order), then ratchet (if not disabled), then bit.
  List<BeybladePart> get stackedParts =>
      [...assembly.parts, if (ratchet != null) ratchet!, bit];

  /// The short, official-style name — Blade + Ratchet + Bit's base name
  /// for a unibody build; Lock Chip + Main Blade (or Lock Chip + Metal
  /// Blade) + Ratchet + Bit's base name for a separated one. Over Blade
  /// and Assist Blade are deliberately never included here — that's the
  /// real naming convention, not a gap. Ratchet is skipped only when
  /// there genuinely isn't one (integrated), not otherwise.
  String get nomenclatureName {
    final parts = <String>[];
    switch (assembly) {
      case UnibodyAssembly(:final blade):
        parts.add(blade.name);
      case SeparatedAssembly(:final lockChip, :final core):
        parts.add(lockChip.name);
        switch (core) {
          case MainCore(:final mainBlade):
            parts.add(mainBlade.name);
          case OverMetalCore(:final metalBlade):
            parts.add(metalBlade.name); // overBlade deliberately omitted
        }
    }
    if (ratchet != null) parts.add(ratchet!.name);
    parts.add(bit.baseName);
    return parts.join(' ');
  }

  @override
  List<Object?> get props => [
        loadout,
        assembly,
        ratchet,
        bit,
        combinedStats,
        totalMass,
        archetype,
        spinDirection,
        legality
      ];
}

// ── SYNC METADATA ───────────────────────────────────────────────
/// What BeybladeSyncCubit tracks about the ONE thing left to sync:
/// bundled metadata. hasMetadata is the only fact this app's lifecycle
/// actually needs -- there's no "check for updates" concept anymore
/// (metadata only ever changes with a new app version), so this is
/// deliberately much smaller than it used to be.
class SyncMetadata extends Equatable {
  const SyncMetadata({
    this.lastMetadataSyncAt,
    this.catalogVersion,
    this.catalogSha256,
  });

  static const SyncMetadata initial = SyncMetadata();

  /// Null until metadata has been loaded at least once.
  final DateTime? lastMetadataSyncAt;

  /// Which catalog is in the boxes: `'bundled'` for the JSON shipped in
  /// the app, otherwise the release version string it was downloaded
  /// from. Null on data written before this field existed.
  final String? catalogVersion;

  /// SHA-256 of the catalog.zip that was applied. Compared against the
  /// published release to decide whether an update exists. Null for the
  /// bundled catalog, which is why the first online launch always
  /// fetches once.
  final String? catalogSha256;

  bool get hasMetadata => lastMetadataSyncAt != null;
  bool get isBundled => catalogSha256 == null;

  SyncMetadata copyWith({
    DateTime? lastMetadataSyncAt,
    String? catalogVersion,
    String? catalogSha256,
  }) =>
      SyncMetadata(
        lastMetadataSyncAt: lastMetadataSyncAt ?? this.lastMetadataSyncAt,
        catalogVersion: catalogVersion ?? this.catalogVersion,
        catalogSha256: catalogSha256 ?? this.catalogSha256,
      );

  @override
  List<Object?> get props =>
      [lastMetadataSyncAt, catalogVersion, catalogSha256];
}

// ── SYNC PROGRESS ───────────────────────────────────────────────
/// Emitted by BeybladeSyncRepository.loadBundledMetadata() so the UI can
/// show progress (the actual off-thread work happens via `compute()` in
/// the repository implementation — this type is just the
/// progress-reporting shape).
sealed class SyncProgress {
  const SyncProgress();
}

class SyncStarted extends SyncProgress {
  const SyncStarted();
}

class SyncInProgress extends SyncProgress {
  const SyncInProgress({required this.fraction, required this.message});

  /// 0.0–1.0, coarse — this isn't meant to be a precise progress bar, just
  /// enough to keep a spinner/label honest.
  final double fraction;
  final String message;
}

class SyncCompleted extends SyncProgress {
  const SyncCompleted({required this.summary});
  final SyncSummary summary;
}

class SyncFailed extends SyncProgress {
  const SyncFailed({required this.message});
  final String message;
}

class SyncSummary extends Equatable {
  const SyncSummary({required this.totalRecords, required this.syncedAt});

  final int totalRecords;
  final DateTime syncedAt;

  @override
  List<Object?> get props => [totalRecords, syncedAt];
}

// ── DECK SLOT (raw, unresolved) ─────────────────────────────────────
/// One of exactly 3 fixed local slots -- just the stored loadout (or
/// nothing), before it's been resolved into a live Beyblade. What
/// DeckSlotsRepository.getAllSlots() returns straight from storage.
/// Feeds the tournament flow: converting to a PlayerDeck is just
/// `loadout.toShareCode()` -- nothing here needs to change shape for that.
class DeckSlot extends Equatable {
  const DeckSlot({required this.index, required this.loadout});

  /// Always 0, 1, or 2 -- there are exactly 3 slots, not a growable list.
  final int index;
  final BeybladeLoadout? loadout;

  @override
  List<Object?> get props => [index, loadout];
}

// ── RESOLVED DECK SLOT ───────────────────────────────────────────────
/// The UI-ready version DeckSlotsCubit actually emits -- loadout already
/// resolved into a live Beyblade (null for an empty slot, or one whose
/// loadout no longer resolves), so the page never has to resolve
/// anything itself.
class ResolvedDeckSlot extends Equatable {
  const ResolvedDeckSlot({required this.index, required this.beyblade});

  final int index;
  final Beyblade? beyblade;

  bool get isEmpty => beyblade == null;

  @override
  List<Object?> get props => [index, beyblade];
}

// ── COMBO ───────────────────────────────────────────────────────
/// One saved, named build -- unbounded count, unlike DeckSlot's fixed 3.
class Combo extends Equatable {
  const Combo(
      {required this.id,
      required this.name,
      required this.loadout,
      required this.createdAt});
  final String id;
  final String name;
  final BeybladeLoadout loadout;
  final DateTime createdAt;

  @override
  List<Object?> get props => [id, name, loadout, createdAt];
}

// ── DECK (named group of combos) ─────────────────────────────────
/// A named group of 3+ Combos -- separate, higher-level concept from a
/// Combo itself. References Combos by id, not by embedding their
/// loadouts directly, so editing/deleting a Combo has one source of truth.
class Deck extends Equatable {
  const Deck(
      {required this.id,
      required this.name,
      required this.comboIds,
      required this.createdAt});
  final String id;
  final String name;
  final List<String> comboIds;
  final DateTime createdAt;

  @override
  List<Object?> get props => [id, name, comboIds, createdAt];
}

// ── PRODUCT ───────────────────────────────────────────────────────────
/// The physical box/packaging a set of parts ships in -- its own image,
/// own price. Deliberately not itself a BeybladePart -- a box isn't a
/// performance part, so forcing it into that hierarchy just to reuse
/// stat fields it doesn't have would be the wrong shape.
class Product extends Equatable {
  const Product({
    required this.productId,
    required this.manufacturer,
    required this.hobbyName,
    required this.hobbyGeneration,
    required this.productName,
    this.productType,
    this.releaseDate,
    this.itemCost,
    this.boxImageUrl,
    this.boxImageHash,
    this.minifiedBoxImageUrl,
    this.minifiedBoxImageHash,
    this.sku,
    this.description,
    required this.isIncomplete,
  });

  final String productId;
  final String manufacturer;
  final String hobbyName;
  final String hobbyGeneration;
  final String productName;
  final String? productType;
  final DateTime? releaseDate;
  final double? itemCost;
  final String? boxImageUrl;
  final String? boxImageHash;
  final String? minifiedBoxImageUrl;
  final String? minifiedBoxImageHash;
  final String? sku;
  final String? description;
  final bool isIncomplete;

  @override
  List<Object?> get props => [
        productId,
        manufacturer,
        hobbyName,
        hobbyGeneration,
        productName,
        productType,
        releaseDate,
        itemCost,
        boxImageUrl,
        boxImageHash,
        minifiedBoxImageUrl,
        minifiedBoxImageHash,
        sku,
        description,
        isIncomplete,
      ];
}

// ── PRODUCT CONTENT ───────────────────────────────────────────────────
/// One row of "this part is inside this box, this many times". partType
/// names the SHEET a part belongs to (e.g. "blades"), not a Dart type --
/// resolving that string to an actual BeybladePart is the repository's
/// job, since only it knows how to route by sheet name to the right
/// datasource method. A product has many of these; the same part can
/// appear across several products over time (a re-release, a different
/// bundling) -- that's why this is its own join entity, not a "which
/// box" field directly on the part itself.
class ProductContent extends Equatable {
  const ProductContent({
    required this.productId,
    required this.partType,
    required this.partDataId,
    required this.quantity,
  });

  final String productId;
  final String partType;
  final String partDataId;
  final int quantity;

  @override
  List<Object?> get props => [productId, partType, partDataId, quantity];
}

// ── ACCESSORY ─────────────────────────────────────────────────────────
enum AccessoryType {
  stadium,
  launcher,
  grip,
  deckBox,
  battlePass,
  unknown;

  static AccessoryType parse(dynamic raw) {
    final s = raw?.toString().trim().toLowerCase() ?? '';
    return switch (s) {
      'stadium' => AccessoryType.stadium,
      'launcher' => AccessoryType.launcher,
      'grip' => AccessoryType.grip,
      'deckbox' => AccessoryType.deckBox,
      'battlepass' => AccessoryType.battlePass,
      _ => AccessoryType.unknown,
    };
  }
}

/// Stadiums, launchers, grips, deck boxes, and battle passes -- none of
/// these have performance stats, so they don't extend BeybladePart at
/// all. One shared entity with an accessoryType field rather than five
/// near-identical classes.
class Accessory extends Equatable {
  const Accessory({
    required this.dataId,
    required this.accessoryType,
    this.subType,
    required this.manufacturer,
    required this.hobbyName,
    required this.hobbyGeneration,
    required this.name,
    this.itemCost,
    this.imageUrl,
    this.imageHash,
    this.minifiedImageUrl,
    this.minifiedImageHash,
    this.description,
    required this.isIncomplete,
  });

  final String dataId;
  final AccessoryType accessoryType;
  final String? subType;
  final String manufacturer;
  final String hobbyName;
  final String hobbyGeneration;
  final String name;
  final double? itemCost;
  final String? imageUrl;
  final String? imageHash;
  final String? minifiedImageUrl;
  final String? minifiedImageHash;
  final String? description;
  final bool isIncomplete;

  @override
  List<Object?> get props => [
        dataId,
        accessoryType,
        subType,
        manufacturer,
        hobbyName,
        hobbyGeneration,
        name,
        itemCost,
        imageUrl,
        imageHash,
        minifiedImageUrl,
        minifiedImageHash,
        description,
        isIncomplete,
      ];
}

// ── Part compatibility ──────────────────────────────────────────────────
/// A blade with a built-in ratchet (e.g. Bullet Griffon) and a bit with a
/// built-in ratchet (e.g. Turbo, Operate) can't go on the same bey: each
/// one takes the ratchet's place. Every place that builds or rolls a bey
/// checks this.
bool integratedRatchetConflict(Blade? blade, Bit? bit) =>
    (blade?.hasIntegratedRatchet ?? false) &&
    (bit?.hasIntegratedRatchet ?? false);

/// Some blades (single-blade builds) and assist blades (lock chip builds) only
/// fit a simple ratchet. True when the top of the build needs one.
bool needsSimpleRatchet({Blade? blade, AssistBlade? assistBlade}) =>
    (blade?.requiresSimpleRatchet ?? false) ||
    (assistBlade?.requiresSimpleRatchet ?? false);

/// [ratchet] can't go on this top: it needs a simple ratchet and this isn't
/// one. Every place that builds or rolls a bey checks this.
bool simpleRatchetConflict(Ratchet? ratchet,
        {Blade? blade, AssistBlade? assistBlade}) =>
    ratchet != null &&
    !ratchet.isSimple &&
    needsSimpleRatchet(blade: blade, assistBlade: assistBlade);
