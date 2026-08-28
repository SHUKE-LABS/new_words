import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:new_words/apis/account_api_v2.dart';
import 'package:new_words/apis/settings_api_v2.dart';
import 'package:new_words/apis/user_settings_api_v2.dart';
import 'package:new_words/entities/language.dart';
import 'package:new_words/features/settings/presentation/settings_screen.dart';
import 'package:new_words/generated/app_localizations.dart';
import 'package:new_words/providers/auth_provider.dart';
import 'package:new_words/providers/locale_provider.dart';
import 'package:new_words/services/account_service_v2.dart';
import 'package:new_words/services/settings_service_v2.dart';
import 'package:new_words/services/tts_service.dart';
import 'package:new_words/services/user_settings_service_v2.dart';
import 'package:new_words/user_session.dart';
import 'package:new_words/utils/app_logger_interface.dart';
import 'package:new_words/utils/token_utils.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks/mock_app_logger.dart';

/// A settings service that answers the language list immediately, so these
/// tests are about the voice row rather than the language load.
class _ImmediateSettingsService extends SettingsServiceV2 {
  _ImmediateSettingsService()
    : super(settingsApi: SettingsApiV2(Dio()), logger: MockAppLogger());

  @override
  Future<List<Language>> getSupportedLanguages() async => const [
    Language(code: 'en', name: 'English'),
    Language(code: 'zh', name: 'Chinese'),
    Language(code: 'fr', name: 'French'),
  ];
}

/// A TTS service with a scripted inventory, recording what the screen selects.
///
/// Selection is stored in-memory the way the real service stores it in
/// preferences, so "the row shows what was chosen" is asserted against the
/// service's own answer rather than against the widget's local state.
class _FakeTtsService extends TtsService {
  _FakeTtsService({
    this.supported = true,
    Map<String, List<TtsVoice>>? inventory,
  }) : _inventory = inventory ?? const {};

  final bool supported;
  final Map<String, List<TtsVoice>> _inventory;

  TtsVoice? stored;

  /// Every `selectVoice` call, so an immediate application can be asserted.
  final List<TtsVoice?> selections = [];

  @override
  bool get isSupported => supported;

  @override
  Future<List<TtsVoice>> voicesForLanguage(String languageCode) async =>
      _inventory[languageCode] ?? const [];

  @override
  Future<TtsVoice?> selectedVoiceFor(String languageCode) async {
    final voice = stored;
    if (voice == null) return null;
    final available = _inventory[languageCode] ?? const <TtsVoice>[];
    return available.contains(voice) ? voice : null;
  }

  @override
  Future<void> selectVoice(
    TtsVoice? voice, {
    required String languageCode,
  }) async {
    selections.add(voice);
    stored = voice;
  }
}

/// An account service whose language update is local, so the language-change
/// path can be driven end to end without a network call.
class _FakeAccountService extends AccountServiceV2 {
  _FakeAccountService()
    : super(
        accountApi: AccountApiV2(Dio()),
        userSettingsService: UserSettingsServiceV2(
          userSettingsApi: UserSettingsApiV2(Dio()),
        ),
        tokenUtils: TokenUtils(),
        logger: MockAppLogger(),
      );

