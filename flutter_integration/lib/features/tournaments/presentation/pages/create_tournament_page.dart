import 'package:clasher_st/core/config/media_target.dart';
import 'package:clasher_st/core/constants/trc_constant_tokens.dart';
import 'package:clasher_st/core/init_injection/injection.dart';
import 'package:clasher_st/core/responsive/responsive.dart';
import 'package:clasher_st/core/services/translation/translation_helper.dart';
import 'package:clasher_st/core/widgets/app_beyblade_loading_indicator.dart';
import 'package:clasher_st/core/widgets/app_drop_down.dart';
import 'package:clasher_st/core/widgets/app_info_chip.dart';
import 'package:clasher_st/core/widgets/app_media_picker_helper.dart';
import 'package:clasher_st/core/widgets/app_text_field.dart';
import 'package:clasher_st/core/widgets/app_widgets.dart';
import 'package:clasher_st/core/widgets/holow_components.dart';
import 'package:clasher_st/features/auth/presentation/cubits/auth_flow_cubit/auth_cubit.dart';
import 'package:clasher_st/features/beyblade/b_routes/beyblade_routes.dart';
import 'package:clasher_st/features/beyblade/parts_list.dart';
import 'package:clasher_st/features/beyblade/presentation/cubit/parts_list_cubit/parts_list_cubit.dart';
import 'package:clasher_st/features/beyblade/presentation/widgets/part_list_editor.dart';
import 'package:clasher_st/features/orgs/domain/entities/entities.dart';
import 'package:clasher_st/features/orgs/presentation/cubits/org_cubit/org_cubit.dart';
import 'package:clasher_st/features/tournaments/data/model/models.dart';
import 'package:clasher_st/features/tournaments/data/tournament_stadium_repository.dart';
import 'package:clasher_st/features/tournaments/domain/entities/entities.dart';
import 'package:clasher_st/features/tournaments/presentation/cubits/tournament_cubit.dart';
import 'package:clasher_st/features/tournaments/presentation/widgets/create_tournament_widgets/create_tourn_widgets.dart';
import 'package:clasher_st/features/tournaments/presentation/widgets/stadium_picker_field.dart';
import 'package:clasher_st/features/tournaments/presentation/widgets/step_trail.dart';
import 'package:clasher_st/features/user_dt/presentation/cubits/profile_CU/profile_cubit.dart';
import 'package:clasher_st/features/user_dt/presentation/widgets/timeline_line.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:clasher_st/features/prizes/domain/prize_drafts.dart';
import 'package:clasher_st/features/prizes/domain/prize_repository.dart';
import 'package:clasher_st/features/prizes/presentation/widgets/prize_planner.dart';
import 'package:clasher_st/features/predictions/presentation/cubits/wallet_cubit/wallet_cubit.dart';

const currencies = [
  'USD',
  'EUR',
  'GBP',
  'VND',
  'INR',
  'PKR',
  'PHP',
  'IDR',
  'MYR',
  'SGD',
  'THB',
  'JPY',
  'AUD',
  'CAD',
  'BRL',
  'MXN',
];

class CreateTournamentPage extends StatefulWidget {
  const CreateTournamentPage({super.key});

  @override
  State<CreateTournamentPage> createState() => _CreateTournamentPageState();
}

class _CreateTournamentPageState extends State<CreateTournamentPage> {
  late final TournamentDraft _draft;

  static const _steps = CreateStep.values;

  int _step = 0;
  String? _stepError;
  bool _savingPrizes = false;

  /// Index of the first step that doesn't validate (steps.length when all
  /// do). Drives the wide layout's rail and "complete" ticks. Stored so the
  /// page rebuilds only when it changes, not on every keystroke.
  late int _firstInvalid;

  /// Wide layout shows every section at once; tapping the rail scrolls to
  /// a section through these.
  final _sectionKeys = {for (final s in _steps) s: GlobalKey()};

  /// Built once. When the page rebuilds (step change, validity change),
  /// Flutter sees the same widget instances and skips them; each block
  /// inside updates itself through _DraftSelect instead.
  late final Map<CreateStep, Widget> _sections = {
    for (final s in _steps) s: _section(s),
  };
  late final Widget _summaryWide =
      _SummaryCard(draft: _draft, onCreate: _submit, showCreate: true);
  late final Widget _summaryPhone =
      _SummaryCard(draft: _draft, onCreate: _submit, showCreate: false);

