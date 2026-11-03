import 'dart:developer' as dev;
import 'dart:math' as math;

import 'package:clasher_st/core/constants/trc_constant_tokens.dart';
import 'package:clasher_st/core/init_injection/injection.dart';
import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/router/deep_links.dart';
import 'package:clasher_st/core/services/translation/translation_helper.dart';
import 'package:clasher_st/core/widgets/app_beyblade_loading_indicator.dart';
import 'package:clasher_st/core/widgets/app_facet_widget.dart';
import 'package:clasher_st/features/beyblade/domain/entities/entities.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/resolved_bey_thumb.dart';
import 'package:clasher_st/features/match_recordings/data/match_recordings_store.dart';
import 'package:clasher_st/features/match_recordings/match_recording_support.dart';
import 'package:clasher_st/features/match_recordings/presentation/match_recordings_routes.dart';
import 'package:clasher_st/features/match_recordings/presentation/recorder/floating_recorder.dart';
import 'package:clasher_st/features/match_recordings/presentation/recorder/match_recorder_controller.dart';
import 'package:clasher_st/features/match_recordings/presentation/widgets/recordings_badge.dart';
import 'package:clasher_st/features/predictions/presentation/widgets/match_wager_panel.dart';
import 'package:clasher_st/features/tournaments/domain/entities/entities.dart';
import 'package:clasher_st/features/tournaments/presentation/cubits/tournament_cubit.dart';
import 'package:clasher_st/features/tournaments/presentation/widgets/arena_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String? _kDisplayFont = null;

const Color _kSuccess = Color(0xFF3DDC84);
const Color _kFoul = Color(0xFFFFA726);
const double _kCut = 14;

/// Beveled ("cut corner") shape used across the whole arena UI.
BeveledRectangleBorder _bevel({
  Color? border,
  double width = 1.4,
  double cut = _kCut,
  bool mirror = false,
}) {
  return BeveledRectangleBorder(
    side: border == null
        ? BorderSide.none
        : BorderSide(color: border, width: width),
    borderRadius: mirror
        ? BorderRadius.only(
            topRight: Radius.circular(cut), bottomLeft: Radius.circular(cut))
        : BorderRadius.only(
            topLeft: Radius.circular(cut), bottomRight: Radius.circular(cut)),
  );
}

class MatchScorekeeperPage extends StatefulWidget {
  final String matchId;

  const MatchScorekeeperPage({super.key, required this.matchId});

  @override
  State<MatchScorekeeperPage> createState() => _MatchScorekeeperPageState();
}

