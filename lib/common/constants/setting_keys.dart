/// Centralized constants for configuration and user-setting names
///
/// These strings are the `settingName` values used to look up server-stored user
/// settings via `UserSession().settings(key)`, and the keys of
/// `AppConfig._propertyAccessors`. They are distinct from `StorageKeys`, which
/// holds SharedPreferences keys.
class SettingKeys {
  // Private constructor to prevent instantiation
  SettingKeys._();

  static const String apiBaseUrl = 'apiBaseUrl';
  static const String pageSize = 'pageSize';
  static const String timezone = 'timezone';
  static const String quietErrorCode = 'quietErrorCode';
  static const String fontFamily = 'fontFamily';
  static const String isIOSWeb = 'isIOSWeb';
  static const String version = 'version';
  static const String debugging = 'debugging';
  static const String githubRepo = 'GITHUB_REPO';
}
