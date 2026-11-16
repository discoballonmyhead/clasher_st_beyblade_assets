import 'package:clasher_st/features/contributions/domain/contributions_repository.dart';
import 'package:clasher_st/features/contributions/domain/entities.dart';
import 'package:clasher_st/features/contributions/domain/usecases.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// ── the list ─────────────────────────────────────────────────────────────────

/// Pictures only, details only, or both.
enum GapKind { all, pictures, details }

class MissingListState extends Equatable {
  const MissingListState({
    this.loading = true,
    this.configured = true,
    this.list,
    this.sheet,
    this.gap = GapKind.all,
    this.query = '',
    this.error,
  });

  final bool loading;
  final bool configured;
  final WantedList? list;

  /// Only this catalog sheet (null = all).
  final String? sheet;
  final GapKind gap;
  final String query;
  final String? error;

  bool _isPicture(WantedItem i, String f) => list?.field(i.sheet, f)?.isPicture ?? (f == 'image' || f == 'fullBodyImage');

  List<WantedItem> get visible {
    final l = list;
    if (l == null) return const [];
    final q = query.trim().toLowerCase();
    return [
      for (final i in l.items)
        if ((sheet == null || i.sheet == sheet) &&
            (q.isEmpty || '${i.name} ${i.code} ${i.variant ?? ''}'.toLowerCase().contains(q)) &&
            switch (gap) {
              GapKind.all => true,
              GapKind.pictures => i.missing.any((f) => _isPicture(i, f)),
              GapKind.details => i.missing.any((f) => !_isPicture(i, f)),
            })
          i,
    ];
  }

  /// Sheets that have gaps, with how many entries each.
  List<(WantedSheet, int)> get sheetsWithCounts {
    final l = list;
    if (l == null) return const [];
    final n = <String, int>{};
    for (final i in l.items) {
      n[i.sheet] = (n[i.sheet] ?? 0) + 1;
    }
    return [for (final s in l.sheets.values) if ((n[s.key] ?? 0) > 0) (s, n[s.key]!)];
  }

  MissingListState copyWith({
    bool? loading,
    bool? configured,
    WantedList? list,
    String? Function()? sheet,
    GapKind? gap,
    String? query,
    String? Function()? error,
  }) =>
      MissingListState(
        loading: loading ?? this.loading,
        configured: configured ?? this.configured,
        list: list ?? this.list,
        sheet: sheet != null ? sheet() : this.sheet,
        gap: gap ?? this.gap,
        query: query ?? this.query,
        error: error != null ? error() : null,
      );

  @override
  List<Object?> get props => [loading, configured, list, sheet, gap, query, error];
}

/// "Help complete the catalog": what's missing, filtered by sheet, by pictures / details, and searched.
class MissingListCubit extends Cubit<MissingListState> {
  MissingListCubit(this._source) : super(const MissingListState());

  final WantedSource _source;

  Future<void> load({bool refresh = false}) async {
    if (!_source.isConfigured) {
      emit(state.copyWith(loading: false, configured: false));
      return;
    }
    emit(state.copyWith(loading: true));
    try {
      final list = await _source.load(refresh: refresh);
      emit(state.copyWith(loading: false, list: list));
    } on ContributionException catch (e) {
      emit(state.copyWith(loading: false, error: () => e.message));
    }
  }

  void setSheet(String? sheet) => emit(state.copyWith(sheet: () => sheet));
  void setGap(GapKind gap) => emit(state.copyWith(gap: gap));
  void setQuery(String q) => emit(state.copyWith(query: q));
}

// ── one entry ────────────────────────────────────────────────────────────────

class FillMissingState extends Equatable {
  const FillMissingState({
    this.loading = true,
    this.contributor,
    this.values = const {},
    this.picture,
    this.pictureField,
    this.credit = '',
    this.note = '',
    this.consent = false,
    this.submitting = false,
    this.receipt,
    this.error,
  });

  final bool loading;
  final Contributor? contributor;

  /// What the person typed, per missing field.
  final Map<String, String> values;
  final PickedPicture? picture;

  /// Which missing picture [picture] is for (image / fullBodyImage).
  final String? pictureField;
  final String credit;
  final String note;
  final bool consent;
  final bool submitting;
  final ContributionReceipt? receipt;
  final String? error;