class _MatchScorekeeperPageState extends State<MatchScorekeeperPage>
    with TickerProviderStateMixin {
  final String _currentUserId =
      Supabase.instance.client.auth.currentUser?.id ?? '';
  String? _selectedWinnerId;
  FinishType? _selectedFinishType;

  /// Slow breathing pulse for the few "live" status elements (round chip,
  /// flip warning, awaiting icon). Buttons don't use it: a selection is a
  /// static gradient border, so nothing repaints every frame.
  late final AnimationController _pulseCtrl;

  /// One-shot controller that drives the big "+N" round flash.
  late final AnimationController _flashCtrl;

  int? _lastRoundCount;
  _FlashData? _flash;

  /// The camera for this page. Created on first use; lives as long as the
  /// page, so the floating window can be hidden, minimized or expanded
  /// without stopping a recording.
  MatchRecorderController? _recorder;
  bool _recorderVisible = false;

  // ── Optimistic state ──────────────────────────────────────────────────────
  // The page shows what you tapped at once; the server catches up behind it.

  /// Bey picks not yet saved ('player1' / 'player2' -> slot key). Removed
  /// when the save finishes: on success the server has the same value, on
  /// an error the picker falls back to the server's (the snack says why).
  final Map<String, String> _pendingBey = {};
  final Map<String, Future<void>> _beySaves = {};

  /// Rounds logged here that the server hasn't confirmed yet, oldest first.
  /// They already count in the score, the round number and the history.
  final List<MatchRound> _pendingRounds = [];

  /// Saves run one after another, so round numbers stay in order.
  Future<void> _submitChain = Future.value();

  /// Rounds this device already flashed; their server echo doesn't flash.
  final Set<int> _flashedLocally = {};

  @override
  void initState() {
    super.initState();
    dev.log('[SCOREKEEPER] Initialized for Match ID: ${widget.matchId}');

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _flashCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cubit = context.read<TournamentCubit>();
      final tId = cubit.state.selectedMatch?.tournamentId ??
          cubit.state.selectedTournament?.id;
      if (tId != null && cubit.state.participants.isEmpty) {
        cubit.loadParticipants(tId);
      }
      // Baseline so we don't flash for rounds that already existed.
      _lastRoundCount = cubit.state.selectedMatch?.rounds.length ?? 0;
    });
  }

  @override
  void dispose() {
    // Saves a recording still in progress, then releases the camera.
    _recorder?.shutdown();
    _pulseCtrl.dispose();
    _flashCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Actions (optimistic: the UI changes on tap, the server catches up)
  // ---------------------------------------------------------------------------

  /// Shows the pick immediately and saves it in the background.
  void _selectBey(BeybladeMatch match, String playerSlot, String slotKey) {
    HapticFeedback.selectionClick();
    setState(() => _pendingBey[playerSlot] = slotKey);
    final save = context.read<TournamentCubit>().selectBey(
          matchId: match.id,
          tournamentId: match.tournamentId,
          playerSlot: playerSlot,
          beySlotKey: slotKey,
        );
    _beySaves[playerSlot] = save;
    save.whenComplete(() {
      // A newer pick for this player is still on its way: keep showing it.
      if (!mounted || !identical(_beySaves[playerSlot], save)) return;
      setState(() {
        _pendingBey.remove(playerSlot);
        _beySaves.remove(playerSlot);
      });
    });
  }

  /// Saved or picked-and-saving.
  bool _beyReady(BeybladeMatch m, String playerSlot) =>
      _pendingBey.containsKey(playerSlot) ||
      (playerSlot == 'player1' ? m.player1BeyConfirmed : m.player2BeyConfirmed);

  /// Server score plus the rounds still being saved.
  (int, int) _scores(BeybladeMatch m) {
    var p1 = m.player1Score, p2 = m.player2Score;
    for (final r in _pendingRounds) {
      if (r.finishType == FinishType.foul || r.winnerId == null) continue;
      if (r.winnerId == m.player1Id) {
        p1 += r.finishType.points;
      } else {
        p2 += r.finishType.points;
      }
    }
    return (p1, p2);
  }

  void _submitRound(BeybladeMatch match) {
    dev.log('[SCOREKEEPER] Attempting to submit round...');

    if (_selectedFinishType == null) {
      dev.log('[SCOREKEEPER] Error: No finish type selected.');
      _snack(TrTokens.selectFinishTypeError.tr, isError: true);
      return;
    }
    if (_selectedFinishType != FinishType.foul && _selectedWinnerId == null) {
      dev.log('[SCOREKEEPER] Error: No winner selected for non-foul finish.');
      _snack(TrTokens.selectWinnerError.tr, isError: true);
      return;
    }

    final newRound = MatchRound(
      roundNumber: match.rounds.length + _pendingRounds.length + 1,
      finishType: _selectedFinishType!,
      winnerId:
          _selectedFinishType == FinishType.foul ? null : _selectedWinnerId,
    );

    dev.log(
        '[SCOREKEEPER] Submitting Round ${newRound.roundNumber}: Finish: ${newRound.finishType.name}, Winner: ${newRound.winnerId}');

    HapticFeedback.mediumImpact();

    // Count it now: score, round number, history and flash update on tap.
    setState(() {
      _pendingRounds.add(newRound);
      _flashedLocally.add(newRound.roundNumber);
      _selectedWinnerId = null;
      _selectedFinishType = null;
    });
    _showFlash(match, newRound);

    final cubit = context.read<TournamentCubit>();
    final beySaves = _beySaves.values.toList();
    _submitChain = _submitChain.then((_) async {
      // The server needs the beys before it accepts the round.
      await Future.wait(beySaves);
      if (!mounted ||
          !_pendingRounds.any((r) => r.roundNumber == newRound.roundNumber)) {
        return; // dropped after an earlier round failed
      }
      await cubit.submitMatchRound(
        tournamentId: match.tournamentId,
        matchId: match.id,
        round: newRound,
      );
      if (!mounted) return;
      final serverCount = cubit.state.selectedMatch?.rounds.length ?? 0;
      setState(() {
        if (serverCount >= newRound.roundNumber) {
          _pendingRounds
              .removeWhere((r) => r.roundNumber == newRound.roundNumber);
        } else {
          // Not saved (the error snack says why). Later rounds were numbered
          // after this one, so they go too; the board shows the server again.
          _pendingRounds
              .removeWhere((r) => r.roundNumber >= newRound.roundNumber);
          _flashedLocally.removeWhere((n) => n >= newRound.roundNumber);
        }
      });
    });
  }

  // ---------------------------------------------------------------------------
  // Video recording (local only; never part of scoring)
  // ---------------------------------------------------------------------------

  void _toggleRecorder(BeybladeMatch m) {
    // Web and desktop: no camera recording (the button is hidden too).
    if (!MatchRecordingSupport.isAvailable) return;
    if (_recorder != null) {
      setState(() => _recorderVisible = !_recorderVisible);
      return;
    }
    final r = MatchRecorderController(
      store: sl<MatchRecordingsStore>(),
      tournamentId: m.tournamentId,
      matchId: m.id,
      onSaved: (rec) {
        if (mounted) {
          _snack('Recording saved on this device (${rec.durationLabel}).');
        }
      },
    );
    setState(() {
      _recorder = r;
      _recorderVisible = true;
    });
    r.open();
  }

  Future<void> _closeRecorder() async {
    final r = _recorder;
    if (r == null) return;
    setState(() {
      _recorder = null;
      _recorderVisible = false;
    });
    await r.shutdown(); // saves a recording in progress first
  }

  /// True when it's fine to leave. Asks first while recording, then saves.
  Future<bool> _confirmLeave() async {
    final r = _recorder;
    if (r == null || !r.isRecording) return true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Stop recording?'),
        content:
            const Text('The video is saved on this device before you leave.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Keep recording')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Stop & leave')),
        ],
      ),
    );
    if (ok != true) return false;
    await r.stop();
    return true;
  }

  void _snack(String message, {bool isError = false}) {
    final cs = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? cs.error : cs.inverseSurface,
        shape: _bevel(cut: 10),
        margin: const EdgeInsets.all(12),
      ));
  }

  void _pick({String? winnerId, FinishType? finish}) {
    HapticFeedback.selectionClick();
    setState(() {
      if (finish == FinishType.foul) {
        _selectedFinishType =
            _selectedFinishType == FinishType.foul ? null : FinishType.foul;
        _selectedWinnerId = null;
        return;
      }
      if (winnerId != null) _selectedWinnerId = winnerId;
      if (finish != null) {
        _selectedFinishType =
            (_selectedFinishType == finish && winnerId == _selectedWinnerId)
                ? null
                : finish;
      }
    });
  }

  void _confirmUndo(BeybladeMatch match) {
    dev.log('[SCOREKEEPER] Undo button tapped.');
    if (match.rounds.isEmpty) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: _bevel(cut: 16),
        title: Text(TrTokens.undoLastRoundHead.tr),
        content: Text(TrTokens.undoLastRoundContent.tr),
        actions: [
          TextButton(
              onPressed: () {
                dev.log('[SCOREKEEPER] Undo cancelled.');
                context.pop();
              },
              child: Text(TrTokens.cancelTxt.tr)),
          FilledButton(
            style: FilledButton.styleFrom(
                shape: _bevel(cut: 10),
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              dev.log('[SCOREKEEPER] Undo confirmed. Calling Cubit...');
              context.pop();
              context
                  .read<TournamentCubit>()
                  .undoLastRound(match.id, match.tournamentId);
            },
            child: Text(TrTokens.undoTxt.tr),
          ),
        ],
      ),
    );
  }

  void _confirmRestart(BeybladeMatch match) {
    dev.log('[SCOREKEEPER] Restart button tapped.');

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: _bevel(cut: 16),
        title: Text(TrTokens.restartMatchHead.tr),
        content: Text(TrTokens.restartMatchContent.tr),
        actions: [
          TextButton(
              onPressed: () => context.pop(),
              child: Text(TrTokens.cancelTxt.tr)),
          FilledButton(
            style: FilledButton.styleFrom(
                shape: _bevel(cut: 10),
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () {
              context.pop();
              context
                  .read<TournamentCubit>()
                  .restartMatch(match.id, match.tournamentId);
            },
            child: Text(TrTokens.restartTxt.tr),
          ),
        ],
      ),
    );
  }

  /// Rounds that arrive from the server. The ones logged on this device
  /// already flashed when they were tapped; only others (another scorer)
  /// flash here.
  void _handleRoundChange(TournamentState state) {
    final match = state.selectedMatch;
    if (match == null) return;
    final count = match.rounds.length;
    final prev = _lastRoundCount;
    _lastRoundCount = count;
    if (prev == null || count <= prev) return;

    final r = match.rounds.last;
    final mine = _flashedLocally.contains(r.roundNumber);
    _flashedLocally.removeWhere((n) => n <= count);
    if (mine) return;
    _showFlash(match, r);
  }

  void _showFlash(BeybladeMatch match, MatchRound r) {
    final isFoul = r.finishType == FinishType.foul;

    // 🚀 EXPLICIT MATCHING: Compare IDs and Names safely for both players
    final isP1 = !isFoul &&
        (r.winnerId == match.player1Id ||
            (match.player1Id.isEmpty && r.winnerId == 'BYE'));

    final cs = Theme.of(context).colorScheme;

    setState(() {
      _flash = _FlashData(
        title: isFoul
            ? TrTokens.foulRestartTxt.tr
            : (isP1 ? match.player1Name : match.player2Name),
        subtitle: r.finishType.label,
        points: isFoul ? 0 : r.finishType.points,
        color: isFoul ? _kFoul : (isP1 ? cs.primary : cs.secondary),
        isFoul: isFoul,
      );
    });
    _flashCtrl.forward(from: 0);
    HapticFeedback.heavyImpact();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);

    return PopScope(
      // With the camera open, leaving goes through _confirmLeave so a
      // recording in progress is saved, never lost.
      canPop: _recorder == null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!await _confirmLeave() || !mounted) return;
        await _closeRecorder();
        if (mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: cs.surface,
        extendBodyBehindAppBar: false,
        appBar: AppBar(
          backgroundColor: cs.surface,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: Text(
            TrTokens.matchScoreTxt.tr.toUpperCase(),
            style: const TextStyle(
              fontFamily: _kDisplayFont,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.5,
              fontSize: 15,
            ),
          ),
          centerTitle: true,
          actions: [
            Builder(builder: (context) {
              final s = context.watch<TournamentCubit>().state;
              final tId =
                  s.selectedMatch?.tournamentId ?? s.selectedTournament?.id;
              if (tId == null) return const SizedBox.shrink();
              final m = s.selectedMatch;
              final rec = _recorder;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RecordingsBadge(
                    matchId: widget.matchId,
                    title: m == null
                        ? null
                        : '${m.player1Name} vs ${m.player2Name}',
                  ),
                  // Android and iOS only; hidden on web and desktop.
                  if (MatchRecordingSupport.isAvailable)
                    IconButton(
                      tooltip:
                          rec == null ? 'Record video' : 'Show / hide camera',
                      onPressed: m == null ? null : () => _toggleRecorder(m),
                      icon: rec == null
                          ? const Icon(Icons.videocam_outlined)
                          : ListenableBuilder(
                              listenable: rec,
                              builder: (context, _) => Icon(
                                rec.isRecording
                                    ? Icons.videocam
                                    : Icons.videocam_outlined,
                                color: rec.isRecording ? cs.error : cs.primary,
                              ),
                            ),
                    ),
                  ShareLinkButton(
                    path: DeepLinks.match(tId, widget.matchId),
                    title: m == null
                        ? 'Match score'
                        : '${m.player1Name} vs ${m.player2Name}',
                  ),
                ],
              );
            }),
          ],
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              dev.log('[SCOREKEEPER] Back button pressed.');
              if (!await _confirmLeave() || !context.mounted) return;
              await _closeRecorder();
              if (!context.mounted) return;
              if (context.canPop()) {
                dev.log('[SCOREKEEPER] canPop() is true. Popping normally.');
                context.pop();
              } else {
                final tId = context
                        .read<TournamentCubit>()
                        .state
                        .selectedTournament
                        ?.id ??
                    '';
                dev.log(
                    '[SCOREKEEPER] canPop() is false. Using Web Failsafe. tId: $tId');
                if (tId.isNotEmpty) {
                  context.go('/tournaments/$tId/matches');
                } else {
                  context.go('/home/shell-tournaments');
                }
              }
            },
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  cs.primary.withValues(alpha: 0.0),
                  cs.primary.withValues(alpha: 0.6),
                  cs.secondary.withValues(alpha: 0.6),
                  cs.secondary.withValues(alpha: 0.0),
                ]),
              ),
            ),
          ),
        ),
        body: Stack(children: [
          Positioned.fill(
            child: BlocConsumer<TournamentCubit, TournamentState>(
              listenWhen: (prev, curr) =>
                  prev.errorMessage != curr.errorMessage ||
                  prev.selectedMatch?.rounds.length !=
                      curr.selectedMatch?.rounds.length,
              // Rebuild only for what this page shows. Without this, every
              // TournamentCubit emission (participants loading, list refreshes,
              // anything) rebuilt the whole scorekeeper, arena painting included.
              buildWhen: (prev, curr) =>
                  prev.selectedMatch != curr.selectedMatch ||
                  prev.selectedTournament != curr.selectedTournament ||
                  prev.isOperationLoading != curr.isOperationLoading ||
                  prev.participants != curr.participants,
              listener: (context, state) {
                _handleRoundChange(state);

                if (state.errorMessage == null) return;
                _snack(state.errorMessage!, isError: true);
                final tId = state.selectedMatch?.tournamentId;
                if (tId != null) {
                  context
                      .read<TournamentCubit>()
                      .loadMatches(tournamentId: tId);
                }
                context.read<TournamentCubit>().clearMessages();
              },
              builder: (context, state) {
                final match = state.selectedMatch;
                final tournament = state.selectedTournament;

                if (match == null || tournament == null) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const BeybladeSpinner(),
                        SizedBox(height: rc.md),
                        Text('...',
                            style: TextStyle(
                                color: cs.onSurfaceVariant, letterSpacing: 4)),
                      ],
                    ),
                  );
                }

                final isHost = tournament.canManage;
                final isScorer = tournament.canManage ||
                    tournament.scorerIds.contains(_currentUserId);

                final isPlayer1 = match.player1Id == _currentUserId;
                final isPlayer2 = match.player2Id == _currentUserId;
                final isParticipant = isPlayer1 || isPlayer2;

                final isCompleted = match.status == MatchStatus.completed;
                final isAwaiting =
                    match.status == MatchStatus.awaitingConfirmation;
                final requiresFlip =
                    match.rounds.length >= 3 && !isCompleted && !isAwaiting;

                return SafeArea(
                  child: Stack(
                    children: [
                      // Ambient arena glow behind everything.
                      // Own layer: the pulse animations above no longer force the
                      // static background to repaint every frame.
                      Positioned.fill(
                        child: IgnorePointer(
                          child: RepaintBoundary(
                            child: CustomPaint(
                              painter: _ArenaBackgroundPainter(
                                p1: cs.primary,
                                p2: cs.secondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                      RefreshIndicator(
                        color: cs.primary,
                        onRefresh: () => context
                            .read<TournamentCubit>()
                            .loadMatches(tournamentId: match.tournamentId),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final maxW = constraints.maxWidth > 900
                                ? 860.0
                                : double.infinity;
                            return ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: EdgeInsets.only(bottom: rc.xl * 2),
                              children: [
                                Center(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(maxWidth: maxW),
                                    child: Column(
                                      children: [
                                        // -- Warning Banner --
                                        AnimatedSize(
                                          duration:
                                              const Duration(milliseconds: 260),
                                          child: requiresFlip
                                              ? _FlipBanner(
                                                  rc: rc, pulse: _pulseCtrl)
                                              : const SizedBox(
                                                  width: double.infinity,
                                                  height: 0),
                                        ),

                                        // -- Arena scoreboard --
                                        _ArenaBoard(
                                          match: match,
                                          scores: _scores(match),
                                          roundNo: match.rounds.length +
                                              _pendingRounds.length +
                                              1,
                                          rc: rc,
                                          cs: cs,
                                          pulse: _pulseCtrl,
                                          isCompleted: isCompleted,
                                        ),

                                        // -- Main body --
                                        Padding(
                                          padding: EdgeInsets.all(rc.md),
                                          child: Column(
                                            children: [
                                              // Watching, not scoring: predictions first, opened.
                                              if (!isScorer &&
                                                  !isCompleted) ...[
                                                MatchWagerPanel(
                                                    matchId: match.id,
                                                    initiallyExpanded: true),
                                                const SizedBox(height: 16),
                                              ],
                                              AnimatedSwitcher(
                                                duration: const Duration(
                                                    milliseconds: 320),
                                                transitionBuilder:
                                                    (child, anim) =>
                                                        FadeTransition(
                                                  opacity: anim,
                                                  child: SlideTransition(
                                                    position: Tween<Offset>(
                                                      begin:
                                                          const Offset(0, 0.04),
                                                      end: Offset.zero,
                                                    ).animate(CurvedAnimation(
                                                        parent: anim,
                                                        curve: Curves
                                                            .easeOutCubic)),
                                                    child: child,
                                                  ),
                                                ),
                                                child: KeyedSubtree(
                                                  key: ValueKey(
                                                      '${match.status}-$isScorer'),
                                                  child: isCompleted
                                                      ? _buildCompletedState(
                                                          cs, rc, match)
                                                      : isAwaiting
                                                          ? _buildAwaitingState(
                                                              cs,
                                                              rc,
                                                              match,
                                                              isPlayer1,
                                                              isPlayer2,
                                                              isHost)
                                                          : isScorer
                                                              ? _buildControls(
                                                                  cs,
                                                                  rc,
                                                                  match,
                                                                  state
                                                                      .isOperationLoading,
                                                                  state
                                                                      .participants)
                                                              : _SpectatorView(
                                                                  isParticipant:
                                                                      isParticipant,
                                                                  cs: cs,
                                                                  rc: rc,
                                                                ),
                                                ),
                                              ),
                                              if (isScorer || isCompleted) ...[
                                                const SizedBox(height: 24),
                                                MatchWagerPanel(
                                                    matchId: match.id),
                                              ],
                                              if (match.rounds.isNotEmpty ||
                                                  _pendingRounds.isNotEmpty)
                                                _buildMatchHistory(
                                                    match,
                                                    isScorer,
                                                    isHost,
                                                    state.isOperationLoading,
                                                    cs,
                                                    rc),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),

                      // -- Round result flash --
                      if (_flash != null)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: _RoundFlash(data: _flash!, ctrl: _flashCtrl),
                          ),
                        ),

                      // -- Saving: a thin line at the top, never a scrim over the
                      // page, so scoring keeps going while the server works.
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 150),
                            opacity: state.isOperationLoading ||
                                    _pendingRounds.isNotEmpty ||
                                    _pendingBey.isNotEmpty
                                ? 1
                                : 0,
                            child: LinearProgressIndicator(
                              minHeight: 2,
                              color: cs.primary,
                              backgroundColor: Colors.transparent,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          if (_recorder != null && _recorderVisible)
            Positioned.fill(
              child: FloatingRecorder(
                controller: _recorder!,
                onClose: _closeRecorder,
                onOpenRecordings: () => context
                    .push(MatchRecordingsRoutes.forMatch(widget.matchId)),
              ),
            ),
        ]),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Ongoing controls (scorer only)
  // ---------------------------------------------------------------------------
  Widget _buildControls(ColorScheme cs, dynamic rc, BeybladeMatch match,
      bool isLoading, List<TournamentParticipant> participants) {
    PlayerDeck? deckFor(String mId, String mName) {
      // 🚀 THE FINAL FIX: Strict BYE check.
      // Only abort if the ID is BYE/empty AND the name is actually "BYE".
      final isRealBye =
          (mId == 'BYE' || mId.isEmpty) && mName.trim().toUpperCase() == 'BYE';

      if (isRealBye) {
        return null; // It's an actual ghosted bracket slot
      }

      // It's a real player or walk-in. Let's find them!
      for (final p in participants) {
        if (p.id == mId) return p.deck;
        if (p.userId.isNotEmpty && p.userId == mId) return p.deck;
        if (p.displayName.trim().toLowerCase() == mName.trim().toLowerCase()) {
          return p.deck;
        }
      }
      return null;
    }

    final p1Deck = deckFor(match.player1Id, match.player1Name);
    final p2Deck = deckFor(match.player2Id, match.player2Name);

    final canScore = match.bothBeysConfirmed ||
        (_beyReady(match, 'player1') && _beyReady(match, 'player2'));
    final ready = canScore &&
        _selectedFinishType != null &&
        (_selectedFinishType == FinishType.foul || _selectedWinnerId != null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionHeader(
          step: 1,
          done: canScore,
          active: true,
          title: TrTokens.confirmBeysHead.tr,
          subtitle: TrTokens.confirmBeysHead.tr,
          cs: cs,
          rc: rc,
        ),
        SizedBox(height: rc.md),
        // No IntrinsicHeight: it laid both pickers out twice on every
        // rebuild.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _BeyPicker(
                label: match.player1Name,
                deck: p1Deck,
                selected: _pendingBey['player1'] ?? match.player1BeySelection,
                confirmed: _beyReady(match, 'player1'),
                saving: _pendingBey.containsKey('player1'),
                color: cs.primary,
                mirror: false,
                onSelect: (slotKey) => _selectBey(match, 'player1', slotKey),
              ),
            ),
            SizedBox(width: rc.sm),
            Expanded(
              child: _BeyPicker(
                label: match.player2Name,
                deck: p2Deck,
                selected: _pendingBey['player2'] ?? match.player2BeySelection,
                confirmed: _beyReady(match, 'player2'),
                saving: _pendingBey.containsKey('player2'),
                color: cs.secondary,
                mirror: true,
                onSelect: (slotKey) => _selectBey(match, 'player2', slotKey),
              ),
            ),
          ],
        ),
        SizedBox(height: rc.lg),
        _NeonDivider(cs: cs),
        SizedBox(height: rc.lg),
        _SectionHeader(
          step: 2,
          done: false,
          active: canScore,
          title: TrTokens.logNextRoundHead.tr,
          cs: cs,
          rc: rc,
        ),
        SizedBox(height: rc.md),

        // -- Finish grid: pick winner + finish in a single tap --
        Opacity(
          opacity: canScore ? 1 : 0.45,
          child: IgnorePointer(
            ignoring: !canScore,
            child: LayoutBuilder(
              builder: (context, c) {
                final compact = c.maxWidth < 340;
                return compact
                    ? _buildCompactPicker(cs, rc, match)
                    : _buildFinishGrid(cs, rc, match);
              },
            ),
          ),
        ),

        SizedBox(height: rc.md),

        // -- Foul (no winner) --
        _FoulButton(
          label: TrTokens.foulRestartTxt.tr,
          selected: _selectedFinishType == FinishType.foul,
          enabled: canScore,
          onTap: () => _pick(finish: FinishType.foul),
        ),

        if (!canScore) ...[
          SizedBox(height: rc.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline, size: 13, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Flexible(
                child: Text(TrTokens.waitingBeyConfirmation.tr,
                    style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: cs.onSurfaceVariant)),
              ),
            ],
          ),
        ],
        SizedBox(height: rc.xl),
        _LogRoundButton(
          label: TrTokens.logRoundTxt.tr,
          // Rounds queue up while earlier ones save; only another operation
          // (undo, restart ...) holds the button.
          enabled: canScore && (!isLoading || _pendingRounds.isNotEmpty),
          ready: ready,
          cs: cs,
          onTap: () => _submitRound(match),
        ),
      ],
    );
  }

  /// Wide layout — two mirrored stacks of finishes, exactly like a fight board.
  Widget _buildFinishGrid(ColorScheme cs, dynamic rc, BeybladeMatch match) {
    final finishes =
        FinishType.values.where((t) => t != FinishType.foul).toList();

    Widget column(String playerId, String name, Color color, bool mirror) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PlayerTag(
              name: name,
              color: color,
              mirror: mirror,
              active: _selectedWinnerId == playerId &&
                  _selectedFinishType != FinishType.foul),
          SizedBox(height: rc.sm),
          ...finishes.map((type) {
            final selected = _selectedWinnerId == playerId &&
                _selectedFinishType == type &&
                _selectedFinishType != FinishType.foul;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _FinishButton(
                label: type.label,
                points: type.points,
                color: color,
                selected: selected,
                mirror: mirror,
                onTap: () => _pick(winnerId: playerId, finish: type),
              ),
            );
          }),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
            child:
                column(match.player1Id, match.player1Name, cs.primary, false)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: rc.sm),
          child: Column(
            children: [
              SizedBox(height: rc.lg),
              Text('VS',
                  style: TextStyle(
                    fontFamily: _kDisplayFont,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 1,
                    color: cs.outline,
                  )),
              SizedBox(height: rc.sm),
              Container(
                width: 1.5,
                height: 132,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      cs.primary.withValues(alpha: 0.5),
                      cs.outlineVariant.withValues(alpha: 0.2),
                      cs.secondary.withValues(alpha: 0.5),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
            child:
                column(match.player2Id, match.player2Name, cs.secondary, true)),
      ],
    );
  }

  /// Very narrow screens — pick the player, then the finish.
  Widget _buildCompactPicker(ColorScheme cs, dynamic rc, BeybladeMatch match) {
    final finishes =
        FinishType.values.where((t) => t != FinishType.foul).toList();
    final activeColor =
        _selectedWinnerId == match.player2Id ? cs.secondary : cs.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _SelectionCard(
                label: match.player1Name,
                isSelected: _selectedWinnerId == match.player1Id,
                color: cs.primary,
                onTap: () => _pick(winnerId: match.player1Id),
              ),
            ),
            SizedBox(width: rc.sm),
            Expanded(
              child: _SelectionCard(
                label: match.player2Name,
                isSelected: _selectedWinnerId == match.player2Id,
                color: cs.secondary,
                onTap: () => _pick(winnerId: match.player2Id),
              ),
            ),
          ],
        ),
        SizedBox(height: rc.md),
        Wrap(
          spacing: rc.sm,
          runSpacing: rc.sm,
          children: finishes.map((type) {
            final selected = _selectedFinishType == type;
            return _FinishChip(
              label: type.label,
              points: type.points,
              color: activeColor,
              selected: selected,
              onTap: () => _pick(finish: type),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Awaiting confirmation
  // ---------------------------------------------------------------------------

  Widget _buildAwaitingState(ColorScheme cs, dynamic rc, BeybladeMatch match,
      bool isPlayer1, bool isPlayer2, bool isHost) {
    final amIPlayer = isPlayer1 || isPlayer2;
    final haveIConfirmed = (isPlayer1 && match.player1Confirmed) ||
        (isPlayer2 && match.player2Confirmed);

    return Container(
      padding: EdgeInsets.symmetric(vertical: rc.lg, horizontal: rc.md),
      decoration: ShapeDecoration(
        color: cs.surfaceContainerLow,
        shape: _bevel(border: cs.primary.withValues(alpha: 0.35), cut: 18),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (_, child) => Transform.scale(
              scale: 1 + (_pulseCtrl.value * 0.06),
              child: child,
            ),
            child: Icon(Icons.handshake_outlined, size: 64, color: cs.primary),
          ),
          SizedBox(height: rc.md),
          Text(TrTokens.awaitingPlayerConfirmationHead.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: _kDisplayFont,
                  fontSize: rc.bodyLG + 2,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w800)),
          SizedBox(height: rc.sm),
          Text(
            TrTokens.awaitingPlayerConfirmationHead.tr,
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant),
          ),
          SizedBox(height: rc.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ConfirmBadge(
                  name: match.player1Name,
                  hasConfirmed: match.player1Confirmed,
                  cs: cs),
              _ConfirmBadge(
                  name: match.player2Name,
                  hasConfirmed: match.player2Confirmed,
                  cs: cs),
            ],
          ),
          SizedBox(height: rc.xl),
          if (amIPlayer && !haveIConfirmed)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    shape: _bevel(cut: 12),
                    backgroundColor: _kSuccess,
                    foregroundColor: Colors.black),
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  context
                      .read<TournamentCubit>()
                      .confirmMatchResult(match.id, match.tournamentId);
                },
                icon: const Icon(Icons.check_circle),
                label: Text(TrTokens.confirmScoresTxt.tr,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          if (isHost && (!match.player1Confirmed || !match.player2Confirmed))
            TextButton.icon(
              onPressed: () {
                context
                    .read<TournamentCubit>()
                    .forceCompleteMatch(match.id, match.tournamentId);
              },
              icon: const Icon(Icons.admin_panel_settings),
              label: Text(TrTokens.forceCompleteTxt.tr),
              style: TextButton.styleFrom(foregroundColor: cs.error),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Completed
  // ---------------------------------------------------------------------------

  Widget _buildCompletedState(ColorScheme cs, dynamic rc, BeybladeMatch match) {
    final winnerName = match.winnerId == match.player1Id
        ? match.player1Name
        : match.player2Name;
    final winnerColor =
        match.winnerId == match.player1Id ? cs.primary : cs.secondary;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 900),
      curve: Curves.elasticOut,
      builder: (context, t, child) => Transform.scale(
        scale: 0.85 + (t.clamp(0.0, 1.4) * 0.15),
        child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(vertical: rc.xl, horizontal: rc.md),
        decoration: ShapeDecoration(
          shape: _bevel(border: winnerColor.withValues(alpha: 0.6), cut: 20),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              winnerColor.withValues(alpha: 0.14),
              cs.surfaceContainerLow.withValues(alpha: 0.2),
            ],
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.workspace_premium, size: 68, color: winnerColor),
            SizedBox(height: rc.md),
            Text(TrTokens.matchConcludedHead.tr.toUpperCase(),
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: _kDisplayFont,
                    fontSize: rc.bodyLG + 2,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w900)),
            SizedBox(height: rc.sm),
            Text(
              TrTokens.playerWinsMsg.trParams({'name': winnerName}),
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: rc.bodyLG,
                  fontWeight: FontWeight.w600,
                  color: winnerColor),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. History timeline
  // ---------------------------------------------------------------------------

  Widget _buildMatchHistory(BeybladeMatch match, bool isScorer, bool isHost,
      bool isLoading, ColorScheme cs, dynamic rc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _NeonDivider(cs: cs),
        SizedBox(height: rc.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 3, height: 16, color: cs.primary),
                  SizedBox(width: rc.sm),
                  Flexible(
                    child: Text(TrTokens.roundHistoryHead.tr.toUpperCase(),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontFamily: _kDisplayFont,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.5,
                            fontSize: rc.body,
                            color: cs.primary)),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isScorer && match.status != MatchStatus.completed)
                  TextButton.icon(
                    // Waits for rounds still saving, so it undoes the right one.
                    onPressed: isLoading || _pendingRounds.isNotEmpty
                        ? null
                        : () => _confirmUndo(match),
                    icon: const Icon(Icons.undo, size: 18),
                    label: Text(TrTokens.undoLastTxt.tr,
                        style: const TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: cs.error),
                  ),
                if (isHost)
                  TextButton.icon(
                    onPressed: isLoading || _pendingRounds.isNotEmpty
                        ? null
                        : () => _confirmRestart(match),
                    icon: const Icon(Icons.replay, size: 18),
                    label: Text(TrTokens.restartMatchTxt.tr,
                        style: const TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(foregroundColor: cs.error),
                  ),
              ],
            ),
          ],
        ),
        SizedBox(height: rc.sm),
        ...[...match.rounds, ..._pendingRounds].map((r) {
          final saving = _pendingRounds.contains(r);
          final isFoul = r.finishType == FinishType.foul;

          // 🚀 ROBUST MATCHING FOR HISTORY TILES
          final bool isP1Winner = !isFoul && (r.winnerId == match.player1Id);
          final bool isP2Winner = !isFoul &&
              (r.winnerId == match.player2Id ||
                  (!isP1Winner &&
                      r.winnerId != null &&
                      r.winnerId!.isNotEmpty));

          final String winnerName =
              isP1Winner ? match.player1Name : match.player2Name;
          final String loserName =
              isP1Winner ? match.player2Name : match.player1Name;

          final Color accent =
              isFoul ? _kFoul : (isP1Winner ? cs.primary : cs.secondary);

          return _HistoryTile(
            key: ValueKey('round-${r.roundNumber}'),
            roundNumber: r.roundNumber,
            accent: accent,
            isFoul: isFoul,
            title: isFoul
                ? TrTokens.foulRestartTxt.tr
                : TrTokens.defeatedText.trParams({
                    'winner': winnerName,
                    'loser': loserName,
                  }),
            finishLabel: r.finishType.label,
            points: r.finishType.points,
            saving: saving,
            cs: cs,
            rc: rc,
          );
        }),
      ],
    );
  }
}

