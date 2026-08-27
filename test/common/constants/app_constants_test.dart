import 'package:flutter_test/flutter_test.dart';
import 'package:new_words/common/constants/app_constants.dart';

void main() {
  group('AppConstants', () {
    group('Business Logic Limits', () {
      test('word limits are properly defined', () {
        expect(AppConstants.maxWordLength, equals(100));
        expect(AppConstants.minWordLength, equals(1));
        expect(AppConstants.maxWordsPerPage, equals(50));
      });

      test('word limits are logically ordered', () {
        expect(
          AppConstants.minWordLength,
          lessThan(AppConstants.maxWordLength),
        );
        expect(AppConstants.maxWordsPerPage, greaterThan(0));
      });

      test('user input limits are properly defined', () {
        expect(AppConstants.minPasswordLength, equals(6));
        expect(AppConstants.maxPasswordLength, equals(128));
        expect(AppConstants.maxEmailLength, equals(254));
      });

      test('user input limits are logically ordered', () {
        expect(
          AppConstants.minPasswordLength,
          lessThan(AppConstants.maxPasswordLength),
        );
        expect(AppConstants.maxEmailLength, greaterThan(0));
      });
    });

    group('Timing Constants', () {
      test('token refresh threshold is properly defined', () {
        expect(AppConstants.tokenRefreshThreshold, equals(300000)); // 5 minutes
      });
    });

    group('Regex Patterns', () {
      test('email regex pattern is valid', () {
        final emailRegex = RegExp(AppConstants.emailRegex);

        // Valid emails
        expect(emailRegex.hasMatch('test@example.com'), isTrue);
        expect(emailRegex.hasMatch('user.name@domain.co.uk'), isTrue);
        expect(emailRegex.hasMatch('user+tag@example.org'), isTrue);

        // Invalid emails
        expect(emailRegex.hasMatch('invalid-email'), isFalse);
        expect(emailRegex.hasMatch('test@'), isFalse);
        expect(emailRegex.hasMatch('@example.com'), isFalse);
        expect(emailRegex.hasMatch(''), isFalse);
      });

      test('password regex pattern is valid', () {
        final passwordRegex = RegExp(AppConstants.passwordRegex);

        // Valid passwords: lower + upper + digit, at least 6 chars
        expect(passwordRegex.hasMatch('Passw0rd'), isTrue);
        expect(passwordRegex.hasMatch('aB3\$xy'), isTrue);

        // Invalid passwords
        expect(passwordRegex.hasMatch('password'), isFalse); // no upper/digit
        expect(passwordRegex.hasMatch('PASSW0RD'), isFalse); // no lowercase
        expect(passwordRegex.hasMatch('Pass0'), isFalse); // too short
        expect(passwordRegex.hasMatch(''), isFalse);
      });

      test('word regex pattern is valid', () {
        // Matches how the pattern is applied in VocabularyServiceV2.
        final wordRegex = RegExp(AppConstants.wordRegex, unicode: true);

        // Valid words
        expect(wordRegex.hasMatch('hello'), isTrue);
        expect(wordRegex.hasMatch('hello world'), isTrue);
        expect(wordRegex.hasMatch('well-known'), isTrue);
        expect(wordRegex.hasMatch("don't"), isTrue);
        expect(wordRegex.hasMatch('café'), isTrue);
        expect(wordRegex.hasMatch('单词'), isTrue);

        // Invalid words
        expect(wordRegex.hasMatch('hello123'), isFalse);
        expect(wordRegex.hasMatch('hello@world'), isFalse);
        expect(wordRegex.hasMatch(''), isFalse);
      });
    });
  });
}
