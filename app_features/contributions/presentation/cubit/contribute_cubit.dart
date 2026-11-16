import 'package:clasher_st/features/contributions/domain/contributions_repository.dart';
import 'package:clasher_st/features/contributions/domain/entities.dart';
import 'package:clasher_st/features/contributions/domain/usecases.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// What the picture is of, as the page offers it.
enum TargetGroup {
  parts('Part'),
  bladers('Blader'),
  products('Box'),
  accessories('Accessory'),
  other('Other');

  const TargetGroup(this.label);
  final String label;
}

class ContributeState extends Equatable {
  const ContributeState({
    this.loading = true,
    this.configured = true,
    this.contributor,
    this.group = TargetGroup.parts,
    this.query = '',
    this.results = const [],
    this.searching = false,
    this.target,
    this.kind = ContributionKind.image,
    this.picture,
    this.credit = '',
    this.note = '',
    this.consent = false,
    this.submitting = false,
    this.receipt,
    this.error,
  });

  final bool loading;
  final bool configured;
  final Contributor? contributor;
  final TargetGroup group;
  final String query;
  final List<ContributionTarget> results;
  final bool searching;
  final ContributionTarget? target;
  final ContributionKind kind;
  final PickedPicture? picture;
  final String credit;
  final String note;
  final bool consent;
  final bool submitting;

  /// Set after a successful send (the page shows "thanks").
  final ContributionReceipt? receipt;
  final String? error;

  bool get isOther => group == TargetGroup.other;

  /// What will be sent as the target.
  ContributionTarget? get effectiveTarget => isOther ? const ContributionTarget.other() : target;

  bool get canSubmit =>
      configured &&
      contributor != null &&
      !submitting &&
      picture != null &&
      consent &&
      (isOther ? note.trim().isNotEmpty : target != null);

  ContributeState copyWith({
    bool? loading,
    bool? configured,
    Contributor? Function()? contributor,
    TargetGroup? group,
    String? query,
    List<ContributionTarget>? results,
    bool? searching,
    ContributionTarget? Function()? target,
    ContributionKind? kind,
    PickedPicture? Function()? picture,
    String? credit,
    String? note,
    bool? consent,
    bool? submitting,
    ContributionReceipt? Function()? receipt,
    String? Function()? error,
  }) =>
      ContributeState(
        loading: loading ?? this.loading,
        configured: configured ?? this.configured,
        contributor: contributor != null ? contributor() : this.contributor,
        group: group ?? this.group,
        query: query ?? this.query,
        results: results ?? this.results,
        searching: searching ?? this.searching,
        target: target != null ? target() : this.target,
        kind: kind ?? this.kind,
        picture: picture != null ? picture() : this.picture,
        credit: credit ?? this.credit,
        note: note ?? this.note,
        consent: consent ?? this.consent,
        submitting: submitting ?? this.submitting,
        receipt: receipt != null ? receipt() : this.receipt,
        error: error != null ? error() : null,
      );

  @override
  List<Object?> get props => [
        loading, configured, contributor, group, query, results, searching, target, kind, picture, credit,
        note, consent, submitting, receipt, error,
      ];
}

/// Settings -> Send pictures: pick what it's of, pick a picture, optional credit and note, send.
class ContributeCubit extends Cubit<ContributeState> {
  ContributeCubit({
    required SubmitContributionUseCase submit,
    required ContributionTargetSearch search,
    required ContributionPicturePicker picker,
    ContributionTarget? initialTarget,
  })  : _submit = submit,
        _search = search,
        _picker = picker,
        super(ContributeState(
          target: initialTarget,
          group: _groupOf(initialTarget),
        ));

  final SubmitContributionUseCase _submit;
  final ContributionTargetSearch _search;
  final ContributionPicturePicker _picker;
  int _searchToken = 0;

  static TargetGroup _groupOf(ContributionTarget? t) => switch (t?.type) {
        null => TargetGroup.parts,
        'bladers' => TargetGroup.bladers,
        'products' => TargetGroup.products,
        'accessories' => TargetGroup.accessories,
        'other' => TargetGroup.other,
        _ => TargetGroup.parts,
      };

  Future<void> start() async {
    final configured = _submit.isConfigured;
    final who = await _submit.contributor();
    emit(state.copyWith(loading: false, configured: configured, contributor: () => who));
    if (state.group != TargetGroup.parts && state.group != TargetGroup.other) await search('');
  }

  Future<void> setGroup(TargetGroup g) async {
    if (g == state.group) return;
    emit(state.copyWith(
      group: g,
      query: '',
      results: const [],
      target: () => null,
      kind: ContributionKind.image,
    ));
    // bladers / boxes / accessories are short lists: show them straight away
    if (g != TargetGroup.parts && g != TargetGroup.other) await search('');
  }

  Future<void> search(String q) async {
    final token = ++_searchToken;
    emit(state.copyWith(query: q, searching: true));
    try {
      final res = await _search.search(state.group.name, q);
      if (token != _searchToken || isClosed) return; // a newer search started
      emit(state.copyWith(results: res, searching: false));
    } catch (e) {
      if (token == _searchToken && !isClosed) {
        emit(state.copyWith(searching: false, error: () => 'Search failed: $e'));
      }
    }
  }

  void selectTarget(ContributionTarget? t) => emit(state.copyWith(
        target: () => t,
        kind: t?.isBlader == true ? state.kind : ContributionKind.image,
      ));

  void setKind(ContributionKind k) => emit(state.copyWith(kind: k));

  Future<void> pickPicture({bool camera = false}) async {
    try {
      final p = await _picker.pick(camera: camera);
      if (p != null) emit(state.copyWith(picture: () => p, receipt: () => null));
    } on ContributionException catch (e) {
      emit(state.copyWith(error: () => e.message));
    } catch (_) {
      emit(state.copyWith(error: () => 'Couldn\'t open the picture.'));
    }
  }

  void clearPicture() => emit(state.copyWith(picture: () => null));
  void setCredit(String v) => emit(state.copyWith(credit: v));
  void setNote(String v) => emit(state.copyWith(note: v));
  void setConsent(bool v) => emit(state.copyWith(consent: v));

  Future<void> send() async {
    final t = state.effectiveTarget;
    final p = state.picture;
    if (!state.canSubmit || t == null || p == null) return;
    emit(state.copyWith(submitting: true));
    try {
      final receipt = await _submit(ContributionDraft(
        kind: state.isOther ? ContributionKind.other : state.kind,
        target: t,
        picture: p,
        credit: state.credit,
        note: state.note,
        consent: state.consent,
      ));
      emit(state.copyWith(submitting: false, receipt: () => receipt));
    } on ContributionException catch (e) {
      emit(state.copyWith(submitting: false, error: () => e.message));
    } catch (_) {
      emit(state.copyWith(submitting: false, error: () => 'Something went wrong. Try again.'));
    }
  }

  /// After a send: the next picture, keeping who and how to credit.
  void another() => emit(state.copyWith(
        receipt: () => null,
        picture: () => null,
        note: '',
        consent: false,
      ));
}