// =============================================================================
// ARENA SCOREBOARD
// =============================================================================

class _ArenaBoard extends StatelessWidget {
  const _ArenaBoard({
    required this.match,
    required this.scores,
    required this.roundNo,
    required this.rc,
    required this.cs,
    required this.pulse,
    required this.isCompleted,
  });

  final BeybladeMatch match;

  /// (player 1, player 2), including rounds still being saved.
  final (int, int) scores;
  final int roundNo;
  final dynamic rc;
  final ColorScheme cs;
  final Animation<double> pulse;
  final bool isCompleted;

  @override
  Widget build(BuildContext context) {

    return Container(
      padding: EdgeInsets.fromLTRB(rc.md, rc.md, rc.md, rc.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            cs.surfaceContainerHighest.withValues(alpha: 0.55),
            cs.surface,
          ],
        ),
        border: Border(
            bottom: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.6), width: 1)),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _CrossPainter(p1: cs.primary, p2: cs.secondary),
              ),
            ),
          ),
          Column(
            children: [
              // Round chip + names
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: _NamePlate(
                        name: match.player1Name,
                        color: cs.primary,
                        mirror: false),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: rc.sm),
                    child: _RoundChip(
                      round: roundNo,
                      completed: isCompleted,
                      cs: cs,
                      pulse: pulse,
                    ),
                  ),
                  Expanded(
                    child: _NamePlate(
                        name: match.player2Name,
                        color: cs.secondary,
                        mirror: true),
                  ),
                ],
              ),
              SizedBox(height: rc.md),

              // Scores
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _ScoreDigits(value: scores.$1, color: cs.primary),
                        SizedBox(height: rc.xs),
                        _ScorePips(
                          target: match.targetScore,
                          filled: scores.$1,
                          color: cs.primary,
                          cs: cs,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow,
                              size: 16,
                              color: cs.primary.withValues(alpha: 0.7)),
                          Text('VS',
                              style: TextStyle(
                                  fontFamily: _kDisplayFont,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: cs.outline)),
                          Transform.rotate(
                            angle: math.pi,
                            child: Icon(Icons.play_arrow,
                                size: 16,
                                color: cs.secondary.withValues(alpha: 0.7)),
                          ),
                        ],
                      ),
                      SizedBox(height: rc.xs),
                      Text(
                        TrTokens.targetScorePrefix
                            .trParams({'score': match.targetScore.toString()}),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 0.8,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _ScoreDigits(value: scores.$2, color: cs.secondary),
                        SizedBox(height: rc.xs),
                        _ScorePips(
                          target: match.targetScore,
                          filled: scores.$2,
                          color: cs.secondary,
                          cs: cs,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NamePlate extends StatelessWidget {
  const _NamePlate(
      {required this.name, required this.color, required this.mirror});

  final String name;
  final Color color;
  final bool mirror;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: ShapeDecoration(
        color: color.withValues(alpha: 0.08),
        shape: _bevel(border: color.withValues(alpha: 0.75), mirror: mirror),
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: mirror ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontFamily: _kDisplayFont,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: color,
          fontSize: 14,
        ),
      ),
    );
  }
}

