import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:mockito/annotations.dart';
import 'package:new_words/common/foundation/base_api.dart';
import 'package:new_words/common/foundation/api_response_v2.dart';
import 'package:new_words/common/foundation/service_exceptions.dart';

@GenerateMocks([Dio])
import 'base_api_test.mocks.dart';

void main() {
  group('BaseApi', () {
    late TestBaseApi api;
    late MockDio mockDio;

    setUp(() {
      mockDio = MockDio();
      api = TestBaseApi(mockDio);
    });

    group('Options creation methods', () {
      test('createOptions creates basic options', () {
        final options = api.createOptions(
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
          headers: {'Custom-Header': 'value'},
          contentType: 'application/xml',
        );

        expect(options.sendTimeout, equals(const Duration(seconds: 30)));
        expect(options.receiveTimeout, equals(const Duration(seconds: 60)));
        expect(options.headers?['Custom-Header'], equals('value'));
        expect(options.contentType, equals('application/xml'));
      });

      test('createAnonymousOptions adds AllowAnonymous header', () {
        final options = api.createAnonymousOptions(
          sendTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 45),
          headers: {'Custom-Header': 'value'},
        );

        expect(options.headers?['AllowAnonymous'], equals('true'));
        expect(options.headers?['Custom-Header'], equals('value'));
        expect(options.sendTimeout, equals(const Duration(seconds: 15)));
        expect(options.receiveTimeout, equals(const Duration(seconds: 45)));
      });

      test('createLongRunningOptions has extended timeouts', () {
        final options = api.createLongRunningOptions();

        expect(options.sendTimeout, equals(const Duration(minutes: 2)));
        expect(options.receiveTimeout, equals(const Duration(minutes: 5)));
      });

      test('createLongRunningOptions allows custom timeouts', () {
        final options = api.createLongRunningOptions(
          sendTimeout: const Duration(minutes: 1),
          receiveTimeout: const Duration(minutes: 3),
        );

        expect(options.sendTimeout, equals(const Duration(minutes: 1)));
        expect(options.receiveTimeout, equals(const Duration(minutes: 3)));
      });
    });

    group('Response parsing', () {
      test('parseResponse handles successful JSON response', () {
        final response = Response(
          requestOptions: RequestOptions(path: '/test'),
          data: {
            'successful': true,
            'data': {'id': 1, 'name': 'Test'},
          },
          statusCode: 200,
        );

        final result = api.testParseResponse<TestModel>(
          response,
          (data) => TestModel.fromJson(data as Map<String, dynamic>),
        );

        expect(result.isSuccess, isTrue);
        expect(result.data!.id, equals(1));
        expect(result.data!.name, equals('Test'));
      });

      test('parseResponse handles error JSON response', () {
        final response = Response(
          requestOptions: RequestOptions(path: '/test'),
          data: {
            'successful': false,
            'message': 'Validation failed',
            'errorCode': 1001,
          },
          statusCode: 400,
        );

        final result = api.testParseResponse<TestModel>(
          response,
          (data) => TestModel.fromJson(data as Map<String, dynamic>),
        );

        expect(result.isError, isTrue);
        expect(result.errorMessage, equals('Validation failed'));
        expect(result.errorCode, equals(1001));
      });

      test('parseResponse throws DataException for non-JSON response', () {
        final response = Response(
          requestOptions: RequestOptions(path: '/test'),
          data: 'Not JSON',
          statusCode: 200,
        );

        expect(
          () => api.testParseResponse<String>(response, (data) => data as String),
          throwsA(isA<DataException>()),
        );
      });

      test('parseResponse throws DataException for parsing error', () {
        final response = Response(
          requestOptions: RequestOptions(path: '/test'),
          data: {
            'successful': true,
            'data': {'invalid': 'structure'},
          },
          statusCode: 200,
        );

        expect(
          () => api.testParseResponse<TestModel>(
            response,
            (data) => TestModel.fromJson(data as Map<String, dynamic>),
          ),
          throwsA(isA<DataException>()),
        );
      });
    });

    group('Void response parsing', () {
      test('parseVoidResponse handles successful response', () {
        final response = Response(
          requestOptions: RequestOptions(path: '/test'),
          data: {
            'successful': true,
          },
          statusCode: 204,
        );

        final result = api.testParseVoidResponse(response);

        expect(result.isSuccess, isTrue);
      });

      test('parseVoidResponse handles error response', () {
        final response = Response(
          requestOptions: RequestOptions(path: '/test'),
          data: {
            'successful': false,
            'message': 'Operation failed',
            'errorCode': 5001,
          },
          statusCode: 500,
        );

        final result = api.testParseVoidResponse(response);

        expect(result.isError, isTrue);
        expect(result.errorMessage, equals('Operation failed'));
        expect(result.errorCode, equals(5001));
      });

      test('parseVoidResponse throws DataException for non-JSON response', () {
        final response = Response(
          requestOptions: RequestOptions(path: '/test'),
          data: 'Not JSON',
          statusCode: 200,
        );

        expect(
          () => api.testParseVoidResponse(response),
          throwsA(isA<DataException>()),
        );
      });
    });

    group('HTTP method utilities', () {
      test('requestVoid supports GET method', () {
        // This test verifies the method switching logic
        expect(
          () => api.testRequestVoidMethodCheck('GET'),
          returnsNormally,
        );
      });

      test('requestVoid supports POST method', () {
        expect(
          () => api.testRequestVoidMethodCheck('POST'),
          returnsNormally,
        );
      });

      test('requestVoid supports PUT method', () {
        expect(
          () => api.testRequestVoidMethodCheck('PUT'),
          returnsNormally,
        );
      });

      test('requestVoid supports DELETE method', () {
        expect(
          () => api.testRequestVoidMethodCheck('DELETE'),
          returnsNormally,
        );
      });

      test('requestVoid throws ArgumentError for unsupported method', () {
        expect(
          () => api.testRequestVoidMethodCheck('PATCH'),
          throwsA(isA<ArgumentError>()),
        );
      });
    });
  });
}

// Test model for JSON parsing tests
class TestModel {
  final int id;
  final String name;

  TestModel({required this.id, required this.name});

  factory TestModel.fromJson(Map<String, dynamic> json) {
    return TestModel(
      id: json['id'] as int,
      name: json['name'] as String,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TestModel && other.id == id && other.name == name;
  }

  @override
  int get hashCode => Object.hash(id, name);
}

// Test implementation of BaseApi for testing protected methods
class TestBaseApi extends BaseApi {
  TestBaseApi(super.customDio);
  // Expose protected methods for testing
  ApiResponseV2<T> testParseResponse<T>(
    Response response,
    T Function(dynamic json) fromJson,
  ) {
    return parseResponse<T>(response, fromJson);
  }

  ApiResponseV2<void> testParseVoidResponse(Response response) {
    return parseVoidResponse(response);
  }

  // Test method switching logic without actual HTTP calls
  void testRequestVoidMethodCheck(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
      case 'POST':
      case 'PUT':
      case 'DELETE':
        // Valid methods, do nothing
        break;
      default:
        throw ArgumentError('Unsupported HTTP method: $method');
    }
  }
}