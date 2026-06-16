import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/app_constants.dart';

/// 普通配置存储类
class SharedPrefs {
  static SharedPreferences? _prefs;

  /// 初始化
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// 确保已初始化
  static Future<void> _ensureInitialized() async {
    if (_prefs == null) {
      await init();
    }
  }

  // ========== 生物识别开关 ==========
  static Future<void> setBiometricEnabled(bool enabled) async {
    await _ensureInitialized();
    await _prefs!.setBool(AppConstants.keyBiometricEnabled, enabled);
  }

  static Future<bool> isBiometricEnabled() async {
    await _ensureInitialized();
    return _prefs!.getBool(AppConstants.keyBiometricEnabled) ?? false;
  }

  // ========== 暗黑模式 ==========
  static Future<void> setDarkMode(bool isDark) async {
    await _ensureInitialized();
    await _prefs!.setBool(AppConstants.keyDarkMode, isDark);
  }

  static Future<bool> isDarkMode() async {
    await _ensureInitialized();
    return _prefs!.getBool(AppConstants.keyDarkMode) ?? false;
  }

  // ========== 应用列表视图模式 ==========
  static Future<void> setAppListViewMode(String mode) async {
    await _ensureInitialized();
    await _prefs!.setString(AppConstants.keyAppListViewMode, mode);
  }

  static Future<String> getAppListViewMode() async {
    await _ensureInitialized();
    return _prefs!.getString(AppConstants.keyAppListViewMode) ?? 'grid';
  }

  // ========== 手势图案是否已设置 ==========
  static Future<void> setHasGesture(bool has) async {
    await _ensureInitialized();
    await _prefs!.setBool(AppConstants.keyHasGesture, has);
  }

  static Future<bool> hasGesture() async {
    await _ensureInitialized();
    return _prefs!.getBool(AppConstants.keyHasGesture) ?? false;
  }
}