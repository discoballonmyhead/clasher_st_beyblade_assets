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
  const ContributionTarget({required this.type, required this.id, required this.name});

  /// Something that isn't in the catalog: say what it is in the note.
  const ContributionTarget.other()
      : type = 'other',
        id = '',
        name = 'Something else';

  final String type;
  final String id;
  final String name;

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
    required this.picture,
    this.credit,
    this.note,
    this.consent = false,
  });

  final ContributionKind kind;
  final ContributionTarget target;
  final PickedPicture picture;

  /// How the person wants to be credited in the app (a name, a handle, a link). Optional: when empty the
  /// username is used.
  final String? credit;
  final String? note;

  /// The person confirmed the picture is theirs to share.
  final bool consent;

  @override
  List<Object?> get props => [kind, target, picture, credit, note, consent];
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
