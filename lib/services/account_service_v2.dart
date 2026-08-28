import 'package:shared_preferences/shared_preferences.dart';
import 'package:new_words/apis/account_api_v2.dart';
import 'package:new_words/common/foundation/foundation.dart';
import 'package:new_words/common/constants/constants.dart';
import 'package:new_words/entities/user.dart';
import 'package:new_words/services/user_settings_service_v2.dart';
import 'package:new_words/user_session.dart';
import 'package:new_words/utils/app_logger.dart';
import 'package:new_words/utils/app_logger_interface.dart';
import 'package:new_words/utils/token_utils.dart';
import 'package:new_words/app_config.dart';

/// Modern account service implementation using BaseService foundation
/// 
/// This class replaces the old AccountService with standardized error handling,
/// validation patterns, and centralized constants usage.
class AccountServiceV2 extends BaseService {
  final AccountApiV2 _accountApi;
  final UserSettingsServiceV2 _userSettingsService;
  final TokenUtils _tokenUtils;
  final AppLoggerInterface _logger;

  // Token Payload Keys
  final String _payloadUserIdKey =
      'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/nameidentifier';
  final String _payloadEmailKey =
      'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress';

  AccountServiceV2({
    required AccountApiV2 accountApi,
    required UserSettingsServiceV2 userSettingsService,
    required TokenUtils tokenUtils,
    AppLoggerInterface? logger,
  })  : _accountApi = accountApi,
        _userSettingsService = userSettingsService,
        _tokenUtils = tokenUtils,
        _logger = logger ?? AppLogger.instance;

  /// Login user with email and password
  Future<void> login(String email, String password) async {
    logOperation('login', parameters: {'email': email});

    try {
      final response = await _accountApi.login(email, password);
      final sessionData = processResponse(response);
      await _processLoginOrRegisterSuccess(sessionData);
    } catch (e) {
      final error = ServiceExceptionFactory.fromException(e);
      logError('login', error);
      throw error;
    }
  }

  /// Register new user account
  Future<void> register(
    String email,
    String password,
    String nativeLanguage,
    String learningLanguage,
  ) async {
    logOperation('register', parameters: {
      'email': email,
      'nativeLanguage': nativeLanguage,
      'learningLanguage': learningLanguage,
    });

    try {
      final response = await _accountApi.register(
        email,
        password,
        nativeLanguage,
        learningLanguage,
      );
      final sessionData = processResponse(response);
      await _processLoginOrRegisterSuccess(sessionData);
    } catch (e) {
      final error = ServiceExceptionFactory.fromException(e);
      logError('register', error);
      throw error;
    }
  }

  /// Logout current user
  Future<void> logout() async {
    logOperation('logout');

    try {
      await _clearUserSessionAndStorage();
    } catch (e) {
      final error = ServiceExceptionFactory.fromException(e);
      logError('logout', error);
      throw error;
    }
  }

  /// Get current user information
  Future<User> getMyInformation() async {
    logOperation('getMyInformation');

    try {
      final response = await _accountApi.getMyInformation();
      return processResponse(response);
    } catch (e) {
      final error = ServiceExceptionFactory.fromException(e);
      logError('getMyInformation', error);
      throw error;
    }
  }

  /// Change user password
  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    logOperation('changePassword');

