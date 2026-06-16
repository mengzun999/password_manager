import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/constants/app_constants.dart';
import 'package:password_manager/core/crypto/aes_gcm.dart';
import 'package:password_manager/core/crypto/random.dart';
import 'package:password_manager/core/services/biometric_service.dart';
import 'package:password_manager/core/storage/secure_storage.dart';
import 'package:password_manager/core/storage/shared_prefs.dart';
import 'package:password_manager/providers/auth_provider.dart';
import 'package:password_manager/providers/settings_provider.dart';

import '../../utils/toast_utils.dart';

/// 指纹设置页面（设置页面的指纹设置）
class BiometricSetupPage extends ConsumerStatefulWidget {
  const BiometricSetupPage({super.key});

  @override
  ConsumerState<BiometricSetupPage> createState() => _BiometricSetupPageState();
}

class _BiometricSetupPageState extends ConsumerState<BiometricSetupPage> {
  /// 生物识别开关是否开启
  bool _isEnabled = false;

  /// 是否正在加载
  bool _isLoading = true;

  /// 是否支持指纹（兼容新旧 Android）
  bool _hasFingerprint = false;

  /// 是否正在验证
  bool _isAuthenticating = false;

  /// 错误信息
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// 加载数据：读取开关状态和设备支持情况
  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    // ✅ 从 SharedPrefs 读取状态
    _isEnabled = await SharedPrefs.isBiometricEnabled();

    // ✅ 使用 BiometricService.hasFingerprint() 检测
    _hasFingerprint = await BiometricService.hasFingerprint();

    // ✅ 同步到 SettingsProvider
    await ref.read(settingsProvider.notifier).toggleBiometric(_isEnabled);

    setState(() => _isLoading = false);
  }

  /// 显示密码输入对话框（用于验证主密码）
  Future<String?> _showPasswordDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('验证身份'),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '请输入主密码',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 验证主密码
  Future<bool> _verifyMasterPassword() async {
    final password = await _showPasswordDialog();
    if (password == null || password.isEmpty) return false;

    final authNotifier = ref.read(authProvider.notifier);
    return await authNotifier.verifyMasterPassword(password);
  }

  /// 启用/重新录制指纹（覆盖旧的）
  Future<void> _enableBiometric() async {
    // 1. 验证主密码
    final verified = await _verifyMasterPassword();
    if (!verified) {
      ToastUtils.showError(context, '验证失败');
      return;
    }

    setState(() {
      _isAuthenticating = true;
      _error = null;
    });

    try {
      // 2. 弹出生物识别验证（录制新指纹）
      final isAuthenticated = await BiometricService.authenticate(
        reason: '请验证指纹以启用指纹解锁',
      );

      setState(() {
        _isAuthenticating = false;
      });

      if (!isAuthenticated) {
        ToastUtils.showError(context, '验证失败，请重试');
        return;
      }

      // 3. 获取主密钥
      final authState = ref.read(authProvider);
      final masterKey = authState.masterKey;

      if (masterKey == null) {
        ToastUtils.showError(context, '未获取到主密钥');
        return;
      }

      // 4. 生成 32 字节生物识别密钥
      final biometricKey = SecureRandom.generateBytes(32);

      // 5. 存储 biometricKey 的 Base64 编码（覆盖旧的）
      await SecureStorage.write(
        AppConstants.keyBiometricKeyId,
        base64Encode(biometricKey),
      );

      // 6. 使用 biometricKey 加密 masterKey（覆盖旧的）
      final encryptedMasterKey = await AESGCMHelper.encryptBytes(masterKey, biometricKey);

      await SecureStorage.write(
        AppConstants.keyEncryptedMasterKeyForBiometric,
        base64Encode(encryptedMasterKey),
      );

      // 7. 开启开关
      await SharedPrefs.setBiometricEnabled(true);

      // 8. 更新 UI 状态
      await ref.read(settingsProvider.notifier).toggleBiometric(true);

      setState(() {
        _isEnabled = true;
        _isLoading = false;
      });

      ToastUtils.showSuccess(context, '指纹解锁已启用');
    } catch (e) {
      setState(() {
        _isAuthenticating = false;
        _error = '启用失败: $e';
      });
      ToastUtils.showError(context, '启用失败');
    }
  }

  /// 禁用生物识别（删除存储的数据）
  Future<void> _disableBiometric() async {
    // 1. 验证主密码
    final verified = await _verifyMasterPassword();
    if (!verified) {
      ToastUtils.showSuccess(context, '指纹解锁已关闭');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 2. 删除存储的生物识别数据
      await SecureStorage.delete(AppConstants.keyBiometricKeyId);
      await SecureStorage.delete(AppConstants.keyEncryptedMasterKeyForBiometric);

      // 3. 关闭开关
      await SharedPrefs.setBiometricEnabled(false);

      // 4. 更新 UI 状态
      await ref.read(settingsProvider.notifier).toggleBiometric(false);

      setState(() {
        _isEnabled = false;
        _isLoading = false;
      });

      ToastUtils.showSuccess(context, '指纹解锁已关闭');
    } catch (e) {
      ToastUtils.showError(context, '关闭失败: $e');
      setState(() => _isLoading = false);
    }
  }

  /// 切换生物识别开关
  Future<void> _toggleEnabled(bool value) async {
    if (value) {
      await _enableBiometric();
    } else {
      await _disableBiometric();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('指纹设置'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isLoading) ...[
                const Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('加载中...'),
                    ],
                  ),
                ),
              ] else if (!_hasFingerprint) ...[
                // 不支持指纹
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.fingerprint, color: Colors.grey.shade600),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('当前设备不支持指纹识别'),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // ========== 开关区域 ==========
                SwitchListTile(
                  title: const Text('启用指纹解锁'),
                  subtitle: Text(
                    _isEnabled ? '已开启，可用指纹快速解锁' : '开启后可以用指纹快速解锁应用',
                  ),
                  value: _isEnabled,
                  onChanged: _isAuthenticating ? null : _toggleEnabled,
                  secondary: Icon(
                    Icons.fingerprint,
                    color: _isEnabled ? Colors.blue : Colors.grey,
                  ),
                ),

                // ✅ 开启状态下显示"重新录制"提示
                if (_isEnabled) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '关闭后重新开启可更换指纹',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ),
                ],

                const Divider(),

                // ========== 状态说明 ==========
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _isEnabled
                          ? Colors.green.shade50
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _isEnabled
                            ? Colors.green.shade200
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      children: [
                        if (_isAuthenticating)
                          const SizedBox(
                            width: 28,
                            height: 28,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          Icon(
                            _isEnabled
                                ? Icons.check_circle
                                : Icons.info_outline,
                            color: _isEnabled
                                ? Colors.green
                                : Colors.grey.shade600,
                            size: 28,
                          ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isAuthenticating
                                    ? '验证中...'
                                    : (_isEnabled
                                    ? '指纹解锁已启用'
                                    : '指纹解锁已关闭'),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: _isEnabled
                                      ? Colors.green.shade800
                                      : Colors.grey.shade700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _isAuthenticating
                                    ? '请将手指放在传感器上'
                                    : (_isEnabled
                                    ? '每次解锁应用时会自动弹出指纹验证'
                                    : '开启后可以用指纹快速解锁应用，无需输入主密码'),
                                style: TextStyle(
                                  fontSize: 13,
                                  color: _isEnabled
                                      ? Colors.green.shade600
                                      : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ========== 底部提示 ==========
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    '💡 开启后解锁页面会自动弹出指纹验证\n'
                        '如需更换指纹，先关闭再重新开启即可',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              // ✅ 底部留白
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}