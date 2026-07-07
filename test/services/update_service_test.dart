import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:new_words/apis/github_api.dart';
import 'package:new_words/entities/github_release.dart';
import 'package:new_words/services/update_service.dart';

import 'update_service_test.mocks.dart';

@GenerateMocks([GitHubApi])
void main() {
  group('UpdateService.checkForUpdate', () {
    late UpdateService updateService;
    late MockGitHubApi mockGitHubApi;

    setUp(() {
      mockGitHubApi = MockGitHubApi();
      updateService = UpdateService(mockGitHubApi);
    });

    GitHubRelease releaseWithVersion(String version) {
      return GitHubRelease(
        tagName: 'v$version',
        name: 'v$version',
        htmlUrl: 'https://github.com/example/repo/releases/tag/v$version',
        apkDownloadUrl: 'https://github.com/example/repo/releases/download/v$version/app.apk',
        publishedAt: 0,
      );
    }

    Future<void> setInstalledVersion(String version) async {
      PackageInfo.setMockInitialValues(
        appName: 'new_words',
        packageName: 'com.shukebeta.newwords',
        version: version,
        buildNumber: '1',
        buildSignature: '',
      );
    }

    test('returns the release when a newer version is published', () async {
      await setInstalledVersion('1.0.0');
      final release = releaseWithVersion('1.1.0');
      when(mockGitHubApi.getLatestRelease()).thenAnswer((_) async => release);

      final result = await updateService.checkForUpdate();

      expect(result, same(release));
    });

    test('returns null when the installed version is already ahead', () async {
      await setInstalledVersion('1.1.0');
      final release = releaseWithVersion('1.0.0');
      when(mockGitHubApi.getLatestRelease()).thenAnswer((_) async => release);

      final result = await updateService.checkForUpdate();

      expect(result, isNull);
    });

    test('returns null when the installed version equals the release version', () async {
      await setInstalledVersion('1.0.0');
      final release = releaseWithVersion('1.0.0');
      when(mockGitHubApi.getLatestRelease()).thenAnswer((_) async => release);

      final result = await updateService.checkForUpdate();

      expect(result, isNull);
    });
  });
}
