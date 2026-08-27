import 'package:dio/dio.dart';
import 'package:new_words/common/constants/api_constants.dart';
import 'package:new_words/dependency_injection.dart';
import 'package:new_words/services/session_expiry_notifier.dart';

/// Turns a server-side session rejection into a real logout.
///
/// Without this, a 401 surfaced as an error message per screen while
/// `AuthProvider.isAuthenticated` stayed true, leaving the user visibly
/// logged in with every feature broken.
///
/// The original [DioException] always continues down the chain, so callers
/// keep seeing the failure they already handle.
class SessionExpiryInterceptor extends Interceptor {
  /// [notifier] is injected by tests; production resolves it from the
  /// locator on first use.
  SessionExpiryInterceptor({SessionExpiryNotifier? notifier})
    : _notifier = notifier;

  final SessionExpiryNotifier? _notifier;

  /// Endpoints whose own 401 must not log the user out.
  ///
  /// `accountRefreshToken` is an authenticated call: logging out here would
  /// race the refresh it is trying to perform, and `getToken()` already
  /// handles a failed refresh. Login and register 401s are wrong credentials,
  /// not an expired session.
  static const Set<String> _exemptPaths = {
    ApiConstants.accountRefreshToken,
    ApiConstants.authLogin,
    ApiConstants.authRegister,
  };

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401 && !_isExempt(err.requestOptions)) {
      // Fire-and-forget: the Dio failure below must not wait on logout. The
      // notifier already swallows handler errors; `catchError` guards the
      // future regardless so it can never surface as an unhandled error.
      _resolveNotifier()?.notifySessionExpired().catchError((Object _) {});
    }
    handler.next(err);
  }

  SessionExpiryNotifier? _resolveNotifier() {
    if (_notifier != null) return _notifier;
    try {
      return locator<SessionExpiryNotifier>();
    } catch (_) {
      return null;
    }
  }

  bool _isExempt(RequestOptions options) {
    final isAnonymous = options.headers.keys.any(
      (key) =>
          key.toLowerCase() == ApiConstants.headerAllowAnonymous.toLowerCase(),
    );
    if (isAnonymous) return true;

    // Compare on the path alone: `options.path` may be a full URL, and a
    // query string would otherwise defeat `endsWith`.
    final path = options.path.split('?').first;
    return _exemptPaths.any(
      (exempt) => path == exempt || path.endsWith(exempt),
    );
  }
}
