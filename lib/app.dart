import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/providers/settings_provider.dart';
import 'core/models/password_entry.dart';
import 'pages/unlock/unlock_page.dart';
import 'pages/setup/setup_master_password_page.dart';
import 'pages/home/password_list_page.dart';
import 'pages/setup/setup_mnemonic_page.dart';
import 'pages/setup/setup_gesture_page.dart';
import 'pages/setup/setup_biometric_page.dart';
import 'pages/add_edit/add_edit_page.dart';
import 'pages/home/password_detail_page.dart';
import 'pages/settings/settings_page.dart';

class AppRoutes {
  static const String setup = '/setup';
  static const String setupMnemonic = '/setup/mnemonic';
  static const String setupGesture = '/setup/gesture';
  static const String setupBiometric = '/setup/biometric';
  static const String unlock = '/unlock';
  static const String home = '/home';
  static const String addEdit = '/add-edit';
  static const String detail = '/detail';
  static const String settings = '/settings';
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  @override
  Widget build(BuildContext context) {
    final settingsState = ref.watch(settingsProvider);

    return MaterialApp(
      title: '',  // ✅ 改为空字符串，状态栏不显示"密码管家"
      // title: AppConstants.appName,
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: settingsState.themeMode,
      initialRoute: AppRoutes.unlock,
      onGenerateRoute: _generateRoute,
      debugShowCheckedModeBanner: false,
    );
  }

  Route<dynamic> _generateRoute(RouteSettings settings) {
    Widget page;

    switch (settings.name) {
      case AppRoutes.setup:
        page = const SetupMasterPasswordPage();
        break;
      case AppRoutes.unlock:
        page = const UnlockPage();
        break;
      case AppRoutes.home:
        page = const PasswordListPage();
        break;
      case AppRoutes.setupMnemonic:
        page = const SetupMnemonicPage();
        break;
      case AppRoutes.setupGesture:
        page = const SetupGesturePage();
        break;
      case AppRoutes.setupBiometric:
        page = const SetupBiometricPage();
        break;
      case AppRoutes.addEdit:
        final args = settings.arguments;
        if (args == null) {
          page = const AddEditPage();
        } else if (args is PasswordEntry) {
          page = AddEditPage(entry: args);
        } else if (args is String) {
          page = AddEditPage(presetTitle: args);
        } else {
          page = const AddEditPage();
        }
        break;
      case AppRoutes.detail:
        final entry = settings.arguments as PasswordEntry;
        page = PasswordDetailPage(entry: entry);
        break;
      case AppRoutes.settings:
        page = const SettingsPage();
        break;
      default:
        page = const Scaffold(
          body: Center(child: Text('页面不存在')),
        );
    }

    // ✅ 移除 SafeArea，由每个页面自己控制
    return MaterialPageRoute(
      builder: (_) => page,
    );
  }
}