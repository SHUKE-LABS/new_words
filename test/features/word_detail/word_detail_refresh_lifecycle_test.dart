import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:new_words/apis/stories_api_v2.dart';
import 'package:new_words/apis/vocabulary_api_v2.dart';
import 'package:new_words/entities/explanations_response.dart';
import 'package:new_words/entities/word_explanation.dart';
import 'package:new_words/features/word_detail/presentation/word_detail_screen.dart';
import 'package:new_words/generated/app_localizations.dart';
import 'package:new_words/providers/stories_provider.dart';
import 'package:new_words/providers/vocabulary_provider.dart';
import 'package:new_words/services/stories_service_v2.dart';
import 'package:new_words/services/tts_service.dart';
import 'package:new_words/services/vocabulary_service_v2.dart';
import 'package:provider/provider.dart';

import '../../mocks/mock_app_logger.dart';

/// A vocabulary service that answers a refresh straight away, then holds the
/// explanation reload open, so the screen can be disposed inside the second
/// async gap of `_refreshExplanation`.
class _GatedVocabularyService extends VocabularyServiceV2 {
  _GatedVocabularyService() : super(VocabularyApiV2(Dio()));

  /// Installed before the reload that the test wants to hold open; the
  /// initial load on `initState` runs ungated.
  Completer<void>? holdReload;

  @override
  Future<RefreshExplanationResult> refreshExplanation(
    WordExplanation explanation,
  ) async => RefreshExplanationResult.updated(_explanation);

  @override
  Future<ExplanationsResponse> getExplanationsForWord(
    int wordCollectionId,
    String learningLanguage,
    String explanationLanguage,
  ) async {
    final gate = holdReload;
    if (gate != null) await gate.future;
    return ExplanationsResponse(
      explanations: [_explanation],
      userDefaultExplanationId: _explanation.id,
    );
  }
}

/// The screen resolves the shared TTS singleton; nothing here plays.
class _FakeTtsService extends TtsService {
  @override
  bool get isSupported => false;

  @override
  Future<void> init({String? language}) async {}

  @override
  Future<List<String>> getLanguages() async => const [];

  @override
  Future<void> stop() async {}
}

// wordCollectionId must be positive, or the screen skips the background load
// this test is about.
final _explanation = WordExplanation(
  id: 1,
  wordCollectionId: 7,
  wordText: 'calm',
  learningLanguage: 'en',
  explanationLanguage: 'zh',
  markdownExplanation: 'calm — 平静的',
  createdAt: 1700000000,
  updatedAt: 1700000000,
);

void main() {
  setUpAll(() {
    // AppConfig.pageSize and AppConfig.isProduction both read dotenv.
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://test.example.com\n');
  });

  late _GatedVocabularyService service;

  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerSingleton<TtsService>(_FakeTtsService());
    service = _GatedVocabularyService();
  });

  tearDown(() async => GetIt.I.reset());

  Widget wrap(Widget child) => MultiProvider(
    providers: [
      ChangeNotifierProvider<VocabularyProvider>(
        create: (_) => VocabularyProvider(service),
      ),
      ChangeNotifierProvider<StoriesProvider>(
        create:
            (_) => StoriesProvider(
              StoriesServiceV2(
                storiesApi: StoriesApiV2(Dio()),
                logger: MockAppLogger(),
              ),
            ),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );

  testWidgets('refresh does not touch a disposed state when the explanation '
      'reload completes after the screen is gone', (tester) async {
    await tester.pumpWidget(
      wrap(WordDetailScreen(wordExplanation: _explanation)),
    );
    await tester.pumpAndSettle();

    // Hold only the reload that the refresh triggers.
    final gate = Completer<void>();
    service.holdReload = gate;

    await tester.tap(find.byIcon(Icons.shuffle));
    await tester.pump();

    // The screen's State is disposed while the reload is still in flight.
    await tester.pumpWidget(wrap(const SizedBox.shrink()));

    gate.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
