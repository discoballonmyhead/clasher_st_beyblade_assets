// Optional stadium for a tournament, on the shared accessory picker
// (features/beyblade/presentation/widgets/accessory_picker.dart) - the same
// one bey_testing uses for its session stadium and launchers.
//
// TournamentStadiumField: the "Stadium" block on the create-tournament page;
//   "No specific stadium" (null) is the default.
// TournamentStadiumPanel: on the tournament detail page under "How it's
//   played"; renders nothing when the host didn't pick a stadium.
//
// Stored with TournamentStadiumRepository right after the tournament is
// created (sql/21_tournament_stadium.sql).

import 'package:clasher_st/core/init_injection/injection.dart';
import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/accessory_picker.dart';
import 'package:clasher_st/features/tournaments/data/tournament_stadium_repository.dart';
import 'package:clasher_st/features/tournaments/presentation/widgets/arena_style.dart';
import 'package:flutter/material.dart';

const kNoSpecificStadium = 'No specific stadium';

class TournamentStadiumField extends StatelessWidget {
  const TournamentStadiumField({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// Accessory dataId of the stadium, or null for "not specified".
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => AccessoryField(
        type: AccessoryType.stadium,
        title: 'Stadium',
        noneLabel: kNoSpecificStadium,
        value: value,
        onChanged: onChanged,
      );
}

/// The tournament's stadium, if the host picked one. Nothing otherwise
/// (also while loading, and when it can't be read), so the page never
/// jumps or shows an error for an optional detail.
class TournamentStadiumPanel extends StatefulWidget {
  const TournamentStadiumPanel({super.key, required this.tournamentId});

  final String tournamentId;

  @override
  State<TournamentStadiumPanel> createState() => _TournamentStadiumPanelState();
}

class _TournamentStadiumPanelState extends State<TournamentStadiumPanel> {
  late Future<(String, Accessory?)?> _stadium = _load();

  @override
  void didUpdateWidget(covariant TournamentStadiumPanel old) {
    super.didUpdateWidget(old);
    if (old.tournamentId != widget.tournamentId) _stadium = _load();
  }

  Future<(String, Accessory?)?> _load() async {
    try {
      final id = await sl<TournamentStadiumRepository>()
          .getStadium(widget.tournamentId);
      if (id == null) return null;
      return (id, await AccessoryCache.byId(id));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    return FutureBuilder<(String, Accessory?)?>(
      future: _stadium,
      builder: (context, snap) {
        final data = snap.data;
        if (data == null) return const SizedBox.shrink();
        final (id, stadium) = data;
        return Padding(
          padding: EdgeInsets.only(top: rc.sm),
          child: ArenaPanel(
            padding: EdgeInsets.all(rc.md),
            child: Row(
              children: [
                AccessoryThumb(
                    accessory: stadium, type: AccessoryType.stadium, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Stadium',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                      Text(stadium?.name ?? 'Stadium #$id',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
