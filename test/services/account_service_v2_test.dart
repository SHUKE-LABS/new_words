import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:new_words/apis/account_api_v2.dart';
import 'package:new_words/services/account_service_v2.dart';
import 'package:new_words/services/user_settings_service_v2.dart';
import 'package:new_words/utils/token_utils.dart';
import 'package:new_words/common/foundation/foundation.dart';
import '../mocks/mock_app_logger.dart';
import 'package:new_words/common/constants/constants.dart';
import 'package:new_words/entities/user.dart';
import 'package:new_words/user_session.dart';

@GenerateMocks([
  AccountApiV2,
  UserSettingsServiceV2,
  TokenUtils,
])
import 'account_service_v2_test.mocks.dart';

void main() {
  group('AccountServiceV2', () {
    late AccountServiceV2 service;
    late MockAccountApiV2 mockApi;
    late MockUserSettingsServiceV2 mockUserSettingsService;
    late MockTokenUtils mockTokenUtils;
    late MockAppLogger mockLogger;

    setUpAll(() async {
      // Initialize dotenv for tests with mock values
      dotenv.testLoad(fileInput: '''
API_BASE_URL=https://test.example.com
''');
    });

    setUp(() {
      mockApi = MockAccountApiV2();
      mockUserSettingsService = MockUserSettingsServiceV2();
      mockTokenUtils = MockTokenUtils();
      mockLogger = MockAppLogger();
      service = AccountServiceV2(
        accountApi: mockApi,
        userSettingsService: mockUserSettingsService,
        tokenUtils: mockTokenUtils,
        logger: mockLogger,
      );

      // Setup SharedPreferences mock
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() {
      // Clear UserSession after each test
      UserSession().id = null;
      UserSession().email = null;
      UserSession().token = null;
      UserSession().nativeLanguage = null;
      UserSession().currentLearningLanguage = null;
      UserSession().userSettings = null;
    });

    group('login', () {
      test('successfully logs in user', () async {
        final email = 'test@example.com';
        final password = 'Test123!';
        final responseData = {
          'token': 'mock-jwt-token',
          'userId': 1,
          'email': email,
          'nativeLanguage': 'en',
          'currentLearningLanguage': 'zh',
        };

        final apiResponse = ApiResponseV2<Map<String, dynamic>>.success(
          responseData,
          statusCode: 200,
        );

        when(mockApi.login(email, password)).thenAnswer((_) async => apiResponse);
        when(mockUserSettingsService.getAll()).thenAnswer((_) async => []);

        await service.login(email, password);

        // Verify API was called
        verify(mockApi.login(email, password)).called(1);

        // Verify UserSession was populated
        expect(UserSession().id, equals(1));
        expect(UserSession().email, equals(email));
        expect(UserSession().token, equals('mock-jwt-token'));
        expect(UserSession().nativeLanguage, equals('en'));
        expect(UserSession().currentLearningLanguage, equals('zh'));

        // Verify SharedPreferences was updated
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(StorageKeys.accessToken), equals('mock-jwt-token'));
        expect(prefs.getString(StorageKeys.userEmail), equals(email));
      });

      test('throws exception for API error', () async {
        final apiResponse = ApiResponseV2<Map<String, dynamic>>.error(
          'Invalid credentials',
          statusCode: 401,
          errorCode: 1001,
        );

        when(mockApi.login(any, any)).thenAnswer((_) async => apiResponse);

        expect(
          () => service.login('test@example.com', 'wrongpass'),
          throwsA(isA<AuthenticationException>()),
        );

        verifyNever(mockUserSettingsService.getAll());
      });

      test('handles missing token in response', () async {
        final responseData = {
          'userId': 1,
          'email': 'test@example.com',
          // Missing token
        };

        final apiResponse = ApiResponseV2<Map<String, dynamic>>.success(
          responseData,
          statusCode: 200,
        );

        when(mockApi.login(any, any)).thenAnswer((_) async => apiResponse);

        expect(
          () => service.login('test@example.com', 'password'),
          throwsA(isA<DataException>()),
        );
      });
    });

    group('register', () {
      test('successfully registers user', () async {
        final email = 'newuser@example.com';
        final password = 'NewUser123!';
        final nativeLanguage = 'en';
        final learningLanguage = 'zh';
        final responseData = {
          'token': 'mock-jwt-token',
          'userId': 2,
          'email': email,
          'nativeLanguage': nativeLanguage,
          'currentLearningLanguage': learningLanguage,
        };

        final apiResponse = ApiResponseV2<Map<String, dynamic>>.success(
          responseData,
          statusCode: 200,
        );

        when(mockApi.register(email, password, nativeLanguage, learningLanguage))
            .thenAnswer((_) async => apiResponse);
        when(mockUserSettingsService.getAll()).thenAnswer((_) async => []);

        await service.register(email, password, nativeLanguage, learningLanguage);

        verify(mockApi.register(email, password, nativeLanguage, learningLanguage))
            .called(1);

        expect(UserSession().id, equals(2));
        expect(UserSession().email, equals(email));
        expect(UserSession().nativeLanguage, equals(nativeLanguage));
        expect(UserSession().currentLearningLanguage, equals(learningLanguage));
      });

      test('throws exception for registration error', () async {
        final apiResponse = ApiResponseV2<Map<String, dynamic>>.error(
          'Email already exists',
          statusCode: 400,
          errorCode: 1002,
        );

        when(mockApi.register(any, any, any, any)).thenAnswer((_) async => apiResponse);

        expect(
          () => service.register('existing@example.com', 'password', 'en', 'zh'),
          throwsA(isA<ApiBusinessException>()),
        );
      });
    });

    group('logout', () {
      test('successfully logs out user', () async {
        // Setup initial session
        UserSession().id = 1;
        UserSession().email = 'test@example.com';
        UserSession().token = 'some-token';

        await service.logout();

        // Verify session was cleared
        expect(UserSession().id, isNull);
        expect(UserSession().email, isNull);
        expect(UserSession().token, isNull);

        // Verify SharedPreferences was cleared
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(StorageKeys.accessToken), isNull);
        expect(prefs.getString(StorageKeys.userEmail), isNull);
      });
    });

    group('getMyInformation', () {
      test('successfully gets user information', () async {
        final user = User(
          email: 'user@example.com',
          gravatar: 'gravatar-url',
          createdAt: 1704067200,
          nativeLanguage: 'en',
          currentLearningLanguage: 'zh',
        );

        final apiResponse = ApiResponseV2<User>.success(user, statusCode: 200);

        when(mockApi.getMyInformation()).thenAnswer((_) async => apiResponse);

        final result = await service.getMyInformation();

        expect(result.email, equals('user@example.com'));
        expect(result.nativeLanguage, equals('en'));
        verify(mockApi.getMyInformation()).called(1);
      });

      test('throws exception for API error', () async {
        final apiResponse = ApiResponseV2<User>.error(
          'Unauthorized',
          statusCode: 401,
        );

        when(mockApi.getMyInformation()).thenAnswer((_) async => apiResponse);

        expect(
          () => service.getMyInformation(),
          throwsA(isA<AuthenticationException>()),
        );
      });
    });

    group('changePassword', () {
      test('successfully changes password', () async {
        final apiResponse = ApiResponseV2<void>.success(null, statusCode: 200);

        when(mockApi.changePassword(any, any)).thenAnswer((_) async => apiResponse);

        await service.changePassword('currentPass123!', 'newPass123!');

        verify(mockApi.changePassword('currentPass123!', 'newPass123!')).called(1);
      });

      test('throws exception for invalid current password', () async {
        final apiResponse = ApiResponseV2<void>.error(
          'Current password is incorrect',
          statusCode: 400,
          errorCode: 1003,
        );

        when(mockApi.changePassword(any, any)).thenAnswer((_) async => apiResponse);

        expect(
          () => service.changePassword('wrongPass', 'newPass123!'),
          throwsA(isA<ApiBusinessException>()),
        );
      });
    });

    group('updateUserLanguages', () {
      test('successfully updates languages', () async {
        final apiResponse = ApiResponseV2<void>.success(null, statusCode: 200);

        when(mockApi.updateLanguages(any, any)).thenAnswer((_) async => apiResponse);

        await service.updateUserLanguages('en', 'fr');

        verify(mockApi.updateLanguages('en', 'fr')).called(1);

        // Verify UserSession was updated
        expect(UserSession().nativeLanguage, equals('en'));
        expect(UserSession().currentLearningLanguage, equals('fr'));

        // Verify SharedPreferences was updated
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(StorageKeys.userNativeLanguage), equals('en'));
        expect(prefs.getString(StorageKeys.userLearningLanguage), equals('fr'));
      });

      test('throws exception for API error', () async {
        final apiResponse = ApiResponseV2<void>.error(
          'Invalid language code',
          statusCode: 400,
        );

        when(mockApi.updateLanguages(any, any)).thenAnswer((_) async => apiResponse);

        expect(
          () => service.updateUserLanguages('invalid', 'fr'),
          throwsA(isA<ApiBusinessException>()),
        );

        // Verify UserSession was not updated on error
        expect(UserSession().nativeLanguage, isNull);
        expect(UserSession().currentLearningLanguage, isNull);
      });
    });

    group('token management', () {
      test('getToken returns stored token', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(StorageKeys.accessToken, 'stored-token');

        when(mockTokenUtils.getTokenRemainingTime('stored-token'))
            .thenAnswer((_) async => const Duration(hours: 2));

        final token = await service.getToken();

        expect(token, equals('stored-token'));
      });

      test('getToken refreshes token when close to expiry', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(StorageKeys.accessToken, 'old-token');

        when(mockTokenUtils.getTokenRemainingTime('old-token'))
            .thenAnswer((_) async => const Duration(minutes: 3)); // Less than 5 minutes

        final refreshResponse = ApiResponseV2<Map<String, dynamic>>.success(
          {'token': 'new-token'},
          statusCode: 200,
        );

        // Stubbed on the exact stored token: an implementation that forwards a
        // different or empty token gets no stub and fails instead of passing.
        when(mockApi.refreshToken('old-token'))
            .thenAnswer((_) async => refreshResponse);

        final token = await service.getToken();

        expect(token, equals('new-token'));
        verify(mockApi.refreshToken('old-token')).called(1);
      });

      test('hasValidToken returns true for valid token', () {
        UserSession().token = 'valid-token';

        when(mockTokenUtils.getTokenRemainingTimeSync('valid-token'))
            .thenReturn(const Duration(hours: 1));

        final isValid = service.hasValidToken();

        expect(isValid, isTrue);
      });

      test('hasValidToken returns false for expired token', () {
        UserSession().token = 'expired-token';

        when(mockTokenUtils.getTokenRemainingTimeSync('expired-token'))
            .thenReturn(const Duration(seconds: -1));

        final isValid = service.hasValidToken();

        expect(isValid, isFalse);
      });

      test('hasValidToken returns false for null token', () {
        UserSession().token = null;

        final isValid = service.hasValidToken();

        expect(isValid, isFalse);
      });
    });

    group('session management', () {
      test('setUserSession populates from token', () async {
        final token = 'mock-jwt-token';
        final payload = {
          'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier': '123',
          'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress': 'user@example.com',
        };

        when(mockTokenUtils.decodeToken(token)).thenAnswer((_) async => payload);
        when(mockUserSettingsService.getAll()).thenAnswer((_) async => []);

        await service.setUserSession(tokenFromInit: token);

        expect(UserSession().id, equals(123));
        expect(UserSession().email, equals('user@example.com'));
        expect(UserSession().token, equals(token));
        verify(mockUserSettingsService.getAll()).called(1);
      });

      test('setUserSession clears session for null token', () async {
        UserSession().id = 1;
        UserSession().email = 'test@example.com';

        await service.setUserSession(tokenFromInit: null);

        expect(UserSession().id, isNull);
        expect(UserSession().email, isNull);
        expect(UserSession().token, isNull);
      });

      test('setUserSession handles token decode error', () async {
        final token = 'invalid-token';

        when(mockTokenUtils.decodeToken(token))
            .thenThrow(Exception('Invalid token'));

        expect(
          () => service.setUserSession(tokenFromInit: token),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('environment validation', () {
      test('isValidToken validates token properly', () async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(StorageKeys.baseUrl, 'https://test.example.com');
        await prefs.setString(StorageKeys.accessToken, 'valid-token');

        when(mockTokenUtils.getTokenRemainingTime('valid-token'))
            .thenAnswer((_) async => const Duration(hours: 1));

        final isValid = await service.isValidToken();

        expect(isValid, isTrue);
      });
    });

    group('error handling', () {
      test('login handles user settings load failure gracefully', () async {
        final responseData = {
          'token': 'mock-jwt-token',
          'userId': 1,
          'email': 'test@example.com',
        };

        final apiResponse = ApiResponseV2<Map<String, dynamic>>.success(
          responseData,
          statusCode: 200,
        );

        when(mockApi.login(any, any)).thenAnswer((_) async => apiResponse);
        when(mockUserSettingsService.getAll())
            .thenThrow(Exception('Settings service error'));

        // Should not throw - should handle gracefully
        await service.login('test@example.com', 'password');
        expect(UserSession().userSettings, isNull);
      });

      test('operations create enhanced error messages', () async {
        when(mockApi.login(any, any)).thenThrow(Exception('Network error'));

        try {
          await service.login('test@example.com', 'password');
          fail('Should have thrown exception');
        } catch (e) {
          expect(e, isA<ServiceException>());
        }
      });
    });
  });
}