  @override
  void initState() {
    super.initState();
    _draft = TournamentDraft(
      hostId: sl<AuthCubit>().state.isAuthenticated
          ? sl<AuthCubit>().state.user!.id
          : '',
    )..addListener(_onDraftChanged);
    _firstInvalid = _draft.firstInvalid()?.index ?? _steps.length;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<OrganizationCubit>().loadMyOrganizations();
      context.read<ProfileCubit>().loadProfile();
    });
  }

  @override
  void dispose() {
    _draft
      ..removeListener(_onDraftChanged)
      ..dispose();
    super.dispose();
  }

  /// The page itself only rebuilds when validity changes: the rail, the
  /// "complete" ticks, or the error under the buttons. Everything else
  /// (typing, toggles, pickers) is picked up by the blocks that show it.
  /// A visible error is re-checked rather than cleared, so it disappears
  /// once fixed and updates if a different problem is now first.
  void _onDraftChanged() {
    if (!mounted) return;
    _syncHostVerified(silent: true);
    final first = _draft.firstInvalid()?.index ?? _steps.length;
    final error = _stepError == null ? null : _draft.validate(_steps[_step]);
    if (first != _firstInvalid || error != _stepError) {
      setState(() {
        _firstInvalid = first;
        _stepError = error;
      });
    }
  }

  /// Currency prizes need a verified organization as host.
  bool _hostIsVerifiedOrg() {
    if (_draft.hostType != HostType.organization) return false;
    final orgs = context.read<OrganizationCubit>().state.managedOrganizations;
    return orgs.any((o) => o.id == _draft.hostId && o.isVerified);
  }

  /// Keeps draft.hostVerifiedOrg in step with the host picker and the org
  /// list. [silent] when called from the draft's own listener: the page's
  /// listener runs first, so the blocks listening after it already see the
  /// new value in the same notification.
  void _syncHostVerified({bool silent = false}) {
    final verified = _hostIsVerifiedOrg();
    if (verified == _draft.hostVerifiedOrg) return;
    if (silent) {
      _draft.hostVerifiedOrg = verified;
    } else {
      _draft.update(() => _draft.hostVerifiedOrg = verified);
    }
  }

  String _userHostName() {
    final profile = context.read<ProfileCubit>().state.currentProfile;
    if (profile?.displayName?.isNotEmpty == true) return profile!.displayName!;
    if (profile?.username?.isNotEmpty == true) return profile!.username!;
    return TrTokens.playerHeader.tr;
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _pickCover() async {
    FocusScope.of(context).unfocus();
    await MediaPickerHelper.pickForSpec(
      context: context,
      hasExisting: _draft.coverBytes != null,
      spec: MediaTarget.tournamentCover,
      onPicked: (result) async {
        if (mounted) _draft.update(() => _draft.coverBytes = result?.bytes);
      },
    );
  }

  /// One Cupertino wheel for date and time. The start can't be picked
  /// earlier than the registration deadline: the wheel stops there.
  Future<void> _pickDateTime({required bool registration}) async {
    FocusScope.of(context).unfocus();
    final now = DateTime.now();

    final floor = registration ? now : (_draft.regDeadline ?? now);
    final initial = (registration ? _draft.regDeadline : _draft.startDate) ??
        (registration
            ? now.add(const Duration(days: 1))
            : floor.add(const Duration(hours: 2)));

    final picked = await CupertinoDateTimeSheet.show(
      context,
      title: registration
          ? TrTokens.registrationDeadlineTxt.tr
          : TrTokens.startDateTxt.tr,
      initial: initial,
      minimum: floor,
      maximum: now.add(const Duration(days: 365)),
    );
    if (picked == null || !mounted) return;

    _draft.update(() {
      if (registration) {
        _draft.regDeadline = picked;
        // A deadline past the chosen start would leave an invalid pair;
        // clear the start so it gets picked again.
        if (_draft.startDate != null && _draft.startDate!.isBefore(picked)) {
          _draft.startDate = null;
        }
      } else {
        _draft.startDate = picked;
      }
    });
  }

  void _next() {
    final error = _draft.validate(_steps[_step]);
    setState(() {
      _stepError = error;
      if (error == null && _step < _steps.length - 1) _step += 1;
    });
  }

  void _goTo(int index) => setState(() {
        _step = index;
        _stepError = null;
      });

  void _scrollToSection(CreateStep step) {
    final ctx = _sectionKeys[step]!.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOutCubic,
      alignment: 0.02,
    );
  }

  Future<void> _submit() async {
    if (_savingPrizes) return;
    final bad = _draft.firstInvalid();
    if (bad != null) {
      setState(() {
        _step = bad.index;
        _stepError = _draft.validate(bad);
      });
      _scrollToSection(bad); // no-op on phones; there it's the step change
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_stepError!)));
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final prizeRepo = sl<PrizeRepository>();
    final prizes = _draft.prizes;
    final hostOrgId =
        _draft.hostType == HostType.organization ? _draft.hostId : null;
    // Organization amounts only count for the organization hosting.
    final poolPlan = _draft.poolPlan.forHost(hostOrgId);
    final id = await context.read<TournamentCubit>().createTournament(
          _draft.toRequest(
            userHostName: _userHostName(),
            // Organizations need the Entry fees feature (admin approval).
            canChargeFee: _draft.hostType != HostType.organization ||
                context
                    .read<OrganizationCubit>()
                    .state
                    .unlockedFeatures
                    .contains(OrgFeatureType.payments.toJson()),
          ),
        );
    if (id == null || !mounted) return;

    // Optional stadium: stored right after creation, like the prizes.
    final stadium = _draft.stadiumDataId;
    if (stadium != null) {
      try {
        await sl<TournamentStadiumRepository>().setStadium(id, stadium);
      } catch (e) {
        messenger.showSnackBar(SnackBar(
            content: Text('Tournament created, but the stadium was not '
                'saved: $e')));
      }
      if (!mounted) return;
    }

    // The tournament exists now, so the planned prizes can be saved.
    if (prizes.isNotEmpty || !poolPlan.isEmpty) {
      setState(() => _savingPrizes = true);
      // Fund the prize pool first, then save the prizes.
      final setup = await setUpTournamentPrizes(prizeRepo, id,
          prizes: prizes, pool: poolPlan, hostOrgId: hostOrgId);
      // Your own wallet may have paid in; every screen reads the app wallet.
      if (!poolPlan.isEmpty) sl<WalletCubit>().load(silent: true);
      final result = setup.prizes;
      if (setup.fundingError != null) {
        messenger.showSnackBar(SnackBar(content: Text(setup.fundingError!)));
      }
      if (result.failed > 0) {
        messenger.showSnackBar(SnackBar(
            content: Text(TrTokens.prizeDraftSomeFailed
                .trParams({'count': '${result.failed}'}))));
      } else if (result.imagesFailed > 0) {
        messenger.showSnackBar(SnackBar(
            content: Text(TrTokens.prizeDraftImagesFailed
                .trParams({'count': '${result.imagesFailed}'}))));
      }
      if (!mounted) return;
      setState(() => _savingPrizes = false);
    }
    context.pop();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  Widget _section(CreateStep step) => switch (step) {
        CreateStep.format => _FormatStep(draft: _draft),
        CreateStep.basics =>
          _BasicsStep(draft: _draft, onPickCover: _pickCover),
        CreateStep.feeRewards => FeeRewardsStep(draft: _draft),
        CreateStep.registration =>
          _RegistrationStep(draft: _draft, onPickDate: _pickDateTime),
      };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    final wide =
        MediaQuery.sizeOf(context).width >= AppBreakpoints.tabletMedium;

    return BlocProvider(
      // The host's saved ban/approve lists for the Part rules section.
      create: (_) => sl<PartListsCubit>()..load(),
      child: BlocListener<TournamentCubit, TournamentState>(
        listenWhen: (p, c) => p.isOperationLoading != c.isOperationLoading,
        listener: (context, state) {
          if (state.isOperationLoading) return;
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(state.errorMessage!), backgroundColor: cs.error));
            context.read<TournamentCubit>().clearMessages();
          } else if (state.successMessage != null) {
            // _submit closes the page once the prizes are saved.
            context.read<TournamentCubit>().clearMessages();
          }
        },
        child: Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(
            title: Text(TrTokens.createTournamentHead.tr),
            centerTitle: !wide,
          ),
          body: BlocListener<OrganizationCubit, OrganizationState>(
            // The org list arrives after the page opens; whether the chosen
            // org is verified decides if prizes can carry currency.
            listenWhen: (p, c) => p.myOrgs != c.myOrgs,
            listener: (_, __) => _syncHostVerified(),
            // No leaving halfway through saving the prizes.
            child: PopScope(
              canPop: !_savingPrizes,
              child: Stack(children: [
                SafeArea(child: wide ? _wideLayout(rc) : _stepLayout(rc)),
                if (_savingPrizes)
                  Positioned.fill(
                    child: ColoredBox(
                      color: cs.scrim.withValues(alpha: 0.25),
                      child: Center(
                        child: HoloCard(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 16),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2.5)),
                            const SizedBox(width: 12),
                            Text(TrTokens.prizeDraftSaving.tr),
                          ]),
                        ),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _wideLayout(ResponsiveConfig rc) {
    // Every section is visible, so "progress" means how far the form is
    // valid: everything before the first invalid section reads as done.
    final firstInvalid = _firstInvalid;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                        rc.horizontalPadding, rc.md, rc.md, rc.md),
                    child: StepRail(
                      steps: _steps,
                      current: firstInvalid,
                      showLabels: true,
                      onTap: (i) => _scrollToSection(_steps[i]),
                    ),
                  ),
                  Expanded(
                    // Every section is built up front (a Column, not a lazy
                    // ListView). The rail and "Create" jump to a section with
                    // Scrollable.ensureVisible, which can't reach a section a
                    // lazy list hasn't built yet -- on a big browser window
                    // that was everything below the fold.
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                          rc.horizontalPadding, rc.xs, rc.md, rc.xl),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final step in _steps) ...[
                            KeyedSubtree(
                              key: _sectionKeys[step],
                              child: SectionShell(
                                step: step,
                                complete: step.index < firstInvalid,
                                child: _sections[step]!,
                              ),
                            ),
                            SizedBox(height: rc.md),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 360,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    rc.sm, rc.md, rc.horizontalPadding, rc.xl),
                child: _summaryWide,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepLayout(ResponsiveConfig rc) {
    final cs = Theme.of(context).colorScheme;
    final last = _step == _steps.length - 1;
    final step = _steps[_step];

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
              rc.horizontalPadding, rc.md, rc.horizontalPadding, 0),
          child: StepRail(
            steps: _steps,
            current: _step,
            // Labels would truncate at phone width; the heading below
            // names the step in full instead.
            showLabels: false,
            // Only backwards: jumping ahead would skip validation.
            canTap: (i) => i < _step,
            onTap: _goTo,
          ),
        ),
        // Only the current step is built. IndexedStack built and laid out
        // all four on every rebuild. Nothing is lost by switching: the form
        // lives in the draft (controllers included), and PageStorageKey
        // gives each step back its scroll position.
        Expanded(
          child: SingleChildScrollView(
            key: PageStorageKey<String>('create-step-${step.name}'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: EdgeInsets.fromLTRB(
                rc.horizontalPadding, rc.lg, rc.horizontalPadding, rc.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StepRailHeader(index: _step, total: _steps.length, step: step),
                SizedBox(height: rc.lg),
                _sections[step]!,
                // Review before creating, on the last step only.
                if (last) ...[
                  const BlockDivider(),
                  _summaryPhone,
                ],
              ],
            ),
          ),
        ),
        Material(
          color: cs.surface,
          elevation: 8,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                rc.horizontalPadding, rc.sm, rc.horizontalPadding, rc.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_stepError != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, size: 15, color: cs.error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(_stepError!,
                              style: TextStyle(color: cs.error, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    if (_step > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: HoloActionButton(
                          label: TrTokens.backBtn.tr,
                          icon: Icons.arrow_back,
                          variant: HoloButtonVariant.outline,
                          onPressed: () => _goTo(_step - 1),
                        ),
                      ),
                    Expanded(
                      child: BlocBuilder<TournamentCubit, TournamentState>(
                        buildWhen: (p, c) =>
                            p.isOperationLoading != c.isOperationLoading,
                        builder: (context, state) => HoloActionButton(
                          // Naming the next step tells people how much is
                          // left.
                          label: last
                              ? TrTokens.createTxt.tr
                              : TrTokens.nextStepFormat.tr
                                  .replaceFirst('%s', _steps[_step + 1].title),
                          trailingIcon:
                              last ? Icons.check : Icons.arrow_forward,
                          expand: true,
                          isLoading: state.isOperationLoading,
                          onPressed: last ? _submit : _next,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  LAYOUT PIECES
// ═════════════════════════════════════════════════════════════════════════════

/// Rebuilds [builder] only when [select] returns something different: the
/// same idea as BlocSelector / context.select, for the page's draft.
///
/// Return exactly what the subtree shows, as a record when it's several
/// values: records compare field by field, so `(d.stage1, d.stage2)` only
/// rebuilds when one of the two changes. Every listener still runs its
/// select on each change, but a select is a few field reads; rebuilding
/// and laying out widgets only happens where something visible changed.
class _DraftSelect<T> extends StatefulWidget {
  const _DraftSelect({
    required this.draft,
    required this.select,
    required this.builder,
  });

  final TournamentDraft draft;
  final T Function(TournamentDraft d) select;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<_DraftSelect<T>> createState() => _DraftSelectState<T>();
}

class _DraftSelectState<T> extends State<_DraftSelect<T>> {
  late T _value = widget.select(widget.draft);

  @override
  void initState() {
    super.initState();
    widget.draft.addListener(_onChange);
  }

  @override
  void didUpdateWidget(covariant _DraftSelect<T> old) {
    super.didUpdateWidget(old);
    if (!identical(old.draft, widget.draft)) {
      old.draft.removeListener(_onChange);
      widget.draft.addListener(_onChange);
    }
    _value = widget.select(widget.draft);
  }

  @override
  void dispose() {
    widget.draft.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    final next = widget.select(widget.draft);
    if (next != _value) setState(() => _value = next);
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}

class BlockDivider extends StatelessWidget {
  const BlockDivider({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Divider(
        height: 1,
        thickness: 1,
        // Same colour as every HoloCard edge (colorScheme.outline), so the
        // dividers match the cards. My earlier half-transparent
        // outlineVariant measured 1.08:1 on white: invisible.
        color: cs.outline,
      ),
    );
  }
}

/// The explanation behind a block, shown by the info marker next to the
/// heading. [icon] heads the popup; [details] is its body.
class FormHint {
  const FormHint(this.icon, this.details);

  final IconData icon;
  final String details;
}

/// One main category of a step: heading (with an optional info marker
/// right after its tab), then the content. Explanations live in the chip's popup, so
/// the page shows headings and controls, and the reasoning is one tap away
/// for whoever needs it.
class FormBlock extends StatelessWidget {
  const FormBlock({
    super.key,
    required this.title,
    this.hint,
    this.trailing,
    required this.child,
  });

  final String title;
  final FormHint? hint;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final h = hint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HoloSectionLabel(
          title: title.tr,
          trailing: trailing,
          // Right where the tab's facet ends, on the rule.
          info: h == null
              ? null
              : InfoChip(
                  title: title.tr,
                  details: h.details.tr,
                  popupIcon: h.icon,
                ),
          alignInfoEnd: true,
          infoEndPadding: 12.0,
        ),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}

class FormBlocks extends StatelessWidget {
  const FormBlocks({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const BlockDivider(),
          children[i],
        ],
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  STEP 1: FORMAT
// ═════════════════════════════════════════════════════════════════════════════

class _FormatStep extends StatelessWidget {
  const _FormatStep({required this.draft});

  final TournamentDraft draft;

  @override
  Widget build(BuildContext context) {
    // Each block rebuilds only for the values it shows: changing the deck
    // size doesn't rebuild the stage tiles, and so on.
    return FormBlocks(children: [
      FormBlock(
        title: TrTokens.deckFormatTitle,
        hint: const FormHint(
          Icons.style_outlined,
          TrTokens.deckFormatHint,
        ),
        child: _DraftSelect(
          draft: draft,
          select: (x) => x.beyVsType,
          builder: (context, beyVsType) => HoloSegmented<String>(
            value: beyVsType,
            onChanged: (v) => draft.update(() => draft.beyVsType = v),
            options: const [
              HoloOption('3v3', '3v3 Combos'),
              HoloOption('5v5', '5v5 Combos'),
            ],
          ),
        ),
      ),
      FormBlock(
        title: TrTokens.howIsItPlayedTitle,
        hint: const FormHint(
          Icons.account_tree_outlined,
          TrTokens.howIsItPlayedHint,
        ),
        child: _DraftSelect(
          // swissRounds / groupCount: they appear in the summary line.
          draft: draft,
          select: (x) => (x.stage1, x.stage2, x.swissRounds, x.groupCount),
          builder: (context, _) => _PhasesTimeline(draft: draft),
        ),
      ),
      FormBlock(
        title: TrTokens.matchSettingsTitle,
        hint: const FormHint(
          Icons.sports_score_outlined,
          TrTokens.matchSettingsHint,
        ),
        child: _DraftSelect(
          draft: draft,
          select: (x) => (
            x.stage1,
            x.stage2,
            x.swissRounds,
            x.groupCount,
            x.winPts,
            x.tiePts,
            x.s1Score,
            x.s2Score,
            x.thirdPlace,
          ),
          builder: (context, _) => _MatchSettings(draft: draft),
        ),
      ),
      FormBlock(
        title: TrTokens.partRulesTitle,
        hint: const FormHint(
          Icons.rule,
          TrTokens.partRulesHint,
        ),
        child: _DraftSelect(
          draft: draft,
          select: (x) => (x.partMode, x.savedList, x.newList),
          builder: (context, _) => _PartRulesBlock(draft: draft),
        ),
      ),
      FormBlock(
        title: 'Stadium',
        hint: const FormHint(
          Icons.stadium_outlined,
          'Optional. Pick the stadium the matches are played on so players '
              'can prepare for it. Leave it on "No specific stadium" when the '
              'venue decides.',
        ),
        child: _DraftSelect(
          draft: draft,
          select: (x) => x.stadiumDataId,
          builder: (context, stadiumDataId) => TournamentStadiumField(
            value: stadiumDataId,
            onChanged: (id) => draft.update(() => draft.stadiumDataId = id),
          ),
        ),
      ),
    ]);
  }
}

/// One size for everything that lines up beside a phase: the numbered
/// bubble, the gap TimelineTile carves in its line, and the HoloSubLabel
/// title row.
const double _kPhaseBubble = 30;

class _PhasesTimeline extends StatelessWidget {
  const _PhasesTimeline({required this.draft});

  final TournamentDraft draft;

  static const _stage1Options = [
    (StageKind.swiss, Icons.swap_horiz),
    (StageKind.roundRobin, Icons.all_inclusive),
    (StageKind.groups, Icons.grid_view),
    (StageKind.groupsSwiss, Icons.view_comfy_alt_outlined),
    (StageKind.singleElimination, Icons.account_tree_outlined),
    (StageKind.doubleElimination, Icons.call_split),
  ];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    final d = draft;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Phase 1. isLast flips when Phase 2 becomes relevant, which
        // animates the line down to meet it.
        TimelineTile(
          isFirst: true,
          isLast: !d.stage1.isPool,
          topSpacing: 0,
          indicatorSize: _kPhaseBubble,
          indicatorColumnWidth: 40,
          contentTopPadding: 0,
          contentRightPadding: 0,
          contentBottomPadding: 16,
          indicator: const StepBubble(
            index: 0,
            state: StepNodeState.active,
            size: _kPhaseBubble,
            animate: false, // state never changes here
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The marker is 30 px tall, the same as the bubble, so the
              // title row stays the bubble's height and both keep sharing a
              // centre line.
              HoloSubLabel(
                title: TrTokens.phase1Title,
                minTitleHeight: _kPhaseBubble,
                info: InfoChip(
                  title: TrTokens.phase1Title.tr,
                  popupIcon: Icons.flag_outlined,
                  details: TrTokens.phase1Hint.tr,
                ),
              ),
              SizedBox(height: rc.sm),
              LayoutBuilder(builder: (context, constraints) {
                final columns = constraints.maxWidth >= 620
                    ? 3
                    : (constraints.maxWidth >= 380 ? 2 : 1);
                final tileWidth =
                    (constraints.maxWidth - (columns - 1) * 10) / columns;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final (kind, icon) in _stage1Options)
                      SizedBox(
                        width: tileWidth,
                        child: StageTile(
                          kind: kind,
                          icon: icon,
                          selected: d.stage1 == kind,
                          onTap: () => d.setStage1(kind),
                        ),
                      ),
                  ],
                );
              }),
            ],
          ),
        ),

        // Phase 2, only when the first phase is a pool.
        AnimatedSize(
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: !d.stage1.isPool
              ? const SizedBox.shrink()
              : TimelineTile(
                  isFirst: false,
                  isLast: true,
                  topSpacing: 0,
                  indicatorSize: _kPhaseBubble,
                  indicatorColumnWidth: 40,
                  contentTopPadding: 0,
                  contentRightPadding: 0,
                  contentBottomPadding: 0,
                  indicator: const StepBubble(
                    index: 1,
                    state: StepNodeState.upcoming,
                    size: _kPhaseBubble,
                    animate: false, // state never changes here
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      HoloSubLabel(
                        title: TrTokens.phase2Title,
                        minTitleHeight: _kPhaseBubble,
                        info: InfoChip(
                          title: TrTokens.phase2Title.tr,
                          popupIcon: Icons.emoji_events_outlined,
                          details: d.stage1.isAnyGroups
                              ? TrTokens.phase2GroupHint.tr
                              : TrTokens.phase2StandardHint.tr,
                        ),
                      ),
                      SizedBox(height: rc.sm),
                      HoloSegmented<StageKind>(
                        value: d.stage2,
                        onChanged: (v) => d.update(() => d.stage2 = v),
                        options: [
                          HoloOption(StageKind.none, TrTokens.noKnockoutTxt.tr,
                              icon: Icons.flag_outlined,
                              enabled: !d.stage1.isAnyGroups),
                          HoloOption(StageKind.singleElimination,
                              TrTokens.singleElimTxt.tr,
                              icon: Icons.account_tree_outlined),
                          HoloOption(StageKind.doubleElimination,
                              TrTokens.doubleElimTxt.tr,
                              icon: Icons.call_split),
                        ],
                      ),
                    ],
                  ),
                ),
        ),
        SizedBox(height: rc.md),
        Row(
          children: [
            Icon(Icons.route_outlined, size: 16, color: cs.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(d.formatSummary(),
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: cs.primary)),
            ),
          ],
        ),
      ],
    );
  }
}

