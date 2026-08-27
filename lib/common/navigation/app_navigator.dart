import 'package:flutter/material.dart';

/// Holds the app-level [Navigator] so non-widget code — Dio interceptors,
/// providers reacting to session expiry — can unwind the route stack.
class AppNavigator {
  AppNavigator._();

  /// Attached to `MaterialApp.navigatorKey` in `main.dart`.
  static final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();

  /// Pops every route above the first one, leaving the root route visible.
  ///
  /// A no-op before the first frame or once the navigator is unmounted, which
  /// is reachable: a 401 can land while the app is still starting up.
  static void popToRoot() {
    key.currentState?.popUntil((route) => route.isFirst);
  }
}
