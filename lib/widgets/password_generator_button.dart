import 'package:flutter/material.dart';

/// 密码生成器悬浮球组件
///
/// 单击生成随机密码，长按清空密码框
class PasswordGeneratorButton extends StatelessWidget {
  /// 生成密码的回调
  final VoidCallback onGenerate;

  /// 清空密码的回调
  final VoidCallback onClear;

  const PasswordGeneratorButton({
    super.key,
    required this.onGenerate,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onGenerate,
      onLongPress: onClear,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: Theme.of(context).primaryColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Icon(
          Icons.auto_awesome,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }
}