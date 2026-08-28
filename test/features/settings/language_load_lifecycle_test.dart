import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:new_words/apis/account_api_v2.dart';
import 'package:new_words/apis/settings_api_v2.dart';
import 'package:new_words/apis/user_settings_api_v2.dart';
import 'package:new_words/entities/language.dart';
import 'package:new_words/features/settings/presentation/language_selection_dialog.dart';
import 'package:new_words/features/settings/presentation/settings_screen.dart';
import 'package:new_words/generated/app_localizations.dart';
import 'package:new_words/providers/auth_provider.dart';
import 'package:new_words/providers/locale_provider.dart';
import 'package:new_words/services/account_service_v2.dart';
import 'package:new_words/services/settings_service_v2.dart';
import 'package:new_words/services/user_settings_service_v2.dart';
import 'package:new_words/utils/token_utils.dart';
import 'package:new_words/utils/app_logger_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks/mock_app_logger.dart';

/// A settings service whose language lookup stays open until the test
/// releases it, so the widget can be disposed inside the async gap.
class _GatedSettingsService extends SettingsServiceV2 {
  _GatedSettingsService()
    : super(settingsApi: SettingsApiV2(Dio()), logger: MockAppLogger());

  final Completer<void> gate = Completer<void>();

  /// What the lookup answers with once released. An empty list drives the
  /// fallback path; a throw drives the `catch` path, which reaches
  /// `_useFallbackLanguages` without passing the post-await guard.
  List<Language> result = const [];
  Object? failure;

  @override
  Future<List<Language>> getSupportedLanguages() async {
    await gate.future;
    final failure = this.failure;
    if (failure != null) throw failure;
    return result;
  }
}

void main() {
  setUpAll(() {
    // AppConfig.version reads dotenv.
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://test.example.com\n');
  });

  late _GatedSettingsService service;

  setUp(() async {
    await GetIt.I.reset();
    GetIt.I.registerLazySingleton<AppLoggerInterface>(() => MockAppLogger());
    service = _GatedSettingsService();
    GetIt.I.registerSingleton<SettingsServiceV2>(service);

    // AuthProvider resolves the account service in its constructor; nothing
    // in these tests calls it.
    GetIt.I.registerSingleton<AccountServiceV2>(
      AccountServiceV2(
        accountApi: AccountApiV2(Dio()),
        userSettingsService: UserSettingsServiceV2(
          userSettingsApi: UserSettingsApiV2(Dio()),
        ),
        tokenUtils: TokenUtils(),
        logger: MockAppLogger(),
      ),
    );
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async => GetIt.I.reset());

  const languages = [
    Language(code: 'en', name: 'English'),
    Language(code: 'zh', name: 'Chinese'),
  ];

  Widget wrap(Widget child) => MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
      ChangeNotifierProvider<LocaleProvider>(create: (_) => LocaleProvider()),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );

  /// Pumps [child], replaces it mid-load so its state is disposed, then
  /// releases the language lookup and lets the continuation run.
  Future<void> disposeDuringLoad(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(wrap(child));
    await tester.pump();

    // Replace the tree: the screen's State is disposed while the lookup
    // is still in flight.
    await tester.pumpWidget(wrap(const SizedBox.shrink()));

    service.gate.complete();
    await tester.pumpAndSettle();
  }

  group('SettingsScreen language load survives disposal mid-flight', () {
    testWidgets('success path does not setState after dispose', (tester) async {
      service.result = languages;

      await disposeDuringLoad(tester, const SettingsScreen());

      expect(tester.takeException(), isNull);
    });

    testWidgets('empty result takes the fallback path without setState after '
        'dispose', (tester) async {
      service.result = const [];

      await disposeDuringLoad(tester, const SettingsScreen());

      expect(tester.takeException(), isNull);
    });

    testWidgets('a thrown lookup reaches the fallback without setState after '
        'dispose', (tester) async {
      service.failure = Exception('offline');

      await disposeDuringLoad(tester, const SettingsScreen());

      expect(tester.takeException(), isNull);
    });
  });

  group(
    'LanguageSelectionDialog language load survives disposal mid-flight',
    () {
      Widget dialog() => LanguageSelectionDialog(
        currentNativeLanguage: 'en',
        currentLearningLanguage: 'zh',
        onLanguagesSelected: (_, __) {},
      );

      testWidgets('success path does not setState after dispose', (
        tester,
      ) async {
        service.result = languages;

        await disposeDuringLoad(tester, dialog());

        expect(tester.takeException(), isNull);
      });

      testWidgets('empty result takes the fallback path without setState or a '
          'messenger call after dispose', (tester) async {
        service.result = const [];

        await disposeDuringLoad(tester, dialog());

        expect(tester.takeException(), isNull);
      });

      testWidgets('a thrown lookup reaches the fallback without setState or a '
          'messenger call after dispose', (tester) async {
        service.failure = Exception('offline');

        await disposeDuringLoad(tester, dialog());

        expect(tester.takeException(), isNull);
      });
    },
  );
}
