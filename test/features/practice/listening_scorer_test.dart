import 'package:flutter_test/flutter_test.dart';
import 'package:new_words/features/practice/utils/listening_scorer.dart';
import 'package:new_words/features/practice/utils/text_normalizer.dart';

void main() {
  group('metricForLanguage', () {
    test('uses the character metric for CJK languages', () {
      expect(ListeningScorer.metricForLanguage('zh'), ScoringMetric.character);
      expect(ListeningScorer.metricForLanguage('ja'), ScoringMetric.character);
    });

    test('reads the base subtag of a locale-shaped code', () {
      expect(
        ListeningScorer.metricForLanguage('zh-CN'),
        ScoringMetric.character,
      );
      expect(
        ListeningScorer.metricForLanguage('zh_Hans_CN'),
        ScoringMetric.character,
      );
      expect(
        ListeningScorer.metricForLanguage(' JA-jp '),
        ScoringMetric.character,
      );
    });

    test('uses the token metric for space-delimited languages', () {
      expect(ListeningScorer.metricForLanguage('en'), ScoringMetric.token);
      expect(ListeningScorer.metricForLanguage('en-US'), ScoringMetric.token);
      expect(ListeningScorer.metricForLanguage(''), ScoringMetric.token);
    });
  });

  group('normalization', () {
    test('collapses case, punctuation and whitespace', () {
      expect(
        TextNormalizer.normalize('  The   FOX, jumped!  '),
        'the fox jumped',
      );
    });

    test('strips CJK full-width punctuation', () {
      expect(TextNormalizer.normalize('他跑了！真的吗？'), '他跑了真的吗');
      expect(TextNormalizer.normalize('「跑步」，很好。'), '跑步很好');
    });

    test('deletes punctuation inside a token instead of splitting it', () {
      // Punctuation is deleted, not spaced, so a comma the user omitted cannot
      // change the token count and fail an otherwise correct sentence.
      expect(
        TextNormalizer.normalize('hello,world'),
        TextNormalizer.normalize('helloworld'),
      );
      expect(TextNormalizer.tokens('hello,world'), ['helloworld']);
    });

    test('a spaced separator still leaves two tokens', () {
      expect(TextNormalizer.tokens('one - two'), ['one', 'two']);
      expect(TextNormalizer.tokens('one two'), ['one', 'two']);
    });

    test('keeps the ideographic zero, which is text and not punctuation', () {
      expect(TextNormalizer.normalize('二〇二五年'), '二〇二五年');
    });

    test('keeps full-width digits and letters', () {
      expect(TextNormalizer.normalize('ＡＢＣ１２３'), 'ａｂｃ１２３');
    });

    test('counts an astral-plane character as one unit', () {
      // A surrogate pair must not be split into two half-characters.
      expect(TextNormalizer.characters('𠮷野'), ['𠮷', '野']);
    });
  });

  group('scoreDictation — token metric', () {
    test('punctuation inside a token is a pass, not a token mismatch', () {
      final score = ListeningScorer.scoreDictation(
        "Wait — it isn't over, is it?",
        'wait it isnt over is it',
        ScoringMetric.token,
      );
      expect(score.ratio, 1.0);
      expect(score.outcome, ListeningOutcome.pass);
    });

    test('a punctuation and case only difference passes', () {
      final score = ListeningScorer.scoreDictation(
        'The quick brown fox jumps over the lazy dog.',
        'the quick brown fox jumps over the lazy dog',
        ScoringMetric.token,
      );
      expect(score.outcome, ListeningOutcome.pass);
      expect(score.ratio, 1.0);
      expect(score.diff.every((s) => s.kind == DiffKind.same), isTrue);
    });

    test('a single dropped word out of ten still passes on overlap', () {
      final score = ListeningScorer.scoreDictation(
        'one two three four five six seven eight nine ten',
        'one two three four five six seven eight nine',
        ScoringMetric.token,
      );
      expect(score.tokenOverlap, closeTo(0.9, 0.001));
      expect(score.outcome, ListeningOutcome.pass);
    });

    test('two wrong words out of six is a near miss, not a pass', () {
      final score = ListeningScorer.scoreDictation(
        'one two three four five six',
        'one two three four ten eleven',
        ScoringMetric.token,
      );
      expect(score.ratio, closeTo(2 / 3, 0.001));
      expect(score.tokenOverlap, closeTo(2 / 3, 0.001));
      expect(score.outcome, ListeningOutcome.nearMiss);
    });

    test('half the sentence wrong fails outright', () {
      final score = ListeningScorer.scoreDictation(
        'one two three four five six',
        'one two three nine ten eleven',
        ScoringMetric.token,
      );
      expect(score.ratio, closeTo(0.5, 0.001));
      expect(score.outcome, ListeningOutcome.fail);
    });

    test('an unrelated attempt fails', () {
      final score = ListeningScorer.scoreDictation(
        'the quick brown fox jumps',
        'nothing like it at all here',
        ScoringMetric.token,
      );
      expect(score.outcome, ListeningOutcome.fail);
    });

    test('an empty attempt fails', () {
      final score = ListeningScorer.scoreDictation(
        'the quick brown fox',
        '   ',
        ScoringMetric.token,
      );
      expect(score.outcome, ListeningOutcome.fail);
      expect(score.ratio, 0.0);
    });
  });

  group('scoreDictation — character metric', () {
    test('a CJK sentence differing only in punctuation passes', () {
      final score = ListeningScorer.scoreDictation(
        '他每天早上都在公园里跑步。',
        '他每天早上都在公园里跑步',
        ScoringMetric.character,
      );
      expect(score.outcome, ListeningOutcome.pass);
      expect(score.ratio, 1.0);
    });

    test('one wrong character out of thirteen passes', () {
      final score = ListeningScorer.scoreDictation(
        '他每天早上都在公园里跑步',
        '他每天早上都在公园里跑走',
        ScoringMetric.character,
      );
      expect(score.ratio, greaterThanOrEqualTo(ListeningScorer.passRatio));
      expect(score.outcome, ListeningOutcome.pass);
    });

    test('the character metric never passes on token overlap alone', () {
      // As one whitespace-free token these two would look identical to a
      // token metric; per character they are clearly different.
      final score = ListeningScorer.scoreDictation(
        '他每天早上都在公园里跑步',
        '她昨天晚上没有去公园里散步',
        ScoringMetric.character,
      );
      expect(score.tokenOverlap, 0.0);
      expect(score.outcome, isNot(ListeningOutcome.pass));
    });
  });

  group('scoreCloze', () {
    test('passes on an exact match after normalization', () {
      final score = ListeningScorer.scoreCloze(
        'Running',
        '  running!  ',
        ScoringMetric.token,
      );
      expect(score.outcome, ListeningOutcome.pass);
      expect(score.ratio, 1.0);
    });

    test('a near-correct inflection does not pass', () {
      final score = ListeningScorer.scoreCloze(
        'running',
        'runing',
        ScoringMetric.token,
      );
      expect(score.outcome, isNot(ListeningOutcome.pass));
    });

    test('scores a CJK blank per character', () {
      final score = ListeningScorer.scoreCloze(
        '跑步',
        '跑步',
        ScoringMetric.character,
      );
      expect(score.outcome, ListeningOutcome.pass);
    });
  });

  group('diff', () {
    test('marks missing and extra tokens around the common run', () {
      final diff = ListeningScorer.diff(
        'the quick brown fox',
        'the slow brown fox',
        ScoringMetric.token,
      );
      expect(diff, [
        const DiffSegment('the', DiffKind.same),
        const DiffSegment('quick', DiffKind.missing),
        const DiffSegment('slow', DiffKind.extra),
        const DiffSegment('brown fox', DiffKind.same),
      ]);
    });

    test('joins character segments without spaces', () {
      final diff = ListeningScorer.diff(
        '跑步很好',
        '跑步真好',
        ScoringMetric.character,
      );
      expect(diff, [
        const DiffSegment('跑步', DiffKind.same),
        const DiffSegment('很', DiffKind.missing),
        const DiffSegment('真', DiffKind.extra),
        const DiffSegment('好', DiffKind.same),
      ]);
    });

    test('reports an empty attempt as entirely missing', () {
      final diff = ListeningScorer.diff(
        'the quick fox',
        '',
        ScoringMetric.token,
      );
      expect(diff, [const DiffSegment('the quick fox', DiffKind.missing)]);
    });
  });

  group('levenshtein', () {
    test('is zero for identical sequences and length for an empty side', () {
      expect(ListeningScorer.levenshtein(['a', 'b'], ['a', 'b']), 0);
      expect(ListeningScorer.levenshtein(['a', 'b', 'c'], []), 3);
      expect(ListeningScorer.levenshtein([], ['a']), 1);
    });

    test('counts substitutions, insertions and deletions', () {
      expect(ListeningScorer.levenshtein(['a', 'b', 'c'], ['a', 'x', 'c']), 1);
      expect(ListeningScorer.levenshtein(['a', 'c'], ['a', 'b', 'c']), 1);
      expect(ListeningScorer.levenshtein(['a', 'b', 'c'], ['a', 'c']), 1);
    });

    test('two empty sequences are a perfect ratio', () {
      expect(ListeningScorer.levenshteinRatio([], []), 1.0);
    });
  });
}
