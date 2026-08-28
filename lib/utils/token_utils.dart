import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import '../exceptions/custom_exception.dart';

class TokenUtils {
  /// Single decode implementation shared by the async and sync entry points.
  ///
  /// Note: under `dart_jsonwebtoken` 3.2.0 the payload-type guard is defensive
  /// only — `JWT.decode` indexes the payload internally, so a non-object
  /// payload raises a `TypeError`/`NoSuchMethodError` before we get here.
  Map<String, dynamic> _decodePayload(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      throw CustomException('Invalid token');
    }

    var jwt = JWT.decode(token);
    if (jwt.payload is! Map<String, dynamic>) {
      throw CustomException('Invalid payload');
    }

    return jwt.payload;
  }

  Duration _remainingFrom(Map<String, dynamic> payload) {
    if (!payload.containsKey('exp')) {
      throw CustomException('Token does not contain an expiration date');
    }

    final exp = payload['exp'];
    final expiryDate = DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    final currentTime = DateTime.now();

    return expiryDate.difference(currentTime);
  }

  Future<Map<String, dynamic>> decodeToken(String token) async {
    return _decodePayload(token);
  }

  Future<Duration> getTokenRemainingTime(String token) async {
    return _remainingFrom(await decodeToken(token));
  }

  /// Synchronous version of getTokenRemainingTime for immediate access
  Duration getTokenRemainingTimeSync(String token) {
    return _remainingFrom(_decodePayload(token));
  }
}
