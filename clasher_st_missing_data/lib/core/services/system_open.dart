import 'dart:io';

/// Opens a folder or file with the system's file manager / default app.
Future<void> openInSystem(String path) async {
  try {
    if (Platform.isWindows) {
      await Process.run('explorer', [path]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else {
      await Process.run('xdg-open', [path]);
    }
  } on ProcessException {
    // nothing to open with: the path is shown in the UI anyway
  }
}
