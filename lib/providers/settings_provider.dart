import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/storage/shared_prefs.dart';

/// 设置状态
class SettingsState {
  /// 是否暗黑模式
  final bool isDarkMode;

  /// 应用列表视图模式（'grid' 网格 / 'list' 列表）
  final String appListViewMode;

  /// 自动锁定时间（分钟，0=立即锁定）
  final int autoLockMinutes;

  /// 是否启用生物识别
  final bool isBiometricEnabled;

  const SettingsState({
    this.isDarkMode = false,
    this.appListViewMode = 'grid',
    this.autoLockMinutes = 1,
    this.isBiometricEnabled = false,
  });

  SettingsState copyWith({
    bool? isDarkMode,
    String? appListViewMode,
    int? autoLockMinutes,
    bool? isBiometricEnabled,
  }) {
    return SettingsState(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      appListViewMode: appListViewMode ?? this.appListViewMode,
      autoLockMinutes: autoLockMinutes ?? this.autoLockMinutes,
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
    // 异步加载设置（不等待，避免阻塞 UI）
    // 加载完成后会自动更新 state，触发 UI 重建
    _loadSettings();
    return const SettingsState();
  }

  /// 从 SharedPreferences 加载设置
  /// 注意：这是异步方法，加载完成后会更新 state
  Future<void> _loadSettings() async {
    final isDarkMode = await SharedPrefs.isDarkMode();
    final appListViewMode = await SharedPrefs.getAppListViewMode();
    final autoLockMinutes = await SharedPrefs.getAutoLockMinutes();
    final isBiometricEnabled = await SharedPrefs.isBiometricEnabled();

    state = state.copyWith(
      isDarkMode: isDarkMode,
      appListViewMode: appListViewMode,
      autoLockMinutes: autoLockMinutes,
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

  /// 设置自动锁定时间
  Future<void> setAutoLockMinutes(int minutes) async {
    await SharedPrefs.setAutoLockMinutes(minutes);
    state = state.copyWith(autoLockMinutes: minutes);
  }

  /// 切换生物识别开关
  Future<void> toggleBiometric(bool value) async {
    await SharedPrefs.setBiometricEnabled(value);
    state = state.copyWith(isBiometricEnabled: value);
  }
}