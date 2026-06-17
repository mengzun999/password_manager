import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';

/// 权限管理服务
/// 负责 Android 14+ 图片权限适配
class PermissionService {
  static final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  /// 检查是否已授予图片访问权限
  static Future<bool> hasImagePermission() async {
    if (!Platform.isAndroid) {
      return true;
    }

    final sdkInt = await _getAndroidSdkVersion();

    if (sdkInt >= 33) {
      // Android 13+ (API 33+) 使用 photos 权限
      final status = await Permission.photos.status;
      return status.isGranted;
    } else {
      // Android 12L 及以下 (API 32-) 使用 storage 权限
      final status = await Permission.storage.status;
      return status.isGranted;
    }
  }

  /// 请求图片访问权限
  static Future<bool> requestImagePermission() async {
    if (!Platform.isAndroid) {
      return true;
    }

    final sdkInt = await _getAndroidSdkVersion();

    if (sdkInt >= 33) {
      // Android 13+ (API 33+) 请求 photos 权限
      // 注意：Android 14 的 "部分访问" 由系统照片选择器自动处理
      // permission_handler 会在底层自动适配
      final status = await Permission.photos.request();
      return status.isGranted;
    } else {
      // Android 12L 及以下 (API 32-) 请求 storage 权限
      final status = await Permission.storage.request();
      return status.isGranted;
    }
  }

  /// 请求相机权限
  static Future<bool> requestCameraPermission() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  /// 获取 Android SDK 版本
  static Future<int> _getAndroidSdkVersion() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await _deviceInfo.androidInfo;
        return androidInfo.version.sdkInt;
      }
      return 0;
    } catch (e) {
      debugPrint('获取 Android SDK 版本失败: $e');
      return 0;
    }
  }
}