class _MatchSettings extends StatelessWidget {
  const _MatchSettings({required this.draft});

  final TournamentDraft draft;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = draft;

    return HoloCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (d.stage1 == StageKind.swiss || d.stage1 == StageKind.groupsSwiss)
            HoloNumberStepper(
              label: TrTokens.swissRoundsTitle.tr,
              helper: d.stage1 == StageKind.groupsSwiss
                  ? TrTokens.swissRoundsGroupHint.tr
                  : TrTokens.swissRoundsStandardHint.tr,
              value: d.swissRounds,
              min: 1,
              max: 12,
              onChanged: (v) => d.update(() => d.swissRounds = v),
            ),
          if (d.stage1 == StageKind.groupsSwiss) const SizedBox(height: 16),
          if (d.stage1.isAnyGroups)
            HoloNumberStepper(
              label: TrTokens.groupsTitle.tr,
              helper: d.stage1 == StageKind.groupsSwiss
                  ? TrTokens.groupsSwissHint.tr
                  : TrTokens.groupsStandardHint.tr,
              value: d.groupCount,
              min: 2,
              max: 16,
              onChanged: (v) => d.update(() => d.groupCount = v),
            ),
          if (d.stage1 == StageKind.roundRobin || d.stage1.isAnyGroups) ...[
            const Divider(height: 20),
            HoloNumberStepper(
              label: TrTokens.pointsPerWinTxt.tr,
              value: d.winPts,
              min: 1,
              max: 10,
              onChanged: (v) => d.update(() => d.winPts = v),
            ),
            HoloNumberStepper(
              label: TrTokens.pointsPerTieTxt.tr,
              value: d.tiePts,
              min: 0,
              max: 10,
              onChanged: (v) => d.update(() => d.tiePts = v),
            ),
          ],
          if (d.stage1.isPool) const Divider(height: 20),
          _ScoreRow(
            label: d.stage1.isPool
                ? TrTokens.phase1MatchScoreFormat.tr
                    .replaceFirst('%s', d.stage1.label)
                : TrTokens.bracketMatchScore.tr,
            value: d.s1Score,
            onChanged: (v) => d.update(() => d.s1Score = v),
          ),

