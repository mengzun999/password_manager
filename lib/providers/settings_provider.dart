import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/app_constants.dart';
import '../core/storage/shared_prefs.dart';
import '../core/services/biometric_service.dart';

class SettingsState {
  final bool isDarkMode;
  final bool isBiometricEnabled;
  final bool darkModeFollowSystem;
  final bool isLoading;

  // ✅ 生物识别可用状态（新增）
  final bool isBiometricAvailable;

  // ✅ 背景图相关
  final bool backgroundEnabled;
  final String? backgroundImagePath;
  final int backgroundOpacity;  // 0-100
  final int backgroundBlur;     // 0-30
  final int textColor;          // ARGB int

  // ✅ 图片压缩档位 (0=原图, 1=高, 2=中)
  final int imageCompressLevel;

  const SettingsState({
    this.isDarkMode = false,
    this.isBiometricEnabled = false,
    this.darkModeFollowSystem = false,
    this.isLoading = true,
    this.isBiometricAvailable = false, // ✅ 新增
    this.backgroundEnabled = false,
    this.backgroundImagePath,
    this.backgroundOpacity = 30,
    this.backgroundBlur = 10,
    this.textColor = 0xFF000000,
    this.imageCompressLevel = AppConstants.compressLevelMedium,
  });

  SettingsState copyWith({
    bool? isDarkMode,
    bool? isBiometricEnabled,
    bool? darkModeFollowSystem,
    bool? isLoading,
    bool? isBiometricAvailable, // ✅ 新增
    bool? backgroundEnabled,
    String? backgroundImagePath,
    int? backgroundOpacity,
    int? backgroundBlur,
    int? textColor,
    int? imageCompressLevel,
  }) {
    return SettingsState(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
      darkModeFollowSystem: darkModeFollowSystem ?? this.darkModeFollowSystem,
      isLoading: isLoading ?? this.isLoading,
      isBiometricAvailable: isBiometricAvailable ?? this.isBiometricAvailable, // ✅ 新增
      backgroundEnabled: backgroundEnabled ?? this.backgroundEnabled,
      backgroundImagePath: backgroundImagePath ?? this.backgroundImagePath,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      backgroundBlur: backgroundBlur ?? this.backgroundBlur,
      textColor: textColor ?? this.textColor,
      imageCompressLevel: imageCompressLevel ?? this.imageCompressLevel,
    );
  }

  ThemeMode get themeMode {
    if (darkModeFollowSystem) return ThemeMode.system;
    if (isDarkMode) return ThemeMode.dark;
    return ThemeMode.light;
  }

  Color get cardBackgroundColor {
    final baseColor = isDarkMode ? Colors.grey.shade900 : Colors.white;
    final opacity = backgroundOpacity / 100;
    return baseColor.withValues(alpha: opacity);
  }

  Color get textColorValue {
    return Color(textColor);
  }

  // ✅ 是否显示背景图（开关打开 + 有图片路径 + 亮色模式）
  bool get showBackground {
    return backgroundEnabled && backgroundImagePath != null && backgroundImagePath!.isNotEmpty;
  }

  // ✅ 是否有背景图（兼容旧逻辑）
  bool get hasBackgroundImage {
    return backgroundImagePath != null && backgroundImagePath!.isNotEmpty;
  }

  // ✅ 获取当前压缩质量值
  int get compressQuality {
    switch (imageCompressLevel) {
      case AppConstants.compressLevelOriginal:
        return 100;
      case AppConstants.compressLevelHigh:
        return AppConstants.compressQualityHigh;
      case AppConstants.compressLevelMedium:
        return AppConstants.compressQualityMedium;
      default:
        return AppConstants.compressQualityMedium;
    }
  }

  // ✅ 是否压缩（原图档位返回 false）
  bool get shouldCompress {
    return imageCompressLevel != AppConstants.compressLevelOriginal;
  }

  // ✅ 获取档位名称
  String get compressLevelName {
    switch (imageCompressLevel) {
      case AppConstants.compressLevelOriginal:
        return AppConstants.compressLevelNameOriginal;
      case AppConstants.compressLevelHigh:
        return AppConstants.compressLevelNameHigh;
      case AppConstants.compressLevelMedium:
        return AppConstants.compressLevelNameMedium;
      default:
        return AppConstants.compressLevelNameMedium;
    }
  }

  // ✅ 获取档位副标题
  String get compressLevelSubtitle {
    switch (imageCompressLevel) {
      case AppConstants.compressLevelOriginal:
        return AppConstants.compressLevelSubtitleOriginal;
      case AppConstants.compressLevelHigh:
        return AppConstants.compressLevelSubtitleHigh;
      case AppConstants.compressLevelMedium:
        return AppConstants.compressLevelSubtitleMedium;
      default:
        return AppConstants.compressLevelSubtitleMedium;
    }
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(() {
  return SettingsNotifier();
});

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    _loadSettingsAsync();
    return const SettingsState();
  }

