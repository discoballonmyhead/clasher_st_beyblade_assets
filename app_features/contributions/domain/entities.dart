import 'dart:typed_data';

import 'package:equatable/equatable.dart';

/// What the picture is: the main picture of a part / product / accessory (or a blader's portrait), a blader's
/// full-body picture, or anything else (described in the note). The wire names match the Apps Script.
enum ContributionKind {
  image('image'),
  fullBodyImage('fullBodyImage'),
  other('other');

  const ContributionKind(this.wire);
  final String wire;
}

/// What the picture is of. [type] is the catalog sheet key the app uses ("blades", "lockChips", "bladers",
/// "products", "accessories" ...) or "other"; [id] is the row id in that sheet (dataID / bladerID / productID).
class ContributionTarget extends Equatable {
  const ContributionTarget({required this.type, required this.id, required this.name, this.missing = const []});

  /// Something that isn't in the catalog: say what it is in the note.
  const ContributionTarget.other()
      : type = 'other',
        id = '',
        name = 'Something else',
        missing = const [];

  final String type;
  final String id;
  final String name;

  /// What the catalog lacks for it (labels, e.g. "Picture", "Weight"), when known. Not part of equality.
  final List<String> missing;

  bool get isOther => type == 'other';
  bool get isBlader => type == 'bladers';

  @override
  List<Object?> get props => [type, id, name];
}

/// The signed-in person sending the picture.
class Contributor extends Equatable {
  const Contributor({required this.username, this.userId});
  final String username;
  final String? userId;

  @override
  List<Object?> get props => [username, userId];
}

/// A picture ready to send.
class PickedPicture extends Equatable {
  const PickedPicture({required this.bytes, required this.mimeType, this.name});
  final Uint8List bytes;

  /// image/jpeg, image/png or image/webp.
  final String mimeType;
  final String? name;

  @override
  List<Object?> get props => [bytes.length, mimeType, name];
}

class ContributionDraft extends Equatable {
  const ContributionDraft({
    required this.kind,
    required this.target,
    this.picture,
    this.values = const {},
    this.credit,
    this.note,
    this.consent = false,
  });

  /// Which picture [picture] is (ignored without one).
  final ContributionKind kind;
  final ContributionTarget target;

  /// Optional when [values] has something.
  final PickedPicture? picture;

  /// Missing fields filled in: field name -> value as typed (e.g. {"mass": "34.6", "type": "attack"}).
  final Map<String, String> values;

  bool get hasValues => values.values.any((v) => v.trim().isNotEmpty);

  /// How the person wants to be credited in the app (a name, a handle, a link). Optional: when empty the
  /// username is used.
  final String? credit;
  final String? note;

  /// The person confirmed the picture is theirs to share.
  final bool consent;

  @override
  List<Object?> get props => [kind, target, picture, values, credit, note, consent];
}

class ContributionReceipt extends Equatable {
  const ContributionReceipt(this.id);
  final String id;
  @override
  List<Object?> get props => [id];
}

/// Why a submission didn't go through, with a message to show as it is.
class ContributionException implements Exception {
  const ContributionException(this.code, this.message);

  /// not_configured, signed_out, invalid, too_large, rate_limited, forbidden, network, server ...
  final String code;
  final String message;

  @override
  String toString() => message;
}

/// What the picker accepts, by the file's first bytes (a renamed file of another kind isn't a picture).
String? sniffImageMime(Uint8List b) {
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'image/jpeg';
  if (b.length >= 4 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
  if (b.length >= 12 &&
      b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
      b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
    return 'image/webp';
  }
  return null;
}

// ── what's missing (data/_wanted.json) ──────────────────────────────────────────

/// How a missing field is filled in.
enum WantedFieldType { number, date, choice, text, image }

class WantedField extends Equatable {
  const WantedField({
    required this.name,
    required this.type,
    required this.label,
    this.unit,
    this.hint,
    this.choices = const [],
  });

  final String name;
  final WantedFieldType type;
  final String label;
  final String? unit;
  final String? hint;
  final List<String> choices;

  bool get isPicture => type == WantedFieldType.image;

  /// Null when [value] is acceptable for this field, else why not.
  String? check(String value) {
    final v = value.trim();
    if (v.isEmpty) return null;
    switch (type) {
      case WantedFieldType.number:
        final n = double.tryParse(v.replaceAll(',', '.'));
        if (n == null) return 'A number, e.g. 34.6';
        if (n < 0) return 'Can\'t be negative';
        return null;
      case WantedFieldType.date:
        return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v) && DateTime.tryParse(v) != null
            ? null
            : 'A date like 2024-07-15';
      case WantedFieldType.choice:
        return choices.contains(v) ? null : 'Pick one of the options';
      case WantedFieldType.text:
      case WantedFieldType.image:
        return v.length > 300 ? 'Keep it under 300 characters' : null;
    }
  }

  @override
  List<Object?> get props => [name, type, label, unit, hint, choices];
}

/// One catalog sheet in the wanted list (Blades, Boxes and sets, Bladers ...).
class WantedSheet extends Equatable {
  const WantedSheet({required this.key, required this.label, this.generation, this.fields = const {}});
  final String key;
  final String label;
  final String? generation;
  final Map<String, WantedField> fields;
  @override
  List<Object?> get props => [key, label, generation, fields];
}

/// A catalog entry with gaps.
class WantedItem extends Equatable {
  const WantedItem({
    required this.sheet,
    required this.id,
    required this.name,
    required this.missing,
    this.code = '',
    this.variant,
    this.generation,
    this.hobby,
    this.thumb,
  });

  final String sheet;
  final String id;
  final String name;
  final String code;
  final String? variant;
  final String? generation;
  final String? hobby;

  /// A small picture of it when there is one.
  final String? thumb;

  /// Missing field names (pictures: image / fullBodyImage).
  final List<String> missing;

  ContributionTarget get target => ContributionTarget(type: sheet, id: id, name: name);

  @override
  List<Object?> get props => [sheet, id, name, code, variant, generation, hobby, thumb, missing];
}

class WantedList extends Equatable {
  const WantedList({required this.sheets, required this.items, this.generatedAt});
  final Map<String, WantedSheet> sheets;
  final List<WantedItem> items;
  final DateTime? generatedAt;

  WantedField? field(String sheet, String name) => sheets[sheet]?.fields[name];

  @override
  List<Object?> get props => [sheets, items, generatedAt];
}
