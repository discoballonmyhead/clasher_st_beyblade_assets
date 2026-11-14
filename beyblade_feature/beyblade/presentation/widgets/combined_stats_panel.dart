import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/loyalty_badge.dart';
import 'package:flutter/material.dart';

import 'stat_bar_row.dart';

/// Tiny by default (mass + legality, one line), expands to the full
/// per-stat breakdown on tap. This is the honest version of what the
/// original spec called a "matchstat scorer" — it shows the build's
/// actual combined stats clearly, but doesn't compute any single
/// head-to-head "match score," since no scoring formula was ever
/// specified for this game. Swap this for a real scorer once you have
/// one — everything it needs (combinedStats, totalMass, legality) is
/// already sitting on [beyblade].
class CombinedStatsPanel extends StatefulWidget {
  const CombinedStatsPanel({super.key, required this.beyblade});

  final Beyblade beyblade;

  @override
  State<CombinedStatsPanel> createState() => _CombinedStatsPanelState();
}

class _CombinedStatsPanelState extends State<CombinedStatsPanel> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final rc = ResponsiveProvider.config(context);
    final bey = widget.beyblade;

    return Card(
      child: Padding(
        padding: EdgeInsets.all(rc.horizontalPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Text('${bey.totalMass.toStringAsFixed(1)} g',
                            style: tt.titleMedium),
                        SizedBox(width: rc.sm),
                        LegalityBadge(legality: bey.legality),
                      ],
                    ),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      color: cs.onSurfaceVariant),
                ],
              ),
            ),
            if (_expanded) ...[
              SizedBox(height: rc.sm),
              Divider(color: cs.outlineVariant),
              ...() {
                final provided = StatKey.values
                    .map((k) => bey.combinedStats[k])
                    .where((s) => s.isProvided)
                    .map((s) =>
                        s.values.reduce((a, b) => a + b) / s.values.length);
                final maxAcrossStats = provided.isEmpty
                    ? 0.0
                    : provided.reduce((a, b) => a > b ? a : b);
                return StatKey.values.map((key) => StatBarRow(
                    label: _label(key),
                    spread: bey.combinedStats[key],
                    maxValue: maxAcrossStats));
              }(),
            ],
          ],
        ),
      ),
    );
  }

  String _label(StatKey key) => switch (key) {
        StatKey.attack => 'Attack',
        StatKey.defense => 'Defense',
        StatKey.stamina => 'Stamina',
        StatKey.dash => 'Dash',
        StatKey.burstResistance => 'Burst Resistance',
      };
}