class _RoundChip extends StatelessWidget {
  const _RoundChip({
    required this.round,
    required this.completed,
    required this.cs,
    required this.pulse,
  });

  final int round;
  final bool completed;
  final ColorScheme cs;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        final glow = completed ? 0.0 : pulse.value;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: CurvedAnimation(parent: anim, curve: Curves.easeOutBack),
                child: FadeTransition(opacity: anim, child: child),
              ),
              child: Row(
                key: ValueKey(completed ? 'done' : 'r$round'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('R',
                      style: TextStyle(
                        fontFamily: _kDisplayFont,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: cs.onSurfaceVariant,
                      )),
                  Text(
                    completed ? '—' : '$round',
                    style: TextStyle(
                      fontFamily: _kDisplayFont,
                      fontSize: 28,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                      shadows: [
                        Shadow(
                            color: cs.primary.withValues(alpha: 0.35 * glow),
                            blurRadius: 16),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Container(
              width: 34,
              height: 2,
              color: cs.primary.withValues(alpha: 0.35 + (0.4 * glow)),
            ),
          ],
        );
      },
    );
  }
}

/// Big animated score digits: pops and glows every time the value changes.
class _ScoreDigits extends StatefulWidget {
  const _ScoreDigits({required this.value, required this.color});

  final int value;
  final Color color;

