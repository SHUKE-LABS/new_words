import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:new_words/apis/github_api.dart';
import 'package:new_words/entities/github_release.dart';
import 'package:new_words/app_config.dart';

/// Service for checking and downloading app updates from GitHub releases
class UpdateService {
  final GitHubApi _githubApi;

  UpdateService(this._githubApi);

  /// Check if a newer version is available on GitHub
  /// Returns the release info if an update is available, null otherwise
  Future<GitHubRelease?> checkForUpdate() async {
    try {
      // Get current app version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      // Get latest release from GitHub
      final release = await _githubApi.getLatestRelease();
      if (release == null || !release.hasApk) {
        return null;
      }

      // Compare versions
      if (_isNewerVersion(currentVersion, release.version)) {
        return release;
      }

      return null;
    } catch (e) {
      debugPrint('Error checking for updates: $e');
      return null;
    }
  }

  /// Download APK from the release
  /// [release] - The release containing APK info
  /// [onProgress] - Callback for download progress (0.0 to 1.0)
  /// Returns the path to downloaded APK file
  Future<String> downloadApk(
    GitHubRelease release, {
    void Function(double progress)? onProgress,
  }) async {
    if (release.apkDownloadUrl == null) {
      throw UpdateException('No APK URL in release');
    }

    // Get temporary directory
    final tempDir = await getTemporaryDirectory();
    final apkFileName = 'app-${release.tagName}.apk';
    final apkPath = '${tempDir.path}/$apkFileName';

    // Download APK
    await _githubApi.downloadApk(
      release.apkDownloadUrl!,
      apkPath,
      onProgress: onProgress,
    );

    return apkPath;
  }

  /// Install the APK at the given path
  /// This will open the system install dialog
  Future<OpenResult> installApk(String apkPath) async {
    final file = File(apkPath);
    if (!await file.exists()) {
      throw UpdateException('APK file not found at $apkPath');
    }

    return await OpenFilex.open(apkPath);
  }

  /// Compare version strings (semver format: major.minor.patch)
  /// Returns true if [versionB] is newer than [versionA]
  bool _isNewerVersion(String versionA, String versionB) {
    final vA = _parseVersion(versionA);
    final vB = _parseVersion(versionB);

    if (vB[0] > vA[0]) return true;
    if (vB[0] < vA[0]) return false;

    if (vB[1] > vA[1]) return true;
    if (vB[1] < vA[1]) return false;

    return vB[2] > vA[2];
  }

  /// Parse version string to [major, minor, patch]
  List<int> _parseVersion(String version) {
    final parts = version.split('.');
    final result = [0, 0, 0];

    for (int i = 0; i < parts.length && i < 3; i++) {
      final cleanPart = parts[i].replaceAll(RegExp(r'[^0-9]'), '');
      result[i] = int.tryParse(cleanPart) ?? 0;
    }

    return result;
  }
}

/// Factory for creating UpdateService with GitHub API configured from AppConfig
class UpdateServiceFactory {
  static UpdateService? _instance;

  static UpdateService getInstance() {
    _instance ??= _createInstance();
    return _instance!;
  }

  static UpdateService _createInstance() {
    final repo = AppConfig.githubRepo;
    final parts = repo.split('/');

    if (parts.length != 2) {
      throw UpdateException('Invalid GITHUB_REPO format: $repo. Expected "owner/repo"');
    }

    final githubApi = GitHubApi(
      repoOwner: parts[0],
      repoName: parts[1],
    );

    return UpdateService(githubApi);
  }

  static void reset() {
    _instance = null;
  }
}
