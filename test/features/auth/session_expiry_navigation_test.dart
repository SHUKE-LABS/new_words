import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:new_words/common/constants/constants.dart';
import 'package:new_words/common/navigation/app_navigator.dart';
import 'package:new_words/features/auth/presentation/login_screen.dart';
import 'package:new_words/generated/app_localizations.dart';
import 'package:new_words/main.dart';
import 'package:new_words/providers/auth_provider.dart';
import 'package:new_words/providers/locale_provider.dart';
import 'package:new_words/services/account_service_v2.dart';
import 'package:new_words/services/session_expiry_notifier.dart';
import 'package:new_words/user_session.dart';
import 'package:new_words/utils/app_logger_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../mocks/mock_app_logger.dart';

@GenerateMocks([AccountServiceV2])
import 'session_expiry_navigation_test.mocks.dart';

/// Stands in for `MainMenuScreen` so this test exercises the real
/// [AuthWrapper] branching, [AppNavigator] key, and route stack without
/// standing up the whole main-menu provider tree.
class _AuthenticatedShell extends StatelessWidget {
  const _AuthenticatedShell();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('authenticated-shell')));
  }
}

void main() {
  group('session expiry navigation', () {
    late MockAccountServiceV2 mockAccountService;
    late SessionExpiryNotifier notifier;

    setUp(() {
      SharedPreferences.setMockInitialValues({
        StorageKeys.accessToken: 'stored-token',
      });

      mockAccountService = MockAccountServiceV2();
      when(mockAccountService.isValidToken()).thenAnswer((_) async => true);
      when(
        mockAccountService.setUserSession(
          tokenFromInit: anyNamed('tokenFromInit'),
        ),
      ).thenAnswer((_) async {});
      when(mockAccountService.logout()).thenAnswer((_) async {});

      final locator = GetIt.I;
      locator.reset();
      locator.registerLazySingleton<AppLoggerInterface>(() => MockAppLogger());
      locator.registerSingleton<AccountServiceV2>(mockAccountService);
      notifier = SessionExpiryNotifier(logger: MockAppLogger());
      locator.registerSingleton<SessionExpiryNotifier>(notifier);
    });

    tearDown(() {
      GetIt.I.reset();
      UserSession().token = null;
    });

    Future<AuthProvider> pumpApp(WidgetTester tester) async {
      final authProvider = AuthProvider();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LocaleProvider>(
              create: (_) => LocaleProvider(),
            ),
            ChangeNotifierProvider<AuthProvider>.value(value: authProvider),
          ],
          child: MaterialApp(
            navigatorKey: AppNavigator.key,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: LocaleProvider.supportedLocales,
            home: const AuthWrapper(authenticatedBuilder: _buildShell),
          ),
        ),
      );
      await tester.pumpAndSettle();

      return authProvider;
    }

    testWidgets(
      'expiry logs out, unwinds pushed routes, and lands on LoginScreen',
      (tester) async {
        final authProvider = await pumpApp(tester);

        expect(authProvider.isAuthenticated, isTrue);
        expect(find.text('authenticated-shell'), findsOneWidget);

        // Push a screen on top, the way word detail or settings would.
        AppNavigator.key.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Center(child: Text('pushed'))),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('pushed'), findsOneWidget);
        expect(AppNavigator.key.currentState!.canPop(), isTrue);

        // A 401 arrives while that route is on top.
        await notifier.notifySessionExpired();
        await tester.pumpAndSettle();

        expect(authProvider.isAuthenticated, isFalse);
        verify(mockAccountService.logout()).called(1);
        expect(find.text('pushed'), findsNothing);
        expect(find.text('authenticated-shell'), findsNothing);
        expect(find.byType(LoginScreen), findsOneWidget);
        expect(
          AppNavigator.key.currentState!.canPop(),
          isFalse,
          reason: 'the login screen must be the only route left',
        );
      },
    );

    testWidgets("the app's own MaterialApp is wired to AppNavigator.key", (
      tester,
    ) async {
      // The tests above build their own MaterialApp, so they would still pass
      // if `navigatorKey:` were dropped from main.dart. This one pumps the
      // real MyApp — unauthenticated, so AuthWrapper renders LoginScreen
      // instead of the full main-menu tree — and proves the key is attached.
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<LocaleProvider>(
              create: (_) => LocaleProvider(),
            ),
            ChangeNotifierProvider<AuthProvider>(create: (_) => AuthProvider()),
          ],
          child: const MyApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LoginScreen), findsOneWidget);
      expect(
        AppNavigator.key.currentState,
        isNotNull,
        reason: 'MaterialApp must expose its navigator via AppNavigator.key',
      );
    });

    testWidgets('a second expiry after logout is a no-op', (tester) async {
      final authProvider = await pumpApp(tester);

      await notifier.notifySessionExpired();
      await tester.pumpAndSettle();
      expect(authProvider.isAuthenticated, isFalse);

      // Stale in-flight requests can still return 401 after logout.
      await notifier.notifySessionExpired();
      await tester.pumpAndSettle();

      verify(mockAccountService.logout()).called(1);
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });
}

Widget _buildShell(BuildContext context) => const _AuthenticatedShell();
