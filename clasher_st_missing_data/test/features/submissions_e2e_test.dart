// Reads the pictures contributions_e2e_test.dart sent, over real HTTP. Skipped unless SUBMISSIONS_E2E_URL is set:
//   SUBMISSIONS_E2E_URL=http://127.0.0.1:8765/exec flutter test test/features/submissions_e2e_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:missing_data_app/core/settings/app_settings.dart';
import 'package:missing_data_app/features/submissions/data/apps_script_submissions_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final url = Platform.environment['SUBMISSIONS_E2E_URL'];
  final skip = url == null ? 'set SUBMISSIONS_E2E_URL to run' : false;

  test('Studio lists, downloads and marks what the app sent', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettings(await SharedPreferences.getInstance());
    await settings.setPublishing(PublishingConstants(
        submissionsUrl: url!, submissionsAdminKey: Platform.environment['SUBMISSIONS_E2E_ADMIN'] ?? 'admin'));
    final repo = AppsScriptSubmissionsRepository(settings);

    final items = (await repo.list()).valueOrNull!;
    final kai = items.firstWhere((s) => s.username == 'kai');
    final ren = items.firstWhere((s) => s.username == 'ren');
    expect(kai.targetType, 'blades');
    expect(kai.targetId, '203');
    expect(kai.creditText, '@kai_photos');
    expect(ren.creditText, 'ren', reason: 'no credit typed: the app sent the username');

    final img = (await repo.image(kai.id)).valueOrNull!;
    expect(img.sublist(0, 3), [0xFF, 0xD8, 0xFF]);

    final marked = await repo.setStatus(kai.id, 'applied', note: 'Parts_X_Blades #203');
    expect(marked.fold((f) => f.message, (_) => 'ok'), 'ok');
    final after = (await repo.list()).valueOrNull!;
    expect(after.any((s) => s.id == kai.id), isFalse);
    expect(after.any((s) => s.id == ren.id), isTrue);
  }, skip: skip);
}
