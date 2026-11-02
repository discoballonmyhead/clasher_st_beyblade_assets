import 'package:equatable/equatable.dart';

import '../../../domain/entities/fill_proposal.dart';

class AutofillState extends Equatable {
  const AutofillState({
    this.proposals = const [],
    this.selected = const {},
    this.hiddenSources = const {},
    this.loading = false,
    this.applying = false,
    this.applied,
    this.error,
  });

  final List<FillProposal> proposals;

  /// Indexes into [proposals] that will be applied.
  final Set<int> selected;

  /// Source kinds switched off ("parent", "same name", "derive").
  final Set<String> hiddenSources;
  final bool loading;
  final bool applying;

  /// Cells filled by the last apply (null until applied).
  final int? applied;
  final String? error;

  List<String> get sourceKinds => {for (final p in proposals) p.sourceKind}.toList()..sort();

  Iterable<int> get visible sync* {
    for (var i = 0; i < proposals.length; i++) {
      if (!hiddenSources.contains(proposals[i].sourceKind)) yield i;
    }
  }

  int get selectedVisible => visible.where(selected.contains).length;

  AutofillState copyWith({
    List<FillProposal>? proposals,
    Set<int>? selected,
    Set<String>? hiddenSources,
    bool? loading,
    bool? applying,
    int? applied,
    String? error,
  }) =>
      AutofillState(
        proposals: proposals ?? this.proposals,
        selected: selected ?? this.selected,
        hiddenSources: hiddenSources ?? this.hiddenSources,
        loading: loading ?? this.loading,
        applying: applying ?? this.applying,
        applied: applied ?? this.applied,
        error: error,
      );

  @override
  List<Object?> get props => [proposals, selected, hiddenSources, loading, applying, applied, error];
}
