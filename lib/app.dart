import 'package:flutter/material.dart';
import 'constants/app_constants.dart';
import 'pages/splash_page.dart';

/// 路由名称常量
/// 统一管理页面跳转用的名字，避免写错
class AppRoutes {
  static const String splash = '/';
  static const String setup = '/setup';
  static const String setupMnemonic = '/setup/mnemonic';
  static const String setupGesture = '/setup/gesture';
  static const String unlock = '/unlock';
  static const String home = '/home';
  static const String addEdit = '/add-edit';
  static const String detail = '/detail';
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConstants.appName,
      theme: ThemeData.light(),      // 亮色主题
      darkTheme: ThemeData.dark(),   // 暗色主题
      themeMode: ThemeMode.system,   // 跟随系统
      initialRoute: AppRoutes.splash, // 启动页
      onGenerateRoute: _generateRoute, // 路由生成器
      debugShowCheckedModeBanner: false, // 去掉右上角的 debug 标志
    );
  }

  /// 路由生成器
  /// 根据路由名称返回对应的页面
  static Route<dynamic> _generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case AppRoutes.splash:
        return MaterialPageRoute(builder: (_) => const SplashPage());

      case AppRoutes.setup:
      // 暂未实现，先占位
        return MaterialPageRoute(builder: (_) => const Scaffold(body: Center(child: Text('设置主密码页'))));

      case AppRoutes.unlock:
      // 暂未实现，先占位
        return MaterialPageRoute(builder: (_) => const Scaffold(body: Center(child: Text('解锁页'))));

      case AppRoutes.home:
      // 暂未实现，先占位
        return MaterialPageRoute(builder: (_) => const Scaffold(body: Center(child: Text('密码列表页'))));

      default:
      // 404 页面
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text('页面不存在')),
          ),
        );
    }
  }
}