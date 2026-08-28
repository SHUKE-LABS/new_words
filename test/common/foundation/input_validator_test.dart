import 'package:flutter_test/flutter_test.dart';
import 'package:new_words/common/foundation/input_validator.dart';
import 'package:new_words/common/foundation/service_exceptions.dart';

/// Minimal host for the mixin under test.
class _Validator with InputValidator {}

/// Matches a [DataException] raised by `DataException.validation`.
Matcher throwsValidation(String field, {String? messageContains}) {
  var matcher = isA<DataException>().having((e) => e.field, 'field', field);
  if (messageContains != null) {
    matcher = matcher.having((e) => e.message, 'message', contains(messageContains));
  }
  return throwsA(matcher);
}

void main() {
  late _Validator validator;

  setUp(() {
    validator = _Validator();
  });

  group('validateInput', () {
    test('passes for non-empty string, list and numeric values', () {
      expect(
        () => validator.validateInput({
          'name': 'shuke',
          'tags': ['a'],
          'count': 0,
          'flag': false,
        }),
        returnsNormally,
      );
    });

    test('passes for an empty map (no arguments to check)', () {
      expect(() => validator.validateInput({}), returnsNormally);
    });

    test('throws when a value is null', () {
      expect(
        () => validator.validateInput({'name': null}),
        throwsValidation('name', messageContains: 'Field is required'),
      );
    });

    test('throws when a string value is empty', () {
      expect(
        () => validator.validateInput({'name': ''}),
        throwsValidation('name', messageContains: 'Field cannot be empty'),
      );
    });

    test('throws when a string value is whitespace only', () {
      expect(
        () => validator.validateInput({'name': '   '}),
        throwsValidation('name', messageContains: 'Field cannot be empty'),
      );
    });

    test('throws when a list value is empty', () {
      expect(
        () => validator.validateInput({'tags': <String>[]}),
        throwsValidation('tags', messageContains: 'List cannot be empty'),
      );
    });

    test('reports the first failing field when several are invalid', () {
      expect(
        () => validator.validateInput({'first': null, 'second': ''}),
        throwsValidation('first'),
      );
    });

    test('accepts an empty map value (only String and List emptiness is checked)', () {
      expect(
        () => validator.validateInput({'meta': <String, dynamic>{}}),
        returnsNormally,
      );
    });
  });

  group('validateStringField', () {
    group('required', () {
      test('throws when value is null', () {
        expect(
          () => validator.validateStringField(null, 'title'),
          throwsValidation('title', messageContains: 'Field is required'),
        );
      });

      test('throws when value is empty', () {
        expect(
          () => validator.validateStringField('', 'title'),
          throwsValidation('title', messageContains: 'Field is required'),
        );
      });

      test('throws when value is whitespace only', () {
        expect(
          () => validator.validateStringField('   ', 'title'),
          throwsValidation('title', messageContains: 'Field is required'),
        );
      });

      test('passes for a non-empty value', () {
        expect(() => validator.validateStringField('hello', 'title'), returnsNormally);
      });
    });

    group('optional', () {
      test('null is a no-op', () {
        expect(
          () => validator.validateStringField(null, 'title', required: false, minLength: 5),
          returnsNormally,
        );
      });

      test('empty string is a no-op', () {
        expect(
          () => validator.validateStringField('', 'title', required: false, minLength: 5),
          returnsNormally,
        );
      });

      test('whitespace-only value is still length checked (length is untrimmed)', () {
        expect(
          () => validator.validateStringField('   ', 'title', required: false, minLength: 5),
          throwsValidation('title', messageContains: 'Must be at least 5 characters'),
        );
      });
    });

    group('minLength', () {
      test('throws below the boundary', () {
        expect(
          () => validator.validateStringField('ab', 'title', minLength: 3),
          throwsValidation('title', messageContains: 'Must be at least 3 characters'),
        );
      });

      test('passes at the boundary', () {
        expect(() => validator.validateStringField('abc', 'title', minLength: 3), returnsNormally);
      });

      test('passes above the boundary', () {
        expect(() => validator.validateStringField('abcd', 'title', minLength: 3), returnsNormally);
      });

      test('counts untrimmed length', () {
        expect(() => validator.validateStringField(' a ', 'title', minLength: 3), returnsNormally);
      });
    });

    group('maxLength', () {
      test('throws above the boundary', () {
        expect(
          () => validator.validateStringField('abcd', 'title', maxLength: 3),
          throwsValidation('title', messageContains: 'Must be no more than 3 characters'),
        );
      });

      test('passes at the boundary', () {
        expect(() => validator.validateStringField('abc', 'title', maxLength: 3), returnsNormally);
      });

      test('passes below the boundary', () {
        expect(() => validator.validateStringField('ab', 'title', maxLength: 3), returnsNormally);
      });

      test('counts untrimmed length', () {
        expect(
          () => validator.validateStringField('ab  ', 'title', maxLength: 3),
          throwsValidation('title', messageContains: 'Must be no more than 3 characters'),
        );
      });
    });

    group('pattern', () {
      test('RegExp match passes', () {
        expect(
          () => validator.validateStringField('abc123', 'code', pattern: RegExp(r'^[a-z0-9]+$')),
          returnsNormally,
        );
      });

      test('RegExp mismatch throws with the default description', () {
        expect(
          () => validator.validateStringField('ABC!', 'code', pattern: RegExp(r'^[a-z0-9]+$')),
          throwsValidation('code', messageContains: 'Invalid format'),
        );
      });

      test('RegExp mismatch surfaces a custom description', () {
        expect(
          () => validator.validateStringField(
            'ABC!',
            'code',
            pattern: RegExp(r'^[a-z0-9]+$'),
            patternDescription: 'Lowercase alphanumerics only',
          ),
          throwsValidation('code', messageContains: 'Lowercase alphanumerics only'),
        );
      });

      test('RegExp matches a substring (hasMatch is unanchored)', () {
        expect(
          () => validator.validateStringField('xx-abc-xx', 'code', pattern: RegExp(r'abc')),
          returnsNormally,
        );
      });

      test('String pattern found in the value passes', () {
        expect(
          () => validator.validateStringField('user@example.com', 'email', pattern: '@'),
          returnsNormally,
        );
      });

      test('String pattern absent from the value throws', () {
        expect(
          () => validator.validateStringField(
            'not-an-email',
            'email',
            pattern: '@',
            patternDescription: 'Must contain @',
          ),
          throwsValidation('email', messageContains: 'Must contain @'),
        );
      });

      test('pattern is skipped for an absent optional value', () {
        expect(
          () => validator.validateStringField(null, 'code', required: false, pattern: RegExp(r'^\d+$')),
          returnsNormally,
        );
      });
    });

    test('applies minLength before pattern when both fail', () {
      expect(
        () => validator.validateStringField('A', 'code', minLength: 3, pattern: RegExp(r'^[a-z]+$')),
        throwsValidation('code', messageContains: 'Must be at least 3 characters'),
      );
    });
  });

  group('validateNumericField', () {
    test('required + null throws', () {
      expect(
        () => validator.validateNumericField(null, 'age'),
        throwsValidation('age', messageContains: 'Field is required'),
      );
    });

    test('optional + null is a no-op', () {
      expect(
        () => validator.validateNumericField(null, 'age', required: false, min: 1),
        returnsNormally,
      );
    });

    test('passes with no bounds', () {
      expect(() => validator.validateNumericField(42, 'age'), returnsNormally);
    });

    group('min', () {
      test('throws below the boundary', () {
        expect(
          () => validator.validateNumericField(0, 'age', min: 1),
          throwsValidation('age', messageContains: 'Must be at least 1'),
        );
      });

      test('passes at the boundary', () {
        expect(() => validator.validateNumericField(1, 'age', min: 1), returnsNormally);
      });

      test('passes above the boundary', () {
        expect(() => validator.validateNumericField(2, 'age', min: 1), returnsNormally);
      });

      test('throws for a negative value below the boundary', () {
        expect(
          () => validator.validateNumericField(-5, 'age', min: 0),
          throwsValidation('age', messageContains: 'Must be at least 0'),
        );
      });
    });

    group('max', () {
      test('throws above the boundary', () {
        expect(
          () => validator.validateNumericField(11, 'score', max: 10),
          throwsValidation('score', messageContains: 'Must be no more than 10'),
        );
      });

      test('passes at the boundary', () {
        expect(() => validator.validateNumericField(10, 'score', max: 10), returnsNormally);
      });

      test('passes below the boundary', () {
        expect(() => validator.validateNumericField(9, 'score', max: 10), returnsNormally);
      });
    });

    group('double values', () {
      test('throws just below min', () {
        expect(
          () => validator.validateNumericField(0.99, 'ratio', min: 1.0),
          throwsValidation('ratio', messageContains: 'Must be at least 1.0'),
        );
      });

      test('passes inside the range', () {
        expect(
          () => validator.validateNumericField(1.5, 'ratio', min: 1.0, max: 2.0),
          returnsNormally,
        );
      });

      test('throws just above max', () {
        expect(
          () => validator.validateNumericField(2.01, 'ratio', min: 1.0, max: 2.0),
          throwsValidation('ratio', messageContains: 'Must be no more than 2.0'),
        );
      });
    });

    test('applies min before max when both bounds are set', () {
      expect(
        () => validator.validateNumericField(0, 'score', min: 1, max: 10),
        throwsValidation('score', messageContains: 'Must be at least 1'),
      );
    });
  });

  group('processPaginationParams', () {
    test('returns the params map for valid input', () {
      expect(validator.processPaginationParams(1, 20), {'pageNumber': 1, 'pageSize': 20});
    });

    test('returns the params map at the default upper bound', () {
      expect(validator.processPaginationParams(3, 100), {'pageNumber': 3, 'pageSize': 100});
    });

    test('throws when pageNumber is below 1', () {
      expect(
        () => validator.processPaginationParams(0, 20),
        throwsValidation('pageNumber', messageContains: 'Must be at least 1'),
      );
    });

    test('throws when pageNumber is negative', () {
      expect(
        () => validator.processPaginationParams(-1, 20),
        throwsValidation('pageNumber', messageContains: 'Must be at least 1'),
      );
    });

    test('throws when pageSize is below the default minimum', () {
      expect(
        () => validator.processPaginationParams(1, 0),
        throwsValidation('pageSize', messageContains: 'Must be at least 1'),
      );
    });

    test('throws when pageSize exceeds the default maximum', () {
      expect(
        () => validator.processPaginationParams(1, 101),
        throwsValidation('pageSize', messageContains: 'Must be no more than 100'),
      );
    });

    test('honours a custom maxPageSize', () {
      expect(validator.processPaginationParams(1, 50, maxPageSize: 50), {'pageNumber': 1, 'pageSize': 50});
      expect(
        () => validator.processPaginationParams(1, 51, maxPageSize: 50),
        throwsValidation('pageSize', messageContains: 'Must be no more than 50'),
      );
    });

    test('honours a custom minPageSize', () {
      expect(validator.processPaginationParams(1, 10, minPageSize: 10), {'pageNumber': 1, 'pageSize': 10});
      expect(
        () => validator.processPaginationParams(1, 9, minPageSize: 10),
        throwsValidation('pageSize', messageContains: 'Must be at least 10'),
      );
    });

    test('validates pageNumber before pageSize', () {
      expect(
        () => validator.processPaginationParams(0, 999),
        throwsValidation('pageNumber'),
      );
    });
  });
}
