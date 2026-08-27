import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:new_words/apis/stories_api_v2.dart';
import 'package:new_words/entities/story.dart';
import 'package:new_words/features/practice/presentation/listening_screen.dart';
import 'package:new_words/features/practice/presentation/speaking_screen.dart';
import 'package:new_words/features/stories/presentation/story_detail_screen.dart';
import 'package:new_words/generated/app_localizations.dart';
import 'package:new_words/providers/stories_provider.dart';
import 'package:new_words/services/mic_permission_service.dart';
import 'package:new_words/services/stories_service_v2.dart';
import 'package:new_words/services/stt_service.dart';
import 'package:new_words/services/tts_service.dart';
import 'package:new_words/utils/platform_info.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../mocks/mock_app_logger.dart';

/// A TTS service that never touches a platform channel, so the screen's wiring
/// can be driven off-device: what it was asked to speak, and in what order, is
/// what the assertions read.
class _FakeTtsService extends TtsService {
  _FakeTtsService({this.supported = true, this.availableLanguages = const ['en-US']});

  final bool supported;
  final List<String> availableLanguages;

  final List<String> spoken = [];
  int stopCount = 0;
  int pauseCount = 0;
  final List<double> rates = [];

  /// Set to hold the current utterance open, so a test can observe the
  /// highlight while a sentence is "playing".
  bool hold = false;
  final List<Completer<TtsSpeakOutcome>> pending = [];

  @override
  bool get isSupported => supported;

  @override
  Future<void> init({String? language}) async {}

  @override
  Future<List<String>> getLanguages() async => availableLanguages;

  @override
  Future<bool> isLanguageAvailable(String languageCode) async =>
      availableLanguages.isNotEmpty;

  @override
  Future<void> setSpeechRateMultiplier(double multiplier) async {
    rates.add(multiplier);
  }

  @override
  Future<TtsSpeakOutcome> speakAndWait(String text, {String? language}) async {
    spoken.add(text);
    if (!hold) return TtsSpeakOutcome.completed;
    final completer = Completer<TtsSpeakOutcome>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<bool> pause() async {
    pauseCount++;
    return true;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }
}

/// Counts every microphone-facing call, so the read and listen paths can be
/// proven never to make one. Both are pinned to an unsupported platform: these
/// tests are about the story screen's wiring, not about recognition.
class _SpySttService extends SttService {
  _SpySttService({required super.logger})
      : super(speech: SpeechToText.withMethodChannel(), platform: PlatformInfo.linux);

  int initializeCount = 0;

  @override
  Future<SttInitResult> initialize() async {
    initializeCount++;
    return SttInitResult.unsupported;
  }
}

class _SpyPermissionService extends MicPermissionService {
  _SpyPermissionService({required super.sttService, required super.logger})
      : super(platform: PlatformInfo.linux);

  int statusCount = 0;
  int requestCount = 0;

  @override
  Future<MicPermission> status() async {
    statusCount++;
    return MicPermission.unsupported;
  }