  @override
  State<_ScoreDigits> createState() => _ScoreDigitsState();
}

class _ScoreDigitsState extends State<_ScoreDigits>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  late final Animation<double> _pop = TweenSequence<double>([
    TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.32)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 32),
    TweenSequenceItem(
        tween: Tween(begin: 1.32, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 68),
  ]).animate(_c);

  bool _up = true;

  @override
  void didUpdateWidget(covariant _ScoreDigits old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _up = widget.value > old.value;
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final glow = math.sin(_c.value * math.pi);
        return Transform.scale(
          scale: _pop.value,
          child: DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.45 * glow),
                  blurRadius: 34 * glow,
                  spreadRadius: 2 * glow,
                ),
              ],
            ),
            child: child,
          ),
        );
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        transitionBuilder: (child, anim) => ClipRect(
          child: SlideTransition(
            position: Tween<Offset>(
              begin: Offset(0, _up ? 0.6 : -0.6),
              end: Offset.zero,
            ).animate(
                CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
            child: FadeTransition(opacity: anim, child: child),
          ),
        ),
        child: Text(
          '${widget.value}',
          key: ValueKey(widget.value),
          style: TextStyle(
            fontFamily: _kDisplayFont,
            fontSize: 54,
            height: 1.05,
            fontWeight: FontWeight.w900,
            color: widget.color,
          ),
        ),
      ),
    );
  }
}

