import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:new_words/utils/app_logger.dart';
import 'package:new_words/utils/app_logger_interface.dart';

void main() {
  group('AppLogger production default', () {
    late List<LogEvent> captured;
    late LogCallback listener;

    setUp(() {
      AppLogger.resetToDefault();
      captured = [];
      listener = captured.add;
      Logger.addLogListener(listener);
    });

    tearDown(() {
      Logger.removeLogListener(listener);
      AppLogger.resetToDefault();
    });

    // Nothing in the app awaits AppLogger.initialize(), and every service that
    // takes an AppLoggerInterface falls back to AppLogger.instance. If the
    // underlying logger were null until initialize(), every one of those
    // services would silently drop all of its logs -- including the
    // completePurchase failure that issue #46 requires to be logged.
    test('emits an error log without initialize() having been called', () {
      AppLogger.instance.e('acknowledgement failed');

      expect(
        captured.where((e) => e.level == Level.error).map((e) => e.message),
        contains('acknowledgement failed'),
      );
    });

    test('emits info and debug logs without initialize()', () {
      AppLogger.instance.i('info message');
      AppLogger.instance.d('debug message');

      final messages = captured.map((e) => e.message).toList();
      expect(messages, containsAll(['info message', 'debug message']));
    });

    test('a freshly resolved instance is an AppLoggerInterface', () {
      expect(AppLogger.instance, isA<AppLoggerInterface>());
    });
  });
}
