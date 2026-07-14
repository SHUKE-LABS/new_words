import 'package:flutter_test/flutter_test.dart';
import 'package:new_words/entities/word_explanation.dart';

void main() {
  group('WordExplanation.status', () {
    Map<String, dynamic> baseJson() => {
          'id': 1,
          'wordCollectionId': 100,
          'wordText': 'test',
          'learningLanguage': 'en',
          'explanationLanguage': 'zh',
          'markdownExplanation': 'placeholder',
          'createdAt': 1234567890,
          'updatedAt': 1234567890,
        };

    test('defaults to Ready when status is absent', () {
      final word = WordExplanation.fromJson(baseJson());
      expect(word.status, equals(ExplanationStatus.ready));
      expect(word.isPending, isFalse);
    });

    test('parses Pending status', () {
      final word = WordExplanation.fromJson(
        baseJson()..['status'] = ExplanationStatus.pending,
      );
      expect(word.status, equals(ExplanationStatus.pending));
      expect(word.isPending, isTrue);
    });

    test('parses Ready status explicitly', () {
      final word = WordExplanation.fromJson(
        baseJson()..['status'] = ExplanationStatus.ready,
      );
      expect(word.isPending, isFalse);
    });

    test('round-trips status through toJson', () {
      final word = WordExplanation.fromJson(
        baseJson()..['status'] = ExplanationStatus.pending,
      );
      expect(word.toJson()['status'], equals(ExplanationStatus.pending));
    });

    test('status participates in equality', () {
      final ready = WordExplanation.fromJson(baseJson());
      final pending = WordExplanation.fromJson(
        baseJson()..['status'] = ExplanationStatus.pending,
      );
      expect(ready == pending, isFalse);
    });
  });
}
