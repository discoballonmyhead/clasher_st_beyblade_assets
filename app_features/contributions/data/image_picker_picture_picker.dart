import 'package:clasher_st/features/contributions/domain/contributions_repository.dart';
import 'package:clasher_st/features/contributions/domain/entities.dart';
import 'package:image_picker/image_picker.dart';

/// Gallery / camera via image_picker. Pictures are scaled to at most 1600 px and re-compressed on the phone,
/// so an upload is a few hundred KB instead of a 12 MP original.
class ImagePickerPicturePicker implements ContributionPicturePicker {
  ImagePickerPicturePicker([ImagePicker? picker]) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<PickedPicture?> pick({bool camera = false}) async {
    final file = await _picker.pickImage(
      source: camera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 85,
    );
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    final mime = sniffImageMime(bytes);
    if (mime == null) {
      throw const ContributionException('invalid', 'Pick a JPEG, PNG or WebP picture.');
    }
    return PickedPicture(bytes: bytes, mimeType: mime, name: file.name);
  }
}
