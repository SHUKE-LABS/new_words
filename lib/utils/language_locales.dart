/// ISO 639-1 language code to platform locale, shared by speech synthesis and
/// speech recognition.
///
/// The lookup is deliberately **nullable and fallback-free**: an unknown code
/// must stay unknown so a caller can refuse it. `TtsService` applies its own
/// legacy `en-US` fallback at its call site; recognition treats null as an
/// unsupported language rather than silently listening for English.
class LanguageLocales {
  LanguageLocales._();

  static const Map<String, String> _localeMap = {
    'en': 'en-US',
    'zh': 'zh-CN',
    'es': 'es-ES',
    'fr': 'fr-FR',
    'de': 'de-DE',
    'ja': 'ja-JP',
    'ko': 'ko-KR',
    'it': 'it-IT',
    'pt': 'pt-BR',
    'ru': 'ru-RU',
    'ar': 'ar-SA',
    'hi': 'hi-IN',
    'th': 'th-TH',
    'vi': 'vi-VN',
    'id': 'id-ID',
    'ms': 'ms-MY',
    'tr': 'tr-TR',
    'pl': 'pl-PL',
    'nl': 'nl-NL',
    'sv': 'sv-SE',
    'no': 'nb-NO',
    'da': 'da-DK',
    'fi': 'fi-FI',
  };

  /// The platform locale for [languageCode], or null when it is not mapped.
  static String? localeFor(String languageCode) => _localeMap[languageCode];
}