class _ScorePips extends StatelessWidget {
  const _ScorePips({
    required this.target,
    required this.filled,
    required this.color,
    required this.cs,
  });

  final int target;
  final int filled;
  final Color color;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    if (target <= 0) return const SizedBox.shrink();

    // Fall back to a linear bar if there are too many target points
    if (target > 8) {
      final pct = (filled / target).clamp(0.0, 1.0);
      return SizedBox(
        width: 84,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: pct),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => LinearProgressIndicator(
              value: v,
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 4,
      runSpacing: 4,
      children: List.generate(target, (i) {
        final on = i < filled;
        return AnimatedContainer(
          duration: Duration(milliseconds: 260 + (i * 40)),
          curve: Curves
              .easeOut, // FIXED: Replaced easeOutBack to prevent negative blur radius
          width: on ? 16 : 12,
          height: 6,
          decoration: BoxDecoration(
            color: on ? color : cs.outlineVariant.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(1),
          ),
        );
      }),
    );
  }
}

// =============================================================================
// SELECTION LOOK
// -----------------------------------------------------------------------------
// Every selectable control shares one look: a neutral fill, a thin outline,
// and - when selected - a theme-gradient border. No inner tint, no glow, no
// pulse: nothing repaints while you think, and a tap shows at once.
// =============================================================================

/// The theme's gradient (primary -> tertiary -> secondary). Mirrored
/// controls (player 2's side) run it the other way, so each side starts
/// from its own colour.
LinearGradient _themeGradient(ColorScheme cs, {bool mirror = false}) =>
    LinearGradient(
      begin: mirror ? Alignment.topRight : Alignment.topLeft,
      end: mirror ? Alignment.bottomLeft : Alignment.bottomRight,
      colors: mirror
          ? [cs.secondary, cs.tertiary, cs.primary]
          : [cs.primary, cs.tertiary, cs.secondary],
    );

/// Outline + gradient border around the bevel; [t] fades between them.
class _BevelBorderPainter extends CustomPainter {
  const _BevelBorderPainter({
    required this.gradient,
    required this.outline,
    required this.t,
    required this.cut,
    required this.mirror,
  });

  /// Selected border thickness.
  static const width = 2.0;

  final Gradient gradient;
  final Color outline;
  final double t;
  final double cut;
  final bool mirror;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = _bevel(cut: cut, mirror: mirror)
        .getOuterPath(rect.deflate(width / 2));
    if (t < 1) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = outline.withValues(alpha: outline.a * (1 - t)),
      );
    }
    if (t > 0) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..shader = gradient.createShader(rect)
          ..color = Color.fromRGBO(0, 0, 0, t), // alpha fades the shader
      );
    }
  }

  @override
  bool shouldRepaint(_BevelBorderPainter old) =>
      old.t != t ||
      old.gradient != gradient ||
      old.outline != outline ||
      old.cut != cut ||
      old.mirror != mirror;
}

/// A bevelled, tappable surface with the selection border. The border fades
/// in over 110 ms; the ink ripple answers the tap immediately.
class _SelectableBevel extends StatelessWidget {
  const _SelectableBevel({
    required this.selected,
    required this.child,
    this.onTap,
    this.cut = 10,
    this.mirror = false,
    this.gradient,
    this.fill,
    this.padding = EdgeInsets.zero,
    this.minHeight = 0,
  });

  final bool selected;
  final Widget child;
  final VoidCallback? onTap;
  final double cut;
  final bool mirror;

  /// Defaults to the theme gradient.
  final Gradient? gradient;
  final Color? fill;
  final EdgeInsetsGeometry padding;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final g = gradient ?? _themeGradient(cs, mirror: mirror);
    final outline = cs.outlineVariant.withValues(alpha: 0.5);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: selected ? 1 : 0),
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      builder: (context, t, child) => CustomPaint(
        foregroundPainter: _BevelBorderPainter(
          gradient: g,
          outline: outline,
          t: t,
          cut: cut,
          mirror: mirror,
        ),
        child: child,
      ),
      child: Material(
        color: fill ?? cs.surfaceContainerHigh.withValues(alpha: 0.55),
        shape: _bevel(cut: cut, mirror: mirror),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          // Instant, faint feedback - no grey wash over the button.
          highlightColor: Colors.transparent,
          splashColor: cs.primary.withValues(alpha: 0.08),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// FINISH PICKERS
// =============================================================================

class _PlayerTag extends StatelessWidget {
  const _PlayerTag({
    required this.name,
    required this.color,
    required this.mirror,
    required this.active,
  });

  final String name;
  final Color color;
  final bool mirror;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return _SelectableBevel(
      selected: active,
      cut: 8,
      mirror: mirror,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: mirror ? TextAlign.right : TextAlign.left,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
          color: color,
        ),
      ),
    );
  }
}

/// The main scoring button: "BURST +2" for a specific player.
class _FinishButton extends StatelessWidget {
  const _FinishButton({
    required this.label,
    required this.points,
    required this.color,
    required this.selected,
    required this.mirror,
    required this.onTap,
  });

  final String label;
  final int points;
  final Color color;
  final bool selected;
  final bool mirror;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final points = Text(
      '+${this.points}',
      style: TextStyle(
        fontFamily: _kDisplayFont,
        fontSize: 15,
        fontWeight: FontWeight.w900,
        color: selected ? color : cs.onSurfaceVariant,
      ),
    );
    return _SelectableBevel(
      selected: selected,
      mirror: mirror,
      onTap: onTap,
      // Tall (about 56 px): easy to hit with a thumb mid-battle.
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      child: Row(
        mainAxisAlignment:
            mirror ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (mirror) ...[points, const SizedBox(width: 8)],
          Flexible(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: mirror ? TextAlign.right : TextAlign.left,
              style: TextStyle(
                fontFamily: _kDisplayFont,
                fontSize: 15,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w800,
                color: selected ? color : cs.onSurface,
              ),
            ),
          ),
          if (!mirror) ...[const SizedBox(width: 8), points],
        ],
      ),
    );
  }
}

/// Compact variant used on very narrow screens.
class _FinishChip extends StatelessWidget {
  const _FinishChip({
    required this.label,
    required this.points,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int points;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _SelectableBevel(
      selected: selected,
      cut: 8,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w800,
                color: selected ? color : cs.onSurface,
              )),
          const SizedBox(width: 6),
          Text('+$points',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: selected ? color : cs.onSurfaceVariant,
              )),
        ],
      ),
    );
  }
}