          //TODO, for final matches can be different scores not just finals, limited option here right now, need to make it less complicated in the future and add more options
          if (d.bracket.isBracket) ...[
            const SizedBox(height: 12),
            _ScoreRow(
              label: d.twoStage
                  ? TrTokens.knockoutMatchScore.tr
                  : TrTokens.finalScore.tr,
              value: d.s2Score,
              onChanged: (v) => d.update(() => d.s2Score = v),
            ),
            const Divider(height: 24),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: d.thirdPlaceApplies && d.thirdPlace,
              onChanged: d.thirdPlaceApplies
                  ? (v) => d.update(() => d.thirdPlace = v)
                  : null,
              title: Text(TrTokens.thirdPlaceMatchTitle.tr),
              subtitle: Text(
                d.thirdPlaceApplies
                    ? (d.thirdPlace
                        ? TrTokens.thirdPlaceMatchHint.tr
                        : TrTokens.thirdPlacePointsHint.tr)
                    : TrTokens.thirdPlaceDoubleElimHint.tr,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        HoloSegmented<int>(
          value: value,
          onChanged: onChanged,
          options: const [
            HoloOption(4, '4 pts', badge: 'WBO'),
            HoloOption(5, '5 pts'),
            HoloOption(7, '7 pts'),
          ],
        ),
      ],
    );
  }
}

// ── Part rules ──────────────────────────────────────────────────────────────

/// None (default), one of the host's saved lists, or a new list built
/// here part by part. A new list can be saved to the host's lists so it's
/// reusable; either way the tournament gets its own copy on creation.
class _PartRulesBlock extends StatelessWidget {
  const _PartRulesBlock({required this.draft});

  final TournamentDraft draft;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        HoloSegmented<PartRulesMode>(
          value: draft.partMode,
          onChanged: (m) => draft.update(() => draft.partMode = m),
          options: [
            HoloOption(PartRulesMode.none, TrTokens.noneTxt.tr),
            HoloOption(PartRulesMode.saved, TrTokens.myListsTxt.tr,
                icon: Icons.bookmarks_outlined),
            HoloOption(PartRulesMode.create, TrTokens.newListTxt.tr,
                icon: Icons.playlist_add),
          ],
        ),
        SizedBox(height: rc.md),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: Alignment.topCenter,
          child: switch (draft.partMode) {
            PartRulesMode.none => Text(
                TrTokens.everyPartAllowedTxt.tr,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            PartRulesMode.saved => SavedListsPicker(draft: draft),
            PartRulesMode.create => _NewListEditor(draft: draft),
          },
        ),
      ],
    );
  }
}

class SavedListsPicker extends StatelessWidget {
  const SavedListsPicker({super.key, required this.draft});

  final TournamentDraft draft;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return BlocBuilder<PartListsCubit, PartListsState>(
      builder: (context, state) {
        if (state.loading && state.lists.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: BeybladeSpinner()),
          );
        }
        if (state.error != null && state.lists.isEmpty) {
          return Row(
            children: [
              Expanded(
                child: Text(state.error!,
                    style: TextStyle(fontSize: 13, color: cs.error)),
              ),
              TextButton(
                onPressed: () => context.read<PartListsCubit>().load(),
                child: Text(
                  TrTokens.retryTxt.tr,
                ),
              ),
            ],
          );
        }
        if (state.lists.isEmpty) {
          return Row(
            children: [
              Expanded(
                child: Text(TrTokens.noSavedListsYetTxt.tr,
                    style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              ),
              TextButton(
                onPressed: () =>
                    draft.update(() => draft.partMode = PartRulesMode.create),
                child: Text(
                  TrTokens.createOneBtn.tr,
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                // Lists are edited in the Beyblade feature; reload on return.
                onPressed: () async {
                  final cubit = context.read<PartListsCubit>();
                  await context.push(BeybladeRoutes.partLists);
                  await cubit.load();
                },
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Manage lists'),
              ),
            ),
            for (final list in state.lists)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: PartListCard(
                  list: list,
                  selected: draft.savedList?.id == list.id,
                  onTap: () => draft.update(() => draft.savedList = list),
                  // Tweak a saved list for this one tournament without
                  // changing the original.
                  onEditCopy: () => draft.update(() {
                    draft.newList = list.unsavedCopy();
                    draft.partListName.text = TrTokens.listCopyFormat.tr
                        .replaceFirst('%s', list.name);
                    draft.partMode = PartRulesMode.create;
                  }),
                ),
              ),
          ],
        );
      },
    );
  }
}

