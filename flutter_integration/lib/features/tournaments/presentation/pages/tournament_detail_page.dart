import 'dart:async';

import 'package:clasher_st/core/constants/app_constants.dart';
import 'package:clasher_st/core/constants/geo_constants.dart';
import 'package:clasher_st/core/constants/trc_constant_tokens.dart';
import 'package:clasher_st/core/pages/image_viewer_page.dart';
import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/responsive/responsive_provider.dart';
import 'package:clasher_st/core/router/deep_links.dart';
import 'package:clasher_st/core/services/translation/translation_helper.dart';
import 'package:clasher_st/core/widgets/app_beyblade_loading_indicator.dart';
import 'package:clasher_st/core/widgets/app_dialog_widget.dart';
import 'package:clasher_st/core/widgets/app_network_image.dart';
import 'package:clasher_st/core/widgets/country_flag.dart';
import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/resolved_minified_bey_tile.dart';
import 'package:clasher_st/features/moderation/data/models/enums.dart';
import 'package:clasher_st/features/moderation/presentation/widgets/report_dialog.dart';
import 'package:clasher_st/features/prizes/presentation/widgets/prize_widgets.dart';
import 'package:clasher_st/features/prizes/presentation/widgets/tournament_prize_extras.dart';
import 'package:clasher_st/features/tournaments/domain/entities/entities.dart';
import 'package:clasher_st/features/tournaments/presentation/cubits/tournament_cubit.dart';
import 'package:clasher_st/features/tournaments/presentation/pages/deck_registration_page.dart';
import 'package:clasher_st/features/tournaments/presentation/widgets/arena_style.dart';
import 'package:clasher_st/features/tournaments/presentation/widgets/stadium_picker_field.dart';
import 'package:clasher_st/features/tournaments/presentation/widgets/step_trail.dart';
import 'package:clasher_st/features/tournaments/presentation/widgets/tab_coordinator_widget.dart';
import 'package:clasher_st/features/user_dt/presentation/widgets/timeline_line.dart';
import 'package:clasher_st/features/user_dt/routes/profile_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class TournamentDetailPage extends StatefulWidget {
  final String tournamentId;
  final bool autoRegister;
  final int initialTab;

  const TournamentDetailPage({
    super.key,
    required this.tournamentId,
    this.autoRegister = false,
    this.initialTab = 0,
  });

  @override
  State<TournamentDetailPage> createState() => _TournamentDetailPageState();
}

class _TournamentDetailPageState extends State<TournamentDetailPage> {
  final String _currentUserId =
      Supabase.instance.client.auth.currentUser?.id ?? '';
  bool _hasAutoOpened = false;

  @override
  void initState() {
    super.initState();
    context.read<TournamentCubit>().loadTournamentDetails(widget.tournamentId);
  }

  Future<void> _handleRefresh() async {
    await context
        .read<TournamentCubit>()
        .loadTournamentDetails(widget.tournamentId, refresh: true);
  }

  void _confirmWithdraw(
      BuildContext context, Tournament t, TournamentParticipant? me) {
    final cubit = context.read<TournamentCubit>();
    final played = me != null && cubit.hasPlayedMatch(me.userId);
    final cs = Theme.of(context).colorScheme;

    AppDialogWidget.show(
      context,
      title: 'Withdraw from tournament?',
      headerColor: cs.errorContainer,
      content: Material(
        color: Colors.transparent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              played
                  ? 'You’ll be removed from all remaining matches. Any unfinished '
                      'match goes to your opponent. ELO you already lost in this '
                      'tournament is not returned.'
                  : 'Your registration will be removed. You can register again '
                      'while registration is still open.',
              style: const TextStyle(height: 1.4),
            ),
            if (t.canManage) ...[
              const SizedBox(height: 10),
              Text('You keep your host controls.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            ],
            const SizedBox(height: 10),
            Text('This can’t be undone.',
                style: TextStyle(color: cs.error, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      actionButton: Builder(
        builder: (dialogContext) => HoloActionButton(
          label: 'Withdraw',
          icon: Icons.logout,
          dense: true,
          variant: HoloButtonVariant.danger,
          onPressed: () {
            Navigator.of(dialogContext).pop();
            cubit.withdraw(t.id);
          },
        ),
      ),
      secondaryButton: Builder(
        builder: (dialogContext) => TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(TrTokens.cancelTxt.tr),
        ),
      ),
    );
  }

  Future<void> _openDeckRegistration(
      BuildContext context, Tournament tournament) async {
    final cubit = context.read<TournamentCubit>();
    // The fee loads after the details; a quick tap on Join could
    // otherwise skip the fee dialog and its balance check.
    await cubit.loadFeeInfo(tournament.id);
    if (!context.mounted) return;
    final fee = cubit.state.feeInfo;
    if (!fee.hasFee) {
      _pushDeckRegistration(context, tournament, acknowledgeFee: false);
      return;
    }

    final agreed = ValueNotifier<bool>(false);
    AppDialogWidget.show(
      context,
      title: 'Entry fee',
      content: Material(
        color: Colors.transparent,
        child: ValueListenableBuilder<bool>(
          valueListenable: agreed,
          builder: (context, value, _) {
            final cs = Theme.of(context).colorScheme;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(fee.formatted,
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                Text(
                  fee.isAppCurrency
                      ? TrTokens.feeAppCurrencyExplain.trParams({
                          'balance':
                              '${(fee.myBalance ?? 0) == (fee.myBalance ?? 0).roundToDouble() ? (fee.myBalance ?? 0).toStringAsFixed(0) : (fee.myBalance ?? 0).toStringAsFixed(2)} ${fee.currencyName ?? fee.currency}',
                        })
                      : fee.note ??
                          'Pay the host directly. The app does not take payments.',
                  style: TextStyle(color: cs.onSurfaceVariant, height: 1.4),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  value: value,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (v) => agreed.value = v ?? false,
                  title: Text(fee.isAppCurrency
                      ? TrTokens.feeAppCurrencyAgree.tr
                      : 'I understand there is an entry fee and I will pay the host.'),
                ),
                if (!fee.canAfford)
                  Text(TrTokens.feeNotEnough.tr,
                      style: TextStyle(color: cs.error, fontSize: 13)),
              ],
            );
          },
        ),
      ),
      actionButton: Builder(
        builder: (dialogContext) => ValueListenableBuilder<bool>(
          valueListenable: agreed,
          builder: (_, value, __) => HoloActionButton(
            label: 'Continue',
            icon: Icons.arrow_forward,
            dense: true,
            onPressed: value && fee.canAfford
                ? () {
                    Navigator.of(dialogContext).pop();
                    _pushDeckRegistration(context, tournament,
                        acknowledgeFee: true);
                  }
                : null,
          ),
        ),
      ),
      secondaryButton: Builder(
        builder: (dialogContext) => TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: Text(TrTokens.cancelTxt.tr),
        ),
      ),
    );
  }

  void _pushDeckRegistration(BuildContext context, Tournament tournament,
      {required bool acknowledgeFee}) {
    final cubit = context.read<TournamentCubit>();

    Navigator.of(context).push(MaterialPageRoute(
      builder: (pageContext) => BlocProvider.value(
        value: cubit,
        child: DeckRegistrationPage(
          tournamentName: tournament.name,
          isExternalRegistration: tournament.isExternalRegistration,
          // 🚀 Dynamically set 3 vs 5 based on tournament format
          beyCount: tournament.beyVsType == '5v5' ? 5 : 3,
          isGhostRegistration: false,
          onSubmit: (beys, _) async {
            // 🚀 FIX: Map the array into PlayerDeck dynamically handling 3 to 5 beys
            final deck = PlayerDeck(
              bey1: beys[0],
              bey2: beys.length > 1 ? beys[1] : beys[0],
              bey3: beys.length > 2 ? beys[2] : beys[0],
              bey4: beys.length > 3 ? beys[3] : null,
              bey5: beys.length > 4 ? beys[4] : null,
            );

            cubit.registerForTournament(
              tournament.id,
              deck: deck,
              acknowledgeFee: acknowledgeFee,
            );

            if (tournament.isExternalRegistration &&
                tournament.externalRegistrationUrl != null) {
              final url = Uri.parse(tournament.externalRegistrationUrl!);
              try {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              } catch (_) {
                if (pageContext.mounted) {
                  ScaffoldMessenger.of(pageContext).showSnackBar(
                    SnackBar(
                      content: Text(TrTokens.couldNotOpenUrlError
                          .trParams({'url': url.toString()})),
                    ),
                  );
                }
              }
            }

            if (pageContext.mounted) Navigator.of(pageContext).pop();
          },
        ),
      ),
    ));
  }

  void _snack(BuildContext context, String msg, Color bg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: arenaBevel(cut: 10),
        margin: const EdgeInsets.all(12),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);

    return BlocConsumer<TournamentCubit, TournamentState>(
      listenWhen: (prev, curr) =>
          prev.isOperationLoading != curr.isOperationLoading ||
          prev.selectedTournament != curr.selectedTournament,
      listener: (context, state) {
        if (widget.autoRegister &&
            !_hasAutoOpened &&
            state.selectedTournament != null) {
          _hasAutoOpened = true;
          final t = state.selectedTournament!;
          final isRegistered = state.participants
              .any((p) => p.userId == _currentUserId && !p.hasLeft);

          if (t.isRegistrationOpen && !isRegistered) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _openDeckRegistration(context, t);
            });
          }
        }

