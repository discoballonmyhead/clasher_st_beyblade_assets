// =============================================================================
// OPTIONAL STADIUM FOR A TOURNAMENT
// -----------------------------------------------------------------------------
// "Stadium (optional)": the host can name the stadium the tournament is played
// on (Xtreme Stadium, Wide Xtreme Stadium, ...), picked from the Accessories in
// the parts catalog (accessoryType = Stadium). Null = not specified, which is
// the default and changes nothing for existing tournaments.
//
// Wiring (see flutter_integration/README.md, "Stadium"):
//   TournamentDraft:  String? stadiumDataId;
//   form block:       TournamentStadiumField(
//                       value: draft.stadiumDataId,
//                       onChanged: (id) => draft.update(() => draft.stadiumDataId = id))
//   request:          CreateTournamentRequest(..., stadiumDataId: stadiumDataId)
//   server:           tournaments.stadium_data_id (text, nullable)
// =============================================================================

import 'package:clasher_st/core/init_injection/injection.dart';
import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/widgets/app_beyblade_loading_indicator.dart';
import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/domain/repositories/beyblade_data_repo.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/part_image_thumb.dart';
import 'package:flutter/material.dart';

/// Stadiums in the local catalog, base models first, each group by name.
Future<List<Accessory>> loadStadiums() async {
  try {
    final all = await sl<BeybladeDataRepo>().getAllAccessories();
    return all.where((a) => a.accessoryType == AccessoryType.stadium).toList()
      ..sort((a, b) {
        final g = b.hobbyGeneration.compareTo(a.hobbyGeneration);
        return g != 0
            ? g
            : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
  } catch (_) {
    return const [];
  }
}

class TournamentStadiumField extends StatefulWidget {
  const TournamentStadiumField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// Accessory dataId of the stadium, or null for "not specified".
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  State<TournamentStadiumField> createState() => _TournamentStadiumFieldState();
}

class _TournamentStadiumFieldState extends State<TournamentStadiumField> {
  late final Future<List<Accessory>> _stadiums = loadStadiums();

  Future<void> _pick(List<Accessory> stadiums) async {
    final picked = await showModalBottomSheet<_Pick>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (_) => _StadiumSheet(stadiums: stadiums, selected: widget.value),
    );
    if (picked != null) widget.onChanged(picked.dataId);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FutureBuilder<List<Accessory>>(
      future: _stadiums,
      builder: (context, snap) {
        final stadiums = snap.data ?? const <Accessory>[];
        Accessory? selected;
        for (final s in stadiums) {
          if (s.dataId == widget.value) selected = s;
        }
        final loading = snap.connectionState != ConnectionState.done;
        return HoloCard(
          onTap: loading || stadiums.isEmpty ? null : () => _pick(stadiums),
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          child: Row(
            children: [
              selected == null
                  ? Icon(Icons.stadium_outlined, color: cs.onSurfaceVariant)
                  : PartImageThumb(
                      imageUrl: preferredImageSource(
                        selected.minifiedImageUrl,
                        selected.imageUrl,
                      ),
                      size: 40,
                      scale: 1,
                    ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      selected?.name ??
                          (widget.value != null
                              ? 'Stadium #${widget.value}'
                              : 'No specific stadium'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      loading
                          ? 'Loading stadiums…'
                          : stadiums.isEmpty
                          ? 'No stadiums in the catalog on this device'
                          : 'Optional - tap to choose',
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.value != null)
                IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close),
                  onPressed: () => widget.onChanged(null),
                )
              else if (loading)
                const SizedBox(width: 20, height: 20, child: BeybladeSpinner())
              else
                const Icon(Icons.chevron_right),
            ],
          ),
        );
      },
    );
  }
}

class _Pick {
  const _Pick(this.dataId);
  final String? dataId;
}

class _StadiumSheet extends StatelessWidget {
  const _StadiumSheet({required this.stadiums, required this.selected});

  final List<Accessory> stadiums;
  final String? selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.8,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: EdgeInsets.fromLTRB(
          rc.horizontalPadding,
          0,
          rc.horizontalPadding,
          rc.md,
        ),
        children: [
          HoloSectionLabel(title: 'Stadium'),
          SizedBox(height: rc.sm),
          _row(
            context,
            null,
            'No specific stadium',
            'Any stadium the venue uses',
            null,
          ),
          for (final s in stadiums)
            _row(
              context,
              s.dataId,
              s.name,
              [
                s.hobbyGeneration,
                if (s.subType != null) s.subType!,
                s.manufacturer,
              ].join(' · '),
              preferredImageSource(s.minifiedImageUrl, s.imageUrl),
            ),
          if (stadiums.isEmpty)
            Padding(
              padding: EdgeInsets.all(rc.md),
              child: Text(
                'No stadiums in the catalog on this device.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String? id,
    String title,
    String subtitle,
    String? image,
  ) {
    final cs = Theme.of(context).colorScheme;
    final isSel = id == selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: HoloCard(
        highlight: isSel,
        onTap: () => Navigator.of(context).pop(_Pick(id)),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Row(
          children: [
            image == null
                ? Icon(Icons.stadium_outlined, color: cs.onSurfaceVariant)
                : PartImageThumb(imageUrl: image, size: 40, scale: 1),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (isSel) Icon(Icons.check_circle, color: cs.primary),
          ],
        ),
      ),
    );
  }
}
