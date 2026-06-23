// core/services/biometric_service.dart

import 'package:local_auth/local_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../storage/shared_prefs.dart';

/// 生物识别服务类
/// 负责指纹、人脸等生物识别验证
class BiometricService {
  static final LocalAuthentication _localAuth = LocalAuthentication();

  /// ✅ 检查设备是否支持生物识别（硬件支持）
  static Future<bool> isHardwareAvailable() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (e) {
      return false;
    }
  }

  /// ✅ 检查是否已录入生物识别信息（指纹/人脸已注册）
  static Future<bool> isBiometricEnrolled() async {
    try {
      final types = await _localAuth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// ✅ 综合判断：硬件支持 且 已录入指纹/人脸
  static Future<bool> isAvailable() async {
    try {
      final hardwareOk = await isHardwareAvailable();
      if (!hardwareOk) return false;

      final types = await _localAuth.getAvailableBiometrics();
      return types.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  /// ✅ 获取生物识别可用状态（优先从缓存读取）
  static Future<bool> getAvailableWithCache() async {
    // 1. 先检查缓存
    final hasCache = await SharedPrefs.hasCachedBiometricData();
    if (hasCache) {
      return await SharedPrefs.getCachedBiometricAvailability();
    }

    // 2. 没有缓存则检测并缓存
    final available = await isAvailable(); // ✅ 修复：使用不同的变量名
    await SharedPrefs.cacheBiometricAvailability(available);

    if (available) {
      final types = await _localAuth.getAvailableBiometrics();
      final typeNames = types.map((e) => e.toString()).toList();
      await SharedPrefs.cacheBiometricTypes(typeNames);
    }

    return available;
  }

  /// ✅ 强制刷新生物识别状态（当用户修改了系统指纹设置后调用）
  static Future<bool> refreshAvailability() async {
    final available = await isAvailable(); // ✅ 修复：使用不同的变量名
    await SharedPrefs.cacheBiometricAvailability(available);

    if (available) {
      final types = await _localAuth.getAvailableBiometrics();
      final typeNames = types.map((e) => e.toString()).toList();
      await SharedPrefs.cacheBiometricTypes(typeNames);
    } else {
      await SharedPrefs.clearBiometricCache();
    }

    return available;
  }

  /// 获取支持的生物识别类型列表（仅返回已录入的）
  static Future<List<BiometricType>> getAvailableTypes() async {
    try {
      final types = await _localAuth.getAvailableBiometrics();
      return types;
    } catch (e) {
      return [];
    }
  }

  /// ✅ 检查是否支持指纹（硬件支持 且 已录入指纹）
  static Future<bool> hasFingerprint() async {
    try {
      final hardwareOk = await isHardwareAvailable();
      if (!hardwareOk) return false;

      final types = await _localAuth.getAvailableBiometrics();

      // 检查是否有指纹类型的生物识别已录入
      if (types.contains(BiometricType.fingerprint)) return true;
      if (types.contains(BiometricType.strong)) return true; // Android 10+ 强生物识别

      return false;
    } catch (e) {
      return false;
    }
  }

  /// 进行生物识别验证
  static Future<bool> authenticate({required String reason}) async {
    try {
      final isAuthenticated = await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );
      return isAuthenticated;
    } catch (e) {
      debugPrint('Authentication error: $e');
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