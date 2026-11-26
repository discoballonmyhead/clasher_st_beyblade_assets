import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';

/// A combo's stats: every stat-bearing part's six stats added up key by key
/// (blank = 0), and every part's mass. Doesn't special-case which parts are
/// present, so a future part type just needs to be in the parts list.
///
/// Two-number stats stay pairs: a dynamic blade ("25/55") on a plain ratchet
/// and bit gives a dynamic combo stat (start + start, end + end), and a
/// dual-mode bit gives a dual-mode combo stat. See [StatValue.+].
class BeybladeStatsCalculator {
  const BeybladeStatsCalculator();

  StatBlock combine(List<BeybladePart> parts) =>
      StatBlock.sum(parts.map((p) => p.stats));

  double totalMass(List<BeybladePart> parts) =>
      parts.fold(0, (sum, p) => sum + p.mass);

  /// What each part adds to [key], in build order -- for a combo's breakdown.
  List<(BeybladePart, StatValue)> contributions(
          List<BeybladePart> parts, StatKey key) =>
      [for (final p in parts) if (p.stats[key].isProvided) (p, p.stats[key])];
}
