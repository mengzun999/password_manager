import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'package:flutter/services.dart';
import 'core/storage/shared_prefs.dart';

/// 应用入口
/// Flutter 启动时第一个执行的文件
void main() async {
  // 确保 Flutter 绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );

  // 初始化 SharedPreferences
  await SharedPrefs.init();

  // 运行 App
  // ProviderScope 是 Riverpod 的根容器，必须在最外层
  runApp(const ProviderScope(child: MyApp()));
}