        if (state.successMessage != null && !state.isOperationLoading) {
          _snack(context, state.successMessage!, kArenaSuccess);
          context.read<TournamentCubit>().clearMessages();
        }
        if (state.errorMessage != null && !state.isOperationLoading) {
          _snack(context, state.errorMessage!, cs.error);
          context.read<TournamentCubit>().clearMessages();
        }
      },
      builder: (context, state) {
        if (state.selectedTournament == null) {
          if (state.isLoading) {
            return Scaffold(
              backgroundColor: cs.surface,
              appBar: AppBar(),
              body: const Center(child: BeybladeSpinner()),
            );
          }
          return Scaffold(
            backgroundColor: cs.surface,
            appBar: AppBar(),
            body: Center(child: Text(TrTokens.tournamentNotFound.tr)),
          );
        }

        final t = state.selectedTournament!;

        if (t.isDeleted) {
          return _RedactedTournamentView(tournament: t, cs: cs, rc: rc);
        }

        final isHost = t.canManage;

        // This relies on Cubit fetching the user's specific entry since the
        // public RPC only returns 'approved' participants.
        final me = state.participants
            .where((p) => p.userId == _currentUserId)
            .firstOrNull;
        final isRegistered = me != null && (me.isPending || me.isApproved);

        return DefaultTabController(
          length: 3,
          initialIndex: widget.initialTab.clamp(0, 2),
          child: Scaffold(
            backgroundColor: cs.surface,
            appBar: AppBar(
              backgroundColor: cs.surface,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              title: Text(
                t.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontFamily: kArenaFont,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.6,
                    fontSize: 17),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go(AppConstants.shellTournaments);
                  }
                },
              ),
              bottom: HoloTabBar(
                isScrollable: true,
                fontFamily: kArenaFont,
                tabs: [
                  HoloTab(TrTokens.overviewTab.tr, icon: Icons.info_outline),
                  HoloTab(TrTokens.bracketStandingsTab.tr,
                      icon: Icons.account_tree_outlined),
                  HoloTab(TrTokens.participantsTab.tr,
                      icon: Icons.groups_outlined),
                ],
              ),
              actions: [
                ShareLinkButton(
                  path: DeepLinks.tournament(t.id),
                  title: t.name,
                  links: [
                    (
                      label: 'Share standings',
                      path: DeepLinks.tournamentStandings(t.id),
                      title: '${t.name} · Standings',
                    ),
                    (
                      label: 'Share matches',
                      path: DeepLinks.tournamentMatches(t.id),
                      title: '${t.name} · Matches',
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.flag_outlined),
                  tooltip: 'Report',
                  onPressed: () => showReportDialog(context,
                      targetType: ReportTargetType.tournament, targetId: t.id),
                ),
                if (t.isVerified && t.wageringEnabled)
                  IconButton(
                    icon: const Icon(Icons.casino_outlined),
                    tooltip: 'Predictions',
                    onPressed: () => context.push(
                      AppConstants.tournamentPredictionsRoute
                          .replaceFirst(':id', t.id),
                      extra: t.name,
                    ),
                  ),
                if (isHost)
                  IconButton(
                    icon: const Icon(Icons.settings),
                    tooltip: TrTokens.manageTournamentHead.tr,
                    // The dashboard has its own cubit: catch up on return.
                    onPressed: () => context
                        .push(AppConstants.tournamentManageRoute
                            .replaceFirst(':id', t.id))
                        .then((_) {
                      if (mounted) _handleRefresh();
                    }),
                  ),
              ],
            ),
            body: SafeArea(
              child: TabBarView(
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _OverviewTab(
                    tournament: t,
                    isRegistered: isRegistered,
                    myEntry: me,
                    rc: rc,
                    cs: cs,
                    onRefresh: _handleRefresh,
                    onRegister: () => _openDeckRegistration(context, t),
                    onWithdraw: () => _confirmWithdraw(context, t, me),
                  ),
                  RefreshIndicator(
                    color: cs.primary,
                    onRefresh: _handleRefresh,
                    child: BracketAndStandingsTab(
                      state: state,
                      rc: rc,
                      cs: cs,
                      currentUserId: _currentUserId,
                    ),
                  ),
                  _ParticipantsTab(
                    state: state,
                    currentUserId: _currentUserId,
                    rc: rc,
                    cs: cs,
                    onRefresh: _handleRefresh,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Redacted View ────────────────────────────────────────────────────────────
class _RedactedTournamentView extends StatelessWidget {
  const _RedactedTournamentView({
    required this.tournament,
    required this.cs,
    required this.rc,
  });

  final Tournament tournament;
  final ColorScheme cs;
  final dynamic rc;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        title: Text(TrTokens.tournamentDeletedHead.tr),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(AppConstants.shellTournaments);
            }
          },
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(rc.horizontalPadding),
          child: ArenaPanel(
            padding: EdgeInsets.all(rc.lg),
            accent: cs.error.withValues(alpha: 0.4),
            cut: 18,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.event_busy, size: 52, color: cs.error),
                SizedBox(height: rc.md),
                Text(tournament.name,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: kArenaFont,
                        fontSize: rc.bodyLG,
                        fontWeight: FontWeight.w800,
                        color: cs.onSurface)),
                SizedBox(height: rc.sm),
                Text(TrTokens.tournamentDeletedBody.tr,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant)),
                if (tournament.deletionReason != null &&
                    tournament.deletionReason!.trim().isNotEmpty) ...[
                  SizedBox(height: rc.md),
                  ArenaPanel(
                    padding: EdgeInsets.all(rc.md),
                    background: cs.surfaceContainerLowest,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(TrTokens.reasonTxt.tr,
                            style: arenaLabel(
                                color: cs.onSurfaceVariant, size: 10)),
                        const SizedBox(height: 6),
                        Text(tournament.deletionReason!),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
// ──────────────────────────────────────────────────────────────────────────
// Replaces the `_OverviewTab` class in tournament_detail_page.dart.
// Needs `import 'dart:async';` at the top of that file (for the
// countdown's Timer) if it isn't there already.
// `_StatTile` and `_InfoRow` in that file stay as they are; this uses them.
// Also needs timeline_tile.dart and step_rail.dart (StepBubble) imported.
//
// One call-site change in _TournamentDetailPageState.build, where
// _OverviewTab is constructed -- add these two arguments:
//
//     entryFee: state.feeInfo.hasFee ? state.feeInfo.formatted : null,
//     entryFeeNote: state.feeInfo.note,
//
// What it shows, top to bottom:
//   hero        name, phase (Live / Registration open / ...), description,
//               country, plus Private and entry-fee tags when they apply
//   at a glance players, deck format, start date (or Live / Ended)
//   matches     the existing live-matches and predictions entries
//   how it's played  each stage with its real rules: rounds, groups,
//               points per win/tie, score to win, top cut, third place
//   entry & prizes   fee (or Free), custom rewards, org ranking points
//   host        avatar and name, links to their page
//   schedule    registration opens/closes, start, end
//   actions     register / registered / withdraw, unchanged
// ──────────────────────────────────────────────────────────────────────────

class _OverviewTab extends StatelessWidget {
  final Tournament tournament;
  final bool isRegistered;
  final TournamentParticipant? myEntry;
  final dynamic rc;
  final ColorScheme cs;
  final Future<void> Function() onRefresh;
  final VoidCallback onRegister;
  final VoidCallback onWithdraw;

  /// Formatted fee (e.g. "$10.00") when the tournament charges one.
  final String? entryFee;
  final String? entryFeeNote;

  const _OverviewTab({
    required this.tournament,
    required this.isRegistered,
    required this.myEntry,
    required this.rc,
    required this.cs,
    required this.onRefresh,
    required this.onRegister,
    required this.onWithdraw,
    this.entryFee,
    this.entryFeeNote,
  });

  /// The next moment a visitor is waiting for, if any: registration
  /// opening, registration closing, or the start. Null once it's live,
  /// finished, or cancelled.
  ({DateTime at, String label})? _countdownTarget() {
    final t = tournament;
    if (t.status == TournamentStatus.ongoing ||
        t.status == TournamentStatus.completed ||
        t.status == TournamentStatus.cancelled) {
      return null;
    }
    if (t.isRegistrationUpcoming) {
      return (at: t.registrationOpenDate, label: 'Registration opens in');
    }
    if (t.isRegistrationOpen) {
      return (at: t.registrationDeadline, label: 'Registration closes in');
    }
    if (DateTime.now().isBefore(t.startDate.toLocal())) {
      return (at: t.startDate, label: 'Starts in');
    }
    return null;
  }

  /// Short form for the "Starts" tile: the time if it's today, otherwise
  /// the day. Keeps the tile to one line without losing the useful part.
  static String _startsShort(DateTime at) {
    final local = at.toLocal();
    final now = DateTime.now();
    final days = DateTime(local.year, local.month, local.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    if (days == 0) return DateFormat.jm().format(local);
    if (days == 1) return 'Tomorrow';
    return DateFormat.MMMd().format(local);
  }

  /// What a visitor needs to know right now. Derived instead of read from
  /// `status` directly: tournaments are created as 'upcoming' and stay
  /// that way while registration is open, so the raw status alone can't
  /// tell "open" from "closed".
  ({String label, Color color, IconData icon}) _phase() {
    final t = tournament;
    if (t.status == TournamentStatus.completed) {
      return (
        label: 'Completed',
        color: cs.onSurfaceVariant,
        icon: Icons.flag_outlined
      );
    }
    if (t.status == TournamentStatus.cancelled) {
      return (label: 'Cancelled', color: kArenaDanger, icon: Icons.block);
    }
    if (t.status == TournamentStatus.ongoing) {
      return (label: 'Live', color: kArenaSuccess, icon: Icons.bolt);
    }
    if (t.isRegistrationOpen) {
      return (
        label: 'Registration open',
        color: cs.primary,
        icon: Icons.how_to_reg
      );
    }
    if (t.isRegistrationUpcoming) {
      return (label: 'Opens soon', color: kArenaWarn, icon: Icons.schedule);
    }
    return (
      label: 'Registration closed',
      color: kArenaWarn,
      icon: Icons.event_busy
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    final hasLeft = myEntry?.hasLeft ?? false;
    final canRegister = t.isRegistrationOpen && !isRegistered && !hasLeft;
    final canWithdraw = isRegistered &&
        t.status != TournamentStatus.completed &&
        t.status != TournamentStatus.cancelled;
    final countryObj = GeoConstants.byCode(t.country);
    final bgUrl = t.displayImageUrl;
    final onImage = bgUrl != null;
    final heroFg = onImage ? Colors.white : cs.onSurface;
    final heroMuted = onImage ? Colors.white70 : cs.onSurfaceVariant;
    final phase = _phase();
    final isLive = t.status == TournamentStatus.ongoing;
    final isDone = t.status == TournamentStatus.completed;

    return RefreshIndicator(
      color: cs.primary,
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            rc.horizontalPadding, rc.md, rc.horizontalPadding, rc.xl * 2),
        children: [
          // ── Hero ──────────────────────────────────────────────────────
          ArenaFadeIn(
            child: Material(
              color: cs.surfaceContainerLow,
              clipBehavior: Clip.antiAlias,
              shape: arenaBevel(
                  border: cs.primary.withValues(alpha: 0.35),
                  width: 1.4,
                  cut: 20),
              child: InkWell(
                onTap: bgUrl != null
                    ? () => ImageViewerPage.show(context, url: bgUrl)
                    : null,
                child: Stack(
                  children: [
                    if (bgUrl != null)
                      Positioned.fill(
                        child: AppNetworkImage(url: bgUrl, fit: BoxFit.cover),
                      ),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: onImage
                            ? LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.45),
                                  Colors.black.withValues(alpha: 0.82),
                                ],
                              )
                            : LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  cs.primary.withValues(alpha: 0.16),
                                  cs.secondary.withValues(alpha: 0.10),
                                ],
                              ),
                      ),
                      padding: EdgeInsets.all(rc.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              ArenaTag(
                                label: phase.label,
                                color: phase.color,
                                icon: phase.icon,
                                fontSize: 9,
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                decoration: ShapeDecoration(
                                  color: onImage ? Colors.black54 : cs.surface,
                                  shape: arenaBevel(
                                      border: heroFg.withValues(alpha: 0.25),
                                      width: 1,
                                      cut: 6),
                                ),
                                child: Text(
                                  'ID: ${t.shortCode}',
                                  style: arenaLabel(
                                      color: heroFg, size: 10, spacing: 1),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: rc.lg),
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  t.name,
                                  style: TextStyle(
                                    fontFamily: kArenaFont,
                                    fontSize: rc.bodyLG + 6,
                                    height: 1.15,
                                    fontWeight: FontWeight.w900,
                                    color: heroFg,
                                  ),
                                ),
                              ),
                              if (t.isVerified) ...[
                                const SizedBox(width: 8),
                                const Icon(Icons.verified,
                                    size: 20, color: kArenaInfo),
                              ],
                            ],
                          ),
                          SizedBox(height: rc.sm),
                          Text(
                            t.description.isNotEmpty
                                ? t.description
                                : TrTokens.noDescriptionProvided.tr,
                            style: TextStyle(
                                fontSize: rc.body,
                                height: 1.35,
                                color: heroMuted),
                          ),
                          if (countryObj != null ||
                              t.isPrivate ||
                              entryFee != null) ...[
                            SizedBox(height: rc.md),
                            Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                if (countryObj != null)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CountryFlag(
                                          country: countryObj, size: 16),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${countryObj.name}, ${countryObj.region.code}',
                                        style: TextStyle(
                                          fontSize: rc.bodySM,
                                          color: heroMuted,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                if (entryFee != null)
                                  ArenaTag(
                                      label: '$entryFee entry',
                                      color: heroFg,
                                      icon: Icons.payments_outlined,
                                      fontSize: 9),
                                if (t.isPrivate)
                                  ArenaTag(
                                      label: 'Private',
                                      color: heroFg,
                                      icon: Icons.lock_outline,
                                      fontSize: 9),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: rc.md),

          // ── At a glance ───────────────────────────────────────────────
          // Each fact appears once on this page: format and scores live in
          // "How it's played", so these tiles cover what that section doesn't.
          ArenaFadeIn(
            index: 1,
            child: Row(
              children: [
                Expanded(
                  child: _StatTile(
                    icon: Icons.people,
                    label: TrTokens.participantsTab.tr,
                    value: '${t.currentParticipantCount}'
                        '${t.maxParticipants != null ? '/${t.maxParticipants}' : ''}',
                    color: kArenaSuccess,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatTile(
                    icon: Icons.style_outlined,
                    label: 'Deck',
                    value: t.beyVsType,
                    color: cs.secondary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatTile(
                    icon: Icons.event,
                    label: isLive || isDone ? 'Status' : 'Starts',
                    value: isLive
                        ? 'Live'
                        : isDone
                            ? 'Ended'
                            : _startsShort(t.startDate),
                    color: cs.primary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: rc.md),

          // ── Matches (unchanged entry points) ──────────────────────────
          ArenaFadeIn(
            index: 2,
            child: Material(
              color: cs.primary,
              clipBehavior: Clip.antiAlias,
              elevation: 4,
              shadowColor: cs.primary.withValues(alpha: 0.5),
              shape: arenaBevel(
                  border: cs.primary.withValues(alpha: 0.6),
                  width: 1.4,
                  cut: 18),
              child: Ink(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage(AppConstants.holo1WebP),
                    fit: BoxFit.cover,
                  ),
                ),
                child: InkWell(
                  onTap: () => context.push(AppConstants.tournamentMatchesRoute
                      .replaceFirst(':id', t.id)),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                        vertical: rc.lg, horizontal: rc.md),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: ShapeDecoration(
                            color: cs.onPrimary.withValues(alpha: 0.18),
                            shape: arenaBevel(
                                border: cs.onPrimary.withValues(alpha: 0.5),
                                width: 1.2,
                                cut: 8),
                          ),
                          child: Icon(Icons.sports_kabaddi,
                              color: cs.onPrimary, size: 24),
                        ),
                        SizedBox(width: rc.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                TrTokens.liveMatchesScoringHead.tr
                                    .toUpperCase(),
                                style: arenaLabel(
                                    color: cs.onPrimary,
                                    size: rc.bodyLG - 2,
                                    spacing: 1.4),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                TrTokens.liveMatchesScoringHead.tr,
                                style: TextStyle(
                                  fontSize: rc.bodySM,
                                  color: cs.onPrimary.withValues(alpha: 0.85),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios,
                            color: cs.onPrimary, size: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (t.isVerified && t.wageringEnabled) ...[
            SizedBox(height: rc.md),
            ArenaFadeIn(
              index: 3,
              child: ArenaPanel(
                padding: EdgeInsets.all(rc.md),
                accent: cs.secondary.withValues(alpha: 0.45),
                onTap: () => context.push(
                  AppConstants.tournamentPredictionsRoute
                      .replaceFirst(':id', t.id),
                  extra: t.name,
                ),
                child: Row(
                  children: [
                    Icon(Icons.casino_outlined, color: cs.secondary),
                    SizedBox(width: rc.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('PREDICTIONS',
                              style: arenaLabel(color: cs.secondary, size: 12)),
                          const SizedBox(height: 4),
                          Text(
                            'Back the champion, call pool records, and predict '
                            'open matches.',
                            style: TextStyle(
                                fontSize: rc.bodySM,
                                color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 8),
                          PredictionCurrencyChip(
                              currencyName: t.extras.wagerCurrencyName),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios,
                        size: 14, color: cs.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ],
          SizedBox(height: rc.xl),

          // ── How it's played ───────────────────────────────────────────
          const ArenaSectionTitle(title: "How it's played"),
          SizedBox(height: rc.sm),
          ArenaPanel(
            padding: EdgeInsets.all(rc.md),
            child: _StagesBreakdown(tournament: t),
          ),
          // Optional stadium; takes no space when the host didn't pick one.
          TournamentStadiumPanel(tournamentId: t.id),
          SizedBox(height: rc.lg),

          // ── Entry & prizes ────────────────────────────────────────────
          const ArenaSectionTitle(title: 'Entry & prizes', accent: kArenaWarn),
          SizedBox(height: rc.sm),
          ArenaPanel(
            padding: EdgeInsets.symmetric(horizontal: rc.sm, vertical: rc.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _InfoRow(
                    icon: Icons.payments_outlined,
                    label: 'Entry fee',
                    value: entryFee ?? 'Free',
                    cs: cs),
                if (entryFee != null &&
                    (entryFeeNote?.trim().isNotEmpty ?? false))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(36, 0, 6, 10),
                    child: Text(entryFeeNote!,
                        style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: cs.onSurfaceVariant)),
                  ),
                if (t.customRewards.isNotEmpty) ...[
                  const ArenaDivider(),
                  for (final reward in t.customRewards)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 9, horizontal: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.card_giftcard,
                              size: 18, color: kArenaWarn),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(reward,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, height: 1.3)),
                          ),
                        ],
                      ),
                    ),
                ],
                if (t.hostType == HostType.organization) ...[
                  const ArenaDivider(),
                  _OrgPoints(config: t.orgPointsConfig),
                ],
              ],
            ),
          ),
          SizedBox(height: rc.lg),

          PrizeSection(
            tournamentId: t.id,
            padding: EdgeInsets.only(bottom: rc.lg),
          ),
          // ── Host ──────────────────────────────────────────────────────
          ArenaSectionTitle(title: TrTokens.hostedByTxt.tr),
          SizedBox(height: rc.sm),
          ArenaPanel(
            padding: EdgeInsets.all(rc.sm),
            onTap: () {
              if (t.hostType == HostType.organization) {
                context.push(
                    AppConstants.orgDetailRoute.replaceFirst(':id', t.hostId));
              } else {
                final param = (t.hostUsername?.isNotEmpty == true)
                    ? t.hostUsername!
                    : t.hostId;
                context.push(
                    ProfileRoutes.publicPath.replaceFirst(':userId', param));
              }
            },
            child: Row(
              children: [
                ClipPath.shape(
                  shape: arenaBevel(cut: 8),
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: t.hostAvatarUrl != null
                        ? AppNetworkImage(
                            url: t.hostAvatarUrl!, fit: BoxFit.cover)
                        : ColoredBox(
                            color: cs.surfaceContainerHighest,
                            child: Icon(
                                t.hostType == HostType.organization
                                    ? Icons.corporate_fare
                                    : Icons.person,
                                size: 20,
                                color: cs.outline),
                          ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(t.hostName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                          ),
                          if (t.hostIsVerified) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified,
                                size: 14, color: kArenaInfo),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t.hostType == HostType.organization
                            ? 'Organization'
                            : (t.hostUsername?.isNotEmpty == true
                                ? '@${t.hostUsername}'
                                : 'Player'),
                        style:
                            TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 18,
                    color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
              ],
            ),
          ),
          SizedBox(height: rc.lg),

          // ── Schedule ──────────────────────────────────────────────────
          // Countdown moved out of the section title's trailing slot, where
          // it was squeezed beside the title, into its own full-width
          // panel that keeps itself current. Date rows stack label, date
          // and time vertically, so on a phone nothing gets cut off.
          ArenaSectionTitle(
            title: TrTokens.scheduleTitle.tr,
            accent: cs.secondary,
          ),
          SizedBox(height: rc.sm),
          if (_countdownTarget() case final target?) ...[
            _Countdown(
              target: target.at,
              label: target.label,
              // Crossing the deadline changes what this page should show
              // (register button, phase tag), so reload once when it hits.
              onElapsed: onRefresh,
            ),
            SizedBox(height: rc.sm),
          ],
          ArenaPanel(
            padding: EdgeInsets.symmetric(horizontal: rc.sm, vertical: rc.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (t.isRegistrationUpcoming) ...[
                  _ScheduleRow(
                      icon: Icons.lock_open,
                      label: 'Registration opens',
                      at: t.registrationOpenDate),
                  const ArenaDivider(),
                ],
                _ScheduleRow(
                    icon: Icons.how_to_reg_outlined,
                    label: TrTokens.registrationEndsTxt.tr,
                    at: t.registrationDeadline),
                const ArenaDivider(),
                _ScheduleRow(
                    icon: Icons.event,
                    label: TrTokens.startDateTxt.tr,
                    at: t.startDate),
                if (t.endDate != null) ...[
                  const ArenaDivider(),
                  _ScheduleRow(
                      icon: Icons.flag_outlined,
                      label: 'Ended',
                      at: t.endDate!),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text(
              'Times are shown in your local time zone.',
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
            ),
          ),
          SizedBox(height: rc.xl),

          // ── Actions (unchanged) ───────────────────────────────────────
          if (isRegistered) ...[
            ArenaPanel(
              padding: EdgeInsets.all(rc.md),
              accent: kArenaSuccess.withValues(alpha: 0.5),
              background: kArenaSuccess.withValues(alpha: 0.10),
              glow: true,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                      myEntry?.isPending == true
                          ? Icons.hourglass_top
                          : Icons.verified_user,
                      color: kArenaSuccess),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                        myEntry?.isPending == true
                            ? 'Registered, waiting for host approval'
                            : TrTokens.registeredSuccessBanner.tr,
                        textAlign: TextAlign.center,
                        style: arenaLabel(color: kArenaSuccess, size: 12)),
                  ),
                ],
              ),
            ),
            if (canWithdraw) ...[
              SizedBox(height: rc.sm),
              TextButton.icon(
                style: TextButton.styleFrom(
                    foregroundColor: kArenaDanger,
                    minimumSize: const Size(double.infinity, 44)),
                onPressed: onWithdraw,
                icon: const Icon(Icons.logout, size: 18),
                label: const Text('Withdraw from tournament'),
              ),
            ],
          ] else if (hasLeft)
            ArenaPanel(
              padding: EdgeInsets.all(rc.md),
              accent: kArenaDanger.withValues(alpha: 0.4),
              background: kArenaDanger.withValues(alpha: 0.08),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(myEntry!.isWithdrawn ? Icons.logout : Icons.gavel,
                      color: kArenaDanger),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                        myEntry!.isWithdrawn
                            ? 'You withdrew from this tournament'
                            : 'You were disqualified from this tournament',
                        textAlign: TextAlign.center,
                        style: arenaLabel(color: kArenaDanger, size: 12)),
                  ),
                ],
              ),
            )
          else if (canRegister)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 54),
                  shape: arenaBevel(cut: 12)),
              onPressed: onRegister,
              icon: const Icon(Icons.how_to_reg),
              label: Text(
                (t.isExternalRegistration
                        ? TrTokens.registerExternalTxt.tr
                        : TrTokens.registerNowTxt.tr)
                    .toUpperCase(),
                style: const TextStyle(
                    fontFamily: kArenaFont,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4),
              ),
            )
          else
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 54),
                  shape: arenaBevel(cut: 12)),
              onPressed: null,
              child: Text(t.isRegistrationUpcoming
                  ? TrTokens.registrationNotOpenTxt.tr
                  : TrTokens.registrationClosedTxt.tr),
            ),
        ],
      ),
    );
  }
}