    try {
      final response = await _accountApi.changePassword(
        currentPassword,
        newPassword,
      );
      processVoidResponse(response);
    } catch (e) {
      final error = ServiceExceptionFactory.fromException(e);
      logError('changePassword', error);
      throw error;
    }
  }

  /// Update user language preferences
  Future<void> updateUserLanguages(
    String nativeLanguage,
    String learningLanguage,
  ) async {
    logOperation('updateUserLanguages', parameters: {
      'nativeLanguage': nativeLanguage,
      'learningLanguage': learningLanguage,
    });

    try {
      final response = await _accountApi.updateLanguages(
        nativeLanguage,
        learningLanguage,
      );
      processVoidResponse(response);

      // Update SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(StorageKeys.userNativeLanguage, nativeLanguage);
      await prefs.setString(StorageKeys.userLearningLanguage, learningLanguage);

      // Update UserSession
      UserSession().nativeLanguage = nativeLanguage;
      UserSession().currentLearningLanguage = learningLanguage;
    } catch (e) {
      final error = ServiceExceptionFactory.fromException(e);
      logError('updateUserLanguages', error);
      throw error;
    }
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
  /// After successful deletion, the user will be logged out automatically.
  Future<void> deleteAccount() async {
    logOperation('deleteAccount');

    try {
      final response = await _accountApi.deleteAccount();
      processVoidResponse(response);

      // Clear local data after successful deletion
      await _clearUserSessionAndStorage();
    } catch (e) {
      final error = ServiceExceptionFactory.fromException(e);
      logError('deleteAccount', error);
      throw error;
    }
  }

  /// Get stored authentication token.
  ///
  /// Throws [AuthenticationException] when the stored token is inside the
  /// refresh window and the refresh fails: the old token is only minutes from
  /// expiry and may well be rejected mid-flight, so callers get an actionable
  /// session error instead of a stale token and a later opaque 401.
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(StorageKeys.accessToken);
    
    if (token != null && token.isNotEmpty) {
      // Check if token is about to expire and refresh if needed
      var remainingTime = await _tokenUtils.getTokenRemainingTime(token);
      if (remainingTime.inMinutes < AppConstants.tokenRefreshThreshold ~/ 60000 && 
          remainingTime.inSeconds > 0) {
        // Refresh if less than threshold time left but not expired
        try {
          _logger.i("Attempting to refresh token...");
          await _refreshTokenAndResave(token);
          return prefs.getString(StorageKeys.accessToken); // Return potentially new token
        } catch (e) {
          _logger.e("Token refresh failed: $e");
          // Deliberately not falling back to the stored token: it is inside the
          // refresh window, so returning it just moves the failure to the
          // server as an opaque 401. Storage is left untouched so the caller
          // can retry; AuthInterceptor turns this into a session error.
          throw AuthenticationException(
            'Your session could not be refreshed. Please sign in again.',
            cause: e,
          );
        }
      }
    }
    return token;
  }

  /// Get valid token for immediate use (doesn't trigger refresh)
  String? getValidToken() {
    // This is a synchronous version that doesn't trigger async operations
    // Used in cases where we need immediate token access
    return UserSession().token;
  }

  /// Check if current token is valid
  bool hasValidToken() {
    try {
      final token = getValidToken();
      if (token == null || token.isEmpty) return false;
      
      final remainingTime = _tokenUtils.getTokenRemainingTimeSync(token);
      return remainingTime.inSeconds > 0;
    } catch (e) {
      return false;
    }
  }

  /// Check if stored token is valid (async version)
  Future<bool> isValidToken() async {
    if (await _isSameEnv()) {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(StorageKeys.accessToken);
      if (token != null && token.isNotEmpty) {
        try {
          return (await _tokenUtils.getTokenRemainingTime(token)).inSeconds > 0;
        } catch (e) {
          _logger.e("isValidToken: Error decoding token or token expired: $e");
          return false;
        }
      }
    }
    return false;
  }

  /// Initialize user session from stored token
  Future<void> setUserSession({String? tokenFromInit}) async {
    logOperation('setUserSession');

    try {
      final tokenToUse = tokenFromInit ?? await getToken();

      if (tokenToUse == null || tokenToUse.isEmpty) {
        await _clearUserSessionAndStorage();
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      
      // Decode token for essential info like userId
      var payload = await _tokenUtils.decodeToken(tokenToUse);
      UserSession().id = int.tryParse(payload[_payloadUserIdKey] ?? '');
      UserSession().token = tokenToUse;

      // Load other details from SharedPreferences
      UserSession().email = prefs.getString(StorageKeys.userEmail) ??
          payload[_payloadEmailKey]; // Fallback to token email
      UserSession().nativeLanguage = prefs.getString(StorageKeys.userNativeLanguage);
      UserSession().currentLearningLanguage = prefs.getString(StorageKeys.userLearningLanguage);

      // Load user settings
      UserSession().userSettings = await _userSettingsService.getAll();
    } catch (e) {
      _logger.e("Failed to set user session during init: $e");
      await _clearUserSessionAndStorage();
      rethrow;
    }
  }

  /// Process successful login or registration response
  Future<void> _processLoginOrRegisterSuccess(
    Map<String, dynamic> sessionData,
  ) async {
    final token = sessionData['token'] as String?;
    final userId = sessionData['userId'] as int?;
    final email = sessionData['email'] as String?;
    final nativeLanguage = sessionData['nativeLanguage'] as String?;
    final currentLearningLanguage = sessionData['currentLearningLanguage'] as String?;

    if (token == null || token.isEmpty) {
      throw DataException('Token not found in API response');
    }

    // Store token and other details in SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(StorageKeys.accessToken, token);
    await prefs.setString(StorageKeys.baseUrl, AppConfig.apiBaseUrl);

    if (email != null) await prefs.setString(StorageKeys.userEmail, email);
    if (nativeLanguage != null) {
      await prefs.setString(StorageKeys.userNativeLanguage, nativeLanguage);
    }
    if (currentLearningLanguage != null) {
      await prefs.setString(StorageKeys.userLearningLanguage, currentLearningLanguage);
    }

    // Populate UserSession singleton
    UserSession().id = userId;
    UserSession().email = email;
    UserSession().token = token;
    UserSession().nativeLanguage = nativeLanguage;
    UserSession().currentLearningLanguage = currentLearningLanguage;
    
    try {
      UserSession().userSettings = await _userSettingsService.getAll();
    } catch (e) {
      _logger.e("Failed to load user settings during login/register: $e");
      UserSession().userSettings = null;
    }
  }

  /// Clear user session and storage
  Future<void> _clearUserSessionAndStorage() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(StorageKeys.accessToken);
    await prefs.remove(StorageKeys.baseUrl);
    await prefs.remove(StorageKeys.userEmail);
    await prefs.remove(StorageKeys.userNativeLanguage);
    await prefs.remove(StorageKeys.userLearningLanguage);

    UserSession().id = null;
    UserSession().email = null;
    UserSession().token = null;
    UserSession().nativeLanguage = null;
    UserSession().currentLearningLanguage = null;
    UserSession().userSettings = null;
  }

  /// Refresh authentication token
  ///
  /// [currentToken] is the token just read from storage; it is forwarded so the
  /// refresh request can carry its own bearer header without re-entering
  /// `AuthInterceptor`.
  Future<void> _refreshTokenAndResave(String currentToken) async {
    final response = await _accountApi.refreshToken(currentToken);
    final sessionData = processResponse(response);
    
    final newToken = sessionData['token'] as String?;
    if (newToken != null && newToken.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(StorageKeys.accessToken, newToken);
      UserSession().token = newToken;
      _logger.i("Token refreshed and resaved successfully.");
    } else {
      throw DataException("No new token in refresh response");
    }
  }

  /// Check if current environment matches stored environment
  Future<bool> _isSameEnv() async {
    final prefs = await SharedPreferences.getInstance();
    final previousBaseUrl = prefs.getString(StorageKeys.baseUrl);
    return previousBaseUrl == null || previousBaseUrl == AppConfig.apiBaseUrl;
  }
}