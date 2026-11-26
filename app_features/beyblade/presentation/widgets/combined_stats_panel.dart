import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/loyalty_badge.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/stats/holo_stat_panel.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/stats/holo_stat_radar.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/stats/stat_graph_page.dart';
import 'package:flutter/material.dart';

/// A build's combined stats (every part's six stats added up) in the
/// builder and on the display page: a header line with the mass, the
/// legality and a thumbnail radar, which opens to the full stat panel
/// (radar + rows). It animates as parts are swapped, so the effect of a
/// part on the shape is visible. "Detailed graph" opens the graph on its own
/// with what each part adds.
///
/// It shows the build's actual combined stats; it doesn't compute a single
/// head-to-head "match score", since no scoring formula was ever specified.
class CombinedStatsPanel extends StatefulWidget {
  const CombinedStatsPanel(
      {super.key, required this.beyblade, this.initiallyExpanded = true});

  final Beyblade beyblade;
  final bool initiallyExpanded;

  @override
  State<CombinedStatsPanel> createState() => _CombinedStatsPanelState();
}

class _CombinedStatsPanelState extends State<CombinedStatsPanel> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bey = widget.beyblade;

    return HoloCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  // A glimpse of the shape while collapsed.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _expanded
                        ? const SizedBox(width: 0, key: ValueKey('none'))
                        : Padding(
                            key: const ValueKey('mini'),
                            padding: const EdgeInsets.only(right: 10),
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: HoloStatRadar(
                                  stats: bey.combinedStats,
                                  compact: true,
                                  maxSize: 40),
                            ),
                          ),
                  ),
                  Text(
                    '${bey.totalMass.toStringAsFixed(1)} g',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 10),
                  LegalityBadge(legality: bey.legality),
                  const Spacer(),
                  Text(
                    'STATS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      color: cs.onSurfaceVariant),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: HoloStatPanel(
                      stats: bey.combinedStats,
                      card: false,
                      onOpenDetailed: () =>
                          StatGraphPage.open(context, StatGraphPage.combo(bey)),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
