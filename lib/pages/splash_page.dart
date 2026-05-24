import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/app.dart';
import 'package:password_manager/constants/app_constants.dart';
import 'package:password_manager/providers/auth_provider.dart';

/// 启动页
/// 显示加载动画，同时检查是否已初始化
/// 根据状态跳转到设置页或解锁页
class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage> {
  @override
  void initState() {
    super.initState();
    _checkAndNavigate();
  }

  /// 检查初始化状态并跳转
  Future<void> _checkAndNavigate() async {
    // 获取 AuthProvider 并调用 checkInitialized
    final authNotifier = ref.read(authProvider.notifier);
    await authNotifier.checkInitialized();

    // 获取当前状态
    final authState = ref.read(authProvider);
    final isInitialized = authState.isInitialized;

    // 延迟一小段时间，让用户看到启动页（可选）
    await Future.delayed(const Duration(milliseconds: 100));

    if (mounted) {
      if (isInitialized) {
        // 已初始化，跳转到解锁页
        Navigator.pushReplacementNamed(context, AppRoutes.unlock);
      } else {
        // 未初始化，跳转到设置主密码页
        Navigator.pushReplacementNamed(context, AppRoutes.setup);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              AppConstants.appName,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        )
      ),
    );
  }
}