  @override
  Future<MicRequestOutcome> request() async {
    requestCount++;
    return MicRequestOutcome.unsupported;
  }
}

void main() {
  setUpAll(() {
    // AppConfig.isProduction reads dotenv, and the screen's app bar consults it.
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://test.example.com\n');
  });

  late _FakeTtsService tts;
  late _SpySttService stt;
  late _SpyPermissionService permissions;
  late StoriesProvider provider;

  Story storyWith(String content) => Story(
        id: 1,
        userId: 1,
        content: content,
        storyWords: 'calm',
        learningLanguage: 'en',
        // Already read, so the screen's post-frame callback does not call the
        // API to mark it read.
        firstReadAt: 1700000000,
        favoriteCount: 0,
        createdAt: 1700000000,
      );

  void register<T extends Object>(T service) {
    if (GetIt.I.isRegistered<T>()) {
      GetIt.I.unregister<T>();
    }
    GetIt.I.registerSingleton<T>(service);
  }

  setUp(() {
    tts = _FakeTtsService();
    register<TtsService>(tts);
    stt = _SpySttService(logger: MockAppLogger());
    permissions = _SpyPermissionService(sttService: stt, logger: MockAppLogger());
    register<SttService>(stt);
    register<MicPermissionService>(permissions);
    provider = StoriesProvider(
      StoriesServiceV2(storiesApi: StoriesApiV2(Dio()), logger: MockAppLogger()),
    );
  });

  tearDown(() {
    GetIt.I.unregister<TtsService>();
    GetIt.I.unregister<SttService>();
    GetIt.I.unregister<MicPermissionService>();
  });

  Future<void> pumpScreen(WidgetTester tester, Story story) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<StoriesProvider>.value(
        value: provider,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: StoryDetailScreen(story: story),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Every distinct tap recognizer in the rendered story content, in the order
  /// the spans appear — one per sentence.
  List<TapGestureRecognizer> recognizersInOrder(WidgetTester tester) {
    final text = tester.widget<Text>(
      find.descendant(of: find.byType(SelectionArea), matching: find.byType(Text)).first,
    );
    final found = <TapGestureRecognizer>[];
    void visit(InlineSpan span) {
      if (span is TextSpan) {
        final recognizer = span.recognizer;
        if (recognizer is TapGestureRecognizer && !found.contains(recognizer)) {
          found.add(recognizer);
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child);
        }
      }
    }
    visit(text.textSpan!);
    return found;
  }

  group('StoryDetailScreen read-aloud', () {
    testWidgets('renders the player bar with play, stop and rate controls',
        (tester) async {
      await pumpScreen(tester, storyWith('She waited. Then it rained.'));

      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.byIcon(Icons.stop), findsOneWidget);
      expect(find.byIcon(Icons.speed), findsOneWidget);
      expect(find.text('1.0x'), findsOneWidget);
    });

    testWidgets('play speaks every sentence in order', (tester) async {
      await pumpScreen(tester, storyWith('She waited. Then it rained.'));

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();

      expect(tts.spoken, ['She waited.', 'Then it rained.']);
    });

    testWidgets('tapping a sentence plays that sentence, by index',
        (tester) async {
      await pumpScreen(
        tester,
        storyWith('First one. Second **two**. Third three.'),
      );

      final recognizers = recognizersInOrder(tester);
      expect(recognizers.length, 3,
          reason: 'one recognizer per sentence, shared by its spans');

      // The middle sentence spans three TextSpans (plain, bold, plain); its
      // recognizer must still play sentence 1, not the span's ordinal.
      recognizers[1].onTap!();
      await tester.pumpAndSettle();

      expect(tts.spoken, ['Second two.']);
    });

    testWidgets('the playing sentence is highlighted and cleared when it ends',
        (tester) async {
      tts.hold = true;
      await pumpScreen(tester, storyWith('She waited. Then it rained.'));

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      Color? backgroundOf(int spanIndex) {
        final text = tester.widget<Text>(
          find.descendant(of: find.byType(SelectionArea), matching: find.byType(Text)).first,
        );
        final children = (text.textSpan! as TextSpan).children!;
        return (children[spanIndex] as TextSpan).style?.backgroundColor;
      }

      expect(backgroundOf(0), isNotNull, reason: 'sentence 0 is playing');
      expect(backgroundOf(1), isNull);

      // Finish sentence 0; the highlight moves on, then clears at the end.
      tts.pending.removeAt(0).complete(TtsSpeakOutcome.completed);
      await tester.pump();
      expect(backgroundOf(0), isNull);
      expect(backgroundOf(1), isNotNull);

      tts.pending.removeAt(0).complete(TtsSpeakOutcome.completed);
      await tester.pump();
      expect(backgroundOf(0), isNull);
      expect(backgroundOf(1), isNull, reason: 'the highlight clears at the end');
    });

    testWidgets('pause and stop drive the service and the button icon',
        (tester) async {
      tts.hold = true;
      await pumpScreen(tester, storyWith('She waited. Then it rained.'));

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      expect(find.byIcon(Icons.pause), findsOneWidget);

      await tester.tap(find.byIcon(Icons.pause));
      await tester.pump();
      expect(tts.pauseCount, 1);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);

      await tester.tap(find.byIcon(Icons.stop));
      await tester.pump();
      expect(tts.stopCount, greaterThan(0));
    });

    testWidgets('stop is disabled while idle', (tester) async {
      await pumpScreen(tester, storyWith('She waited.'));

      final stop = tester.widget<IconButton>(
        find.ancestor(of: find.byIcon(Icons.stop), matching: find.byType(IconButton)),
      );
      expect(stop.onPressed, isNull);
    });

    testWidgets('an unsupported platform disables the controls and explains why',
        (tester) async {
      final unsupported = _FakeTtsService(supported: false);
      register<TtsService>(unsupported);
      await pumpScreen(tester, storyWith('She waited.'));

      final rate = tester.widget<PopupMenuButton<double>>(
        find.byType(PopupMenuButton<double>),
      );
      expect(rate.enabled, isFalse);

      // Play stays tappable so it can explain itself instead of doing nothing.
      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      expect(unsupported.spoken, isEmpty);
      expect(
        find.text('Read aloud is not available on this device'),
        findsOneWidget,
      );
    });

    testWidgets('a device with no voices reports that, not unsupported',
        (tester) async {
      final noVoices = _FakeTtsService(availableLanguages: const []);
      register<TtsService>(noVoices);
      await pumpScreen(tester, storyWith('She waited.'));

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      expect(noVoices.spoken, isEmpty);
      expect(
        find.text('No text-to-speech voice is installed on this device'),
        findsOneWidget,
      );
    });

    testWidgets('leaving the screen stops playback without disposing the '
        'shared service', (tester) async {
      tts.hold = true;
      await pumpScreen(tester, storyWith('She waited. Then it rained.'));

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      final stopsBefore = tts.stopCount;

      // Replace the screen: State.dispose runs.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pumpAndSettle();

      expect(tts.stopCount, greaterThan(stopsBefore));
      expect(GetIt.I.isRegistered<TtsService>(), isTrue,
          reason: 'the singleton is shared with word detail and must survive');
    });
  });

  group('StoryDetailScreen listening entry', () {
    testWidgets('the headphones action pushes listening practice and plays '
        'its first item', (tester) async {
      await pumpScreen(
        tester,
        storyWith('She waited for a long time. Then it rained on the roof.'),
      );

      await tester.tap(find.byIcon(Icons.headphones));
      await tester.pumpAndSettle();

      expect(find.byType(ListeningScreen), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
      // The first item is spoken, and read-aloud's own stop finished before it
      // started, so nothing cancels it.
      expect(tts.spoken, ['She waited for a long time.']);
    });

    testWidgets('read-aloud is stopped before listening starts',
        (tester) async {
      tts.hold = true;
      await pumpScreen(
        tester,
        storyWith('She waited for a long time. Then it rained on the roof.'),
      );

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      expect(tts.spoken, ['She waited for a long time.']);
      final stopsBefore = tts.stopCount;

      // Release read-aloud's utterance so the awaited stop can settle.
      tts.hold = false;
      await tester.tap(find.byIcon(Icons.headphones));
      await tester.pumpAndSettle();

      expect(tts.stopCount, greaterThan(stopsBefore));
      expect(find.byType(ListeningScreen), findsOneWidget);
    });
  });

  group('StoryDetailScreen speaking entry', () {
    testWidgets('the mic action pushes speaking practice', (tester) async {
      await pumpScreen(
        tester,
        storyWith('She waited for a long time. Then it rained on the roof.'),
      );

      await tester.tap(find.byIcon(Icons.mic));
      await tester.pumpAndSettle();

      expect(find.byType(SpeakingScreen), findsOneWidget);
    });

    testWidgets('read-aloud is stopped before speaking starts', (tester) async {
      tts.hold = true;
      await pumpScreen(
        tester,
        storyWith('She waited for a long time. Then it rained on the roof.'),
      );

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();
      expect(tts.spoken, ['She waited for a long time.']);
      final stopsBefore = tts.stopCount;

      // Release read-aloud's utterance so the awaited stop can settle.
      tts.hold = false;
      await tester.tap(find.byIcon(Icons.mic));
      await tester.pumpAndSettle();

      expect(tts.stopCount, greaterThan(stopsBefore));
      expect(find.byType(SpeakingScreen), findsOneWidget);
    });

    testWidgets('read and listen never touch the microphone', (tester) async {
      await pumpScreen(
        tester,
        storyWith('She waited for a long time. Then it rained on the roof.'),
      );

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.headphones));
      await tester.pumpAndSettle();

      expect(find.byType(ListeningScreen), findsOneWidget);
      expect(stt.initializeCount, 0);
      expect(permissions.statusCount, 0);
      expect(permissions.requestCount, 0);
    });
  });
}
