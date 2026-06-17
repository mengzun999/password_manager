import 'package:flutter/material.dart';

/// 密码生成器悬浮球组件
class PasswordGeneratorButton extends StatelessWidget {
  final VoidCallback onGenerate;
  final VoidCallback onClear;
  final bool isDark;

  const PasswordGeneratorButton({
    super.key,
    required this.onGenerate,
    required this.onClear,
    this.isDark = false,
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
          color: isDark ? Colors.purple.shade400 : Theme.of(context).primaryColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
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