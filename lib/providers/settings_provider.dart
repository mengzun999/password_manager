import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/storage/shared_prefs.dart';

/// 设置状态
class SettingsState {
  /// 是否暗黑模式
  final bool isDarkMode;

  /// 应用列表视图模式（'grid' 网格 / 'list' 列表）
  final String appListViewMode;

  /// 是否启用生物识别
  final bool isBiometricEnabled;

  const SettingsState({
    this.isDarkMode = false,
    this.appListViewMode = 'grid',
    this.isBiometricEnabled = false,
  });

  SettingsState copyWith({
    bool? isDarkMode,
    String? appListViewMode,
    bool? isBiometricEnabled,
  }) {
    return SettingsState(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      appListViewMode: appListViewMode ?? this.appListViewMode,
      isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
    );
  }

  /// 获取 Flutter 主题模式
  ThemeMode get themeMode {
    if (isDarkMode) return ThemeMode.dark;
    return ThemeMode.light;
  }
}

/// 设置状态提供者
final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(() {
  return SettingsNotifier();
});

/// 设置提供者（管理应用设置）
class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    _loadSettings();
    return const SettingsState();
  }

  /// 从 SharedPreferences 加载设置
  Future<void> _loadSettings() async {
    final isDarkMode = await SharedPrefs.isDarkMode();
    final appListViewMode = await SharedPrefs.getAppListViewMode();
    final isBiometricEnabled = await SharedPrefs.isBiometricEnabled();

    state = state.copyWith(
      isDarkMode: isDarkMode,
      appListViewMode: appListViewMode,
      isBiometricEnabled: isBiometricEnabled,
    );
  }

  /// 切换暗黑模式
  Future<void> toggleDarkMode(bool value) async {
    await SharedPrefs.setDarkMode(value);
    state = state.copyWith(isDarkMode: value);
  }

  /// 设置应用列表视图模式
  Future<void> setAppListViewMode(String mode) async {
    await SharedPrefs.setAppListViewMode(mode);
    state = state.copyWith(appListViewMode: mode);
  }

  /// 切换生物识别开关
  Future<void> toggleBiometric(bool value) async {
    await SharedPrefs.setBiometricEnabled(value);
    state = state.copyWith(isBiometricEnabled: value);
  }
}