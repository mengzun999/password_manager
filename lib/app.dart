import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/constants/app_constants.dart';
import 'package:password_manager/providers/settings_provider.dart';
import 'core/models/password_entry.dart';
import 'pages/splash_page.dart';
import 'pages/unlock/unlock_page.dart';
import 'pages/setup/setup_master_password_page.dart';
import 'pages/home/password_list_page.dart';
import 'pages/setup/setup_mnemonic_page.dart';
import 'pages/setup/setup_gesture_page.dart';
import 'pages/setup/setup_biometric_page.dart';
import 'pages/add_edit/add_edit_page.dart';
import 'pages/home/password_detail_page.dart';
import 'pages/settings/settings_page.dart';
import 'pages/app_list_page.dart';

/// 路由名称常量
/// 统一管理页面跳转用的名字，避免写错
class AppRoutes {
  static const String splash = '/';
  static const String setup = '/setup';
  static const String setupMnemonic = '/setup/mnemonic';
  static const String setupGesture = '/setup/gesture';
  static const String setupBiometric = '/setup/biometric';
  static const String unlock = '/unlock';
  static const String home = '/home';
  static const String addEdit = '/add-edit';
  static const String detail = '/detail';
  static const String appList = '/app-list';
  static const String settings = '/settings';
}

class MyApp extends ConsumerWidget {  // 改为 ConsumerWidget
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 监听设置状态，当主题改变时自动重建
    final settingsState = ref.watch(settingsProvider);

    return MaterialApp(
      title: AppConstants.appName,
      theme: ThemeData.light(),      // 亮色主题
      darkTheme: ThemeData.dark(),   // 暗色主题
      themeMode: settingsState.themeMode,  // 从 provider 读取主题模式
      initialRoute: AppRoutes.splash,
      onGenerateRoute: _generateRoute,
      debugShowCheckedModeBanner: false,
    );
  }

  /// 路由生成器
  /// 根据路由名称返回对应的页面
  Route<dynamic> _generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.splash:
        return MaterialPageRoute(builder: (_) => const SplashPage());

      case AppRoutes.setup:
        return MaterialPageRoute(builder: (_) => const SetupMasterPasswordPage());

      case AppRoutes.unlock:
        return MaterialPageRoute(builder: (_) => const UnlockPage());

      case AppRoutes.home:
        return MaterialPageRoute(builder: (_) => const PasswordListPage());

      case AppRoutes.setupMnemonic:
        return MaterialPageRoute(builder: (_) => const SetupMnemonicPage());

      case AppRoutes.setupGesture:
        return MaterialPageRoute(builder: (_) => const SetupGesturePage());

      case AppRoutes.setupBiometric:
        return MaterialPageRoute(builder: (_) => const SetupBiometricPage());

      case AppRoutes.addEdit:
        final args = settings.arguments;
        if (args is PasswordEntry) {
          return MaterialPageRoute(builder: (_) => AddEditPage(entry: args));
        } else if (args is String) {
          return MaterialPageRoute(builder: (_) => AddEditPage(presetTitle: args));
        } else {
          return MaterialPageRoute(builder: (_) => const AddEditPage());
        }

      case AppRoutes.detail:
        final entryId = settings.arguments as String;
        return MaterialPageRoute(
          builder: (_) => PasswordDetailPage(entryId: entryId),
        );

      case AppRoutes.settings:
        return MaterialPageRoute(builder: (_) => const SettingsPage());

      case AppRoutes.appList:
        return MaterialPageRoute(builder: (_) => const AppListPage());

      default:
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text('页面不存在')),
          ),
        );
    }
  }
}