  FillMissingState copyWith({
    bool? loading,
    Contributor? Function()? contributor,
    Map<String, String>? values,
    PickedPicture? Function()? picture,
    String? Function()? pictureField,
    String? credit,
    String? note,
    bool? consent,
    bool? submitting,
    ContributionReceipt? Function()? receipt,
    String? Function()? error,
  }) =>
      FillMissingState(
        loading: loading ?? this.loading,
        contributor: contributor != null ? contributor() : this.contributor,
        values: values ?? this.values,
        picture: picture != null ? picture() : this.picture,
        pictureField: pictureField != null ? pictureField() : this.pictureField,
        credit: credit ?? this.credit,
        note: note ?? this.note,
        consent: consent ?? this.consent,
        submitting: submitting ?? this.submitting,
        receipt: receipt != null ? receipt() : this.receipt,
        error: error != null ? error() : null,
      );

  @override
  List<Object?> get props =>
      [loading, contributor, values, picture, pictureField, credit, note, consent, submitting, receipt, error];
}

/// Fill in what one entry is missing: its fields (checked by type) and/or one of its missing pictures.
class FillMissingCubit extends Cubit<FillMissingState> {
  FillMissingCubit({
    required this.item,
    required this.sheet,
    required SubmitContributionUseCase submit,
    required ContributionPicturePicker picker,
  })  : _submit = submit,
        _picker = picker,
        super(const FillMissingState());

  final WantedItem item;

  /// The entry's sheet (field types, labels); fields it doesn't describe are shown as text.
  final WantedSheet? sheet;
  final SubmitContributionUseCase _submit;
  final ContributionPicturePicker _picker;

  WantedField fieldOf(String name) =>
      sheet?.fields[name] ??
      WantedField(
        name: name,
        type: name == 'image' || name == 'fullBodyImage' ? WantedFieldType.image : WantedFieldType.text,
        label: name,
      );

  List<WantedField> get detailFields => [for (final f in item.missing) if (!fieldOf(f).isPicture) fieldOf(f)];
  List<WantedField> get pictureFields => [for (final f in item.missing) if (fieldOf(f).isPicture) fieldOf(f)];

  /// Values that pass their field's check, ready to send.
  Map<String, String> get _cleanValues => {
        for (final f in detailFields)
          if ((state.values[f.name] ?? '').trim().isNotEmpty && f.check(state.values[f.name]!) == null)
            f.name: f.type == WantedFieldType.number
                ? state.values[f.name]!.trim().replaceAll(',', '.')
                : state.values[f.name]!.trim(),
      };

  bool get hasProblems => detailFields.any((f) => f.check(state.values[f.name] ?? '') != null);

  bool get canSubmit =>
      state.contributor != null &&
      !state.submitting &&
      state.consent &&
      !hasProblems &&
      (state.picture != null || _cleanValues.isNotEmpty);

  Future<void> start() async {
    final who = await _submit.contributor();
    emit(state.copyWith(
      loading: false,
      contributor: () => who,
      pictureField: () => pictureFields.isEmpty ? null : pictureFields.first.name,
    ));
  }

  void setValue(String field, String value) => emit(state.copyWith(values: {...state.values, field: value}));
  void setPictureField(String field) => emit(state.copyWith(pictureField: () => field));
  void setCredit(String v) => emit(state.copyWith(credit: v));
  void setNote(String v) => emit(state.copyWith(note: v));
  void setConsent(bool v) => emit(state.copyWith(consent: v));
  void clearPicture() => emit(state.copyWith(picture: () => null));

  Future<void> pickPicture({bool camera = false}) async {
    try {
      final p = await _picker.pick(camera: camera);
      if (p != null) emit(state.copyWith(picture: () => p));
    } on ContributionException catch (e) {
      emit(state.copyWith(error: () => e.message));
    } catch (_) {
      emit(state.copyWith(error: () => 'Couldn\'t open the picture.'));
    }
  }

  Future<void> send() async {
    if (!canSubmit) return;
    emit(state.copyWith(submitting: true));
    try {
      final receipt = await _submit(ContributionDraft(
        kind: state.pictureField == 'fullBodyImage' ? ContributionKind.fullBodyImage : ContributionKind.image,
        target: item.target,
        picture: state.picture,
        values: _cleanValues,
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
}
