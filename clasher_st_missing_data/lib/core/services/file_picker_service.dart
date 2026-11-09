import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// The two file dialogs the app needs, behind an interface so tests can fake them.
abstract class FilePickerService {
  Future<String?> pickWorkbook();
  Future<Uint8List?> pickImage();

  /// A folder (Flutter project root, export folder ...).
  Future<String?> pickFolder({String title = 'Choose a folder'});

  /// Any file with one of [extensions] (no dot).
  Future<String?> pickFile({
    required List<String> extensions,
    String title = 'Choose a file',
  });
}

class NativeFilePickerService implements FilePickerService {
  @override
  Future<String?> pickWorkbook() async {
    final f = await FilePicker.pickFile(
      dialogTitle: 'Open workbook',
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
    return f?.path;
  }

  @override
  Future<Uint8List?> pickImage() async {
    final f = await FilePicker.pickFile(
      dialogTitle: 'Choose image',
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
    );
    return f == null ? null : await f.readAsBytes();
  }

  @override
  Future<String?> pickFolder({String title = 'Choose a folder'}) =>
      FilePicker.getDirectoryPath(dialogTitle: title);

  @override
  Future<String?> pickFile({
    required List<String> extensions,
    String title = 'Choose a file',
  }) async {
    final f = await FilePicker.pickFile(
      dialogTitle: title,
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    return f?.path;
  }
}
