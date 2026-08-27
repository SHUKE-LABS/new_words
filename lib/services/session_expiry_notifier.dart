import 'package:flutter/foundation.dart';
import 'package:new_words/dependency_injection.dart';
import 'package:new_words/utils/app_logger_interface.dart';

/// Called when the server has rejected the current session. Implementations
/// clear auth state and return to the login screen.
typedef SessionExpiryHandler = Future<void> Function();

/// Bridge between the Dio error interceptors and `AuthProvider`.
///
/// The interceptors cannot reach `AuthProvider` directly — it lives in the
/// widget tree as a `ChangeNotifierProvider`, not in the service locator — so
/// the provider registers its handler here on construction and the
/// interceptor fires notifications at this locator-registered singleton.
///
/// Owns the re-entrancy guard: a burst of concurrent 401s collapses into a
/// single handler run.
class SessionExpiryNotifier {
  SessionExpiryNotifier({AppLoggerInterface? logger}) : _logger = logger;

  final AppLoggerInterface? _logger;

  SessionExpiryHandler? _handler;
  bool _isHandling = false;

  /// True while a handler run is in flight.
  bool get isHandling => _isHandling;

  /// Replaces the registered handler. The last registration wins, so a
  /// rebuilt provider takes over from its predecessor.
  void registerHandler(SessionExpiryHandler handler) {
    _handler = handler;
  }

  @visibleForTesting
  void clearHandler() {
    _handler = null;
    _isHandling = false;
  }

  /// Runs the registered handler at most once at a time.
  ///
  /// No-op when no handler is registered or a run is already in flight. The
  /// guard is set before the handler is awaited and released in a `finally`,
  /// so a handler that throws cannot lock this singleton permanently. Handler
  /// failures are logged, never rethrown: the caller is a Dio error
  /// interceptor, where an escaping exception would become an unhandled
  /// future.
  Future<void> notifySessionExpired() async {
    final handler = _handler;
    if (handler == null || _isHandling) return;

    _isHandling = true;
    try {
      await handler();
    } catch (e) {
      _log('SessionExpiryNotifier: session-expiry handler failed: $e');
    } finally {
      _isHandling = false;
    }
  }

  void _log(String message) {
    try {
      (_logger ?? locator<AppLoggerInterface>()).e(message);
    } catch (_) {
      // Logging is best-effort: the same un-wired locator that breaks
      // resolution here is not worth failing the logout over.
    }
  }
}
