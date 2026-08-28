/// Centralized constants for SharedPreferences keys
/// 
/// This class contains all the keys used for storing data in SharedPreferences
/// to eliminate magic strings throughout the codebase and ensure consistency.
class StorageKeys {
  // Private constructor to prevent instantiation
  StorageKeys._();

  // Authentication related keys
  static const String accessToken = 'accessToken';
  static const String baseUrl = 'baseUrl';
  static const String userEmail = 'user_email';
  
  // User language preferences
  static const String userNativeLanguage = 'user_native_language';
  static const String userLearningLanguage = 'user_learning_language';
  
  // Feature-specific keys
  static const String lastAddWordShownTime = 'last_add_word_shown_time';
  
  // UI/UX preferences
  static const String selectedLocale = 'selected_locale';
  static const String storyPlaybackRate = 'story_playback_rate';
  static const String ttsVoiceName = 'tts_voice_name';
  static const String ttsVoiceLocale = 'tts_voice_locale';
  static const String themeMode = 'theme_mode';
  static const String isFirstLaunch = 'is_first_launch';
  
  // App settings
  static const String notificationsEnabled = 'notifications_enabled';
  static const String autoBackupEnabled = 'auto_backup_enabled';
  static const String offlineMode = 'offline_mode';
  
  // Cache keys
  static const String lastSyncTimestamp = 'last_sync_timestamp';
  static const String cachedUserData = 'cached_user_data';
  
  /// Get all storage keys as a set for validation purposes
  static Set<String> get allKeys => {
    accessToken,
    baseUrl,
    userEmail,
    userNativeLanguage,
    userLearningLanguage,
    lastAddWordShownTime,
    selectedLocale,
    storyPlaybackRate,
    ttsVoiceName,
    ttsVoiceLocale,
    themeMode,
    isFirstLaunch,
    notificationsEnabled,
    autoBackupEnabled,
    offlineMode,
    lastSyncTimestamp,
    cachedUserData,
  };
  
  /// Validate that a key exists in the defined constants
  static bool isValidKey(String key) {
    return allKeys.contains(key);
  }
  
  /// Get keys grouped by category for better organization
  static Map<String, Set<String>> get keysByCategory => {
    'authentication': {
      accessToken,
      baseUrl,
      userEmail,
    },
    'user_preferences': {
      userNativeLanguage,
      userLearningLanguage,
      selectedLocale,
      storyPlaybackRate,
      ttsVoiceName,
      ttsVoiceLocale,
      themeMode,
    },
    'app_state': {
      isFirstLaunch,
      lastAddWordShownTime,
      lastSyncTimestamp,
    },
    'settings': {
      notificationsEnabled,
      autoBackupEnabled,
      offlineMode,
    },
    'cache': {
      cachedUserData,
    },
  };
}