import 'package:new_words/common/foundation/foundation.dart';
import 'package:new_words/common/constants/constants.dart';
import 'package:new_words/entities/user.dart';

/// Modern account API implementation using BaseApi foundation
/// 
/// This class replaces the old AccountApi with standardized error handling,
/// type-safe responses, and centralized constants usage.
class AccountApiV2 extends BaseApi {
  /// Create AccountApiV2 instance with optional custom Dio for testing
  AccountApiV2([super.customDio]);

  /// Authenticate user with email and password
  Future<ApiResponseV2<Map<String, dynamic>>> login(
    String email,
    String password,
  ) async {
    validateInput({
      'email': email,
      'password': password,
    });

    validateStringField(
      email,
      'email',
      minLength: 3,
      maxLength: AppConstants.maxEmailLength,
      pattern: RegExp(AppConstants.emailRegex),
      patternDescription: 'Valid email address required',
    );

    validateStringField(
      password,
      'password',
      minLength: AppConstants.minPasswordLength,
      maxLength: AppConstants.maxPasswordLength,
    );

    return await post<Map<String, dynamic>>(
      ApiConstants.authLogin,
      data: {
        'email': email,
        'password': password,
      },
      options: createAnonymousOptions(),
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }

  /// Register new user account
  Future<ApiResponseV2<Map<String, dynamic>>> register(
    String email,
    String password,
    String nativeLanguage,
    String learningLanguage,
  ) async {
    validateInput({
      'email': email,
      'password': password,
      'nativeLanguage': nativeLanguage,
      'learningLanguage': learningLanguage,
    });

    validateStringField(
      email,
      'email',
      minLength: 3,
      maxLength: AppConstants.maxEmailLength,
      pattern: RegExp(AppConstants.emailRegex),
      patternDescription: 'Valid email address required',
    );

    validateStringField(
      password,
      'password',
      minLength: AppConstants.minPasswordLength,
      maxLength: AppConstants.maxPasswordLength,
      pattern: RegExp(AppConstants.passwordRegex),
      patternDescription: 'Password must contain at least one uppercase letter, one lowercase letter, and one number',
    );

    validateStringField(
      nativeLanguage,
      'nativeLanguage',
      minLength: 2,
      maxLength: 10,
    );

    validateStringField(
      learningLanguage,
      'learningLanguage',
      minLength: 2,
      maxLength: 10,
    );

    return await post<Map<String, dynamic>>(
      ApiConstants.authRegister,
      data: {
        'email': email,
        'password': password,
        'nativeLanguage': nativeLanguage,
        'learningLanguage': learningLanguage,
      },
      options: createAnonymousOptions(),
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }

  /// Refresh authentication token
  ///
  /// [currentToken] is the still-valid access token being renewed.
  ///
  /// This request is marked anonymous so `AuthInterceptor` skips it: the
  /// interceptor renews an about-to-expire token, so letting it process the
  /// renewal itself makes every refresh trigger further refreshes. Skipping it
  /// also means nothing else attaches `Authorization`, and the endpoint is
  /// authenticated, so the bearer header is supplied explicitly here.
  Future<ApiResponseV2<Map<String, dynamic>>> refreshToken(
    String currentToken,
  ) async {
    return await post<Map<String, dynamic>>(
      ApiConstants.accountRefreshToken,
      data: {},
      options: createAnonymousOptions(
        headers: {
          ApiConstants.headerAuthorization: 'Bearer $currentToken',
        },
      ),
      fromJson: (json) => json as Map<String, dynamic>,
    );
  }

  /// Get current user information
  Future<ApiResponseV2<User>> getMyInformation() async {
    return await get<User>(
      ApiConstants.accountMyInformation,
      fromJson: (json) => User.fromJson(json as Map<String, dynamic>),
    );
  }

  /// Change user password
  Future<ApiResponseV2<void>> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    validateInput({
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });

    validateStringField(
      currentPassword,
      'currentPassword',
      minLength: AppConstants.minPasswordLength,
      maxLength: AppConstants.maxPasswordLength,
    );

    validateStringField(
      newPassword,
      'newPassword',
      minLength: AppConstants.minPasswordLength,
      maxLength: AppConstants.maxPasswordLength,
      pattern: RegExp(AppConstants.passwordRegex),
      patternDescription: 'Password must contain at least one uppercase letter, one lowercase letter, and one number',
    );

    return await post<void>(
      ApiConstants.accountChangePassword,
      data: {
        'CurrentPassword': currentPassword,
        'NewPassword': newPassword,
      },
    );
  }

  /// Update user language preferences
  Future<ApiResponseV2<void>> updateLanguages(
    String nativeLanguage,
    String learningLanguage,
  ) async {
    validateInput({
      'nativeLanguage': nativeLanguage,
      'learningLanguage': learningLanguage,
    });

    validateStringField(
      nativeLanguage,
      'nativeLanguage',
      minLength: 2,
      maxLength: 10,
    );

    validateStringField(
      learningLanguage,
      'learningLanguage',
      minLength: 2,
      maxLength: 10,
    );

    return await put<void>(
      ApiConstants.accountUpdateLanguages,
      data: {
        'nativeLanguage': nativeLanguage,
        'learningLanguage': learningLanguage,
      },
    );
  }

  /// Delete user account and all associated data
  /// 
  /// This will permanently delete:
  /// - User account information (email, password, profile)
  /// - User settings and preferences
  /// - User's vocabulary words and progress
  /// - User's stories and favorites
  /// 
  /// Shared data like explanations and word collections will be preserved.
  Future<ApiResponseV2<void>> deleteAccount() async {
    return await delete<void>(
      ApiConstants.accountDelete,
    );
  }
}