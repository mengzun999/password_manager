import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';

/// 带背景图的 Scaffold 组件
///
/// 支持全屏背景图、模糊效果、透明度调节、暗色模式适配
class BackgroundScaffold extends StatelessWidget {
  /// 背景图路径（本地文件路径）
  final String? backgroundImagePath;

  /// 背景模糊度 (0-30)
  final int backgroundBlur;

  /// 背景遮罩透明度 (0.0-1.0)
  final double overlayOpacity;

  /// 是否暗色模式
  final bool isDarkMode;

  /// AppBar
  final PreferredSizeWidget? appBar;

  /// 主体内容
  final Widget body;

  /// 是否允许 body 延伸到 AppBar 后面
  final bool extendBodyBehindAppBar;

  /// 背景图未显示时的背景色
  final Color? backgroundColor;

  const BackgroundScaffold({
    super.key,
    this.backgroundImagePath,
    this.backgroundBlur = 10,
    this.overlayOpacity = 0.3,
    required this.isDarkMode,
    this.appBar,
    required this.body,
    this.extendBodyBehindAppBar = true,
    this.backgroundColor,
  });

  /// 是否显示背景图
  bool get showBackground =>
      backgroundImagePath != null && backgroundImagePath!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      backgroundColor: backgroundColor ??
          (isDarkMode ? Colors.grey.shade900 : Colors.grey.shade100),
      appBar: appBar,
      body: Stack(
        children: [
          // ✅ 背景图
          if (showBackground)
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: backgroundBlur.toDouble(),
                  sigmaY: backgroundBlur.toDouble(),
                ),
                child: Image.file(
                  File(backgroundImagePath!),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),

          // ✅ 背景遮罩
          if (showBackground)
            Positioned.fill(
              child: Container(
                color: Colors.white.withValues(alpha: overlayOpacity),
              ),
            ),

          // ✅ 主体内容
          body,
        ],
      ),
    );
  }
}