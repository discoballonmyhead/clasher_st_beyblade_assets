import 'package:equatable/equatable.dart';

import '../../domain/entities/translation_models.dart';
import '../../domain/entities/translation_project.dart';

class TranslationState extends Equatable {
  const TranslationState({
    this.projects = const [],
    this.active,
    this.summary,
    this.report,
    this.loading = false,
    this.busy,
    this.message,
    this.error,
    this.revision = 0,
    this.addToApp = const {},
    this.updateEnglish = const {},
    this.export,
    this.packs,
    this.conflict = false,
  });

  final List<TranslationProject> projects;
  final TranslationProject? active;
  final TrSummary? summary;
  final TrReport? report;
  final bool loading;

  /// What's running ("Building packs ..."), null when idle.
  final String? busy;
  final String? message;
  final String? error;

  /// Bumped after every change, so lists reload.
  final int revision;

  /// Sheet keys to add to the app's constants on the next export: key -> section.
  final Map<String, String> addToApp;

  /// Keys whose app English becomes the sheet's on the next export.
  final Set<String> updateEnglish;
  final ExportResult? export;
  final PackReport? packs;

  /// The last save was refused because the file changed on disk.
  final bool conflict;

  bool get isOpen => summary != null;
  bool get dirty => summary?.sheet?.dirty ?? false;
  int get undoSteps => summary?.sheet?.undo ?? 0;
  List<TrLanguage> get languages => summary?.sheet?.languages ?? const [];
  List<String> get sections => summary?.project?.sections ?? const [];

  TranslationState copyWith({
    List<TranslationProject>? projects,
    TranslationProject? Function()? active,
    TrSummary? Function()? summary,
    TrReport? Function()? report,
    bool? loading,
    String? Function()? busy,
    String? Function()? message,
    String? Function()? error,
    int? revision,
    Map<String, String>? addToApp,
    Set<String>? updateEnglish,
    ExportResult? Function()? export,
    PackReport? Function()? packs,
    bool? conflict,
  }) => TranslationState(
    projects: projects ?? this.projects,
    active: active != null ? active() : this.active,
    summary: summary != null ? summary() : this.summary,
    report: report != null ? report() : this.report,
    loading: loading ?? this.loading,
    busy: busy != null ? busy() : this.busy,
    message: message != null ? message() : null,
    error: error != null ? error() : null,
    revision: revision ?? this.revision,
    addToApp: addToApp ?? this.addToApp,
    updateEnglish: updateEnglish ?? this.updateEnglish,
    export: export != null ? export() : this.export,
    packs: packs != null ? packs() : this.packs,
    conflict: conflict ?? false,
  );

  @override
  List<Object?> get props => [
    projects,
    active,
    summary,
    report,
    loading,
    busy,
    message,
    error,
    revision,
    addToApp,
    updateEnglish,
    export,
    packs,
    conflict,
  ];
}
