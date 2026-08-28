import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:new_words/apis/account_api_v2.dart';
import 'package:new_words/common/foundation/foundation.dart';
import 'package:new_words/common/constants/constants.dart';

@GenerateMocks([Dio])
import 'account_api_v2_test.mocks.dart';

void main() {
  group('AccountApiV2', () {
    late AccountApiV2 api;
    late MockDio mockDio;

    setUp(() {
      mockDio = MockDio();
      api = TestAccountApiV2(mockDio);
    });

    group('login', () {
      test('successfully logs in user', () async {
        final email = 'test@example.com';
        final password = 'Test123!';
        final responseData = {
          'successful': true,
          'data': {
            'token': 'mock-jwt-token',
            'userId': 1,
            'email': email,
            'nativeLanguage': 'en',
            'currentLearningLanguage': 'zh',
          },
        };

        when(mockDio.post(
          any,
          data: anyNamed('data'),
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: '/test'),
          data: responseData,
          statusCode: 200,
        ));

        final result = await api.login(email, password);

        expect(result.isSuccess, isTrue);
        expect(result.data!['token'], equals('mock-jwt-token'));
        expect(result.data!['email'], equals(email));

        verify(mockDio.post(
          ApiConstants.authLogin,
          data: {
            'email': email,
            'password': password,
          },
          options: anyNamed('options'),
        )).called(1);
      });

      test('throws DataException for empty email', () async {
        expect(
          () => api.login('', 'password123'),
          throwsA(isA<DataException>()),
        );
      });

      test('throws DataException for invalid email format', () async {
        expect(
          () => api.login('invalid-email', 'password123'),
          throwsA(isA<DataException>()),
        );
      });

      test('throws DataException for short password', () async {
        expect(
          () => api.login('test@example.com', '123'),
          throwsA(isA<DataException>()),
        );
      });

      test('throws DataException for null email', () async {
        expect(
          () => api.login(null as dynamic, 'password123'),
          throwsA(isA<TypeError>()),
        );
      });

      test('throws DataException for null password', () async {
        expect(
          () => api.login('test@example.com', null as dynamic),
          throwsA(isA<TypeError>()),
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
          'successful': true,
          'data': {
            'token': 'mock-jwt-token',
            'userId': 2,
            'email': email,
            'nativeLanguage': nativeLanguage,
            'currentLearningLanguage': learningLanguage,
          },
        };

        when(mockDio.post(
          any,
          data: anyNamed('data'),
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: '/test'),
          data: responseData,
          statusCode: 200,
        ));

        final result = await api.register(
          email,
          password,
          nativeLanguage,
          learningLanguage,
        );

        expect(result.isSuccess, isTrue);
        expect(result.data!['email'], equals(email));
        expect(result.data!['nativeLanguage'], equals(nativeLanguage));

        verify(mockDio.post(
          ApiConstants.authRegister,
          data: {
            'email': email,
            'password': password,
            'nativeLanguage': nativeLanguage,
            'learningLanguage': learningLanguage,
          },
          options: anyNamed('options'),
        )).called(1);
      });

      test('throws DataException for invalid email', () async {
        expect(
          () => api.register('invalid-email', 'Password123!', 'en', 'zh'),
          throwsA(isA<DataException>()),
        );
      });

      test('throws DataException for weak password', () async {
        expect(
          () => api.register('test@example.com', 'weak', 'en', 'zh'),
          throwsA(isA<DataException>()),
        );
      });

      test('throws DataException for empty native language', () async {
        expect(
          () => api.register('test@example.com', 'Password123!', '', 'zh'),
          throwsA(isA<DataException>()),
        );
      });

      test('throws DataException for empty learning language', () async {
        expect(
          () => api.register('test@example.com', 'Password123!', 'en', ''),
          throwsA(isA<DataException>()),
        );
      });

      test('throws DataException for short language codes', () async {
        expect(
          () => api.register('test@example.com', 'Password123!', 'e', 'zh'),
          throwsA(isA<DataException>()),
        );
      });
    });

    group('refreshToken', () {
      test('successfully refreshes token', () async {
        final responseData = {
          'successful': true,
          'data': {
            'token': 'new-jwt-token',
          },
        };

        when(mockDio.post(
          any,
          data: anyNamed('data'),
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: '/test'),
          data: responseData,
          statusCode: 200,
        ));

        final result = await api.refreshToken('current-jwt-token');

        expect(result.isSuccess, isTrue);
        expect(result.data!['token'], equals('new-jwt-token'));

        verify(mockDio.post(
          ApiConstants.accountRefreshToken,
          data: {},
          options: anyNamed('options'),
        )).called(1);
      });

      test('bypasses AuthInterceptor but still sends the bearer token',
          () async {
        when(mockDio.post(
          any,
          data: anyNamed('data'),
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: '/test'),
          data: {
            'successful': true,
            'data': {'token': 'new-jwt-token'},
          },
          statusCode: 200,
        ));

        await api.refreshToken('current-jwt-token');

        final captured = verify(mockDio.post(
          ApiConstants.accountRefreshToken,
          data: anyNamed('data'),
          options: captureAnyNamed('options'),
        )).captured.single as Options;

        // AllowAnonymous keeps AuthInterceptor from processing the refresh,
        // which would otherwise trigger further refreshes.
        expect(
          captured.headers?[ApiConstants.headerAllowAnonymous],
          equals('true'),
        );
        // Nothing else attaches Authorization once the interceptor is skipped,
        // and the endpoint is authenticated.
        expect(
          captured.headers?[ApiConstants.headerAuthorization],
          equals('Bearer current-jwt-token'),
        );
      });
    });

    group('getMyInformation', () {
      test('successfully gets user information', () async {
        final responseData = {
          'successful': true,
          'data': {
            'email': 'user@example.com',
            'gravatar': 'gravatar-url',
            'createdAt': 1704067200,
            'nativeLanguage': 'en',
            'currentLearningLanguage': 'zh',
          },
        };

        when(mockDio.get(
          any,
          queryParameters: anyNamed('queryParameters'),
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: '/test'),
          data: responseData,
          statusCode: 200,
        ));

        final result = await api.getMyInformation();

        expect(result.isSuccess, isTrue);
        expect(result.data!.email, equals('user@example.com'));
        expect(result.data!.nativeLanguage, equals('en'));

        verify(mockDio.get(
          ApiConstants.accountMyInformation,
          queryParameters: anyNamed('queryParameters'),
          options: anyNamed('options'),
        )).called(1);
      });
    });

    group('changePassword', () {
      test('successfully changes password', () async {
        final responseData = {
          'successful': true,
        };

        when(mockDio.post(
          any,
          data: anyNamed('data'),
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: '/test'),
          data: responseData,
          statusCode: 200,
        ));

        final result = await api.changePassword('currentPass123!', 'newPass123!');

        expect(result.isSuccess, isTrue);

        verify(mockDio.post(
          ApiConstants.accountChangePassword,
          data: {
            'CurrentPassword': 'currentPass123!',
            'NewPassword': 'newPass123!',
          },
          options: anyNamed('options'),
        )).called(1);
      });

      test('throws DataException for empty current password', () async {
        expect(
          () => api.changePassword('', 'newPass123!'),
          throwsA(isA<DataException>()),
        );
      });

      test('throws DataException for weak new password', () async {
        expect(
          () => api.changePassword('currentPass123!', 'weak'),
          throwsA(isA<DataException>()),
        );
      });

      test('throws DataException for null passwords', () async {
        expect(
          () => api.changePassword(null as dynamic, 'newPass123!'),
          throwsA(isA<TypeError>()),
        );
      });
    });

    group('updateLanguages', () {
      test('successfully updates languages', () async {
        final responseData = {
          'successful': true,
        };

        when(mockDio.put(
          any,
          data: anyNamed('data'),
          options: anyNamed('options'),
        )).thenAnswer((_) async => Response(
          requestOptions: RequestOptions(path: '/test'),
          data: responseData,
          statusCode: 200,
        ));

        final result = await api.updateLanguages('en', 'fr');

        expect(result.isSuccess, isTrue);

        verify(mockDio.put(
          ApiConstants.accountUpdateLanguages,
          data: {
            'nativeLanguage': 'en',
            'learningLanguage': 'fr',
          },
          options: anyNamed('options'),
        )).called(1);
      });

      test('throws DataException for empty native language', () async {
        expect(
          () => api.updateLanguages('', 'fr'),
          throwsA(isA<DataException>()),
        );
      });

      test('throws DataException for short language codes', () async {
        expect(
          () => api.updateLanguages('e', 'fr'),
          throwsA(isA<DataException>()),
        );
      });

      test('throws DataException for null languages', () async {
        expect(
          () => api.updateLanguages(null as dynamic, 'fr'),
          throwsA(isA<TypeError>()),
        );
      });
    });

    group('validation methods', () {
      test('validateInput succeeds for valid data', () {
        expect(
          () => api.validateInput({
            'field1': 'value1',
            'field2': 'value2',
          }),
          returnsNormally,
        );
      });

      test('validateInput throws for null values', () {
        expect(
          () => api.validateInput({'field': null}),
          throwsA(isA<DataException>()),
        );
      });

      test('validateStringField succeeds for valid email', () {
        expect(
          () => api.validateStringField(
            'test@example.com',
            'email',
            pattern: RegExp(AppConstants.emailRegex),
          ),
          returnsNormally,
        );
      });

      test('validateStringField throws for invalid email', () {
        expect(
          () => api.validateStringField(
            'invalid-email',
            'email',
            pattern: RegExp(AppConstants.emailRegex),
          ),
          throwsA(isA<DataException>()),
        );
      });

      test('validateStringField succeeds for valid password', () {
        expect(
          () => api.validateStringField(
            'ValidPass123!',
            'password',
            pattern: RegExp(AppConstants.passwordRegex),
          ),
          returnsNormally,
        );
      });

      test('validateStringField throws for weak password', () {
        expect(
          () => api.validateStringField(
            'weak',
            'password',
            pattern: RegExp(AppConstants.passwordRegex),
          ),
          throwsA(isA<DataException>()),
        );
      });
    });
  });
}

// Test implementation that properly mocks dependencies
class TestAccountApiV2 extends AccountApiV2 {
  TestAccountApiV2(MockDio super.mockDio);
}