class PartListCard extends StatelessWidget {
  const PartListCard({
    super.key,
    required this.list,
    required this.selected,
    required this.onTap,
    required this.onEditCopy,
  });

  final PartList list;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEditCopy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tokens = HoloTokens.of(context);
    final n = list.partCount;

    return HoloCard(
      highlight: selected,
      wash: selected,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        children: [
          Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 20, color: selected ? cs.primary : cs.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(list.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    HoloPill(
                      label: list.kind.shortLabel,
                      color: list.kind == PartListKind.ban
                          ? tokens.danger
                          : tokens.success,
                    ),
                    const SizedBox(width: 8),
                    Text(
                        TrTokens.partsCountFormat.tr
                            .replaceFirst('%s', n.toString()),
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 4),
                PartListPreview(list: list),
              ],
            ),
          ),
          if (selected)
            TextButton(
                onPressed: onEditCopy, child: Text(TrTokens.editACopyBtn.tr)),
        ],
      ),
    );
  }
}

class _NewListEditor extends StatelessWidget {
  const _NewListEditor({required this.draft});

  final TournamentDraft draft;

  Future<void> _saveToLists(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = draft.partListName.text.trim();
    if (name.isEmpty) {
      messenger
          .showSnackBar(SnackBar(content: Text(TrTokens.nameListToSaveMsg.tr)));
      return;
    }
    final cubit = context.read<PartListsCubit>();
    final saved = await cubit.save(draft.newList.copyWith(name: name));
    if (saved == null) {
      messenger.showSnackBar(SnackBar(
          content: Text(cubit.state.error ?? TrTokens.couldNotSaveListMsg.tr)));
      return;
    }
    // The saved list is now the tournament's rules; further edits go
    // through "Edit a copy" so the stored one stays as saved.
    draft.update(() {
      draft.savedList = saved;
      draft.partMode = PartRulesMode.saved;
      draft.newList = PartList(kind: saved.kind);
      draft.partListName.clear();
    });
    messenger.showSnackBar(SnackBar(
      content: Text(TrTokens.savedToListsFormat.tr.replaceFirst('%s', name)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    final list = draft.newList;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Ban/approve switch, parts by type with images, and the real part
        // picker (search, type filter, "include all its variants").
        PartListEditor(
          list: list,
          onChanged: (l) => draft.update(() => draft.newList = l),
        ),
        if (!list.isEmpty) ...[
          SizedBox(height: rc.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: draft.partListName,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: TrTokens.listNameLabel.tr,
                    hintText: TrTokens.listNameHint.tr,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              BlocBuilder<PartListsCubit, PartListsState>(
                buildWhen: (p, c) => p.saving != c.saving,
                builder: (context, state) => TextButton.icon(
                  onPressed: state.saving ? null : () => _saveToLists(context),
                  icon: state.saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.bookmark_add_outlined, size: 18),
                  label: Text(
                    TrTokens.saveToMyListsBtn.tr,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            TrTokens.saveListHint.tr,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  STEP 2: BASICS
// ═════════════════════════════════════════════════════════════════════════════
class _BasicsStep extends StatelessWidget {
  const _BasicsStep({required this.draft, required this.onPickCover});

  final TournamentDraft draft;
  final VoidCallback onPickCover;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rc = ResponsiveProvider.config(context);
    final d = draft;

    // select, not watch: only these two values rebuild this step, not
    // every unrelated change to the org or profile state.
    final orgs =
        context.select((OrganizationCubit c) => c.state.managedOrganizations);
    final profileVerified = context.select(
        (ProfileCubit c) => c.state.currentProfile?.isVerified ?? false);
    final me = Supabase.instance.client.auth.currentUser?.id ?? '';
    bool verifiedHost(String hostId) => hostId == me
        ? profileVerified
        : orgs.any((o) => o.id == hostId && o.isVerified);

    return FormBlocks(children: [
      FormBlock(
        title: TrTokens.coverImageTitle.tr,
        hint: FormHint(
          Icons.image_outlined,
          TrTokens.coverImageHint.tr,
        ),
        child: _DraftSelect(
          draft: d,
          select: (x) => x.coverBytes,
          builder: (context, bytes) =>
              CoverPicker(bytes: bytes, onTap: onPickCover),
        ),
      ),
      // Text fields redraw themselves from their controllers; nothing
      // around them needs to rebuild while typing.
      FormBlock(
        title: TrTokens.aboutTitle
            .tr, // Note: 'About' wasn't in the provided token list, leaving as is unless you have a token for it.
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppTextField(
              controller: d.name,
              label: TrTokens.tournamentNameTxt.tr,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? TrTokens.requiredError.tr : null,
            ),
            SizedBox(height: rc.sm),
            AppTextField(
              controller: d.desc,
              label: TrTokens.tournamentDescriptionTxt.tr,
              maxLines: 3,
              validator: (v) =>
                  (v ?? '').trim().isEmpty ? TrTokens.requiredError.tr : null,
            ),
          ],
        ),
      ),
      FormBlock(
        title: TrTokens.hostedByTxt
            .tr, // Note: 'Hosted by' title wasn't in the provided token list, leaving as is.
        hint: FormHint(
          Icons.groups_outlined,
          TrTokens.hostedByHint.tr,
        ),
        child: _DraftSelect(
          draft: d,
          select: (x) => x.hostId,
          builder: (context, hostId) {
            final verified = verifiedHost(hostId);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HoloSegmented<String>(
                  value: hostId,
                  options: [
                    HoloOption(me, TrTokens.meTxt.tr,
                        icon: Icons.person_outline),
                    for (final org in orgs)
                      HoloOption(org.id, org.name, icon: Icons.groups_outlined),
                  ],
                  onChanged: (id) {
                    d.update(() {
                      d.hostId = id;
                      if (id == me) {
                        d.hostType = HostType.user;
                      } else {
                        final org = orgs.firstWhere((o) => o.id == id);
                        d.hostType = HostType.organization;
                        d.hostName = org.name;
                      }
                    });
                    if (id != me) {
                      context
                          .read<OrganizationCubit>()
                          .loadUnlockedFeatures(id);
                    }
                  },
                ),
                SizedBox(height: rc.sm),
                AppInfoBanner(
                  isSuccess: verified,
                  message: verified
                      ? TrTokens.verifiedHostBanner.tr
                      : TrTokens.unverifiedHostBanner.tr,
                ),
              ],
            );
          },
        ),
      ),
      //TODO need to profvide information about it not being shown to explain
      FormBlock(
        title: TrTokens.visibilityTitle
            .tr, // Note: 'Visibility' wasn't in the provided token list, leaving as is.
        child: _DraftSelect(
          draft: d,
          select: (x) => (x.isPrivate, x.wageringEnabled, x.hostId),
          builder: (context, v) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HoloCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: SwitchListTile.adaptive(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                  value: v.$1,
                  onChanged: (on) => d.update(() => d.isPrivate = on),
                  title: Text(TrTokens.privateTournamentTitle.tr),
                  subtitle: Text(
                    TrTokens.privateTournamentHint.tr,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
              ),
              if (verifiedHost(v.$3)) ...[
                SizedBox(height: rc.xs),
                HoloCard(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: SwitchListTile.adaptive(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    value: v.$2,
                    onChanged: (on) => d.update(() => d.wageringEnabled = on),
                    title: Text(TrTokens.predictionsWageringTitle.tr),
                    subtitle: Text(
                      TrTokens.predictionsWageringHint.tr,
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  STEP 3: FEE & REWARDS
// ═════════════════════════════════════════════════════════════════════════════
class FeeRewardsStep extends StatelessWidget {
  const FeeRewardsStep({super.key, required this.draft});

  final TournamentDraft draft;

  @override
  Widget build(BuildContext context) {
    final unlocked =
        context.select((OrganizationCubit c) => c.state.unlockedFeatures);

    // Entry-fee paywall: decided in one place (tournament_feature_flags.dart)
    // for both this step and the manage page's Stats tab. Off for now.

    return _DraftSelect(
      draft: draft,
      select: (x) => x.hostType == HostType.organization,
      builder: (context, isOrgHost) {
        final canGiveRankings =
            isOrgHost && unlocked.contains(OrgFeatureType.rankings.toJson());
        // Organizations need the Entry fees feature (admin approval); a
        // player hosting as themselves can always charge one.
        final canChargeFee =
            !isOrgHost || unlocked.contains(OrgFeatureType.payments.toJson());
        return FormBlocks(children: [
          FormBlock(
            title: TrTokens.entryFeeTitle
                .tr, // Note: 'Entry fee' title wasn't in the provided list
            hint: FormHint(
              Icons.payments_outlined,
              TrTokens.entryFeeHint.tr,
            ),
            child: canChargeFee
                ? _DraftSelect(
                    draft: draft,
                    select: (x) => (x.feeEnabled, x.currency),
                    builder: (context, _) => _EntryFeeCard(draft: draft),
                  )
                : _FeeLockedCard(isOrgHost: isOrgHost),
          ),
          if (canGiveRankings)
            FormBlock(
              title: TrTokens.orgRankingPointsHeader.tr,
              hint: FormHint(
                Icons.leaderboard_outlined,
                TrTokens.orgRankingPointsSubhead.tr,
              ),
              child: OrgPointsFields(draft: draft),
            ),
          FormBlock(
            title: TrTokens.prizesTxt.tr,
            hint: FormHint(
              Icons.emoji_events_outlined,
              TrTokens.prizeDraftBlockHint.tr,
            ),
            child: _DraftSelect(
              draft: draft,
              select: (x) => (x.prizes, x.poolPlan, x.hostId, x.hostType),
              builder: (context, _) => PrizePlanner(
                prizes: draft.prizes,
                pool: draft.poolPlan,
                // Hosting as an organization you manage: its wallet can
                // fund the prize pool.
                hostOrgId: draft.hostType == HostType.organization
                    ? draft.hostId
                    : null,
                onChanged: (list) => draft.update(() => draft.prizes = list),
                onPoolChanged: (plan) =>
                    draft.update(() => draft.poolPlan = plan),
              ),
            ),
          ),
        ]);
      },
    );
  }
}

class _EntryFeeCard extends StatelessWidget {
  const _EntryFeeCard({required this.draft});

  final TournamentDraft draft;

  @override
  Widget build(BuildContext context) {
    final d = draft;

    return HoloCard(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: d.feeEnabled,
            onChanged: (v) => d.update(() => d.feeEnabled = v),
            title: Text(TrTokens.chargeEntryFeeTitle.tr),
          ),
          if (d.feeEnabled) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: d.feeAmount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'^\d*\.?\d{0,2}'))
                    ],
                    decoration: InputDecoration(
                        labelText: TrTokens.amountLabel
                            .tr), // Assuming 'Amount' doesn't have a token yet
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: AppDropdown<String>(
                    label: TrTokens.currencyLabel
                        .tr, // Assuming 'Currency' doesn't have a token yet
                    value: d.currency,
                    items: [
                      // The app currency first: taken from players' wallets.
                      for (final w in context
                          .select((WalletCubit c) => c.state.wallets)
                          .where((w) => w.isWagerCurrency))
                        DropdownMenuItem(value: w.code, child: Text(w.name)),
                      for (final c in currencies)
                        DropdownMenuItem(value: c, child: Text(c)),
                      // Keeps the dropdown valid while the wallet loads.
                      if (!currencies.contains(d.currency) &&
                          !_isAppFee(context, d.currency))
                        DropdownMenuItem(
                            value: d.currency, child: Text(d.currency)),
                    ],
                    onChanged: (v) => d.update(() => d.currency = v ?? 'USD'),
                  ),
                ),
              ],
            ),
            if (_isAppFee(context, d.currency))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(TrTokens.feeAppCurrencyHint.tr,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: d.feeNote,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: TrTokens.howToPayLabel.tr,
                hintText: TrTokens.howToPayHint.tr,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class OrgPointsFields extends StatelessWidget {
  const OrgPointsFields({super.key, required this.draft});

  final TournamentDraft draft;

  @override
  Widget build(BuildContext context) {
    final d = draft;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
              child: AppTextField(
                  controller: d.regPts,
                  label: TrTokens.regPointsTxt.tr,
                  isNumber: true)),
          const SizedBox(width: 8),
          Expanded(
              child: AppTextField(
                  controller: d.top1,
                  label: TrTokens.place1st.tr,
                  isNumber: true)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
              child: AppTextField(
                  controller: d.top2,
                  label: TrTokens.place2nd.tr,
                  isNumber: true)),
          const SizedBox(width: 8),
          Expanded(
              child: AppTextField(
                  controller: d.top3,
                  label: TrTokens.place3rd.tr,
                  isNumber: true)),
          const SizedBox(width: 8),
          Expanded(
              child: AppTextField(
                  controller: d.top4,
                  label: TrTokens.place4th.tr,
                  isNumber: true)),
        ]),
      ],
    );
  }
}

class _FeeLockedCard extends StatelessWidget {
  const _FeeLockedCard({required this.isOrgHost});
  final bool isOrgHost;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return HoloCard(
      wash: true,
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, color: cs.onSurfaceVariant, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(TrTokens.entryFeesLockedTitle.tr,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurface)),
                const SizedBox(height: 4),
                Text(
                  isOrgHost
                      ? TrTokens.entryFeesLockedOrgHint.tr
                      : TrTokens.entryFeesLockedUserHint.tr,
                  style: TextStyle(
                      fontSize: 13, color: cs.onSurfaceVariant, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  STEP 4: REGISTRATION
// ═════════════════════════════════════════════════════════════════════════════
class _RegistrationStep extends StatelessWidget {
  const _RegistrationStep({required this.draft, required this.onPickDate});

  final TournamentDraft draft;
  final Future<void> Function({required bool registration}) onPickDate;

  @override
  Widget build(BuildContext context) {
    final rc = ResponsiveProvider.config(context);
    final d = draft;

    return FormBlocks(children: [
      FormBlock(
        title: TrTokens.howDoPlayersSignUpTitle.tr,
        child: _DraftSelect(
          draft: d,
          select: (x) => x.registrationType,
          builder: (context, type) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HoloSegmented<RegistrationType>(
                value: type,
                onChanged: (v) => d.update(() => d.registrationType = v),
                options: [
                  HoloOption(RegistrationType.internal, TrTokens.inAppDirect.tr,
                      icon: Icons.phone_iphone),
                  HoloOption(
                      RegistrationType.external, TrTokens.externalFormLink.tr,
                      icon: Icons.link),
                ],
              ),
              if (type == RegistrationType.external) ...[
                SizedBox(height: rc.sm),
                AppTextField(
                    controller: d.extUrl, label: TrTokens.externalUrlTxt.tr),
              ],
            ],
          ),
        ),
      ),
      FormBlock(
        title: TrTokens.scheduleTitle.tr,
        hint: FormHint(
          Icons.schedule,
          TrTokens.scheduleHint.tr,
        ),
        child: _DraftSelect(
          draft: d,
          select: (x) => (x.regDeadline, x.startDate),
          builder: (context, dates) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppDateTimePicker(
                title: TrTokens.registrationDeadlineTxt.tr,
                selectedDate: dates.$1,
                onTap: () => onPickDate(registration: true),
              ),
              SizedBox(height: rc.sm),
              AppDateTimePicker(
                title: TrTokens.startDateTxt.tr,
                selectedDate: dates.$2,
                onTap: () => onPickDate(registration: false),
              ),
            ],
          ),
        ),
      ),
      FormBlock(
        title: TrTokens.capacityTitle.tr,
        child: AppTextField(
          controller: d.maxParts,
          label: TrTokens.maxParticipantsTxt.tr,
          hint: TrTokens.maxParticipantsHint.tr,
          isNumber: true,
        ),
      ),
    ]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
//  SUMMARY
// ═════════════════════════════════════════════════════════════════════════════
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.draft,
    required this.onCreate,
    required this.showCreate,
  });

  final TournamentDraft draft;
  final VoidCallback onCreate;
  final bool showCreate;

  /// Everything the card displays, as one record: the card rebuilds only
  /// when one of these changes (typing the name, yes; typing the
  /// description, which it doesn't show, no).
  static Object _shown(TournamentDraft d) => (
        d.name.text,
        d.beyVsType,
        d.formatSummary(),
        d.s1Score,
        d.s2Score,
        d.stage1,
        d.stage2,
        d.thirdPlace,
        d.partRules,
        d.isPrivate,
        d.wageringEnabled,
        d.feeEnabled,
        d.feeValue,
        d.currency,
        d.prizes,
        d.poolPlan,
        d.regDeadline,
        d.startDate,
        d.firstInvalid(),
      );

  @override
  Widget build(BuildContext context) => _DraftSelect(
        draft: draft,
        select: _shown,
        builder: (context, _) => _card(context),
      );

  Widget _card(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = draft;
    final df = DateFormat('EEE, MMM d · h:mm a');
    final rules = d.partRules;

    Widget row(IconData icon, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: cs.onSurfaceVariant),
              const SizedBox(width: 10),
              SizedBox(
                  width: 84,
                  child: Text(label,
                      style: TextStyle(
                          fontSize: 12.5, color: cs.onSurfaceVariant))),
              Expanded(
                  child: Text(value,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600))),
            ],
          ),
        );

    return HoloCard(
      highlight: true,
      wash: true,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              d.name.text.trim().isEmpty
                  ? TrTokens.untitledTournament.tr
                  : d.name.text.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          // Same order as the steps.
          row(
              Icons.view_carousel_outlined,
              TrTokens.deckSizeLabel
                  .tr, // Note: 'Deck size' not in provided token list
              '${d.beyVsType} Combos'),
          row(Icons.account_tree_outlined, TrTokens.formatTxt.tr,
              d.formatSummary()), // Note: 'Format' not in provided token list
          row(
              Icons.sports_score_outlined,
              TrTokens.scoresLabel.tr,
              d.bracket.isBracket && !d.stage1.isBracket
                  ? TrTokens.scoresTwoStageFormat.tr
                      .replaceFirst('%s', '${d.s1Score}')
                      .replaceFirst('%s', '${d.s2Score}')
                  : '${d.s1Score} pts${d.bracket.isBracket ? ', ${TrTokens.finalLabel.tr} ${d.s2Score} pts' : ''}'), // Note: The second half of this ternary needs custom handling if it's supposed to use scoresFinalFormat.
          if (d.bracket.isBracket)
            row(
                Icons.emoji_events_outlined,
                TrTokens.thirdPlaceLabel.tr,
                !d.thirdPlaceApplies
                    ? TrTokens.lowerBracketFinal.tr
                    : (d.thirdPlace
                        ? TrTokens.bronzeMatch.tr
                        : TrTokens.mostSemiFinalPoints.tr)),
          row(
              Icons.rule,
              TrTokens.partRulesTitle
                  .tr, // Note: 'Part rules' label not explicitly in token list for summary
              rules == null
                  ? TrTokens.noneTxt.tr // Note: 'None' not in token list
                  : TrTokens.partRulesSummaryFormat.tr
                      .replaceFirst('%s', rules.kind.label)
                      .replaceFirst('%s', '${rules.partCount}')),
          row(
              Icons.visibility_off_outlined,
              TrTokens
                  .visibilityTitle.tr, // Note: 'Visibility' not in token list
              d.isPrivate ? TrTokens.privateTxt.tr : TrTokens.publicTxt.tr),
          row(
              Icons.casino_outlined,
              TrTokens.predictionsPill.tr
                  .tr, // Note: 'Predictions' not in token list
              d.wageringEnabled ? TrTokens.enabledTxt.tr : TrTokens.offTxt.tr),
          row(
              Icons.payments_outlined,
              TrTokens
                  .entryFeeTitle.tr.tr, // Note: 'Entry fee' not in token list
              d.feeEnabled && d.feeValue > 0
                  ? TournamentFeeInfo(amount: d.feeValue, currency: d.currency)
                      .formatted
                  : TrTokens.freeTxt.tr),
          if (d.prizes.isNotEmpty || !d.hostPoolPlan.isEmpty)
            row(Icons.emoji_events_outlined, TrTokens.prizesTxt.tr,
                prizeDraftSummary(d.prizes, d.hostPoolPlan)),
          row(
              Icons.event_available_outlined,
              TrTokens.closesLabel.tr,
              d.regDeadline == null
                  ? TrTokens.notSet.tr
                  : df.format(
                      d.regDeadline!)), // Note: 'Not set' not in token list
          row(
              Icons.play_circle_outline,
              TrTokens.startsLabel.tr, // Note: 'Starts' not in token list
              d.startDate == null
                  ? TrTokens.notSet.tr
                  : df.format(d.startDate!)),
          if (showCreate) ...[
            const SizedBox(height: 14),
            BlocBuilder<TournamentCubit, TournamentState>(
              buildWhen: (p, c) => p.isOperationLoading != c.isOperationLoading,
              builder: (context, state) => HoloActionButton(
                label: TrTokens.createTxt.tr,
                icon: Icons.check,
                expand: true,
                isLoading: state.isOperationLoading,
                onPressed: onCreate,
              ),
            ),
            if (d.firstInvalid() case final bad?)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(d.validate(bad)!,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ),
          ],
        ],
      ),
    );
  }
}
// ═════════════════════════════════════════════════════════════════════════════
//  STEPS + DRAFT
// ═════════════════════════════════════════════════════════════════════════════

