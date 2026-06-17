import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/providers/settings_provider.dart';
import 'constants/app_constants.dart';
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
      // title: AppConstants.appName,  // ❌ 注释掉
      theme: ThemeData.light(),
      darkTheme: ThemeData.dark(),
      themeMode: settingsState.themeMode,
      initialRoute: AppRoutes.unlock,
      onGenerateRoute: _generateRoute,
      debugShowCheckedModeBanner: false,
    );
  }

  Route<dynamic> _generateRoute(RouteSettings settings) {
    switch (settings.name) {
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
        if (args == null) {
          return MaterialPageRoute(builder: (_) => const AddEditPage());
        }
        if (args is PasswordEntry) {
          return MaterialPageRoute(builder: (_) => AddEditPage(entry: args));
        }
        if (args is String) {
          return MaterialPageRoute(builder: (_) => AddEditPage(presetTitle: args));
        }
        return MaterialPageRoute(builder: (_) => const AddEditPage());

      case AppRoutes.detail:
        final entryId = settings.arguments as String;
        return MaterialPageRoute(
          builder: (_) => PasswordDetailPage(entryId: entryId),
        );

      case AppRoutes.settings:
        return MaterialPageRoute(builder: (_) => const SettingsPage());

      default:
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text('页面不存在')),
          ),
        );
    }
  }
}