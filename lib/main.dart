import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:new_words/providers/auth_provider.dart';
import 'package:new_words/providers/locale_provider.dart';
import 'package:new_words/services/vocabulary_service_v2.dart'; // Import VocabularyServiceV2
import 'package:new_words/providers/vocabulary_provider.dart'; // Import VocabularyProvider
import 'package:new_words/services/stories_service_v2.dart'; // Import StoriesServiceV2
import 'package:new_words/providers/stories_provider.dart'; // Import StoriesProvider
import 'package:new_words/services/memories_service_v2.dart'; // Import MemoriesServiceV2
import 'package:new_words/providers/memories_provider.dart'; // Import MemoriesProvider
import 'package:new_words/providers/subscription_provider.dart'; // Import SubscriptionProvider
import 'package:new_words/providers/update_provider.dart'; // Import UpdateProvider
import 'package:new_words/services/update_service.dart'; // Import UpdateService
import 'package:new_words/providers/app_state_provider.dart'; // Import AppStateProvider
import 'package:new_words/features/auth/presentation/login_screen.dart';
import 'package:new_words/features/auth/presentation/register_page.dart';
import 'package:new_words/features/home/presentation/home_screen.dart';
import 'package:new_words/features/main_menu/presentation/main_menu_screen.dart';
import 'package:new_words/features/new_words_list/presentation/new_words_list_screen.dart';
import 'package:new_words/features/settings/presentation/delete_account_screen.dart';
import 'package:new_words/features/legal/presentation/privacy_policy_screen.dart';
import 'package:new_words/common/constants/routes.dart'; // Updated import
import 'package:new_words/common/navigation/app_navigator.dart';
import 'package:new_words/generated/app_localizations.dart';
import 'package:new_words/dependency_injection.dart' as di;
import 'package:flutter_dotenv/flutter_dotenv.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Configure URL strategy for web
  if (kIsWeb) {
    usePathUrlStrategy();
  }
  
  await dotenv.load(fileName: ".env");
  di.init();

  runApp(
    MultiProvider(
      providers: [
        // Create individual providers first
        ChangeNotifierProvider(create: (_) => LocaleProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(
          create: (_) => VocabularyProvider(di.locator<VocabularyServiceV2>()),
        ),
        ChangeNotifierProvider(
          create: (_) => StoriesProvider(di.locator<StoriesServiceV2>()),
        ),
        ChangeNotifierProvider(
          create: (_) => MemoriesProvider(di.locator<MemoriesServiceV2>()),
        ),
        ChangeNotifierProvider(
          create: (_) => SubscriptionProvider(),
        ),
        ChangeNotifierProvider(
          create: (_) => UpdateProvider(di.locator<UpdateService>()),
        ),

        // Create AppStateProvider that manages all other providers
        // Use ChangeNotifierProvider with lazy: false to ensure immediate creation
        ChangeNotifierProvider<AppStateProvider>(
          lazy: false, // Force immediate creation
          create: (context) {
            return AppStateProvider(
              authProvider: Provider.of<AuthProvider>(context, listen: false),
              vocabularyProvider: Provider.of<VocabularyProvider>(
                context,
                listen: false,
              ),
              storiesProvider: Provider.of<StoriesProvider>(
                context,
                listen: false,
              ),
              memoriesProvider: Provider.of<MemoriesProvider>(
                context,
                listen: false,
              ),
              subscriptionProvider: Provider.of<SubscriptionProvider>(
                context,
                listen: false,
              ),
              localeProvider: Provider.of<LocaleProvider>(
                context,
                listen: false,
              ),
            );
          },
        ),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  @override
  void initState() {
    super.initState();
    // Initialize locale after the widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final localeProvider = Provider.of<LocaleProvider>(
        context,
        listen: false,
      );
      localeProvider.initializeLocale();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<LocaleProvider>(
      builder: (context, localeProvider, child) {
        return MaterialApp(
          // Lets session expiry unwind pushed routes from outside the tree.
          navigatorKey: AppNavigator.key,
          title: 'New Words',
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
            useMaterial3: true, // Recommended for new apps
          ),
          locale: localeProvider.locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: LocaleProvider.supportedLocales,
          home: const AuthWrapper(), // Use AuthWrapper for initial screen decision
          routes: {
            // Define routes for explicit navigation
            Routes.login: (context) => const LoginScreen(),
            Routes.register: (context) => const RegisterPage(),
            Routes.home: (context) => const HomeScreen(),
            Routes.newWordsList: (context) => const NewWordsListScreen(),
            Routes.deleteAccount: (context) => const DeleteAccountScreen(),
            Routes.privacyPolicy: (context) => const PrivacyPolicyScreen(),
            // AuthWrapper handles MainMenuScreen navigation based on auth state
            // WordDetailScreen requires arguments, so it's handled via Navigator.pushNamed with arguments
          },
          onGenerateRoute: (settings) {
            // Handle web deep links and route generation
            switch (settings.name) {
              case Routes.deleteAccount:
                return MaterialPageRoute(
                  builder: (context) => const DeleteAccountScreen(),
                  settings: settings,
                );
              case Routes.privacyPolicy:
                return MaterialPageRoute(
                  builder: (context) => const PrivacyPolicyScreen(),
                  settings: settings,
                );
              case Routes.login:
                return MaterialPageRoute(
                  builder: (context) => const LoginScreen(),
                  settings: settings,
                );
              case Routes.register:
                return MaterialPageRoute(
                  builder: (context) => const RegisterPage(),
                  settings: settings,
                );
              default:
                // Handle unknown routes gracefully for web
                if (kIsWeb) {
                  return MaterialPageRoute(
                    builder: (context) => const AuthWrapper(),
                    settings: settings,
                  );
                }
                return null;
            }
          },
        );
      },
    );
  }
}

// AuthWrapper decides the initial screen based on authentication state
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key, this.authenticatedBuilder});

  /// Builds the authenticated shell. Defaults to [MainMenuScreen]; tests pass
  /// a light widget so this branching and the route stack can be exercised
  /// without standing up the whole main-menu provider tree.
  final WidgetBuilder? authenticatedBuilder;

  @override
  Widget build(BuildContext context) {
    // Listen to AuthProvider changes
    final auth = Provider.of<AuthProvider>(context);

    // If AuthProvider is still initializing, show a loading screen
    if (!auth.isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(key: Key('auth_init_loading')),
        ),
      );
    }

    // Once initialized, show HomeScreen if authenticated, otherwise LoginScreen
    if (auth.isAuthenticated) {
      return authenticatedBuilder?.call(context) ?? const MainMenuScreen();
    } else {
      return const LoginScreen();
    }
  }
}