class _FoulButton extends StatelessWidget {
  const _FoulButton({
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: IgnorePointer(
        ignoring: !enabled,
        child: _SelectableBevel(
          selected: selected,
          onTap: onTap,
          // A foul isn't a player's point: its own warm gradient.
          gradient: LinearGradient(colors: [_kFoul, cs.error]),
          fill: cs.surfaceContainerHigh.withValues(alpha: 0.4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.replay_circle_filled_outlined,
                  size: 18, color: selected ? _kFoul : cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: _kDisplayFont,
                    fontSize: 12,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    color: selected ? _kFoul : cs.onSurfaceVariant,
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

class _LogRoundButton extends StatelessWidget {
  const _LogRoundButton({
    required this.label,
    required this.enabled,
    required this.ready,
    required this.cs,
    required this.onTap,
  });

  final String label;
  final bool enabled;

  /// A winner and a finish are picked: the button takes the theme gradient.
  final bool ready;
  final ColorScheme cs;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? cs.onPrimary : cs.onSurfaceVariant;
    return Material(
      shape: _bevel(cut: 14),
      clipBehavior: Clip.antiAlias,
      color: Colors.transparent,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          color: !enabled
              ? cs.surfaceContainerHighest
              : (ready ? null : cs.primary.withValues(alpha: 0.85)),
          gradient: enabled && ready
              ? LinearGradient(colors: [cs.primary, cs.tertiary, cs.secondary])
              : null,
        ),
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: SizedBox(
            height: 58,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bolt, color: fg),
                const SizedBox(width: 8),
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontFamily: _kDisplayFont,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.6,
                    fontSize: 15,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// ROUND RESULT FLASH
// =============================================================================

class _FlashData {
  const _FlashData({
    required this.title,
    required this.subtitle,
    required this.points,
    required this.color,
    required this.isFoul,
  });

  final String title;
  final String subtitle;
  final int points;
  final Color color;
  final bool isFoul;
}

class _RoundFlash extends StatelessWidget {
  const _RoundFlash({required this.data, required this.ctrl});

  final _FlashData data;
  final AnimationController ctrl;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) {
        final t = ctrl.value;
        if (t == 0 || t >= 1) return const SizedBox.shrink();

        // fade in 0-0.12, hold, fade out 0.7-1.0
        final opacity =
            t < 0.12 ? (t / 0.12) : (t > 0.7 ? (1 - ((t - 0.7) / 0.3)) : 1.0);
        final scale = 0.8 +
            (Curves.easeOutBack.transform((t / 0.35).clamp(0.0, 1.0)) * 0.2);
        final drift = -18.0 * (t > 0.7 ? (t - 0.7) / 0.3 : 0.0);

        return Center(
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, drift),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 28),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
                  decoration: ShapeDecoration(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.96),
                    shape: _bevel(border: data.color, width: 2, cut: 18),
                    shadows: [
                      BoxShadow(
                          color: data.color.withValues(alpha: 0.4),
                          blurRadius: 40,
                          spreadRadius: 2),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!data.isFoul)
                        Text('+${data.points}',
                            style: TextStyle(
                              fontFamily: _kDisplayFont,
                              fontSize: 46,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              color: data.color,
                            )),
                      const SizedBox(height: 6),
                      Text(
                        data.title.toUpperCase(),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: _kDisplayFont,
                          fontSize: 16,
                          letterSpacing: 1.6,
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        data.subtitle.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 2,
                          fontWeight: FontWeight.bold,
                          color: data.color,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// =============================================================================
// SHARED CHROME
// =============================================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.step,
    required this.done,
    required this.active,
    required this.title,
    required this.cs,
    required this.rc,
    this.subtitle,
  });

  final int step;
  final bool done;
  final bool active;
  final String title;
  final String? subtitle;
  final ColorScheme cs;
  final dynamic rc;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _StepBadge(number: step, done: done, cs: cs, active: active),
            SizedBox(width: rc.sm),
            Flexible(
              child: Text(title.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: _kDisplayFont,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    fontSize: rc.body,
                    color: done
                        ? _kSuccess
                        : (active ? cs.onSurface : cs.onSurfaceVariant),
                  )),
            ),
          ],
        ),
        if (subtitle != null) ...[
          SizedBox(height: rc.xs),
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Text(subtitle!,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ),
        ],
      ],
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({
    required this.number,
    required this.done,
    required this.cs,
    this.active = true,
  });

  final int number;
  final bool done;
  final bool active;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final color = done ? _kSuccess : (active ? cs.primary : cs.outline);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: ShapeDecoration(
        color: color.withValues(alpha: done ? 1.0 : 0.14),
        shape: _bevel(border: color, width: 1.4, cut: 7),
      ),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        transitionBuilder: (child, anim) =>
            ScaleTransition(scale: anim, child: child),
        child: done
            ? const Icon(Icons.check,
                key: ValueKey('done'), size: 14, color: Colors.black)
            : Text('$number',
                key: ValueKey('n$number'),
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w900, color: color)),
      ),
    );
  }
}

class _NeonDivider extends StatelessWidget {
  const _NeonDivider({required this.cs});
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          cs.primary.withValues(alpha: 0.0),
          cs.outlineVariant.withValues(alpha: 0.8),
          cs.secondary.withValues(alpha: 0.0),
        ]),
      ),
    );
  }
}

class _FlipBanner extends StatelessWidget {
  const _FlipBanner({required this.rc, required this.pulse});