  @override
  Future<void> updateUserLanguages(
    String nativeLanguage,
    String learningLanguage,
  ) async {
    UserSession().nativeLanguage = nativeLanguage;
    UserSession().currentLearningLanguage = learningLanguage;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://test.example.com\n');
  });

  const enhanced = TtsVoice(
    name: 'en-us-enhanced',
    locale: 'en-US',
    quality: TtsVoiceQuality.veryHigh,
  );
  const basic = TtsVoice(
    name: 'en-us-basic',
    locale: 'en-US',
    quality: TtsVoiceQuality.low,
  );
  const networked = TtsVoice(
    name: 'en-us-network',
    locale: 'en-US',
    quality: TtsVoiceQuality.veryHigh,
    networkRequired: true,
  );
  const chinese = TtsVoice(
    name: 'zh-cn-basic',
    locale: 'zh-CN',
    quality: TtsVoiceQuality.normal,
  );

  Future<void> registerServices(_FakeTtsService tts) async {
    await GetIt.I.reset();
    GetIt.I.registerLazySingleton<AppLoggerInterface>(() => MockAppLogger());
    GetIt.I.registerSingleton<SettingsServiceV2>(_ImmediateSettingsService());
    GetIt.I.registerSingleton<AccountServiceV2>(_FakeAccountService());
    GetIt.I.registerSingleton<TtsService>(tts);
    SharedPreferences.setMockInitialValues({});
    UserSession().currentLearningLanguage = 'en';
    UserSession().nativeLanguage = 'fr';
  }

  tearDown(() async => GetIt.I.reset());

  Widget wrap(Widget child) => MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
      ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
    ],
    child: MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );

  /// The voice row: the tile whose title is the read-aloud voice label.
  Finder voiceRow() => find.ancestor(
    of: find.text('Read-aloud Voice').first,
    matching: find.byType(ListTile),
  );

  String voiceSubtitle(WidgetTester tester) {
    final tile = tester.widget<ListTile>(voiceRow().first);
    return ((tile.subtitle as Text).data)!;
  }

  testWidgets('with no choice stored, the row reads Automatic', (tester) async {
    await registerServices(
      _FakeTtsService(
        inventory: {
          'en': const [basic, enhanced],
        },
      ),
    );

    await tester.pumpWidget(wrap(const SettingsScreen()));
    await tester.pumpAndSettle();

    expect(voiceSubtitle(tester), 'Automatic (best available)');
  });

  testWidgets('a remembered voice is shown by name', (tester) async {
    final tts = _FakeTtsService(
      inventory: {
        'en': const [basic, enhanced],
      },
    )..stored = basic;
    await registerServices(tts);

    await tester.pumpWidget(wrap(const SettingsScreen()));
    await tester.pumpAndSettle();

    expect(voiceSubtitle(tester), basic.name);
  });

  testWidgets('a device with no voices explains itself and cannot be tapped', (
    tester,
  ) async {
    await registerServices(_FakeTtsService(inventory: const {}));

    await tester.pumpWidget(wrap(const SettingsScreen()));
    await tester.pumpAndSettle();

    expect(voiceSubtitle(tester), 'No voices available on this device');
    expect(
      tester.widget<ListTile>(voiceRow().first).onTap,
      isNull,
      reason: 'an empty picker must not be reachable',
    );
  });

  testWidgets('an unsupported platform explains itself too', (tester) async {
    await registerServices(
      _FakeTtsService(
        supported: false,
        inventory: {
          'en': const [enhanced],
        },
      ),
    );

    await tester.pumpWidget(wrap(const SettingsScreen()));
    await tester.pumpAndSettle();

    expect(voiceSubtitle(tester), 'No voices available on this device');
    expect(tester.widget<ListTile>(voiceRow().first).onTap, isNull);
  });

  testWidgets('the picker lists Automatic first and marks network voices', (
    tester,
  ) async {
    await registerServices(
      _FakeTtsService(
        inventory: {
          'en': const [basic, enhanced, networked],
        },
      ),
    );

    await tester.pumpWidget(wrap(const SettingsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(voiceRow().first);
    await tester.pumpAndSettle();

    final dialogTiles = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(ListTile),
    );
    final titles =
        tester
            .widgetList<ListTile>(dialogTiles)
            .map((t) => (t.title as Text).data)
            .toList();
    expect(titles, [
      'Automatic (best available)',
      basic.name,
      enhanced.name,
      networked.name,
    ]);

    final networkTile = tester.widget<ListTile>(
      find
          .ancestor(
            of: find.text(networked.name),
            matching: find.byType(ListTile),
          )
          .first,
    );
    expect((networkTile.subtitle as Text).data, 'Needs internet');
    expect(
      tester
          .widget<ListTile>(
            find
                .ancestor(
                  of: find.text(enhanced.name),
                  matching: find.byType(ListTile),
                )
                .first,
          )
          .subtitle,
      isNull,
      reason: 'only network voices carry the connectivity warning',
    );
  });

  testWidgets('picking a voice applies it immediately and updates the row', (
    tester,
  ) async {
    final tts = _FakeTtsService(
      inventory: {
        'en': const [basic, enhanced],
      },
    );
    await registerServices(tts);

    await tester.pumpWidget(wrap(const SettingsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(voiceRow().first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(enhanced.name));
    await tester.pumpAndSettle();

    expect(tts.selections, [enhanced]);
    expect(voiceSubtitle(tester), enhanced.name);
  });

  testWidgets('picking Automatic clears the choice and restores the subtitle', (
    tester,
  ) async {
    final tts = _FakeTtsService(
      inventory: {
        'en': const [basic, enhanced],
      },
    )..stored = basic;
    await registerServices(tts);

    await tester.pumpWidget(wrap(const SettingsScreen()));
    await tester.pumpAndSettle();
    expect(voiceSubtitle(tester), basic.name);

    await tester.tap(voiceRow().first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Automatic (best available)'));
    await tester.pumpAndSettle();

    expect(tts.selections, [null]);
    expect(voiceSubtitle(tester), 'Automatic (best available)');
  });

  testWidgets('dismissing the picker leaves the current choice alone', (
    tester,
  ) async {
    final tts = _FakeTtsService(
      inventory: {
        'en': const [basic, enhanced],
      },
    )..stored = basic;
    await registerServices(tts);

    await tester.pumpWidget(wrap(const SettingsScreen()));
    await tester.pumpAndSettle();

    await tester.tap(voiceRow().first);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(AlertDialog))).pop();
    await tester.pumpAndSettle();

    expect(tts.selections, isEmpty);
    expect(voiceSubtitle(tester), basic.name);
  });

  testWidgets('changing the learning language reloads the voice inventory', (
    tester,
  ) async {
    final tts = _FakeTtsService(
      inventory: {
        'en': const [basic, enhanced],
        'zh': const [chinese],
      },
    )..stored = basic;
    await registerServices(tts);

    await tester.pumpWidget(wrap(const SettingsScreen()));
    await tester.pumpAndSettle();
    expect(voiceSubtitle(tester), basic.name);

    // Drive the real path: the learning-language dialog, whose completion is
    // what re-reads the inventory.
    await tester.tap(find.text('Learning Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chinese').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(UserSession().currentLearningLanguage, 'zh');
    expect(
      voiceSubtitle(tester),
      'Automatic (best available)',
      reason: 'an English voice must not be shown as the Chinese selection',
    );

    await tester.tap(voiceRow().first);
    await tester.pumpAndSettle();
    expect(
      find.text(chinese.name),
      findsOneWidget,
      reason: 'the picker offers the new language\'s voices',
    );
    expect(find.text(enhanced.name), findsNothing);
  });
}