/// The steps, in order. The ONLY place order is defined: the phone pages,
/// the wide-layout sections, the progress rail, the headers and validation
/// all read from this.
///
/// Implements RailStep so the shared StepRail takes `CreateStep.values`
/// directly, with no mapping list.
enum CreateStep implements RailStep {
  format(
    TrTokens.tournamentFormatTxt, // 1. Pass the token directly, NO .tr here
    TrTokens.stepFormatSubtitle,
    Icons.account_tree_rounded,
    'assets/icons/create_tournament/format.svg',
  ),
  basics(
    TrTokens
        .basicsHeader, // Replace this with your TrTokens key if you have one
    TrTokens.stepBasicsSubtitle,
    Icons.edit_note_rounded,
    'assets/icons/create_tournament/basics.svg',
  ),
  feeRewards(
    TrTokens.stepFeeRewardsTitle,
    TrTokens.stepFeeRewardsSubtitle,
    Icons.emoji_events_rounded,
    'assets/icons/create_tournament/rewards.svg',
  ),
  registration(
    TrTokens.stepRegistrationTitle,
    TrTokens.stepRegistrationSubtitle,
    Icons.how_to_reg_rounded,
    'assets/icons/create_tournament/registration.svg',
  );

  // 2. Map the token to a private variable
  const CreateStep(this._titleKey, this._subTitleKey, this.icon, this.svgAsset);

