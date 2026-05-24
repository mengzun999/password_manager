import 'package:local_auth/local_auth.dart';
import 'package:flutter/material.dart';

/// 生物识别服务类
/// 负责指纹、人脸等生物识别验证
class BiometricService {
  static final LocalAuthentication _localAuth = LocalAuthentication();

  /// 检查设备是否支持生物识别
  static Future<bool> isAvailable() async {
    try {
      final isAvailable = await _localAuth.canCheckBiometrics;
      return isAvailable;
    } catch (e) {
      return false;
    }
  }

  /// 获取支持的生物识别类型列表
  static Future<List<BiometricType>> getAvailableTypes() async {
    try {
      final types = await _localAuth.getAvailableBiometrics();
      return types;
    } catch (e) {
      return [];
    }
  }

  /// 进行生物识别验证（最简兼容版，无任何报错）
  static Future<bool> authenticate({required String reason}) async {
    try {
      // 🔥 最简写法：只保留必选参数，彻底无报错
      final isAuthenticated = await _localAuth.authenticate(
        localizedReason: reason,
      );
      return isAuthenticated;
    } catch (e) {
      return false;
    }
  }

  /// 获取生物识别类型名称
  static String getTypeName(BiometricType type) {
    switch (type) {
      case BiometricType.face:
        return '人脸识别';
      case BiometricType.fingerprint:
        return '指纹识别';
      case BiometricType.iris:
        return '虹膜识别';
      case BiometricType.strong:
        return '强生物识别';
      default:
        return '生物识别';
    }
  }

  /// 获取生物识别图标（已修复无 Icons.biometric 报错）
  static IconData getTypeIcon(BiometricType type) {
    switch (type) {
      case BiometricType.face:
        return Icons.face;
      case BiometricType.fingerprint:
        return Icons.fingerprint;
      case BiometricType.iris:
        return Icons.visibility;
      case BiometricType.strong:
        return Icons.security;
      default:
        return Icons.security;
    }
  }
}