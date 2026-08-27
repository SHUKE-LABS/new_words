/// One sentence of a story, located in the original marked-up content.
///
/// [start] and [end] are offsets into the string that was passed to
/// [SentenceSegmenter.segment], so `content.substring(start, end) == raw`.
/// [raw] keeps the `**bold**` / `__underline__` markers so rendering can reuse
/// the existing markdown regex; [speakable] strips them for TTS.
class SentenceSpan {
  final int start;
  final int end;
  final String raw;

  const SentenceSpan({
    required this.start,
    required this.end,
    required this.raw,
  });

  /// The sentence with markdown markers removed, for handing to TTS.
  String get speakable => SentenceSegmenter.stripMarkdown(raw).trim();

  @override
  String toString() => 'SentenceSpan($start, $end, ${raw.trim()})';
}

/// Splits story content into ordered sentences that keep their offsets into the
/// original content.
///
/// Shared foundation for story read-aloud and the listening features built on
/// top of it.
class SentenceSegmenter {
  SentenceSegmenter._();

  /// Terminators: latin `.!?` plus CJK full-width forms.
  static const String _terminators = '.!?。！？';

  /// Closing marks that belong to the sentence they follow.
  static const String _trailingMarks = '"\'’”）)]』」》>*_';

  /// A sentence whose spoken form is shorter than this is merged into the
  /// previous sentence instead of being emitted as a fragment.
  static const int _minSpeakableLength = 3;

  /// Tokens that end with `.` but do not end a sentence. Compared
  /// case-insensitively against the word immediately before the terminator.
  static const Set<String> _abbreviations = {
    'mr',
    'mrs',
    'ms',
    'dr',
    'prof',
    'st',
    'jr',
    'sr',
    'vs',
    'etc',
    'e.g',
    'i.e',
    'approx',
    'fig',
  };

  /// Removes `**bold**` and `__underline__` markers, keeping the inner text.
  static String stripMarkdown(String text) {
    var result = text.replaceAllMapped(
      RegExp(r'\*\*(.*?)\*\*'),
      (match) => match.group(1) ?? '',
    );
    result = result.replaceAllMapped(
      RegExp(r'__(.+?)__'),
      (match) => match.group(1) ?? '',
    );
    return result;
  }

  /// Splits [content] into sentences.
  ///
  /// Returns an empty list for empty or whitespace-only content. Otherwise the
  /// returned spans are ordered, non-overlapping and cover [content] in full,
  /// so a renderer can emit the spans alone without losing any character:
  /// leading whitespace stays on the first sentence and trailing whitespace on
  /// the sentence that precedes it.
  static List<SentenceSpan> segment(String content) {
    if (content.trim().isEmpty) return [];

    final spans = <SentenceSpan>[];
    // Start of the sentence currently being accumulated. Offsets start at 0 so
    // the spans reproduce the content exactly, including any leading
    // whitespace; `speakable` trims it for TTS.
    var cursor = 0;
    var i = 0;

    while (i < content.length) {
      final char = content[i];

      // A paragraph break closes the current sentence even without a
      // terminator, so an unterminated heading or line is spoken on its own.
      if (char == '\n') {
        final afterBreak = _skipWhitespace(content, i);
        if (_isParagraphBreak(content, i, afterBreak)) {
          if (_markersBalanced(content.substring(cursor, afterBreak))) {
            _append(spans, content, cursor, afterBreak);
            cursor = afterBreak;
          }
          i = afterBreak;
          continue;
        }
      }

      if (!_terminators.contains(char)) {
        i++;
        continue;
      }

      if (!_isSentenceEnd(content, i)) {
        i++;
        continue;
      }

      // Consume repeated terminators (`?!`, `...`) and closing marks.
      var end = i + 1;
      while (end < content.length &&
          (_terminators.contains(content[end]) ||
              _trailingMarks.contains(content[end]))) {
        end++;
      }

      // Trailing whitespace belongs to this sentence, so spans stay contiguous.
      end = _skipWhitespace(content, end);

      // Never cut through an open `**`/`__` pair: the renderer runs the
      // markdown regex per sentence, so a split pair would leak raw markers.
      if (!_markersBalanced(content.substring(cursor, end))) {
        i = end;
        continue;
      }

      _append(spans, content, cursor, end);
      cursor = end;
      i = end;
    }

    // Text after the last terminator (or content with no terminator at all).
    if (cursor < content.length) {
      _append(spans, content, cursor, content.length);
    }

    return spans;
  }

