import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/storage/shared_prefs.dart';

class SettingsState {
  final bool isDarkMode;
  final bool isBiometricEnabled;
  final bool darkModeFollowSystem;
  final bool isLoading;  // ✅ 新增

  const SettingsState({
    this.isDarkMode = false,
    this.isBiometricEnabled = false,
    this.darkModeFollowSystem = false,
    this.isLoading = true,  // ✅ 默认加载中
  });

  SettingsState copyWith({
    bool? isDarkMode,
    bool? isBiometricEnabled,
    bool? darkModeFollowSystem,
    bool? isLoading,
  }) {
    return SettingsState(
      isDarkMode: isDarkMode ?? this.isDarkMode,
      isBiometricEnabled: isBiometricEnabled ?? this.isBiometricEnabled,
      darkModeFollowSystem: darkModeFollowSystem ?? this.darkModeFollowSystem,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  ThemeMode get themeMode {
    if (darkModeFollowSystem) return ThemeMode.system;
    if (isDarkMode) return ThemeMode.dark;
    return ThemeMode.light;
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(() {
  return SettingsNotifier();
});

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    _loadSettingsAsync();
    return const SettingsState();  // isLoading = true
  }

  void _loadSettingsAsync() {
    Future.microtask(() => _loadSettings());
  }

  Future<void> _loadSettings() async {
    final isDarkMode = await SharedPrefs.isDarkMode();
    final isBiometricEnabled = await SharedPrefs.isBiometricEnabled();
    final darkModeFollowSystem = await SharedPrefs.isDarkModeFollowSystem();

    state = state.copyWith(
      isDarkMode: isDarkMode,
      isBiometricEnabled: isBiometricEnabled,
      darkModeFollowSystem: darkModeFollowSystem,
      isLoading: false,  // ✅ 加载完成
    );
  }

  Future<void> toggleDarkMode(bool value) async {
    // ✅ 如果开启跟随系统，切换时关闭跟随系统
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
    // ✅ 如果开启跟随系统，覆盖手动设置
    if (value) {
      // 跟随系统时，手动设置的值被覆盖，但保留以便切换回来时恢复
    }
  }


  Future<void> toggleBiometric(bool value) async {
    await SharedPrefs.setBiometricEnabled(value);
    state = state.copyWith(isBiometricEnabled: value);
  }
}