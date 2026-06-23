import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'package:flutter/services.dart';
import 'core/storage/shared_prefs.dart';
import 'core/services/biometric_service.dart';

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
/// ✅ 后台预缓存生物识别状态
void _preCacheBiometricStatus() {
  // 使用 Future.microtask 避免阻塞主线程
  Future.microtask(() async {
    try {
      // 检查是否已有缓存
      final hasCache = await SharedPrefs.hasCachedBiometricData();
      if (hasCache) {
        // 已有缓存，检查缓存是否过期（可选：24小时后刷新）
        // 这里简单判断，如果有缓存就不再检测
        return;
      }

      // 没有缓存则检测并保存
      final isAvailable = await BiometricService.isAvailable();
      await SharedPrefs.cacheBiometricAvailability(isAvailable);

      if (isAvailable) {
        final types = await BiometricService.getAvailableTypes();
        final typeNames = types.map((e) => e.toString()).toList();
        await SharedPrefs.cacheBiometricTypes(typeNames);
      }
    } catch (e) {
      // 静默失败，不影响应用启动
      debugPrint('预缓存生物识别状态失败: $e');
    }
  });
}
