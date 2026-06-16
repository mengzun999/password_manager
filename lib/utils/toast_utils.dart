import 'package:flutter/material.dart';

/// 统一提示工具类
/// 封装 SnackBar 和 Dialog 的常用方法
class ToastUtils {
  /// 显示短提示（底部）
  static void showSnackBar(
      BuildContext context,
      String message, {
        Duration duration = const Duration(seconds: 2),
        SnackBarAction? action,
        Color? backgroundColor,
        bool showCloseIcon = false,
      }) {
    // 移除已有的 SnackBar，避免堆积
    ScaffoldMessenger.of(context).removeCurrentSnackBar();

    final snackBar = SnackBar(
      content: Text(
        message,
        style: const TextStyle(fontSize: 14),
      ),
      duration: duration,
      action: action,
      backgroundColor: backgroundColor,
      showCloseIcon: showCloseIcon,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      margin: const EdgeInsets.all(12),
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  /// 显示成功提示（绿色）
  static void showSuccess(
      BuildContext context,
      String message, {
        Duration duration = const Duration(seconds: 2),
      }) {
    showSnackBar(
      context,
      message,
      duration: duration,
      backgroundColor: Colors.green.shade700,
      showCloseIcon: true,
    );
  }

  /// 显示错误提示（红色）
  static void showError(
      BuildContext context,
      String message, {
        Duration duration = const Duration(seconds: 3),
      }) {
    showSnackBar(
      context,
      message,
      duration: duration,
      backgroundColor: Colors.red.shade700,
      showCloseIcon: true,
    );
  }

  /// 显示警告提示（橙色）
  static void showWarning(
      BuildContext context,
      String message, {
        Duration duration = const Duration(seconds: 3),
      }) {
    showSnackBar(
      context,
      message,
      duration: duration,
      backgroundColor: Colors.orange.shade700,
      showCloseIcon: true,
    );
  }

  /// 显示信息提示（蓝色）
  static void showInfo(
      BuildContext context,
      String message, {
        Duration duration = const Duration(seconds: 2),
      }) {
    showSnackBar(
      context,
      message,
      duration: duration,
      backgroundColor: Colors.blue.shade700,
      showCloseIcon: true,
    );
  }

  /// 显示确认对话框
  static Future<bool?> showConfirmDialog(
      BuildContext context, {
        required String title,
        required String content,
        String confirmText = '确定',
        String cancelText = '取消',
        Color? confirmColor,
        bool isDestructive = false,
      }) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        content: Text(
          content,
          style: const TextStyle(fontSize: 15),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              cancelText,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: isDestructive ? Colors.red : confirmColor,
            ),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  }

  /// 显示危险操作确认对话框（红色确认按钮）
  static Future<bool?> showDangerConfirmDialog(
      BuildContext context, {
        required String title,
        required String content,
        String confirmText = '删除',
        String cancelText = '取消',
      }) async {
    return showConfirmDialog(
      context,
      title: title,
      content: content,
      confirmText: confirmText,
      cancelText: cancelText,
      confirmColor: Colors.red,
      isDestructive: true,
    );
  }

  /// 显示加载对话框
  static Future<void> showLoadingDialog(
      BuildContext context, {
        String message = '加载中...',
      }) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 隐藏加载对话框
  static void hideLoadingDialog(BuildContext context) {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    }
  }

  /// 显示简单提示对话框
  static Future<void> showAlertDialog(
      BuildContext context, {
        required String title,
        required String content,
        String buttonText = '知道了',
        VoidCallback? onPressed,
      }) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        content: Text(
          content,
          style: const TextStyle(fontSize: 15),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onPressed?.call();
            },
            child: Text(buttonText),
          ),
        ],
      ),
    );
  }
}