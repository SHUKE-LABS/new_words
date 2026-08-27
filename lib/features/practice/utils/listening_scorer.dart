import 'package:new_words/features/practice/utils/text_normalizer.dart';

/// Which unit a comparison counts.
enum ScoringMetric {
  /// Space-delimited languages: whole words.
  token,

  /// CJK: single characters, because the text carries no word boundaries and
  /// token metrics would compare one giant "token" against another.
  character,
}

/// How close the user's attempt was.
enum ListeningOutcome { pass, nearMiss, fail }

/// One run of units that agree, are missing, or were invented.
enum DiffKind {
  /// Present in both, in order.
  same,

  /// In the reference, absent from the attempt.
  missing,

  /// In the attempt, absent from the reference.
  extra,
}

class DiffSegment {
  final String text;
  final DiffKind kind;

  const DiffSegment(this.text, this.kind);

  @override
  String toString() => '${kind.name}($text)';

  @override
  bool operator ==(Object other) =>
      other is DiffSegment && other.text == text && other.kind == kind;

  @override
  int get hashCode => Object.hash(text, kind);
}

/// The result of scoring one attempt.
class ListeningScore {
  final ListeningOutcome outcome;

  /// Levenshtein similarity in `[0, 1]` over the metric's units.
  final double ratio;

  /// Overlap of reference units present in the attempt, `[0, 1]`. Always 0 for
  /// [ScoringMetric.character], which does not use it.
  final double tokenOverlap;

  final List<DiffSegment> diff;

  const ListeningScore({
    required this.outcome,
    required this.ratio,
    required this.tokenOverlap,
    required this.diff,
  });

  bool get isPass => outcome == ListeningOutcome.pass;
}

/// Local, deterministic scoring of a dictation or cloze attempt.
///
/// No network, no model: the reference text is known, so the whole judgement is
/// string comparison over normalized units.
class ListeningScorer {
  ListeningScorer._();

  /// A Levenshtein similarity at or above this passes, under either metric.
  static const double passRatio = 0.85;

  /// Token overlap at or above this passes on its own, so a dropped article
  /// does not fail an otherwise correct sentence.
  static const double passTokenOverlap = 0.80;

  /// Below the pass bar but at or above this is a near miss, worth retrying
  /// rather than reporting as wrong.
  static const double nearMissRatio = 0.60;

  /// Languages whose text has no word boundaries.
  static const Set<String> _characterLanguages = {'zh', 'ja'};

  /// Picks the metric from the story's language — never from the input, which
  /// would let an empty or latin-only attempt change how it is judged.
  ///
  /// Accepts the bare code and the locale-shaped forms the API may carry
  /// (`zh-CN`, `zh_Hans_CN`), comparing on the base subtag.
  static ScoringMetric metricForLanguage(String languageCode) {
    final base = languageCode.trim().toLowerCase().split(RegExp(r'[-_]')).first;
    return _characterLanguages.contains(base)
        ? ScoringMetric.character
        : ScoringMetric.token;
  }

  static List<String> _units(String text, ScoringMetric metric) =>
      metric == ScoringMetric.character
          ? TextNormalizer.characters(text)
          : TextNormalizer.tokens(text);

  /// Scores a full-sentence dictation attempt.
  static ListeningScore scoreDictation(
    String reference,
    String attempt,
    ScoringMetric metric,
  ) {
    final referenceUnits = _units(reference, metric);
    final attemptUnits = _units(attempt, metric);

    final ratio = levenshteinRatio(referenceUnits, attemptUnits);
    final overlap =
        metric == ScoringMetric.token
            ? _tokenOverlap(referenceUnits, attemptUnits)
            : 0.0;

    final passed =
        ratio >= passRatio ||
        (metric == ScoringMetric.token && overlap >= passTokenOverlap);

    return ListeningScore(
      outcome:
          passed
              ? ListeningOutcome.pass
              : (ratio >= nearMissRatio
                  ? ListeningOutcome.nearMiss
                  : ListeningOutcome.fail),
      ratio: ratio,
      tokenOverlap: overlap,
      diff: diff(reference, attempt, metric),
    );
  }

