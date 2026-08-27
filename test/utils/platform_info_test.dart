import 'package:flutter_test/flutter_test.dart';
import 'package:new_words/utils/platform_info.dart';

void main() {
  group('classifySpeechPlatform', () {
    test('Android and iOS are the shipping platforms', () {
      expect(
        classifySpeechPlatform(PlatformInfo.android),
        SpeechPlatform.android,
      );
      expect(classifySpeechPlatform(PlatformInfo.ios), SpeechPlatform.ios);
    });

    test('every other platform is unsupported', () {
      expect(
        classifySpeechPlatform(PlatformInfo.macOS),
        SpeechPlatform.unsupported,
      );
      expect(
        classifySpeechPlatform(PlatformInfo.windows),
        SpeechPlatform.unsupported,
      );
      expect(
        classifySpeechPlatform(PlatformInfo.linux),
        SpeechPlatform.unsupported,
      );
      expect(
        classifySpeechPlatform(PlatformInfo.web),
        SpeechPlatform.unsupported,
      );
    });

    test('web wins over the host it is compiled on', () {
      // The web double reports only isWeb, but the ordering matters: a web
      // build must never be classified by the underlying OS.
      expect(classifySpeechPlatform(_AndroidWeb()), SpeechPlatform.unsupported);
    });
  });

  group('PlatformInfo.current', () {
    test('reports exactly one platform on this host', () {
      const info = PlatformInfo.current;
      final flags = [
        info.isAndroid,
        info.isIOS,
        info.isMacOS,
        info.isWindows,
        info.isLinux,
        info.isWeb,
      ];
      expect(flags.where((f) => f).length, 1);
    });
  });
}

/// A web build running on an Android host, which the classifier must treat as
/// web.
class _AndroidWeb extends PlatformInfo {
  @override
  bool get isWeb => true;
  @override
  bool get isAndroid => true;
  @override
  bool get isIOS => false;
  @override
  bool get isMacOS => false;
  @override
  bool get isWindows => false;
  @override
  bool get isLinux => false;
}
