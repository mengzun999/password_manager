import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';

/// 应用入口
/// Flutter 启动时第一个执行的文件
void main() async {
  // 确保 Flutter 绑定初始化
  // 如果不加这一行，调用某些原生 API 会报错
  WidgetsFlutterBinding.ensureInitialized();

  // 运行 App
  // ProviderScope 是 Riverpod 的根容器，必须在最外层
  runApp(const ProviderScope(child: MyApp()));
}