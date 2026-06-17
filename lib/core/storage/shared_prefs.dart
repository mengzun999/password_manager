import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import '../../constants/app_constants.dart';

class SharedPrefs {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  static Future<void> _ensureInitialized() async {
    if (_prefs == null) {
      await init();
    }
  }

  /// ✅ 获取 SharedPreferences 实例（供外部直接使用，如保存 FAB 位置）
  static Future<SharedPreferences> getPrefs() async {
    if (_prefs == null) {
      await init();
    }
    return _prefs!;
  }

  // ========== 生物识别开关 ==========
  static Future<void> setBiometricEnabled(bool enabled) async {
    await _ensureInitialized();
    await _prefs!.setBool(AppConstants.keyBiometricEnabled, enabled);
  }

  // ========== 暗黑模式跟随系统 ==========
  static Future<void> setDarkModeFollowSystem(bool follow) async {
    await _ensureInitialized();
    await _prefs!.setBool(AppConstants.keyDarkModeFollowSystem, follow);
  }

  static Future<bool> isDarkModeFollowSystem() async {
    await _ensureInitialized();
    return _prefs!.getBool(AppConstants.keyDarkModeFollowSystem) ?? false;
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

  // ========== 手势图案是否已设置 ==========
  static Future<void> setHasGesture(bool has) async {
    await _ensureInitialized();
    await _prefs!.setBool(AppConstants.keyHasGesture, has);
  }

  static Future<bool> hasGesture() async {
    await _ensureInitialized();
    return _prefs!.getBool(AppConstants.keyHasGesture) ?? false;
  }

  // ========== ✅ FAB 位置 ==========
  static const String _keyFabDx = 'fab_position_dx';
  static const String _keyFabDy = 'fab_position_dy';

  static Future<void> saveFabPosition(double dx, double dy) async {
    final prefs = await getPrefs();
    await prefs.setDouble(_keyFabDx, dx);
    await prefs.setDouble(_keyFabDy, dy);
  }

  static Future<Offset?> getFabPosition() async {
    final prefs = await getPrefs();
    final dx = prefs.getDouble(_keyFabDx);
    final dy = prefs.getDouble(_keyFabDy);
    if (dx != null && dy != null) {
      return Offset(dx, dy);
    }
    return null;
  }
}