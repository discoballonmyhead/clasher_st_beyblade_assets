import 'dart:typed_data';

import 'package:equatable/equatable.dart';

import '../../../core/error/failure.dart';

/// A picture or one field value someone sent from the app (one row of the Submissions sheet). Values sent
/// together share a [batch].
class Submission extends Equatable {
  const Submission({
    required this.id,
    required this.submittedAt,
    required this.status,
    required this.kind,
    required this.targetType,
    required this.targetId,
    required this.targetName,
    required this.username,
    this.credit = '',
    this.note = '',
    this.mimeType = '',
    this.bytes = 0,
    this.platform = '',
    this.appVersion = '',
    this.field = '',
    this.value = '',
    this.batch = '',
  });

  final String id;
  final DateTime? submittedAt;

  /// new, applied, rejected.
  final String status;

  /// image (the main picture / a blader's portrait), fullBodyImage (a blader's full body), other, or value (a
  /// typed-in [field] = [value], no picture).
  final String kind;

  /// The catalog key (blades, lockChips, products, bladers ...) or "other".
  final String targetType;
  final String targetId;
  final String targetName;
  final String username;

  /// How they want to be credited (the username when they left it empty).
  final String credit;
  final String note;
  final String mimeType;
  final int bytes;
  final String platform;
  final String appVersion;

  /// For value rows: the column and what was typed (already checked by type in the app).
  final String field;
  final String value;

  /// Shared by everything sent at once.
  final String batch;

  bool get isValue => kind == 'value';

  bool get isOther => targetType == 'other' || kind == 'other';

  /// The picture column it goes into: null = the tab's main picture.
  String? get pictureField => kind == 'fullBodyImage' ? 'fullBodyImage' : null;

  /// What goes into the row's credits column.
  String get creditText => credit.trim().isNotEmpty ? credit.trim() : username;

  @override
  List<Object?> get props => [id, status, kind, targetType, targetId, credit, note, field, value, batch];
}

/// The submissions web app (Apps Script). Everything needs the admin key.
abstract class SubmissionsRepository {
  bool get isConfigured;
  Future<Result<List<Submission>>> list({String status = 'new'});
  Future<Result<Uint8List>> image(String id);
  Future<Result<void>> setStatus(String id, String status, {String note = ''});
}

/// [existing] credits plus [add], unless it's already there ("a; b" -> "a; b; c").
String mergeCredits(String? existing, String add) {
  final parts = [
    for (final p in (existing ?? '').split(RegExp(r'[;\n]'))) if (p.trim().isNotEmpty) p.trim(),
  ];
  final a = add.trim();
  if (a.isEmpty || parts.any((p) => p.toLowerCase() == a.toLowerCase())) return parts.join('; ');
  return [...parts, a].join('; ');
}
