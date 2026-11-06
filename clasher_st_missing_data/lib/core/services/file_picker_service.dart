import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// The two file dialogs the app needs, behind an interface so tests can fake them.
abstract class FilePickerService {
  Future<String?> pickWorkbook();
  Future<Uint8List?> pickImage();
}

class NativeFilePickerService implements FilePickerService {
  @override
  Future<String?> pickWorkbook() async {
    final f = await FilePicker.pickFile(
        dialogTitle: 'Open workbook', type: FileType.custom, allowedExtensions: const ['xlsx']);
    return f?.path;
  }

  @override
  Future<Uint8List?> pickImage() async {
    final f = await FilePicker.pickFile(
        dialogTitle: 'Choose image',
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp']);
    return f == null ? null : await f.readAsBytes();
  }
}