  void _loadSettingsAsync() {
    Future.microtask(() => _loadSettings());
  }

  Future<void> _loadSettings() async {
    final isDarkMode = await SharedPrefs.isDarkMode();
    final isBiometricEnabled = await SharedPrefs.isBiometricEnabled();
    final darkModeFollowSystem = await SharedPrefs.isDarkModeFollowSystem();
    final backgroundEnabled = await SharedPrefs.isBackgroundEnabled();
    final backgroundImagePath = await SharedPrefs.getBackgroundImagePath();
    final backgroundOpacity = await SharedPrefs.getBackgroundOpacity();
    final backgroundBlur = await SharedPrefs.getBackgroundBlur();
    final textColor = await SharedPrefs.getTextColor();
    final imageCompressLevel = await SharedPrefs.getImageCompressLevel();

    // ✅ 从缓存读取生物识别可用状态
    final hasCache = await SharedPrefs.hasCachedBiometricData();
    bool isBiometricAvailable = false;

    if (hasCache) {
      isBiometricAvailable = await SharedPrefs.getCachedBiometricAvailability();
    } else {
      // 没有缓存则异步检测（不阻塞 UI）
      _cacheBiometricStatus();
    }

    state = state.copyWith(
      isDarkMode: isDarkMode,
      isBiometricEnabled: isBiometricEnabled,
      darkModeFollowSystem: darkModeFollowSystem,
      isLoading: false,
      isBiometricAvailable: isBiometricAvailable, // ✅
      backgroundEnabled: backgroundEnabled,
      backgroundImagePath: backgroundImagePath,
      backgroundOpacity: backgroundOpacity,
      backgroundBlur: backgroundBlur,
      textColor: textColor,
      imageCompressLevel: imageCompressLevel,
    );
  }

  /// ✅ 异步检测生物识别并缓存（不阻塞 UI）
  Future<void> _cacheBiometricStatus() async {
    final isAvailable = await BiometricService.isAvailable();
    await SharedPrefs.cacheBiometricAvailability(isAvailable);

    if (isAvailable) {
      final types = await BiometricService.getAvailableTypes();
      final typeNames = types.map((e) => e.toString()).toList();
      await SharedPrefs.cacheBiometricTypes(typeNames);
    }

    // 更新状态
    state = state.copyWith(isBiometricAvailable: isAvailable);
  }

  /// ✅ 刷新生物识别状态（当用户从设置页返回时调用）
  Future<void> refreshBiometricStatus() async {
    final isAvailable = await BiometricService.refreshAvailability();
    state = state.copyWith(isBiometricAvailable: isAvailable);
  }

  Future<void> toggleDarkMode(bool value) async {
    if (state.darkModeFollowSystem) {
      await SharedPrefs.setDarkModeFollowSystem(false);
      state = state.copyWith(darkModeFollowSystem: false);
    }
    await SharedPrefs.setDarkMode(value);
    state = state.copyWith(isDarkMode: value);
  }

  Future<void> toggleDarkModeFollowSystem(bool value) async {
    await SharedPrefs.setDarkModeFollowSystem(value);
    state = state.copyWith(darkModeFollowSystem: value);
  }

  Future<void> toggleBiometric(bool value) async {
    await SharedPrefs.setBiometricEnabled(value);
    state = state.copyWith(isBiometricEnabled: value);
  }

  // ========== ✅ 背景图相关方法 ==========

  /// 设置背景图开关
  Future<void> setBackgroundEnabled(bool value) async {
    await SharedPrefs.setBackgroundEnabled(value);
    state = state.copyWith(backgroundEnabled: value);
  }

  /// 设置背景图
  Future<void> setBackgroundImage(String? path) async {
    await SharedPrefs.setBackgroundImagePath(path);
    state = state.copyWith(backgroundImagePath: path);
  }

  /// 设置卡片透明度
  Future<void> setBackgroundOpacity(int value) async {
    await SharedPrefs.setBackgroundOpacity(value);
    state = state.copyWith(backgroundOpacity: value);
  }

  /// 设置背景模糊度
  Future<void> setBackgroundBlur(int value) async {
    await SharedPrefs.setBackgroundBlur(value);
    state = state.copyWith(backgroundBlur: value);
  }

  /// 设置文字颜色
  Future<void> setTextColor(int color) async {
    await SharedPrefs.setTextColor(color);
    state = state.copyWith(textColor: color);
  }

  /// 恢复默认
  Future<void> resetBackgroundSettings() async {
    await SharedPrefs.resetBackgroundSettings();
    state = state.copyWith(
      backgroundEnabled: false,
      backgroundImagePath: null,
      backgroundOpacity: 30,
      backgroundBlur: 10,
      textColor: 0xFF000000,
    );
  }

  // ========== ✅ 图片压缩相关方法 ==========

  /// 设置压缩档位
  Future<void> setImageCompressLevel(int level) async {
    await SharedPrefs.setImageCompressLevel(level);
    state = state.copyWith(imageCompressLevel: level);
  }
}