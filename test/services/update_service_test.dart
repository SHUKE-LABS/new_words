import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:new_words/apis/github_api.dart';
import 'package:new_words/entities/github_release.dart';
import 'package:new_words/services/update_service.dart';

@GenerateMocks([GitHubApi])
import 'update_service_test.mocks.dart';

GitHubRelease _release(String tagName, {String? apkUrl, bool hasApk = true}) {
  return GitHubRelease(
    tagName: tagName,
    name: tagName,
    htmlUrl: 'https://example.com/release/$tagName',
    apkDownloadUrl: hasApk ? (apkUrl ?? 'https://example.com/$tagName.apk') : null,
    publishedAt: 1700000000,
  );
}

void main() {
  group('UpdateService.checkForUpdate', () {
    late MockGitHubApi mockApi;

    setUp(() {
      mockApi = MockGitHubApi();
    });

    test('returns release when installed is older than release', () async {
      when(mockApi.getLatestRelease())
          .thenAnswer((_) async => _release('v1.1.0'));

      final service = UpdateService.test(mockApi, '1.0.0');
      final result = await service.checkForUpdate();

      expect(result, isNotNull);
      expect(result!.tagName, equals('v1.1.0'));
    });

    test('returns null when installed is newer than release', () async {
      when(mockApi.getLatestRelease())
          .thenAnswer((_) async => _release('v1.0.0'));

      final service = UpdateService.test(mockApi, '1.1.0');
      final result = await service.checkForUpdate();

      expect(result, isNull);
    });

    test('returns null when versions are equal', () async {
      when(mockApi.getLatestRelease())
          .thenAnswer((_) async => _release('v1.0.0'));

      final service = UpdateService.test(mockApi, '1.0.0');
      final result = await service.checkForUpdate();

      expect(result, isNull);
    });

    test('returns null when release has no APK', () async {
      when(mockApi.getLatestRelease()).thenAnswer(
          (_) async => _release('v1.1.0', hasApk: false));

      final service = UpdateService.test(mockApi, '1.0.0');
      final result = await service.checkForUpdate();

      expect(result, isNull);
    });

    test('returns null when GitHub API returns null', () async {
      when(mockApi.getLatestRelease()).thenAnswer((_) async => null);

      final service = UpdateService.test(mockApi, '1.0.0');
      final result = await service.checkForUpdate();

      expect(result, isNull);
    });

    test('returns null when API throws', () async {
      when(mockApi.getLatestRelease())
          .thenThrow(UpdateException('boom'));

      final service = UpdateService.test(mockApi, '1.0.0');
      final result = await service.checkForUpdate();

      expect(result, isNull);
    });
  });
}