// ── How it's played ──────────────────────────────────────────────────────────

/// Each stage as a numbered step with its rules underneath. Two-stage
/// formats (pool then bracket) get a connecting line between the steps;
/// single-stage formats get one step and no line.
class _StagesBreakdown extends StatelessWidget {
  const _StagesBreakdown({required this.tournament});

  final Tournament tournament;

  @override
  Widget build(BuildContext context) {
    final t = tournament;
    // Prefer the explicit stage columns, fall back to the combined format
    // string for older rows that only stored that.
    final s1 = t.stage1Kind == StageKind.none ? t.format.stage1 : t.stage1Kind;
    final s2 = t.stage2Kind == StageKind.none ? t.format.stage2 : t.stage2Kind;
    final twoStages = s1.isPool && s2.isBracket;

    final stage1Rules = <String>[
      if (s1 == StageKind.swiss) '${t.swissRounds} rounds',
      if (s1.isAnyGroups) '${t.preferredGroupCount} groups',
      if (s1 == StageKind.groupsSwiss) '${t.swissRounds} rounds per group',
      if (s1 == StageKind.roundRobin || s1.isAnyGroups) ...[
        'Win ${t.matchWinPoints} pts',
        'Draw ${t.matchTiePoints} pts',
      ],
      if (s1.isPool) 'First to ${t.poolTargetScore}',
      if (s1.isBracket) 'First to ${t.bracketTargetScore}',
      if (s1.isBracket && t.championshipTargetScore != t.bracketTargetScore)
        'Final: first to ${t.championshipTargetScore}',
      if (s1 == StageKind.singleElimination && t.hasThirdPlaceMatch)
        'Third place match',
    ];

    final stage2Rules = <String>[
      // The cut is picked by the host when the bracket starts.
      'Host picks who advances',
      'First to ${t.stage2TargetScore}',
      if (s2 == StageKind.singleElimination && t.hasThirdPlaceMatch)
        'Third place match',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stage(context, 0, s1, stage1Rules, isLast: !twoStages),
        if (twoStages) _stage(context, 1, s2, stage2Rules, isLast: true),
      ],
    );
  }

  Widget _stage(
      BuildContext context, int index, StageKind kind, List<String> rules,
      {required bool isLast}) {
    final cs = Theme.of(context).colorScheme;
    const bubble = 26.0;

    return TimelineTile(
      isFirst: index == 0,
      isLast: isLast,
      topSpacing: 0,
      indicatorSize: bubble,
      indicatorColumnWidth: 40,
      contentTopPadding: 2,
      contentRightPadding: 0,
      contentBottomPadding: isLast ? 0 : 18,
      indicator: StepBubble(
        index: index,
        state: StepNodeState.active,
        size: bubble,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(kind.label,
              style: TextStyle(
                  fontFamily: kArenaFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: cs.onSurface)),
          const SizedBox(height: 4),
          Text(kind.shortDescription,
              style: TextStyle(
                  fontSize: 12.5, height: 1.35, color: cs.onSurfaceVariant)),
          if (rules.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final r in rules) _RuleChip(label: r)],
            ),
          ],
        ],
      ),
    );
  }
}

