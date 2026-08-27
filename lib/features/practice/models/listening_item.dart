/// Which exercise one item asks for.
enum ListeningVariant {
  /// The whole sentence is hidden; the user types everything they heard.
  dictation,

  /// The sentence is shown with its vocabulary span blanked; the user types
  /// only the blank.
  cloze,
}

/// One exercise in a listening set.
///
/// [sentenceIndex] is the index into the story's `SentenceSegmenter.segment()`
/// list and stays aligned to it whatever order the items are presented in, so
/// `StoryAudioController.playSentence(sentenceIndex)` plays the right sentence
/// and keeps its anti-overlap guard.
class ListeningItem {
  final int sentenceIndex;
  final ListeningVariant variant;

  /// What the attempt is compared against: the whole sentence for dictation,
  /// the blanked span alone for cloze.
  final String reference;

  /// The full spoken sentence, markers stripped — what audio says and what
  /// `Show answer` reveals.
  final String sentence;

  /// Cloze only: the shown text before and after the blank.
  final String promptBefore;
  final String promptAfter;

  const ListeningItem({
    required this.sentenceIndex,
    required this.variant,
    required this.reference,
    required this.sentence,
    this.promptBefore = '',
    this.promptAfter = '',
  });

  bool get isCloze => variant == ListeningVariant.cloze;
}
