import 'package:new_words/features/practice/models/listening_item.dart';
import 'package:new_words/features/practice/utils/listening_scorer.dart';
import 'package:new_words/features/practice/utils/text_normalizer.dart';
import 'package:new_words/features/stories/utils/sentence_segmenter.dart';

/// Derives a listening exercise set from a story's segmented sentences.
class ListeningSetBuilder {
  ListeningSetBuilder._();

  /// Upper bound on a set: past this it stops being a session and starts being
  /// homework.
  static const int maxItems = 8;

  /// Items with fewer units than this are fragments, not sentences.
  static const int minUnits = 3;

  /// The `**bold**` / `__underline__` span the story generator wrapped the
  /// user's vocabulary in — the same shape `StoryDetailScreen` renders.
  ///
  /// This span, taken from the sentence's own offsets, is what cloze blanks.
  /// Matching `Story.vocabularyWords` against the text instead would blank
  /// nothing or the wrong token, because the saved lemma (`run`) and the story
  /// form (`running`) differ.
  static final RegExp markedSpan = RegExp(r'\*\*(.+?)\*\*|__(.+?)__');

  /// Builds the set for [sentences] in [languageCode].
  ///
  /// Cloze-eligible sentences are selected first and the rest fill up to
  /// [maxItems]; the selection is then presented in story order, so playback
  /// runs forward through the story while the preference still decides *which*
  /// sentences made it in.
  ///
  /// A story with fewer than [maxItems] eligible sentences yields a smaller
  /// set: there is nothing to invent.
  static List<ListeningItem> build({
    required String languageCode,
    required List<SentenceSpan> sentences,
  }) {
    final metric = ListeningScorer.metricForLanguage(languageCode);

    final cloze = <ListeningItem>[];
    final dictation = <ListeningItem>[];
    final seen = <String>{};

    for (var index = 0; index < sentences.length; index++) {
      final span = sentences[index];
      final sentence = span.speakable;
      if (_unitCount(sentence, metric) < minUnits) continue;

      final key = TextNormalizer.normalize(sentence);
      if (key.isEmpty || !seen.add(key)) continue;

      final item = _clozeItem(index, span, sentence, metric);
      if (item != null) {
        cloze.add(item);
      } else {
        dictation.add(
          ListeningItem(
            sentenceIndex: index,
            variant: ListeningVariant.dictation,
            reference: sentence,
            sentence: sentence,
          ),
        );
      }
    }

    final selected = <ListeningItem>[
      ...cloze.take(maxItems),
      ...dictation.take(maxItems - cloze.take(maxItems).length),
    ];
    selected.sort((a, b) => a.sentenceIndex.compareTo(b.sentenceIndex));
    return selected;
  }

  /// A cloze item for [span], or null when it has no usable marked span — that
  /// sentence is routed to dictation instead.
  static ListeningItem? _clozeItem(
    int index,
    SentenceSpan span,
    String sentence,
    ScoringMetric metric,
  ) {
    final match = markedSpan.firstMatch(span.raw);
    if (match == null) return null;

    final blank = (match.group(1) ?? match.group(2) ?? '').trim();
    if (blank.isEmpty) return null;

    // The remaining text is shown, so it loses its markers like every other
    // rendered sentence; only the blank's own text is withheld.
    final before =
        SentenceSegmenter.stripMarkdown(
          span.raw.substring(0, match.start),
        ).trimLeft();
    final after =
        SentenceSegmenter.stripMarkdown(
          span.raw.substring(match.end),
        ).trimRight();

    return ListeningItem(
      sentenceIndex: index,
      variant: ListeningVariant.cloze,
      reference: blank,
      sentence: sentence,
      promptBefore: before,
      promptAfter: after,
    );
  }

  static int _unitCount(String sentence, ScoringMetric metric) =>
      metric == ScoringMetric.character
          ? TextNormalizer.characters(sentence).length
          : TextNormalizer.tokens(sentence).length;
}
