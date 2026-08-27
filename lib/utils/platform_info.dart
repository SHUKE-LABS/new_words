import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Which platform the app is running on, behind an injectable seam.
///
/// `dart:io`'s `Platform` cannot be varied in a test and throws on Web, so
/// every platform decision goes through this instead of touching `Platform`
/// directly. Production uses [PlatformInfo.current]; tests construct the
/// const doubles below.
abstract class PlatformInfo {
  const PlatformInfo();

  static const PlatformInfo current = _RuntimePlatformInfo();

  static const PlatformInfo android = _FixedPlatformInfo(isAndroid: true);
  static const PlatformInfo ios = _FixedPlatformInfo(isIOS: true);
  static const PlatformInfo macOS = _FixedPlatformInfo(isMacOS: true);
  static const PlatformInfo windows = _FixedPlatformInfo(isWindows: true);
  static const PlatformInfo linux = _FixedPlatformInfo(isLinux: true);
  static const PlatformInfo web = _FixedPlatformInfo(isWeb: true);

  bool get isAndroid;
  bool get isIOS;
  bool get isMacOS;
  bool get isWindows;
  bool get isLinux;
  bool get isWeb;
}

class _RuntimePlatformInfo extends PlatformInfo {
  const _RuntimePlatformInfo();

  /// True when `dart:io`'s `Platform` cannot be consulted at all.
  ///
  /// `kIsWeb` covers the compiled-for-web case; the `UnsupportedError` guards
  /// in the getters cover any other host where the accessors throw.
  @override
  bool get isWeb => kIsWeb;

  @override
  bool get isAndroid => _query(() => Platform.isAndroid);

  @override
  bool get isIOS => _query(() => Platform.isIOS);

  @override
  bool get isMacOS => _query(() => Platform.isMacOS);

  @override
  bool get isWindows => _query(() => Platform.isWindows);

  @override
  bool get isLinux => _query(() => Platform.isLinux);

  static bool _query(bool Function() probe) {
    if (kIsWeb) return false;
    try {
      return probe();
    } on UnsupportedError {
      return false;
    }
  }
}

class _FixedPlatformInfo extends PlatformInfo {
  const _FixedPlatformInfo({
    this.isAndroid = false,
    this.isIOS = false,
    this.isMacOS = false,
    this.isWindows = false,
    this.isLinux = false,
    this.isWeb = false,
  });

  @override
  final bool isAndroid;
  @override
  final bool isIOS;
  @override
  final bool isMacOS;
  @override
  final bool isWindows;
  @override
  final bool isLinux;
  @override
  final bool isWeb;
}

/// Where speaking practice runs.
enum SpeechPlatform {
  android,
  ios,

  /// Everything else. macOS is excluded because `permission_handler` has no
  /// macOS implementation, so the permanently-denied classification and the
  /// settings opener have no backing there; Windows and Web are a product
  /// scope decision; Linux has no recognizer at all.
  unsupported,
}

/// Pure classification of [platform], so every branch is testable off-device.
SpeechPlatform classifySpeechPlatform(PlatformInfo platform) {
  if (platform.isWeb) return SpeechPlatform.unsupported;
  if (platform.isAndroid) return SpeechPlatform.android;
  if (platform.isIOS) return SpeechPlatform.ios;
  return SpeechPlatform.unsupported;
}