  final dynamic rc;
  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(vertical: rc.sm, horizontal: rc.md),
          color: _kFoul.withValues(alpha: 0.10 + (0.10 * pulse.value)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform.rotate(
                angle: (pulse.value - 0.5) * 0.25,
                child:
                    const Icon(Icons.sync_alt_rounded, color: _kFoul, size: 18),
              ),
              SizedBox(width: rc.sm),
              Flexible(
                child: Text(
                  TrTokens.flipStadiumWarning.tr.toUpperCase(),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: _kFoul,
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── 1. Round history row (scorekeeper) ───────────────────────────────────────
//
// The old version drew `Container(width: 3, height: 58)` beside a beveled
// border: the bar ran straight past the cut corner, and the hardcoded 58 never
// matched the real row height, so it floated. FacetPanel's accent stripe is
// painted inside the clip and stretches to the row, so it can't do either.

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    super.key,
    required this.roundNumber,
    required this.accent,
    required this.isFoul,
    required this.title,
    required this.finishLabel,
    required this.points,
    required this.cs,
    required this.rc,
    this.saving = false,
  });

  final int roundNumber;
  final Color accent;
  final bool isFoul;
  final String title;
  final String finishLabel;
  final int points;

  /// Logged on this device, not confirmed by the server yet.
  final bool saving;
  final ColorScheme cs;
  final dynamic rc;

  @override
  Widget build(BuildContext context) {
    return ArenaFadeIn(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 150),
        opacity: saving ? 0.6 : 1,
        child: FacetPanel(
        cut: 10,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
        color: cs.surfaceContainerLow.withValues(alpha: 0.6),
        borderColor: accent.withValues(alpha: 0.28),
        accent: accent,
        accentEdge: FacetEdge.left,
        accentThickness: 3,
        child: Row(
          children: [
            FacetPanel(
              cut: 7,
              width: 38,
              height: 38,
              padding: EdgeInsets.zero,
              alignment: Alignment.center,
              color: accent.withValues(alpha: 0.12),
              borderColor: accent.withValues(alpha: 0.4),
              child: Text('R$roundNumber',
                  style: TextStyle(
                      fontFamily: kArenaFont,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      color: accent)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isFoul ? cs.onSurfaceVariant : cs.onSurface,
                      fontSize: rc.body,
                      fontWeight: isFoul ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    saving
                        ? '${finishLabel.toUpperCase()} · SAVING'
                        : finishLabel.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isFoul ? cs.onSurfaceVariant : accent,
                      fontSize: 10,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            if (!isFoul)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  '+$points',
                  style: TextStyle(
                    fontFamily: kArenaFont,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                    color: accent,
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

// =============================================================================
// BEY PICKER
// =============================================================================

class _BeyPicker extends StatefulWidget {
  const _BeyPicker({
    required this.label,
    required this.deck,
    required this.selected,
    required this.confirmed,
    required this.color,
    required this.onSelect,
    this.saving = false,
    this.mirror = false,
  });

  final String label;
  final PlayerDeck? deck;

  /// Slot key ("bey1" … "bey5"), already including a pick that is still
  /// saving: the page passes its optimistic value.
  final String? selected;
  final bool confirmed;

  /// The pick is on its way to the server.
  final bool saving;
  final Color color;
  final bool mirror;
  final ValueChanged<String> onSelect; // receives the slot key

  @override
  State<_BeyPicker> createState() => _BeyPickerState();
}

class _BeyPickerState extends State<_BeyPicker> {
  bool _showCustomEntry = false;
  final _customCtrl = TextEditingController();

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  void _submitCustom() {
    final value = _customCtrl.text.trim();
    if (value.isEmpty) return;
    widget.onSelect(value);
    setState(() => _showCustomEntry = false);
    _customCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final deck = widget.deck;
    final hasDeck = deck != null;
    final slots = hasDeck
        ? <(String, BeybladeLoadout)>[
            ('bey1', deck.bey1),
            ('bey2', deck.bey2),
            ('bey3', deck.bey3),
            if (deck.bey4 != null) ('bey4', deck.bey4!),
            if (deck.bey5 != null) ('bey5', deck.bey5!),
          ]
        : const <(String, BeybladeLoadout)>[];

    return _SelectableBevel(
      // Picked: the panel takes the gradient too, green-led for "ready".
      selected: widget.confirmed,
      cut: 12,
      mirror: widget.mirror,
      gradient: LinearGradient(
        begin: widget.mirror ? Alignment.topRight : Alignment.topLeft,
        end: widget.mirror ? Alignment.bottomLeft : Alignment.bottomRight,
        colors: [_kSuccess, widget.color],
      ),
      fill: cs.surfaceContainerLow.withValues(alpha: 0.5),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.label,
                    style: TextStyle(
                        fontFamily: _kDisplayFont,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        fontSize: 13,
                        color: widget.color),
                    overflow: TextOverflow.ellipsis),
              ),
              if (widget.confirmed)
                Icon(Icons.verified,
                    color: _kSuccess.withValues(alpha: widget.saving ? 0.5 : 1),
                    size: 18),
            ],
          ),
          const SizedBox(height: 8),
          if (!hasDeck && !_showCustomEntry)
            Text(TrTokens.noDeckOnFile.tr,
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          // One big row per bey (52 px+): quick to hit, readable names.
          for (var i = 0; i < slots.length; i++) ...[
            _BeyOption(
              number: i + 1,
              loadout: slots[i].$2,
              selected: widget.selected == slots[i].$1,
              saving: widget.saving && widget.selected == slots[i].$1,
              color: widget.color,
              mirror: widget.mirror,
              onTap: () => widget.onSelect(slots[i].$1),
            ),
            if (i != slots.length - 1) const SizedBox(height: 6),
          ],
          if (!hasDeck) ...[
            const SizedBox(height: 6),
            AnimatedSize(
              duration: const Duration(milliseconds: 160),
              alignment: Alignment.topLeft,
              child: _showCustomEntry
                  ? Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _customCtrl,
                            autofocus: true,
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: TrTokens.beyNameHint.tr,
                              border: const OutlineInputBorder(),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 12),
                            ),
                            onSubmitted: (_) => _submitCustom(),
                          ),
                        ),
                        IconButton(
                            icon: const Icon(Icons.check),
                            onPressed: _submitCustom),
                      ],
                    )
                  : TextButton.icon(
                      onPressed: () => setState(() => _showCustomEntry = true),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(TrTokens.enterBeyManuallyTxt.tr),
                      style: TextButton.styleFrom(
                          foregroundColor: widget.color,
                          minimumSize: const Size(0, 44)),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One selectable bey: number, full name (two lines), selection state.
class _BeyOption extends StatelessWidget {
  const _BeyOption({
    required this.number,
    required this.loadout,
    required this.selected,
    required this.saving,
    required this.color,
    required this.onTap,
    this.mirror = false,
  });

  final int number;
  final BeybladeLoadout loadout;
  final bool selected;

  /// Picked on this device, server not confirmed yet. Shown as selected
  /// anyway; the check is a little dimmer until it's saved.
  final bool saving;
  final Color color;
  final bool mirror;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onSurface : cs.onSurfaceVariant;
    return _SelectableBevel(
      selected: selected,
      cut: 8,
      mirror: mirror,
      onTap: onTap,
      fill: Colors.transparent,
      minHeight: 52,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Text('$number',
              style: TextStyle(
                  fontFamily: _kDisplayFont,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: selected ? color : cs.onSurfaceVariant)),
          const SizedBox(width: 10),
          Expanded(
            child: ResolvedBeyBuilder(
              loadout: loadout,
              builder: (context, bey) => Text(
                bey.nomenclatureName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: fg),
              ),
              loading: (_) =>
                  Text('Bey $number', style: TextStyle(fontSize: 14, color: fg)),
              failed: (_) => Text('Bey $number (unavailable)',
                  style: TextStyle(fontSize: 14, color: fg)),
            ),
          ),
          if (selected)
            Icon(Icons.check_circle,
                size: 20, color: color.withValues(alpha: saving ? 0.5 : 1)),
        ],
      ),
    );
  }
}

class _ConfirmBadge extends StatelessWidget {
  final String name;
  final bool hasConfirmed;
  final ColorScheme cs;

  const _ConfirmBadge(
      {required this.name, required this.hasConfirmed, required this.cs});

  @override
  Widget build(BuildContext context) {
    final color = hasConfirmed ? _kSuccess : _kFoul;
    return Flexible(
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(10),
            decoration: ShapeDecoration(
              color: color.withValues(alpha: 0.12),
              shape: _bevel(border: color.withValues(alpha: 0.7), cut: 10),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              child: Icon(
                hasConfirmed ? Icons.check_circle : Icons.hourglass_top,
                key: ValueKey(hasConfirmed),
                color: color,
                size: 30,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface)),
          Text(
              hasConfirmed
                  ? TrTokens.confirmedStatus.tr
                  : TrTokens.waitingStatus.tr,
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _SelectionCard extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color color;
  final VoidCallback onTap;

  const _SelectionCard({
    required this.label,
    required this.isSelected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _SelectableBevel(
      selected: isSelected,
      onTap: onTap,
      fill: cs.surfaceContainerHighest.withValues(alpha: 0.6),
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      child: Center(
        child: Text(
          label,
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: _kDisplayFont,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: isSelected ? color : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _SpectatorView extends StatelessWidget {
  const _SpectatorView({
    required this.isParticipant,
    required this.cs,
    required this.rc,
  });

  final bool isParticipant;
  final ColorScheme cs;
  final dynamic rc;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: rc.xl, horizontal: rc.md),
      decoration: ShapeDecoration(
        color: cs.surfaceContainerLow.withValues(alpha: 0.4),
        shape:
            _bevel(border: cs.outlineVariant.withValues(alpha: 0.5), cut: 16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isParticipant ? Icons.hourglass_empty : Icons.visibility_outlined,
            size: 46,
            color: cs.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          SizedBox(height: rc.md),
          Text(
            (isParticipant
                    ? TrTokens.waitingForScorerHead.tr
                    : TrTokens.spectatingHead.tr)
                .toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: _kDisplayFont,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                fontSize: rc.body,
                color: cs.onSurfaceVariant),
          ),
          SizedBox(height: rc.xs),
          Text(
            isParticipant
                ? TrTokens.waitingForScorerHead.tr
                : TrTokens.spectatingHead.tr,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// PAINTERS
// =============================================================================

/// The big X behind the scoreboard, tinted with each player's colour.
class _CrossPainter extends CustomPainter {
  const _CrossPainter({required this.p1, required this.p2});

  final Color p1;
  final Color p2;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRect(rect);

    final stroke = size.height * 0.22;

    final left = Paint()
      ..color = p1.withValues(alpha: 0.07)
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.square;
    final right = Paint()
      ..color = p2.withValues(alpha: 0.07)
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.square;

    canvas.drawLine(Offset(-stroke, -stroke),
        Offset(size.width * 0.62, size.height + stroke), left);
    canvas.drawLine(Offset(size.width + stroke, -stroke),
        Offset(size.width * 0.38, size.height + stroke), right);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_CrossPainter old) => old.p1 != p1 || old.p2 != p2;
}

/// Very faint page-wide grid + corner glows.
class _ArenaBackgroundPainter extends CustomPainter {
  const _ArenaBackgroundPainter({required this.p1, required this.p2});

  final Color p1;
  final Color p2;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = p1.withValues(alpha: 0.025)
      ..strokeWidth = 1;

    const gap = 42.0;
    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    canvas.drawCircle(
      Offset(0, size.height * 0.15),
      size.width * 0.5,
      Paint()
        ..shader = RadialGradient(colors: [
          p1.withValues(alpha: 0.10),
          p1.withValues(alpha: 0.0),
        ]).createShader(Rect.fromCircle(
            center: Offset(0, size.height * 0.15), radius: size.width * 0.5)),
    );
    canvas.drawCircle(
      Offset(size.width, size.height * 0.15),
      size.width * 0.5,
      Paint()
        ..shader = RadialGradient(colors: [
          p2.withValues(alpha: 0.10),
          p2.withValues(alpha: 0.0),
        ]).createShader(Rect.fromCircle(
            center: Offset(size.width, size.height * 0.15),
            radius: size.width * 0.5)),
    );
  }

  @override
  bool shouldRepaint(_ArenaBackgroundPainter old) =>
      old.p1 != p1 || old.p2 != p2;
}