  final String _titleKey;
  final String _subTitleKey;
  // 3. Apply the translation helper in a getter so it evaluates at runtime
  @override
  String get title => _titleKey.tr;
  @override
  String get subtitle => _subTitleKey.tr;

  @override
  final IconData icon;

  final String svgAsset;
}

enum PartRulesMode { none, saved, create }

/// Everything the form holds, in one place the section widgets share.
/// Sections call [update]; blocks that show a value pick up the change
/// through _DraftSelect, and the page rebuilds only when validity changes.
class TournamentDraft extends ChangeNotifier {
  TournamentDraft({required this.hostId}) {
    for (final c in _rebuildOnType) {
      c.addListener(notifyListeners);
    }
  }

  // ── Text ────────────────────────────────────────────────────────────────
  final name = TextEditingController();
  final desc = TextEditingController();
  final extUrl = TextEditingController();
  final maxParts = TextEditingController();
  final feeAmount = TextEditingController();
  final feeNote = TextEditingController();
  final regPts = TextEditingController(text: '10');
  final top1 = TextEditingController(text: '100');
  final top2 = TextEditingController(text: '70');
  final top3 = TextEditingController(text: '50');
  final top4 = TextEditingController(text: '40');
  final partListName = TextEditingController();

  /// Fields whose value shows elsewhere (summary card, validation state).
  /// Typing in them notifies; the selectors decide what actually rebuilds.
  List<TextEditingController> get _rebuildOnType =>
      [name, desc, extUrl, maxParts, feeAmount];

