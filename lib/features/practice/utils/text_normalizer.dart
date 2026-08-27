/// Normalization shared by every listening comparison.
///
/// Both sides of a comparison go through the same pipeline, so a difference
/// that survives is a real difference in what the user heard — not casing,
/// spacing or punctuation.
class TextNormalizer {
  TextNormalizer._();

  /// Punctuation stripped before comparison.
  ///
  /// Ranges rather than literals, so what is included stays readable:
  /// - `0021-002F 003A-0040 005B-0060 007B-007E` — ASCII punctuation.
  /// - `2013-2014 2018-2019 201C-201D 2025-2026` — dashes, curly quotes,
  ///   ellipses.
  /// - `3000-3003 3008-3011 3014-301F` and `30FB` — CJK punctuation. The gaps
  ///   are deliberate: `3007` is the ideographic zero (二〇二五) and `3005`
  ///   the iteration mark, which are text, not punctuation.
  /// - `FF01-FF0F FF1A-FF20 FF3B-FF40 FF5B-FF65` — full-width forms, which a
  ///   Chinese or Japanese IME emits instead of the ASCII ones. The ranges
  ///   step over the full-width digits and letters.
  static final RegExp _punctuation = RegExp(
    r'[!-/:-@[-`{-~'
    r'–—‘’“”‥…'
    r'　-〃〈-】〔-〟・'
    r'！-／：-＠［-｀｛-･]',
  );

  static final RegExp _whitespace = RegExp(r'\s+');

  /// Trim, lowercase, drop punctuation and collapse whitespace.
  ///
  /// Punctuation is removed before the whitespace collapse so `"one - two"`
  /// and `"one two"` normalize alike.
  static String normalize(String text) {
    final stripped = text.toLowerCase().replaceAll(_punctuation, ' ');
    return stripped.replaceAll(_whitespace, ' ').trim();
  }

  /// The normalized text split on whitespace; empty for empty input.
  static List<String> tokens(String text) {
    final normalized = normalize(text);
    if (normalized.isEmpty) return const [];
    return normalized.split(' ');
  }

  /// The normalized text as characters, with spaces dropped.
  ///
  /// CJK sentences carry no word boundaries, so the comparison unit is the
  /// character and the spaces an IME may leave behind are noise. Split on
  /// runes, not code units, so a character outside the BMP counts as one unit
  /// instead of two halves of a surrogate pair.
  static List<String> characters(String text) =>
      normalize(
        text,
      ).replaceAll(' ', '').runes.map(String.fromCharCode).toList();
}
