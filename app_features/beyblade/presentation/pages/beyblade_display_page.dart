import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/beyblade_stack_preview.dart';
import '../widgets/combined_stats_panel.dart';
import '../widgets/part_detail_sheet.dart';

enum _ViewMode { combined, isolated }

/// What tapping a [MinifiedBeybladeTile] (with `onTap` set) opens.
///
/// Share is a deliberate no-op right now — wiring it up needs a decision
/// about what's actually being shared (a deep link? an image export?
/// through which channel?) that hasn't been made yet. Copy Code works
/// today since it only needs [BeybladeLoadout.toShareCode], already
/// built and self-contained.
class BeybladeDisplayPage extends StatefulWidget {
  const BeybladeDisplayPage({super.key, required this.beyblade});

  final Beyblade beyblade;

  @override
  State<BeybladeDisplayPage> createState() => _BeybladeDisplayPageState();
}

class _BeybladeDisplayPageState extends State<BeybladeDisplayPage> {
  _ViewMode _mode = _ViewMode.combined;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    final bey = widget.beyblade;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Beyblade Build'),
        actions: [
          IconButton(
            tooltip: 'Share',
            icon: const Icon(Icons.share_outlined),
            onPressed: () {}, // intentionally does nothing yet — see class doc
          ),
          IconButton(
            tooltip: 'Copy code',
            icon: const Icon(Icons.copy_outlined),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: bey.loadout.toShareCode()));
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Build code copied')));
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(rc.horizontalPadding),
          child: Column(
            children: [
              SegmentedButton<_ViewMode>(
                segments: const [
                  ButtonSegment(
                      value: _ViewMode.combined, label: Text('Combined')),
                  ButtonSegment(
                      value: _ViewMode.isolated, label: Text('Isolated')),
                ],
                selected: {_mode},
                onSelectionChanged: (s) => setState(() => _mode = s.first),
              ),
              SizedBox(height: rc.lg),
              Expanded(
                child: SingleChildScrollView(
                  child: _mode == _ViewMode.combined
                      ? Column(
                          children: [
                            BeybladeStackPreview.fromResolved(bey),
                            SizedBox(height: rc.lg),
                            CombinedStatsPanel(beyblade: bey),
                          ],
                        )
                      : Column(
                          children: [
                            for (final part in bey.stackedParts) ...[
                              Card(child: PartDetailSheet(part: part)),
                              SizedBox(height: rc.sm),
                            ],
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
