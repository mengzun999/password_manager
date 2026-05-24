import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:password_manager/constants/app_constants.dart';
import 'package:password_manager/core/crypto/aes_gcm.dart';
import 'package:password_manager/core/crypto/random.dart';
import 'package:password_manager/core/storage/secure_storage.dart';
import 'package:password_manager/providers/auth_provider.dart';
import '../../app.dart';
import '../../core/services/biometric_service.dart';
import '../../core/storage/shared_prefs.dart';

/// 生物识别设置页面
///
/// 首次设置时让用户选择是否启用生物识别（指纹/人脸）
/// 这是一个可选步骤，用户可以跳过
class SetupBiometricPage extends ConsumerStatefulWidget {
  const SetupBiometricPage({super.key});

  @override
  ConsumerState<SetupBiometricPage> createState() =>
      _SetupBiometricPageState();
}

class _SetupBiometricPageState extends ConsumerState<SetupBiometricPage> {
  /// 是否支持生物识别
  bool _isBiometricAvailable = false;

  /// 支持的生物识别类型列表
  List<BiometricType> _availableTypes = [];

  /// 是否正在检查
  bool _isChecking = true;

  /// 是否启用生物识别
  bool _enableBiometric = false;

  /// 是否正在验证
  bool _isAuthenticating = false;

  /// 错误信息
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkBiometricSupport();
  }

  /// 检查设备是否支持生物识别
  Future<void> _checkBiometricSupport() async {
    setState(() {
      _isChecking = true;
      _error = null;
    });

    final isAvailable = await BiometricService.isAvailable();
    final types = await BiometricService.getAvailableTypes();

    setState(() {
      _isBiometricAvailable = isAvailable && types.isNotEmpty;
      _availableTypes = types;
      _isChecking = false;
    });
  }

  /// 验证并启用生物识别
  Future<void> _authenticateAndEnable() async {
    if (!_enableBiometric) return;

    setState(() {
      _isAuthenticating = true;
      _error = null;
    });

    final isAuthenticated = await BiometricService.authenticate(
      reason: '验证身份以启用生物识别解锁',
    );

    setState(() {
      _isAuthenticating = false;
    });

    if (isAuthenticated) {
      // 获取主密钥
      final authState = ref.read(authProvider);
      final masterKey = authState.masterKey;

      if (masterKey != null) {
        // 生成一个随机的生物识别密钥标识符
        final biometricKeyId = SecureRandom.generateHex(32);

        // 使用 biometricKeyId 作为密钥加密 masterKey
        final biometricKey = Uint8List.fromList(utf8.encode(biometricKeyId));
        final encryptedMasterKey = await AESGCMHelper.encryptBytes(masterKey, biometricKey);

        // 存储生物识别相关的加密数据
        await SecureStorage.write(AppConstants.keyBiometricKeyId, biometricKeyId);
        await SecureStorage.write(AppConstants.keyEncryptedMasterKeyForBiometric, base64Encode(encryptedMasterKey));
      }

      await SharedPrefs.setBiometricEnabled(true);

      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.unlock);
      }
    } else {
      setState(() {
        _error = '验证失败，请重试';
      });
    }
  }

  /// 跳过生物识别设置
  Future<void> _skip() async {
    await SharedPrefs.setBiometricEnabled(false);

    if (mounted) {
      Navigator.pushReplacementNamed(context, AppRoutes.unlock);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('生物识别'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 说明文字
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.fingerprint, color: Colors.green.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '启用生物识别后，可以用指纹/人脸快速解锁应用\n'
                          '这是一个可选步骤，你可以稍后在设置中开启',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.green.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // 检查生物识别支持状态
            if (_isChecking) ...[
              const Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('正在检查设备支持情况...'),
                  ],
                ),
              ),
            ] else if (!_isBiometricAvailable) ...[
              // 不支持生物识别
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.device_unknown,
                      size: 48,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '当前设备不支持生物识别',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '你可以稍后在系统设置中添加指纹或人脸',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _skip,
                  child: const Text('继续'),
                ),
              ),
            ] else ...[
              // 支持生物识别，显示选项
              Text(
                '支持以下生物识别方式',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 16),

              // 生物识别类型卡片
              ..._availableTypes.map(
                    (type) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.light
                          ? Colors.grey.shade50
                          : Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(BiometricService.getTypeIcon(type), size: 32),
                        const SizedBox(width: 16),
                        Text(
                          BiometricService.getTypeName(type),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // 启用开关
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.fingerprint, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '启用生物识别解锁',
                            style: TextStyle(fontSize: 16),
                          ),
                          Text(
                            '开启后可以用指纹/人脸快速解锁',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _enableBiometric,
                      onChanged: (value) {
                        setState(() {
                          _enableBiometric = value;
                          _error = null;
                        });
                      },
                    ),
                  ],
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],

              const SizedBox(height: 32),

              // 验证并完成按钮
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _enableBiometric
                      ? _authenticateAndEnable
                      : _skip,
                  child: _isAuthenticating
                      ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : Text(_enableBiometric ? '验证并完成' : '跳过'),
                ),
              ),

              if (!_enableBiometric) ...[
                const SizedBox(height: 12),
                Text(
                  '你也可以稍后在设置中开启',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}