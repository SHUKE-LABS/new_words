import 'package:flutter_test/flutter_test.dart';
import 'package:new_words/features/practice/models/listening_item.dart';
import 'package:new_words/features/practice/utils/listening_set_builder.dart';
import 'package:new_words/features/stories/utils/sentence_segmenter.dart';

List<ListeningItem> buildFor(String content, {String language = 'en'}) =>
    ListeningSetBuilder.build(
      languageCode: language,
      sentences: SentenceSegmenter.segment(content),
    );

void main() {
  group('cloze derivation', () {
    test('blanks the marked span even when the saved word is a different '
        'inflection', () {
      // The user saved "run"; the story text carries "running". A string match
      // against the saved word would blank nothing — the marked span must win.
      final items = buildFor(
        'He was **running** through the park at dawn. '
        'The morning air felt cold and clean.',
      );

      final cloze = items.firstWhere((i) => i.isCloze);
      expect(cloze.reference, 'running');
      expect(cloze.promptBefore, 'He was ');
      // The space that separated the marked span from the next word stays on
      // the shown text, so the rendered line reads "He was _____ through ...".
      expect(cloze.promptAfter, ' through the park at dawn.');
      // No marker leaks into the shown text.
      expect(cloze.promptBefore, isNot(contains('*')));
      expect(cloze.sentence, 'He was running through the park at dawn.');
    });

    test('blanks an __underline__ span too', () {
      final items = buildFor(
        'She __whispered__ something to the cat. It did not care at all.',
      );
      final cloze = items.firstWhere((i) => i.isCloze);
      expect(cloze.reference, 'whispered');
    });

    test('routes a sentence with no marked span to dictation', () {
      final items = buildFor(
        'Nothing here is marked at all. The second sentence is also plain.',
      );
      expect(items, isNotEmpty);
      expect(
        items.every((i) => i.variant == ListeningVariant.dictation),
        isTrue,
      );
      expect(items.first.reference, items.first.sentence);
    });

    test('a marked span of only markers is not cloze-eligible', () {
      final items = buildFor('The sign said ____ and nothing else was clear.');
      expect(items.every((i) => !i.isCloze), isTrue);
    });
  });

  group('set shape', () {
    test('is empty for a story with nothing to practise', () {
      expect(buildFor(''), isEmpty);
      expect(buildFor('   \n\n  '), isEmpty);
    });

    test('drops sub-3-token items', () {
      // "Yes." is a fragment; the segmenter merges it, and anything left with
      // fewer than three tokens is dropped rather than practised.
      final items = buildFor(
        'Go now. The rest of this sentence is long enough.',
      );
      for (final item in items) {
        expect(
          item.sentence.trim().split(RegExp(r'\s+')).length,
          greaterThanOrEqualTo(3),
        );
      }
    });

    test('caps the set at eight items', () {
      final content = List.generate(
        14,
        (i) => 'Sentence number $i is long enough to practise with.',
      ).join(' ');
      expect(buildFor(content).length, ListeningSetBuilder.maxItems);
    });

    test('prefers vocab-bearing sentences when capping', () {
      final plain = List.generate(
        10,
        (i) => 'Plain sentence number $i runs on for a while.',
      ).join(' ');
      final marked = List.generate(
        6,
        (i) => 'Marked sentence number $i mentions **word$i** clearly.',
      ).join(' ');

      final items = buildFor('$plain $marked');
      expect(items.length, ListeningSetBuilder.maxItems);
      expect(items.where((i) => i.isCloze).length, 6);
    });

    test('dedupes repeated sentences', () {
      final items = buildFor(
        'The same sentence appears twice here. '
        'The same sentence appears twice here. '
        'A different sentence closes the story.',
      );
      expect(items.length, 2);
    });

    test('keeps items in story order and aligned to the segmenter indices', () {
      const content =
          'Plain opening sentence goes first here. '
          'Then a marked **word** appears in the middle. '
          'A plain closing sentence ends the story.';
      final sentences = SentenceSegmenter.segment(content);
      final items = ListeningSetBuilder.build(
        languageCode: 'en',
        sentences: sentences,
      );

      expect(items.map((i) => i.sentenceIndex).toList(), [0, 1, 2]);
      for (final item in items) {
        expect(sentences[item.sentenceIndex].speakable, item.sentence);
      }
    });
  });

  group('CJK', () {
    test('counts characters, not tokens, when deciding eligibility', () {
      // Two characters: fewer than three units, so it is not practised.
      expect(buildFor('跑步。', language: 'zh'), isEmpty);
    });

    test('builds a cloze item from a marked CJK span', () {
      final items = buildFor('他每天早上都在公园里**跑步**。他从不觉得累。', language: 'zh');
      final cloze = items.firstWhere((i) => i.isCloze);
      expect(cloze.reference, '跑步');
      expect(cloze.promptBefore, '他每天早上都在公园里');
    });
  });
}
