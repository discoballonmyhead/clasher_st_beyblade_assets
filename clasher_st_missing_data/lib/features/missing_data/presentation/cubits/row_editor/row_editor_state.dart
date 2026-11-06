import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import '../../../domain/entities/row.dart';

class RowEditorState extends Equatable {
  const RowEditorState({
    this.sheet,
    this.detail,
    this.drafts = const {},
    this.loading = false,
    this.saving = false,
    this.newImage,
    this.message,
    this.error,
  });

  final String? sheet;
  final RowDetail? detail;

  /// field -> typed value, only for fields the user changed.
  final Map<String, String> drafts;
  final bool loading;
  final bool saving;

  /// Image picked/pasted but not put on the row yet.
  final Uint8List? newImage;
  final String? message;
  final String? error;

  bool get hasDrafts => drafts.isNotEmpty;

  String valueOf(String field) => drafts[field] ?? detail?.display(field) ?? '';

  RowEditorState copyWith({
    String? sheet,
    RowDetail? detail,
    Map<String, String>? drafts,
    bool? loading,
    bool? saving,
    Uint8List? Function()? newImage,
    String? message,
    String? error,
  }) =>
      RowEditorState(
        sheet: sheet ?? this.sheet,
        detail: detail ?? this.detail,
        drafts: drafts ?? this.drafts,
        loading: loading ?? this.loading,
        saving: saving ?? this.saving,
        newImage: newImage != null ? newImage() : this.newImage,
        message: message,
        error: error,
      );

  @override
  List<Object?> get props => [sheet, detail, drafts, loading, saving, newImage?.length, message, error];
}
