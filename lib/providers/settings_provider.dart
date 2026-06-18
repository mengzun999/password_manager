import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/storage/shared_prefs.dart';

class SettingsState {
  final bool isDarkMode;
  final bool isBiometricEnabled;
  final bool darkModeFollowSystem;
  final bool isLoading;

  // ✅ 背景图相关
  final bool backgroundEnabled;
  final String? backgroundImagePath;
  final int backgroundOpacity;  // 0-100
  final int backgroundBlur;     // 0-30
  final int textColor;          // ARGB int

  const SettingsState({
    this.isDarkMode = false,
    this.isBiometricEnabled = false,
    this.darkModeFollowSystem = false,
    this.isLoading = true,
    this.backgroundEnabled = false,
    this.backgroundImagePath,
    this.backgroundOpacity = 30,
    this.backgroundBlur = 10,
    this.textColor = 0xFF000000,  // ✅ 改为黑色（默认）
  });

  SettingsState copyWith({
    bool? isDarkMode,
    bool? isBiometricEnabled,
    bool? darkModeFollowSystem,
    bool? isLoading,
    bool? backgroundEnabled,
    String? backgroundImagePath,
    int? backgroundOpacity,
    int? backgroundBlur,
    int? textColor,
  }) {
    return SettingsState(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
      darkModeFollowSystem: darkModeFollowSystem ?? this.darkModeFollowSystem,
      isLoading: isLoading ?? this.isLoading,
      backgroundEnabled: backgroundEnabled ?? this.backgroundEnabled,
      backgroundImagePath: backgroundImagePath ?? this.backgroundImagePath,
      backgroundOpacity: backgroundOpacity ?? this.backgroundOpacity,
      backgroundBlur: backgroundBlur ?? this.backgroundBlur,
      textColor: textColor ?? this.textColor,
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

    state = state.copyWith(
      isDarkMode: isDarkMode,
      isBiometricEnabled: isBiometricEnabled,
      darkModeFollowSystem: darkModeFollowSystem,
      isLoading: false,
      backgroundEnabled: backgroundEnabled,
      backgroundImagePath: backgroundImagePath,
      backgroundOpacity: backgroundOpacity,
      backgroundBlur: backgroundBlur,
      textColor: textColor,
    );
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
      textColor: 0xFF000000,  // ✅ 恢复默认黑色
    );
  }
}