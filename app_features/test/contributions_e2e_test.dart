// Sends pictures and values over real HTTP to a running submissions web app (the deployed one, or submissions/test/local_server.js).
// Skipped unless CONTRIBUTIONS_E2E_URL is set:
//   CONTRIBUTIONS_E2E_URL=http://127.0.0.1:8765/exec flutter test test/contributions_e2e_test.dart
import 'dart:io';
import 'dart:typed_data';

import 'package:clasher_st/features/contributions/data/apps_script_contributions_repository.dart';
import 'package:clasher_st/features/contributions/data/contributions_config.dart';
import 'package:clasher_st/features/contributions/domain/entities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final url = Platform.environment['CONTRIBUTIONS_E2E_URL'];
  final key = Platform.environment['CONTRIBUTIONS_E2E_KEY'] ?? 'sk';
  final skip = url == null ? 'set CONTRIBUTIONS_E2E_URL to run' : false;
  final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 0x4A, 0x46, 0x49, 0x46]);

  test('the app sends pictures to the web app', () async {
    final repo = AppsScriptContributionsRepository(
        ContributionsConfig(endpoint: url!, submitKey: key, appVersion: 'e2e', platform: 'test'));
    final a = await repo.submit(
      ContributionDraft(
        kind: ContributionKind.image,
        target: const ContributionTarget(type: 'blades', id: '203', name: 'Hells Scythe'),
        picture: PickedPicture(bytes: jpeg, mimeType: 'image/jpeg'),
        credit: '@kai_photos',
        consent: true,
      ),
      const Contributor(username: 'kai', userId: 'u-1'),
    );
    expect(a.id, isNotEmpty);
    final b = await repo.submit(
      ContributionDraft(
        kind: ContributionKind.image,
        target: const ContributionTarget(type: 'blades', id: '65', name: 'Dran Sword'),
        picture: PickedPicture(bytes: jpeg, mimeType: 'image/jpeg'),
        consent: true,
      ),
      const Contributor(username: 'ren', userId: 'u-2'),
    );
    expect(b.id, isNot(a.id));

    // "Help complete the catalog": typed-in values with a picture, sent together
    final c = await repo.submit(
      ContributionDraft(
        kind: ContributionKind.image,
        target: const ContributionTarget(type: 'products', id: 'P2', name: 'Xtreme Stadium'),
        picture: PickedPicture(bytes: jpeg, mimeType: 'image/jpeg'),
        values: const {'releaseDate': '2023-07-15', 'itemCost': '15.99'},
        credit: '@kai_photos',
        consent: true,
      ),
      const Contributor(username: 'kai', userId: 'u-1'),
    );
    expect(c.id, isNotEmpty);

    final wrongKey = AppsScriptContributionsRepository(ContributionsConfig(endpoint: url, submitKey: 'nope'));
    await expectLater(
      wrongKey.submit(
        ContributionDraft(
          kind: ContributionKind.image,
          target: const ContributionTarget(type: 'blades', id: '65', name: 'x'),
          picture: PickedPicture(bytes: jpeg, mimeType: 'image/jpeg'),
          consent: true,
        ),
        const Contributor(username: 'x'),
      ),
      throwsA(isA<ContributionException>().having((e) => e.code, 'code', 'forbidden')),
    );
  }, skip: skip);
}