  /// Scores a cloze attempt against the blanked span.
  ///
  /// One short span, so the bar is exact-after-normalization: a partial match
  /// on a single word is not evidence the user heard it.
  static ListeningScore scoreCloze(
    String reference,
    String attempt,
    ScoringMetric metric,
  ) {
    final referenceUnits = _units(reference, metric);
    final attemptUnits = _units(attempt, metric);
    final exact = _sameUnits(referenceUnits, attemptUnits);
    final ratio = levenshteinRatio(referenceUnits, attemptUnits);

    return ListeningScore(
      outcome:
          exact
              ? ListeningOutcome.pass
              : (ratio >= nearMissRatio
                  ? ListeningOutcome.nearMiss
                  : ListeningOutcome.fail),
      ratio: exact ? 1.0 : ratio,
      tokenOverlap: 0.0,
      diff: diff(reference, attempt, metric),
    );
  }

  /// Similarity in `[0, 1]`: `1 - distance / longestLength`.
  ///
  /// Two empty sequences are identical (1.0); one empty side is 0.0.
  static double levenshteinRatio(List<String> a, List<String> b) {
    if (a.isEmpty && b.isEmpty) return 1.0;
    final longest = a.length > b.length ? a.length : b.length;
    if (longest == 0) return 1.0;
    return 1.0 - levenshtein(a, b) / longest;
  }

  /// Edit distance over units, two rows of the matrix at a time.
  static int levenshtein(List<String> a, List<String> b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    var previous = List<int>.generate(b.length + 1, (i) => i);
    var current = List<int>.filled(b.length + 1, 0);

    for (var i = 1; i <= a.length; i++) {
      current[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final substitution = previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1);
        final deletion = previous[j] + 1;
        final insertion = current[j - 1] + 1;
        current[j] =
            substitution < deletion
                ? (substitution < insertion ? substitution : insertion)
                : (deletion < insertion ? deletion : insertion);
      }
      final swap = previous;
      previous = current;
      current = swap;
    }

    return previous[b.length];
  }

  /// Fraction of reference units the attempt supplies, counting duplicates
  /// only as often as the reference needs them.
  static double _tokenOverlap(List<String> reference, List<String> attempt) {
    if (reference.isEmpty) return attempt.isEmpty ? 1.0 : 0.0;

    final remaining = <String, int>{};
    for (final unit in attempt) {
      remaining[unit] = (remaining[unit] ?? 0) + 1;
    }

    var matched = 0;
    for (final unit in reference) {
      final available = remaining[unit] ?? 0;
      if (available > 0) {
        remaining[unit] = available - 1;
        matched++;
      }
    }
    return matched / reference.length;
  }

  static bool _sameUnits(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// An ordered diff of [attempt] against [reference], built from their longest
  /// common subsequence so unchanged runs stay merged.
  static List<DiffSegment> diff(
    String reference,
    String attempt,
    ScoringMetric metric,
  ) {
    final a = _units(reference, metric);
    final b = _units(attempt, metric);
    final joiner = metric == ScoringMetric.character ? '' : ' ';

    // lcs[i][j] = length of the LCS of a[i:] and b[j:].
    final lcs = List.generate(
      a.length + 1,
      (_) => List<int>.filled(b.length + 1, 0),
      growable: false,
    );
    for (var i = a.length - 1; i >= 0; i--) {
      for (var j = b.length - 1; j >= 0; j--) {
        lcs[i][j] =
            a[i] == b[j]
                ? lcs[i + 1][j + 1] + 1
                : (lcs[i + 1][j] >= lcs[i][j + 1]
                    ? lcs[i + 1][j]
                    : lcs[i][j + 1]);
      }
    }

    final segments = <DiffSegment>[];
    final buffer = <String>[];
    DiffKind? kind;

    void flush() {
      if (buffer.isEmpty) return;
      segments.add(DiffSegment(buffer.join(joiner), kind!));
      buffer.clear();
    }

    void emit(String unit, DiffKind unitKind) {
      if (kind != unitKind) {
        flush();
        kind = unitKind;
      }
      buffer.add(unit);
    }

    var i = 0;
    var j = 0;
    while (i < a.length && j < b.length) {
      if (a[i] == b[j]) {
        emit(a[i], DiffKind.same);
        i++;
        j++;
      } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
        emit(a[i], DiffKind.missing);
        i++;
      } else {
        emit(b[j], DiffKind.extra);
        j++;
      }
    }
    while (i < a.length) {
      emit(a[i++], DiffKind.missing);
    }
    while (j < b.length) {
      emit(b[j++], DiffKind.extra);
    }
    flush();

    return segments;
  }
}
