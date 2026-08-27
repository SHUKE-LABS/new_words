import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:new_words/services/session_expiry_notifier.dart';

import '../mocks/mock_app_logger.dart';

void main() {
  group('SessionExpiryNotifier', () {
    late MockAppLogger logger;
    late SessionExpiryNotifier notifier;

    setUp(() {
      logger = MockAppLogger();
      notifier = SessionExpiryNotifier(logger: logger);
    });

    test('no handler registered: notification is a silent no-op', () async {
      await notifier.notifySessionExpired();

      expect(notifier.isHandling, isFalse);
    });

    test('registered handler runs once per notification', () async {
      var runs = 0;
      notifier.registerHandler(() async => runs++);

      await notifier.notifySessionExpired();
      await notifier.notifySessionExpired();

      expect(runs, 2);
    });

    test(
      'concurrent notifications collapse into a single handler run',
      () async {
        var runs = 0;
        final gate = Completer<void>();
        notifier.registerHandler(() async {
          runs++;
          await gate.future;
        });

        // Start three notifications while the first handler is still awaiting.
        final inFlight = [
          notifier.notifySessionExpired(),
          notifier.notifySessionExpired(),
          notifier.notifySessionExpired(),
        ];
        expect(runs, 1, reason: 'guard must block before the first await');
        expect(notifier.isHandling, isTrue);

        gate.complete();
        await Future.wait(inFlight);

        expect(runs, 1);
        expect(notifier.isHandling, isFalse);
      },
    );

    test(
      'a throwing handler does not propagate and releases the guard',
      () async {
        var runs = 0;
        notifier.registerHandler(() async {
          runs++;
          throw StateError('logout blew up');
        });

        await notifier.notifySessionExpired();

        expect(
          notifier.isHandling,
          isFalse,
          reason: 'a failed handler must not lock the singleton',
        );
        expect(logger.errorLogs, hasLength(1));
        expect(logger.errorLogs.single, contains('logout blew up'));

        // The guard being released means a later 401 can still log the user out.
        await notifier.notifySessionExpired();
        expect(runs, 2);
      },
    );

    test('a later registration replaces the previous handler', () async {
      var first = 0;
      var second = 0;
      notifier.registerHandler(() async => first++);
      notifier.registerHandler(() async => second++);

      await notifier.notifySessionExpired();

      expect(first, 0);
      expect(second, 1);
    });
  });
}
