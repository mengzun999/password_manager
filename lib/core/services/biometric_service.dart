import 'package:local_auth/local_auth.dart';
import 'package:flutter/material.dart';

/// 生物识别服务类
/// 负责指纹、人脸等生物识别验证
class BiometricService {
  static final LocalAuthentication _localAuth = LocalAuthentication();

  /// 检查设备是否支持生物识别
  static Future<bool> isAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck || isSupported;
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

  /// 检查是否支持指纹（兼容新旧 Android）
  static Future<bool> hasFingerprint() async {
    try {
      final types = await getAvailableTypes();

      // Android 10+ 返回 strong（指纹），旧版返回 fingerprint
      if (types.contains(BiometricType.fingerprint)) return true;
      if (types.contains(BiometricType.strong)) return true;

      // 兜底：检查硬件支持
      return await isAvailable();
    } catch (e) {
      return false;
    }
  }

  /// 进行生物识别验证
  static Future<bool> authenticate({required String reason}) async {
    try {
      // ✅ 只使用 currentVersion 支持的参数
      final isAuthenticated = await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: true,  // 3.0.1 支持
        // stickyAuth 在 4.0.0 才支持，移除
      );
      return isAuthenticated;
    } catch (e) {
      print('Authentication error: $e');
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
        return '指纹识别';
      case BiometricType.weak:
        return '人脸识别';
      default:
        return '生物识别';
    }
  }

  /// 获取生物识别类型图标
  static IconData getTypeIcon(BiometricType type) {
    switch (type) {
      case BiometricType.face:
        return Icons.face;
      case BiometricType.fingerprint:
        return Icons.fingerprint;
      case BiometricType.iris:
        return Icons.visibility;
      case BiometricType.strong:
        return Icons.fingerprint;
      case BiometricType.weak:
        return Icons.face;
      default:
        return Icons.security;
    }
  }
}