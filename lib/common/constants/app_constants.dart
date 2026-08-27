/// Centralized constants for app-wide values
///
/// This class contains the validation limits and patterns used throughout the
/// app. Configuration/user-setting names live in `SettingKeys`,
/// SharedPreferences keys in `StorageKeys`, and route names in `Routes`.
class AppConstants {
  // Private constructor to prevent instantiation
  AppConstants._();

  // ======================
  // BUSINESS LOGIC LIMITS
  // ======================

  // Word management
  static const int maxWordLength = 100;
  static const int minWordLength = 1;
  static const int maxWordsPerPage = 50;

  // User input validation
  static const int minPasswordLength = 6;
  static const int maxPasswordLength = 128;
  static const int maxEmailLength = 254;

  // ======================
  // TIMING CONSTANTS
  // ======================

  // Session management
  static const int tokenRefreshThreshold = 300000; // 5 minutes before expiry

  // ======================
  // REGEX PATTERNS
  // ======================

  static const String emailRegex = r'^[\w+\-\.]+@([\w-]+\.)+[\w-]{2,4}$';
  static const String passwordRegex =
      r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)[a-zA-Z\d@$!%*?&]{6,}$';
  static const String wordRegex = r"^[\p{L}\s\-']+$";
}