  List<TextEditingController> get _all => [
        name,
        desc,
        extUrl,
        maxParts,
        feeAmount,
        feeNote,
        regPts,
        top1,
        top2,
        top3,
        top4,
        partListName,
      ];

  // ── Format ──────────────────────────────────────────────────────────────
  String beyVsType = '3v3';
  StageKind stage1 = StageKind.swiss;
  StageKind stage2 = StageKind.singleElimination;
  int swissRounds = 3;
  int groupCount = 4;
  int winPts = 3;
  int tiePts = 1;
  int s1Score = 4;
  int s2Score = 4;
  bool thirdPlace = true;

  // ── Part rules (None by default) ────────────────────────────────────────
  PartRulesMode partMode = PartRulesMode.none;
  PartList? savedList;
  PartList newList = const PartList(kind: PartListKind.ban);

  // ── Stadium (optional; accessory dataId, null = not specified) ─────────
  String? stadiumDataId;

  // ── Basics ──────────────────────────────────────────────────────────────
  HostType hostType = HostType.user;
  String hostId;
  String hostName = '';
  bool isPrivate = false;
  bool wageringEnabled = true;
  Uint8List? coverBytes;

  // ── Fee ─────────────────────────────────────────────────────────────────
  bool feeEnabled = false;
  String currency = 'USD';

  // ── Prizes (saved once the tournament exists) ───────────────────────────
  List<PrizeFormValue> prizes = const [];

  /// Currency to put in the prize pool once the tournament exists.
  PrizePoolPlan poolPlan = const PrizePoolPlan();

  /// [poolPlan] for the current host (organization amounts only
  /// count for the organization they were planned for).
  PrizePoolPlan get hostPoolPlan =>
      poolPlan.forHost(hostType == HostType.organization ? hostId : null);

  /// The host is a verified organization, so prizes can carry currency
  /// from its pool. Kept up to date by the page.
  bool hostVerifiedOrg = false;

  // ── Registration ────────────────────────────────────────────────────────
  RegistrationType registrationType = RegistrationType.internal;
  DateTime? regDeadline;
  DateTime? startDate;

  void update(VoidCallback change) {
    change();
    notifyListeners();
  }

  // ── Derived ─────────────────────────────────────────────────────────────
  bool get twoStage => stage1.isPool && stage2.isBracket;
  StageKind get bracket => stage1.isBracket ? stage1 : stage2;
  bool get thirdPlaceApplies => bracket == StageKind.singleElimination;
  double get feeValue => double.tryParse(feeAmount.text.trim()) ?? 0;

  /// What gets copied onto the tournament. Null means no restrictions.
  PartList? get partRules => switch (partMode) {
        PartRulesMode.none => null,
        PartRulesMode.saved => savedList,
        PartRulesMode.create => newList.isEmpty
            ? null
            : newList.copyWith(name: partListName.text.trim()),
      };

  void setStage1(StageKind kind) => update(() {
        stage1 = kind;
        if (kind.isBracket) {
          stage2 = StageKind.none;
        } else if (kind.isAnyGroups && !stage2.isBracket) {
          stage2 = StageKind.singleElimination;
        }
      });

  String formatSummary() {
    final parts = <String>[
      switch (stage1) {
        StageKind.swiss => TrTokens.swissFormatSummary.tr
            .replaceFirst('%s', swissRounds.toString()),
        StageKind.groups => TrTokens.groupsFormatSummary.tr
            .replaceFirst('%s', groupCount.toString()),
        StageKind.groupsSwiss => TrTokens.groupsSwissFormatSummary.tr
            .replaceFirst('%s', groupCount.toString()),
        StageKind.roundRobin => TrTokens.roundRobinFormatSummary.tr,
        _ => stage1.label,
      },
      if (twoStage) stage2.label,
    ];
    return parts.join('  →  ');
  }

  // ── Validation ──────────────────────────────────────────────────────────
  String? validate(CreateStep step) => switch (step) {
        CreateStep.format => _validateFormat(),
        CreateStep.basics => _validateBasics(),
        CreateStep.feeRewards => _validateFee(),
        CreateStep.registration => _validateRegistration(),
      };

  CreateStep? firstInvalid() {
    for (final step in CreateStep.values) {
      if (validate(step) != null) return step;
    }
    return null;
  }

  String? _validateFormat() {
    if (stage1.isAnyGroups && !stage2.isBracket) {
      return TrTokens.groupStageNeedsKnockoutError.tr;
    }
    if (partMode == PartRulesMode.saved && savedList == null) {
      return TrTokens.pickSavedListError.tr;
    }
    if (partMode == PartRulesMode.create && newList.isEmpty) {
      return TrTokens.addAtLeastOnePartError.tr;
    }
    return null;
  }

  String? _validateBasics() {
    if (name.text.trim().isEmpty) return TrTokens.giveTournamentNameError.tr;
    if (desc.text.trim().isEmpty) return TrTokens.addShortDescError.tr;
    return null;
  }

  String? _validateFee() {
    if (feeEnabled && feeValue <= 0) {
      return TrTokens.enterFeeAmountError.tr;
    }
    return null;
  }

  String? _validateRegistration() {
    if (registrationType == RegistrationType.external &&
        extUrl.text.trim().isEmpty) {
      return TrTokens.urlRequiredError.tr;
    }
    if (regDeadline == null || startDate == null) {
      return TrTokens.selectDatesError.tr;
    }
    if (startDate!.isBefore(regDeadline!)) {
      return TrTokens.startDateBeforeRegError.tr;
    }
    final max = maxParts.text.trim();
    if (max.isNotEmpty && (int.tryParse(max) ?? 0) < 2) {
      // Re-using capacity format error as mapped in the previous step
      return TrTokens.maxParticipantsMinError.tr;
    }
    return null;
  }

  // ── Submit ──────────────────────────────────────────────────────────────
  CreateTournamentRequest toRequest(
      {required String userHostName, bool canChargeFee = true}) {
    final s2Score =
        stage2 == StageKind.none && stage1.isPool ? s1Score : this.s2Score;

    return CreateTournamentRequest(
      name: name.text.trim(),
      description: desc.text.trim(),
      hostType: hostType,
      hostId: hostId,
      hostName: hostType == HostType.user ? userHostName : hostName,
      stage1Format: stage1.toJson(),
      // Null means no second stage (stage2Format is String? in the request).
      stage2Format: twoStage ? stage2.toJson() : null,
      hasThirdPlaceMatch: thirdPlaceApplies && thirdPlace,
      swissRounds:
          (stage1 == StageKind.swiss || stage1 == StageKind.groupsSwiss)
              ? swissRounds
              : 0,
      preferredGroupCount: stage1.isAnyGroups ? groupCount : 0,
      matchWinPoints: winPts,
      matchTiePoints: tiePts,
      registrationType: registrationType,
      externalRegistrationUrl: registrationType == RegistrationType.external
          ? extUrl.text.trim()
          : null,
      registrationDeadline: regDeadline!,
      stage1TargetScore: s1Score,
      stage2TargetScore: s2Score,
      startDate: startDate!,
      maxParticipants: int.tryParse(maxParts.text.trim()),
      orgPointsConfig: OrgPointsConfigModel(
        registration: int.tryParse(regPts.text.trim()) ?? 10,
        top1: int.tryParse(top1.text.trim()) ?? 100,
        top2: int.tryParse(top2.text.trim()) ?? 70,
        top3: int.tryParse(top3.text.trim()) ?? 50,
        top4: int.tryParse(top4.text.trim()) ?? 40,
      ),
      coverBytes: coverBytes,
      entryFeeAmount: feeEnabled && canChargeFee ? feeValue : 0,
      entryFeeCurrency: currency,
      entryFeeNote: feeEnabled && feeNote.text.trim().isNotEmpty
          ? feeNote.text.trim()
          : null,
      isPrivate: isPrivate,
      beyVsType: beyVsType,
      wageringEnabled: wageringEnabled,
      partRules: partRules,
    );
  }

  @override
  void dispose() {
    for (final c in _rebuildOnType) {
      c.removeListener(notifyListeners);
    }
    for (final c in _all) {
      c.dispose();
    }
    super.dispose();
  }
}

/// The entry fee is in an app currency (taken from players' wallets).
bool _isAppFee(BuildContext context, String code) => context
    .read<WalletCubit>()
    .state
    .wallets
    .any((w) => w.isWagerCurrency && w.code == code);
