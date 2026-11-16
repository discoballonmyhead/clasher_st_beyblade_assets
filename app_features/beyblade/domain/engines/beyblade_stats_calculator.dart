import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';

/// Sums every stat-bearing part's contribution key-by-key (missing = 0),
/// and every part's mass. Works over whatever [BladeAssembly] variant is
/// active plus ratchet/bit — doesn't special-case which parts are
/// present, so a future part type just needs to be in the parts list.
class BeybladeStatsCalculator {
  const BeybladeStatsCalculator();

  StatBlock combine(List<BeybladePart> parts) {
    return StatBlock.combineAll(parts.map((p) => p.stats), (a, b) {
      if (!a.isProvided && !b.isProvided) return StatSpread.notProvided;
      final aLow = a.primary ?? 0, aHigh = a.secondary ?? a.primary ?? 0;
      final bLow = b.primary ?? 0, bHigh = b.secondary ?? b.primary ?? 0;
      final low = aLow + bLow, high = aHigh + bHigh;
      return low == high ? StatSpread.single(low) : StatSpread.dual(low, high);
    });
  }

  double totalMass(List<BeybladePart> parts) =>
      parts.fold(0, (sum, p) => sum + p.mass);
}