class _RuleChip extends StatelessWidget {
  const _RuleChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: ShapeDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        shape: arenaBevel(
            border: cs.outlineVariant.withValues(alpha: 0.6), width: 1, cut: 6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: cs.onSurface)),
    );
  }
}

/// Org-hosted tournaments feed the org's ranking. Shown publicly because
/// it's part of why someone would enter.
class _OrgPoints extends StatelessWidget {
  const _OrgPoints({required this.config});

  final OrgPointsConfig config;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.leaderboard_outlined,
                  size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 12),
              Text('Org ranking points',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _RuleChip(label: '1st +${config.top1}'),
                _RuleChip(label: '2nd +${config.top2}'),
                _RuleChip(label: '3rd +${config.top3}'),
                _RuleChip(label: '4th +${config.top4}'),
                _RuleChip(label: 'Taking part +${config.registration}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Schedule ─────────────────────────────────────────────────────────────────

/// One schedule entry, stacked so nothing gets cut on a phone: the label
/// and date wrap freely on the left, and the time sits on the right at
/// its natural width. The old single-line row put label, spacer and the
/// whole "Oct 01, 2026 • 01:55 PM" string side by side with ellipsis, and
/// the time was the part that disappeared.
class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({
    required this.icon,
    required this.label,
    required this.at,
  });

  final IconData icon;
  final String label;
  final DateTime at;

  /// "Today, Oct 1" / "Tomorrow, Oct 2" / "Yesterday, Sep 30" when close,
  /// otherwise "Wed, Oct 1, 2026". Locale-aware via intl skeletons.
  static String _day(DateTime local) {
    final now = DateTime.now();
    final days = DateTime(local.year, local.month, local.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    final short = DateFormat.MMMd().format(local);
    return switch (days) {
      0 => 'Today, $short',
      1 => 'Tomorrow, $short',
      -1 => 'Yesterday, $short',
      _ => DateFormat.yMMMEd().format(local),
    };
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final local = at.toLocal();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                const SizedBox(height: 3),
                Text(_day(local),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Not Flexible on purpose: the time always gets its full width.
          Text(
            DateFormat.jm().format(local),
            style: TextStyle(
              fontFamily: kArenaFont,
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// Live countdown to the next thing a visitor is waiting for.
///
/// Ticks only as often as what's on screen can change: at each minute
/// boundary while more than an hour is left, every second in the last
/// hour (when seconds are shown). One-shot timers rescheduled each tick,
/// not a fixed periodic one, so there's no wasted rebuild in between.
class _Countdown extends StatefulWidget {
  const _Countdown({
    required this.target,
    required this.label,
    this.onElapsed,
  });

  final DateTime target;
  final String label;

  /// Called once when the countdown reaches zero.
  final Future<void> Function()? onElapsed;

  @override
  State<_Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<_Countdown> {
  Timer? _timer;
  bool _elapsedFired = false;

  Duration get _left => widget.target.difference(DateTime.now());

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(covariant _Countdown old) {
    super.didUpdateWidget(old);
    if (old.target != widget.target) {
      _elapsedFired = false;
      _schedule();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    final left = _left;

    if (left <= Duration.zero) {
      if (!_elapsedFired) {
        _elapsedFired = true;
        // After the frame, so the reload never starts mid-build.
        WidgetsBinding.instance
            .addPostFrameCallback((_) => widget.onElapsed?.call());
      }
      return;
    }

    // <= so that at exactly 1h left it switches to seconds right away;
    // with < it waited a full minute and skipped 59m 59s..59m 01s.
    final unitMs = left <= const Duration(hours: 1) ? 1000 : 60000;
    final remainder = left.inMilliseconds % unitMs;
    _timer = Timer(
      Duration(milliseconds: remainder == 0 ? unitMs : remainder),
      () {
        if (!mounted) return;
        setState(() {});
        _schedule();
      },
    );
  }

  static String _format(Duration d) {
    final h = d.inHours % 24;
    final m = d.inMinutes % 60;
    if (d.inDays > 0) return '${d.inDays}d ${h}h ${m}m';
    if (d.inHours > 0) return '${h}h ${m}m';
    return '${m}m ${(d.inSeconds % 60).toString().padLeft(2, '0')}s';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final left = _left;
    final tone = left < const Duration(hours: 24) ? kArenaWarn : cs.primary;

    return ArenaPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      accent: tone.withValues(alpha: 0.5),
      background: tone.withValues(alpha: 0.08),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, color: tone, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.label,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                const SizedBox(height: 2),
                Text(
                  left <= Duration.zero ? 'Now' : _format(left),
                  style: TextStyle(
                    fontFamily: kArenaFont,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                    // Fixed-width digits so the text doesn't jitter as
                    // the seconds change.
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ArenaPanel(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      accent: color.withValues(alpha: 0.32),
      cut: 10,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: kArenaFont,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: arenaLabel(color: cs.onSurfaceVariant, size: 9, spacing: 1),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme cs;

  const _InfoRow(
      {required this.icon,
      required this.label,
      required this.value,
      required this.cs});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11.0, horizontal: 6.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          Text(label,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
          const Spacer(),
          Flexible(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

// ── Participants Tab ─────────────────────────────────────────────────────────
/// Since tournaments_get_public_participants ONLY returns approved participants,
/// there's no need to manually filter or sort by withdrawn status here.
class _ParticipantsTab extends StatelessWidget {
  final TournamentState state;
  final String currentUserId;
  final dynamic rc;
  final ColorScheme cs;
  final Future<void> Function() onRefresh;

  const _ParticipantsTab({
    required this.state,
    required this.currentUserId,
    required this.rc,
    required this.cs,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final t = state.selectedTournament;
    if (t == null) return const SizedBox.shrink();

    final hasTournamentStarted = t.status == TournamentStatus.ongoing ||
        t.status == TournamentStatus.completed ||
        DateTime.now().toUtc().isAfter(t.startDate.toUtc());

    // The public RPC only returns 'approved' status players. We don't need
    // to filter them or sort withdrawn users to the bottom anymore.
    final visible = state.participants;

    // Check if the current user has a pending local registration
    final myPending =
        state.participants.any((p) => p.userId == currentUserId && p.isPending);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(rc.md, rc.sm, rc.md, rc.sm),
          child: Row(
            children: [
              Icon(Icons.groups, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Text('${visible.length}',
                  style: arenaLabel(color: cs.onSurface, size: 15, spacing: 0)),
              const SizedBox(width: 6),
              Text(TrTokens.participantsTab.tr.toUpperCase(),
                  style: arenaLabel(color: cs.onSurfaceVariant, size: 10)),
              if (t.maxParticipants != null) ...[
                const SizedBox(width: 6),
                Text('/ ${t.maxParticipants}',
                    style: arenaLabel(color: cs.onSurfaceVariant, size: 10)),
              ],
            ],
          ),
        ),
        if (myPending)
          Padding(
            padding: EdgeInsets.fromLTRB(rc.md, 0, rc.md, rc.sm),
            child: ArenaPanel(
              padding: EdgeInsets.all(rc.sm),
              accent: kArenaWarn.withValues(alpha: 0.5),
              background: kArenaWarn.withValues(alpha: 0.08),
              child: Row(children: [
                const Icon(Icons.hourglass_top, size: 16, color: kArenaWarn),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      'Your registration is waiting for the host. You’ll appear here once approved.',
                      style: TextStyle(fontSize: 12, color: cs.onSurface)),
                ),
              ]),
            ),
          ),
        const ArenaDivider(),
        Expanded(
          child: RefreshIndicator(
            color: cs.primary,
            onRefresh: onRefresh,
            child: visible.isEmpty
                ? LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: constraints.maxHeight,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.person_off_outlined,
                                  size: 46,
                                  color: cs.onSurfaceVariant
                                      .withValues(alpha: 0.5)),
                              SizedBox(height: rc.md),
                              Text(TrTokens.noParticipantsYet.tr,
                                  style: arenaLabel(
                                      color: cs.onSurfaceVariant, size: 12)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding:
                        EdgeInsets.fromLTRB(rc.sm, rc.sm, rc.sm, rc.xl * 2),
                    itemCount: visible.length,
                    itemBuilder: (context, index) {
                      final p = visible[index];
                      final isMe = p.userId == currentUserId;

                      return ArenaFadeIn(
                        index: index,
                        child: _ApprovedParticipantTile(
                          participant: p,
                          isMe: isMe,
                          canSeeDeck:
                              hasTournamentStarted || isMe || t.canManage,
                          tournamentId: t.id,
                          rc: rc,
                          cs: cs,
                        ),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _ApprovedParticipantTile extends StatelessWidget {
  const _ApprovedParticipantTile({
    required this.participant,
    required this.isMe,
    required this.canSeeDeck,
    required this.tournamentId,
    required this.rc,
    required this.cs,
  });

  final TournamentParticipant participant;
  final bool isMe;
  final bool canSeeDeck;
  final String tournamentId;
  final dynamic rc;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final p = participant;
    final countryObj = GeoConstants.byCode(p.country);

    return ArenaPanel(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: rc.sm, vertical: rc.sm),
      accent: isMe
          ? cs.primary.withValues(alpha: 0.5)
          : cs.outlineVariant.withValues(alpha: 0.4),
      background: isMe ? cs.primary.withValues(alpha: 0.07) : null,
      cut: 12,
      onTap: p.username != null
          ? () => context.push('/profile/${p.username}')
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _ProfileAvatar(participant: p),
          SizedBox(width: rc.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _ProfileNameRow(participant: p, isMe: isMe),

                // Keep this just in case the backend changes to include them later
                if (p.hasLeft) ...[
                  const SizedBox(height: 4),
                  ArenaTag(
                      label: p.isWithdrawn ? 'Withdrawn' : 'Disqualified',
                      color: kArenaDanger,
                      icon: p.isWithdrawn ? Icons.logout : Icons.gavel,
                      fontSize: 9),
                ],
                const SizedBox(height: 3),
                Row(
                  children: [
                    if (p.username != null)
                      Flexible(
                        child: Text('@${p.username}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11, color: cs.onSurfaceVariant)),
                      ),
                    if (p.username != null && countryObj != null)
                      Text(' • ',
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant)),
                    if (countryObj != null) ...[
                      CountryFlag(country: countryObj, size: 12),
                      const SizedBox(width: 4),
                      Text(countryObj.region.code,
                          style: TextStyle(
                              fontSize: 11, color: cs.onSurfaceVariant)),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                // Deck line
                p.deck != null
                    ? (canSeeDeck
                        ? InkWell(
                            onTap: () => showDeckDialog(
                              context,
                              title: "${p.displayName}'s Deck",
                              beys: p.deck!.beys,
                            ),
                            customBorder: arenaBevel(cut: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: ShapeDecoration(
                                color: cs.primary.withValues(alpha: 0.10),
                                shape: arenaBevel(
                                    border: cs.primary.withValues(alpha: 0.45),
                                    width: 1,
                                    cut: 6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.visibility_outlined,
                                      size: 12, color: cs.primary),
                                  const SizedBox(width: 5),
                                  Text('View deck',
                                      style: arenaLabel(
                                          color: cs.primary,
                                          size: 10,
                                          spacing: 0.8)),
                                ],
                              ),
                            ),
                          )
                        : Text(TrTokens.deckHiddenUntilStart.tr,
                            style: TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: cs.onSurfaceVariant)))
                    : Text(TrTokens.noDeckSubmitted.tr,
                        style: TextStyle(fontSize: 11, color: cs.outline)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.participant});
  final TournamentParticipant participant;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = participant;

    final avatar = Container(
      padding: const EdgeInsets.all(2),
      decoration: ShapeDecoration(
        shape: arenaBevel(
            border: cs.outlineVariant.withValues(alpha: 0.6),
            width: 1.2,
            cut: 10),
      ),
      child: ClipPath.shape(
        shape: arenaBevel(cut: 8),
        child: SizedBox(
          width: 38,
          height: 38,
          child: p.avatarUrl != null
              ? Image.network(p.avatarUrl!, fit: BoxFit.cover)
              : Container(
                  color: cs.surfaceContainerHighest,
                  child: Icon(Icons.person, size: 20, color: cs.outline),
                ),
        ),
      ),
    );

    if (p.username == null) return avatar;
    return InkWell(
      customBorder: arenaBevel(cut: 10),
      onTap: () => context.push('/profile/${p.username}'),
      child: avatar,
    );
  }
}

class _ProfileNameRow extends StatelessWidget {
  const _ProfileNameRow({required this.participant, required this.isMe});
  final TournamentParticipant participant;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(participant.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontFamily: kArenaFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: cs.onSurface)),
        ),
        if (participant.isVerified) ...[
          const SizedBox(width: 4),
          const Icon(Icons.verified, size: 14, color: kArenaInfo),
        ],
        if (isMe) ...[
          const SizedBox(width: 8),
          ArenaTag(label: TrTokens.youBadge.tr, color: cs.primary, fontSize: 8),
        ],
      ],
    );
  }
}
