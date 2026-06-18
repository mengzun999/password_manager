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

// ========== ✅ 背景图相关 ==========

  /// 保存背景图开关状态
  static Future<void> setBackgroundEnabled(bool enabled) async {
    await _ensureInitialized();
    await _prefs!.setBool('background_enabled', enabled);
  }

  /// 获取背景图开关状态
  static Future<bool> isBackgroundEnabled() async {
    await _ensureInitialized();
    return _prefs!.getBool('background_enabled') ?? false;
  }

  /// 保存背景图路径
  static Future<void> setBackgroundImagePath(String? path) async {
    await _ensureInitialized();
    if (path == null) {
      await _prefs!.remove(AppConstants.keyBackgroundImagePath);
    } else {
      await _prefs!.setString(AppConstants.keyBackgroundImagePath, path);
    }
  }

  /// 获取背景图路径
  static Future<String?> getBackgroundImagePath() async {
    await _ensureInitialized();
    return _prefs!.getString(AppConstants.keyBackgroundImagePath);
  }

  /// 保存卡片透明度 (0-100)
  static Future<void> setBackgroundOpacity(int value) async {
    await _ensureInitialized();
    await _prefs!.setInt(AppConstants.keyBackgroundOpacity, value.clamp(0, 100));
  }

  /// 获取卡片透明度
  static Future<int> getBackgroundOpacity() async {
    await _ensureInitialized();
    return _prefs!.getInt(AppConstants.keyBackgroundOpacity) ?? 30;
  }

  /// 保存背景模糊度 (0-30)
  static Future<void> setBackgroundBlur(int value) async {
    await _ensureInitialized();
    await _prefs!.setInt(AppConstants.keyBackgroundBlur, value.clamp(0, 30));
  }

  /// 获取背景模糊度
  static Future<int> getBackgroundBlur() async {
    await _ensureInitialized();
    return _prefs!.getInt(AppConstants.keyBackgroundBlur) ?? 10;
  }

  /// 保存文字颜色 (ARGB int)
  static Future<void> setTextColor(int color) async {
    await _ensureInitialized();
    await _prefs!.setInt(AppConstants.keyTextColor, color);
  }

  /// 获取文字颜色
  static Future<int> getTextColor() async {
    await _ensureInitialized();
    return _prefs!.getInt(AppConstants.keyTextColor) ?? 0xFF000000;
  }

  /// 检查是否有背景图
  static Future<bool> hasBackgroundImage() async {
    final path = await getBackgroundImagePath();
    return path != null && path.isNotEmpty;
  }

  /// 清除所有背景图设置（恢复默认）
  static Future<void> resetBackgroundSettings() async {
    await _ensureInitialized();
    await _prefs!.remove('background_enabled');
    await _prefs!.remove(AppConstants.keyBackgroundImagePath);
    await _prefs!.remove(AppConstants.keyBackgroundOpacity);
    await _prefs!.remove(AppConstants.keyBackgroundBlur);
    await _prefs!.remove(AppConstants.keyTextColor);
  }

  // ========== ✅ 图片压缩相关 ==========

  /// 保存压缩档位 (0=原图, 1=高, 2=中)
  static Future<void> setImageCompressLevel(int level) async {
    await _ensureInitialized();
    await _prefs!.setInt(AppConstants.keyImageCompressLevel, level.clamp(0, 2));
  }

  /// 获取压缩档位，默认中(2)
  static Future<int> getImageCompressLevel() async {
    await _ensureInitialized();
    return _prefs!.getInt(AppConstants.keyImageCompressLevel) ??
        AppConstants.compressLevelMedium;
  }
}