  /// Convenience: the spoken forms of [segment], fragments already merged.
  static List<String> speakableSentences(String content) =>
      segment(content).map((s) => s.speakable).toList();

  static void _append(
    List<SentenceSpan> spans,
    String content,
    int start,
    int end,
  ) {
    if (end <= start) return;
    final raw = content.substring(start, end);

    final isFragment =
        stripMarkdown(raw).trim().length < _minSpeakableLength;
    if (isFragment && spans.isNotEmpty) {
      final previous = spans.removeLast();
      spans.add(
        SentenceSpan(
          start: previous.start,
          end: end,
          raw: content.substring(previous.start, end),
        ),
      );
      return;
    }

    spans.add(SentenceSpan(start: start, end: end, raw: raw));
  }

  /// True when the whitespace run starting at [index] and ending at [end]
  /// separates paragraphs, i.e. it contains more than one newline.
  static bool _isParagraphBreak(String content, int index, int end) {
    var newlines = 0;
    for (var i = index; i < end; i++) {
      if (content[i] == '\n') newlines++;
    }
    return newlines > 1;
  }

  /// True when [text] contains complete `**`/`__` pairs only.
  static bool _markersBalanced(String text) {
    final bold = RegExp(r'\*\*').allMatches(text).length;
    final underline = RegExp(r'__').allMatches(text).length;
    return bold.isEven && underline.isEven;
  }

  static int _skipWhitespace(String content, int index) {
    var i = index;
    while (i < content.length && _isWhitespace(content[i])) {
      i++;
    }
    return i;
  }

  static bool _isWhitespace(String char) => char.trim().isEmpty;

  /// Decides whether the terminator at [index] really ends a sentence.
  static bool _isSentenceEnd(String content, int index) {
    final char = content[index];

    // CJK terminators are unambiguous.
    if (!'.!?'.contains(char)) return true;

    if (char == '.') {
      // Decimal number: digit before and after ("3.14").
      final before = index > 0 ? content[index - 1] : '';
      final after = index + 1 < content.length ? content[index + 1] : '';
      if (_isDigit(before) && _isDigit(after)) return false;

      // Abbreviation, including a single initial ("J. K. Rowling").
      final word = _wordBefore(content, index);
      if (word.length == 1 && _isLetter(word)) return false;
      if (_abbreviations.contains(word.toLowerCase())) return false;
    }

    // A terminator must be followed by whitespace, a closing mark, or the end
    // of the content; "x?y" mid-token is not a boundary.
    var next = index + 1;
    while (next < content.length &&
        (_terminators.contains(content[next]) ||
            _trailingMarks.contains(content[next]))) {
      next++;
    }
    if (next >= content.length) return true;
    if (!_isWhitespace(content[next])) return false;

    // A following lowercase word means the terminator was internal — most
    // often dialogue attribution (`"Stop!" she said.`). Merging keeps the
    // clause with its sentence instead of speaking a dangling fragment.
    final resume = _skipWhitespace(content, next);
    if (resume < content.length && _isLowerCaseLetter(content[resume])) {
      return false;
    }
    return true;
  }

  static bool _isLowerCaseLetter(String char) =>
      char.length == 1 && RegExp(r'[a-z]').hasMatch(char);

  /// The alphanumeric/dot word ending immediately before [index].
  static String _wordBefore(String content, int index) {
    var start = index;
    while (start > 0) {
      final char = content[start - 1];
      if (_isLetter(char) || _isDigit(char) || char == '.') {
        start--;
      } else {
        break;
      }
    }
    // Drop a leading dot left over from "e.g." style tokens.
    var word = content.substring(start, index);
    while (word.startsWith('.')) {
      word = word.substring(1);
    }
    return word;
  }

  static bool _isDigit(String char) =>
      char.length == 1 && RegExp(r'[0-9]').hasMatch(char);

  static bool _isLetter(String char) =>
      char.length == 1 && RegExp(r'[A-Za-z]').hasMatch(char);
}
