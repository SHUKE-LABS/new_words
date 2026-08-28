import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:new_words/exceptions/custom_exception.dart';
import 'package:new_words/utils/token_utils.dart';

/// Builds an unsigned JWT-shaped string with the given raw JSON payload text.
String buildToken(String payloadJson) {
  String segment(String raw) =>
      base64Url.encode(utf8.encode(raw)).replaceAll('=', '');
  return '${segment('{"alg":"HS256","typ":"JWT"}')}.'
      '${segment(payloadJson)}.signature';
}

Matcher customExceptionWith(String message) =>
    isA<CustomException>().having((e) => e.message, 'message', message);

void main() {
  late TokenUtils tokenUtils;

  setUp(() => tokenUtils = TokenUtils());

  group('valid token', () {
    test('decodeToken returns the payload map', () async {
      final token = buildToken('{"exp":1700000000,"sub":"42"}');

      final payload = await tokenUtils.decodeToken(token);

      expect(payload['exp'], 1700000000);
      expect(payload['sub'], '42');
    });

    test('both paths report the same remaining time', () async {
      final exp =
          DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
          1000;
      final token = buildToken('{"exp":$exp}');

      final asyncRemaining = await tokenUtils.getTokenRemainingTime(token);
      final syncRemaining = tokenUtils.getTokenRemainingTimeSync(token);

      expect(asyncRemaining.inMinutes, inInclusiveRange(58, 60));
      expect(syncRemaining.inMinutes, inInclusiveRange(58, 60));
    });
  });

  group('malformed token', () {
    const token = 'only.two';

    test('decodeToken throws Invalid token', () {
      expect(
        () => tokenUtils.decodeToken(token),
        throwsA(customExceptionWith('Invalid token')),
      );
    });

    test('getTokenRemainingTime throws Invalid token', () {
      expect(
        () => tokenUtils.getTokenRemainingTime(token),
        throwsA(customExceptionWith('Invalid token')),
      );
    });

    test('getTokenRemainingTimeSync throws Invalid token', () {
      expect(
        () => tokenUtils.getTokenRemainingTimeSync(token),
        throwsA(customExceptionWith('Invalid token')),
      );
    });
  });

  group('missing exp claim', () {
    final token = buildToken('{"sub":"42"}');

    test('getTokenRemainingTime throws', () {
      expect(
        () => tokenUtils.getTokenRemainingTime(token),
        throwsA(
          customExceptionWith('Token does not contain an expiration date'),
        ),
      );
    });

    test('getTokenRemainingTimeSync throws', () {
      expect(
        () => tokenUtils.getTokenRemainingTimeSync(token),
        throwsA(
          customExceptionWith('Token does not contain an expiration date'),
        ),
      );
    });
  });

  group('non-object payload', () {
    // Under the pinned dart_jsonwebtoken 3.2.0, JWT.decode indexes the payload
    // before returning it, so a string payload fails inside the dependency and
    // never reaches the `Invalid payload` guard. These tests pin that actual
    // behavior and, more importantly, keep the sync and async paths identical.
    final token = buildToken('"a bare string"');

    test('decodeToken throws TypeError', () {
      expect(() => tokenUtils.decodeToken(token), throwsA(isA<TypeError>()));
    });

    test('getTokenRemainingTime throws TypeError', () {
      expect(
        () => tokenUtils.getTokenRemainingTime(token),
        throwsA(isA<TypeError>()),
      );
    });

    test('getTokenRemainingTimeSync throws TypeError', () {
      expect(
        () => tokenUtils.getTokenRemainingTimeSync(token),
        throwsA(isA<TypeError>()),
      );
    });
  });
}
