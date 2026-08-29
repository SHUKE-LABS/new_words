import 'package:flutter_test/flutter_test.dart';
import 'package:new_words/features/stories/utils/sentence_segmenter.dart';

void main() {
  group('SentenceSegmenter.segment', () {
    void expectOffsetsConsistent(String content, List<SentenceSpan> spans) {
      for (var i = 0; i < spans.length; i++) {
        final span = spans[i];
        expect(content.substring(span.start, span.end), span.raw,
            reason: 'span $i raw must match its offsets');
        expect(span.start, lessThan(span.end));
        if (i > 0) {
          expect(span.start, spans[i - 1].end,
              reason: 'spans must be contiguous and ordered');
        }
      }
      if (spans.isNotEmpty) {
        expect(spans.first.start, 0,
            reason: 'spans must start at the beginning of the content');
        expect(spans.last.end, content.length,
            reason: 'spans must cover through the end of the content');
        expect(spans.map((s) => s.raw).join(), content,
            reason: 'spans joined must reproduce the content exactly, so the '
                'renderer loses no characters');
      }
    }

    test('splits English sentences on . ! and ?', () {
      const content = 'She waited. Then it rained! Did she mind? Not at all.';
      final spans = SentenceSegmenter.segment(content);

      expect(spans.map((s) => s.speakable).toList(), [
        'She waited.',
        'Then it rained!',
        'Did she mind?',
        'Not at all.',
      ]);
      expectOffsetsConsistent(content, spans);
    });

    test('splits CJK sentences on 。！？', () {
      const content = '她在等待。然后下雨了！她在意吗？完全不在意。';
      final spans = SentenceSegmenter.segment(content);

      expect(spans.map((s) => s.speakable).toList(), [
        '她在等待。',
        '然后下雨了！',
        '她在意吗？',
        '完全不在意。',
      ]);
      expectOffsetsConsistent(content, spans);
    });

    test('keeps markdown markers in raw and strips them for speech', () {
      const content = 'He felt **elated** today. She was __serene__ too.';
      final spans = SentenceSegmenter.segment(content);

      expect(spans.length, 2);
      expect(spans[0].raw.trim(), 'He felt **elated** today.');
      expect(spans[0].speakable, 'He felt elated today.');
      expect(spans[1].speakable, 'She was serene too.');
      expectOffsetsConsistent(content, spans);
    });

    test('does not split inside an open markdown pair', () {
      // The vocab emphasis spans the sentence terminator; splitting here would
      // leak raw ** markers into both sentences.
      const content = '**A long. phrase** ended. Another one follows.';
      final spans = SentenceSegmenter.segment(content);

      expect(spans.map((s) => s.speakable).toList(), [
        'A long. phrase ended.',
        'Another one follows.',
      ]);
      expectOffsetsConsistent(content, spans);
    });

    test('handles markdown right at the sentence end', () {
      const content = 'She was **calm.** He was not.';
      final spans = SentenceSegmenter.segment(content);

      expect(spans.map((s) => s.speakable).toList(), [
        'She was calm.',
        'He was not.',
      ]);
      expectOffsetsConsistent(content, spans);
    });

    test('returns an empty list for empty or whitespace-only content', () {
      expect(SentenceSegmenter.segment(''), isEmpty);
      expect(SentenceSegmenter.segment('   \n\t  '), isEmpty);
    });

    test('returns a single span when there is no terminator', () {
      const content = 'A story fragment with no terminator';
      final spans = SentenceSegmenter.segment(content);

      expect(spans.length, 1);
      expect(spans.single.speakable, content);
      expectOffsetsConsistent(content, spans);
    });

    test('does not split on abbreviations, decimals or initials', () {
      const content =
          'Dr. Smith paid 3.14 dollars. J. K. wrote it, e.g. last year. Done.';
      final spans = SentenceSegmenter.segment(content);

      expect(spans.map((s) => s.speakable).toList(), [
        'Dr. Smith paid 3.14 dollars.',
        'J. K. wrote it, e.g. last year.',
        'Done.',
      ]);
      expectOffsetsConsistent(content, spans);
    });

    test('keeps an ellipsis with its sentence', () {
      const content = 'She hesitated... Then she spoke.';
      final spans = SentenceSegmenter.segment(content);

      expect(spans.map((s) => s.speakable).toList(), [
        'She hesitated...',
        'Then she spoke.',
      ]);
      expectOffsetsConsistent(content, spans);
    });

    test('keeps dialogue attribution with its quoted sentence', () {
      const content = '"Stop!" she said. Ok then.';
      final spans = SentenceSegmenter.segment(content);

      // The `!` inside the quote is internal: the following lowercase clause
      // belongs to the same spoken sentence.
      expect(spans.map((s) => s.speakable).toList(), [
        '"Stop!" she said.',
        'Ok then.',
      ]);
      expectOffsetsConsistent(content, spans);
    });

    test('merges a too-short trailing fragment into the previous sentence', () {
      const content = 'She left the house. A.';
      final spans = SentenceSegmenter.segment(content);

      expect(spans.map((s) => s.speakable).toList(), [
        'She left the house. A.',
      ]);
      expectOffsetsConsistent(content, spans);
    });

    test('splits across paragraph breaks and keeps whitespace attached', () {
      const content = 'First para ends.\n\nSecond para starts.';
      final spans = SentenceSegmenter.segment(content);

      expect(spans.length, 2);
      expect(spans[0].raw, 'First para ends.\n\n');
      expect(spans[1].raw, 'Second para starts.');
      expectOffsetsConsistent(content, spans);
    });

    test('keeps leading whitespace on the first span', () {
      const content = '  Leading space. Second.';
      final spans = SentenceSegmenter.segment(content);

      // The renderer emits spans only, so dropping the prefix would shift the
      // story text; `speakable` trims it instead.
      expect(spans.first.raw, '  Leading space. ');
      expect(spans.first.speakable, 'Leading space.');
      expectOffsetsConsistent(content, spans);
    });

    test('a leading blank paragraph does not become an empty first sentence',
        () {
      // Regression: the empty span used to be emitted first, so playing from
      // sentence 0 spoke nothing and stopped before the story began.
      const content = '\n\nA long sentence.';
      final spans = SentenceSegmenter.segment(content);

      expect(spans.length, 1);
      expect(spans.single.speakable, 'A long sentence.');
      expectOffsetsConsistent(content, spans);
    });

    test('a leading blank paragraph is folded into the first real sentence', () {
      const content = '\n\n**Vocab** here. Next one.';
      final spans = SentenceSegmenter.segment(content);

      expect(spans.map((s) => s.speakable).toList(), [
        'Vocab here.',
        'Next one.',
      ]);
      // The whitespace stays in `raw`, so the renderer still reproduces the
      // original layout.
      expect(spans.first.raw.startsWith('\n\n'), isTrue);
      expectOffsetsConsistent(content, spans);
    });

    test('every span of a story-shaped content has something to speak', () {
      const content = '\n\n  # A Title\n\nShe waited. "Go!" he said.\n\n**bold**\n\nEnd.';
      final spans = SentenceSegmenter.segment(content);

      expect(spans, isNotEmpty);
      for (final span in spans) {
        expect(span.speakable, isNotEmpty,
            reason: 'an unspeakable span would stall sequential playback');
      }
      expectOffsetsConsistent(content, spans);
    });

    test('content that is entirely a fragment still yields one span', () {
      const content = 'Hi';
      final spans = SentenceSegmenter.segment(content);

      expect(spans.length, 1);
      expect(spans.single.speakable, 'Hi');
      expectOffsetsConsistent(content, spans);
    });

    test('a paragraph break closes a sentence without a terminator', () {
      const content = 'A heading with no terminator\n\nThen a sentence.';
      final spans = SentenceSegmenter.segment(content);

      expect(spans.map((s) => s.speakable).toList(), [
        'A heading with no terminator',
        'Then a sentence.',
      ]);
      expectOffsetsConsistent(content, spans);
    });

    test('a single newline does not close a sentence', () {
      const content = 'A wrapped line\ncontinues here. Next one.';
      final spans = SentenceSegmenter.segment(content);

      expect(spans.map((s) => s.speakable).toList(), [
        'A wrapped line\ncontinues here.',
        'Next one.',
      ]);
      expectOffsetsConsistent(content, spans);
    });

    test('does not close a paragraph inside an open markdown pair', () {
      const content = '**Open marker\n\nstill open** then done. Next.';
      final spans = SentenceSegmenter.segment(content);

      // The pair is kept in one span. The markers survive `speakable` because
      // the strip regexes do not span newlines — the same reason the app's
      // rendering regex leaves such markers literal today.
      expect(spans.map((s) => s.raw).toList(), [
        '**Open marker\n\nstill open** then done. ',
        'Next.',
      ]);
      expectOffsetsConsistent(content, spans);
    });
  });

  group('gloss stripping', () {
    String speakableOf(String content) {
      final spans = SentenceSegmenter.segment(content);
      expect(spans, hasLength(1));
      return spans.single.speakable;
    }

    test('drops a CJK gloss after an underlined target word', () {
      expect(
        speakableOf('The __deadline__ (截止日期) was approaching.'),
        'The deadline was approaching.',
      );
    });

    test('drops a Latin-script gloss, so nothing keys on script', () {
      expect(
        speakableOf('She had to __negotiate__ (negociar) with him.'),
        'She had to negotiate with him.',
      );
    });

    test('drops a gloss after a bolded word the generator added', () {
      expect(
        speakableOf('He asked his **supervisor** (supervisor) for help.'),
        'He asked his supervisor for help.',
      );
    });

    test('drops a gloss written with full-width brackets', () {
      expect(
        speakableOf('The __deadline__（截止日期）was approaching.'),
        'The deadline was approaching.',
      );
    });

    test('drops every gloss when a sentence carries several', () {
      expect(
        speakableOf(
          'The __deadline__ (截止日期) made Maya __negotiate__ (协商) with '
          'her **supervisor** (主管).',
        ),
        'The deadline made Maya negotiate with her supervisor.',
      );
    });

    test('drops a gloss that itself contains parentheses', () {
      expect(
        speakableOf('The __deadline__ (截止日期 (最后期限)) loomed.'),
        'The deadline loomed.',
      );
    });

    test('drops a gloss sitting at the end of the sentence', () {
      expect(
        speakableOf('Maya had to __negotiate__ (协商).'),
        'Maya had to negotiate.',
      );
    });

    test('leaves a marked word that carries no gloss alone', () {
      expect(
        speakableOf('The __deadline__ was approaching.'),
        'The deadline was approaching.',
      );
    });

    test('leaves a parenthesised aside with no marked word before it', () {
      expect(
        speakableOf('She waited (as always) by the door.'),
        'She waited (as always) by the door.',
      );
    });

    test('leaves an aside that follows a marked word at a distance', () {
      expect(
        speakableOf('The __deadline__ loomed (as always) over her.'),
        'The deadline loomed (as always) over her.',
      );
    });

    test('leaves the whole sentence alone when a gloss never closes', () {
      expect(
        speakableOf('The __deadline__ (截止日期 was approaching.'),
        'The deadline (截止日期 was approaching.',
      );
    });

    test('leaves earlier glosses in place when a later one is malformed', () {
      expect(
        speakableOf(
          'The __deadline__ (截止日期) made her __negotiate__ (协商 with him.',
        ),
        'The deadline (截止日期) made her negotiate (协商 with him.',
      );
    });

    test('does not let a gloss run across a line break', () {
      expect(
        speakableOf('The __deadline__ (截止日期\nwas approaching.'),
        'The deadline (截止日期\nwas approaching.',
      );
    });

    test('keeps a word gap when nothing separates the gloss from the next '
        'word', () {
      expect(
        speakableOf('The __deadline__ (截止日期)loomed over her.'),
        'The deadline loomed over her.',
      );
    });

    test('handles a marked span nested inside a gloss', () {
      expect(
        speakableOf('The __deadline__ (**deadline** 截止日期) loomed.'),
        'The deadline loomed.',
      );
    });

    test('leaves raw text and offsets untouched', () {
      const content =
          'The __deadline__ (截止日期) loomed. Maya __negotiated__ (协商).';
      final spans = SentenceSegmenter.segment(content);

      expect(
        spans.map((s) => s.raw).join(),
        content,
        reason: 'the renderer still receives the glosses in full',
      );
      for (final span in spans) {
        expect(content.substring(span.start, span.end), span.raw);
      }
      expect(spans.map((s) => s.speakable).toList(), [
        'The deadline loomed.',
        'Maya negotiated.',
      ]);
    });
  });

  group('SentenceSegmenter.speakableSentences', () {
    test('returns the spoken forms in order', () {
      expect(
        SentenceSegmenter.speakableSentences('One **two**. Three?'),
        ['One two.', 'Three?'],
      );
    });
  });
}
