import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/constants/app_constants.dart';
import 'package:password_manager/core/crypto/aes_gcm.dart';
import 'package:password_manager/core/crypto/random.dart';
import 'package:password_manager/core/storage/secure_storage.dart';
import 'package:password_manager/providers/auth_provider.dart';
import '../../app.dart';
import '../../core/services/biometric_service.dart';
import '../../core/storage/shared_prefs.dart';
import '../../core/widgets/no_back_page.dart';

/// 指纹设置页面（首次设置时显示）
class SetupBiometricPage extends NoBackPage {
  const SetupBiometricPage({super.key});

  @override
  String get title => '指纹解锁';

  @override
  Widget buildContent(BuildContext context) {
    return const _SetupBiometricContent();
  }
}

class _SetupBiometricContent extends ConsumerStatefulWidget {
  const _SetupBiometricContent();

  @override
  ConsumerState<_SetupBiometricContent> createState() =>
      _SetupBiometricContentState();
}

class _SetupBiometricContentState
    extends ConsumerState<_SetupBiometricContent> {
  bool _isFingerprintAvailable = false;
  bool _isChecking = true;
  bool _isAuthenticating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _checkFingerprintSupport();
  }

  Future<void> _checkFingerprintSupport() async {
    setState(() {
      _isChecking = true;
      _error = null;
    });

    final hasFingerprint = await BiometricService.hasFingerprint();

    setState(() {
      _isFingerprintAvailable = hasFingerprint;
      _isChecking = false;
    });
  }

  Future<void> _enrollFingerprint() async {
    if (!_isFingerprintAvailable) return;

    setState(() {
      _isAuthenticating = true;
      _error = null;
    });

    final isAuthenticated = await BiometricService.authenticate(
      reason: '请验证指纹以启用指纹解锁',
    );

    setState(() {
      _isAuthenticating = false;
    });

    if (isAuthenticated) {
      final authState = ref.read(authProvider);
      final masterKey = authState.masterKey;

      if (masterKey != null) {
        final biometricKey = SecureRandom.generateBytes(32);

        await SecureStorage.write(
          AppConstants.keyBiometricKeyId,
          base64Encode(biometricKey),
        );

        final encryptedMasterKey = await AESGCMHelper.encryptBytes(
          masterKey,
          biometricKey,
        );

        await SecureStorage.write(
          AppConstants.keyEncryptedMasterKeyForBiometric,
          base64Encode(encryptedMasterKey),
        );
      }

      await SharedPrefs.setBiometricEnabled(true);

      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.home,
              (route) => false,
        );
      }
    } else {
      setState(() {
        _error = '指纹验证失败，请重试';
      });
    }
  }

  Future<void> _skip() async {
    await SharedPrefs.setBiometricEnabled(false);

    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil(
        AppRoutes.home,
            (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Center(child: CircularProgressIndicator());
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.fingerprint,
              size: 80,
              color: _isFingerprintAvailable
                  ? Theme.of(context).primaryColor
                  : Colors.grey.shade400,
            ),
            const SizedBox(height: 24),
            Text(
              _isFingerprintAvailable ? '设置指纹解锁' : '当前设备不支持指纹',
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _isFingerprintAvailable
                  ? '点击下方按钮验证指纹，之后可以用指纹快速解锁应用'
                  : '你的设备不支持指纹识别，点击跳过继续',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 16),
            if (_isFingerprintAvailable)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle,
                      size: 16,
                      color: Colors.green.shade700,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '指纹可用',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
            ],
            if (_isFingerprintAvailable) ...[
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _isAuthenticating ? null : _enrollFingerprint,
                  icon: _isAuthenticating
                      ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Icon(Icons.fingerprint),
                  label: Text(
                    _isAuthenticating ? '验证中...' : '录制指纹',
                    style: const TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
            if (!_isFingerprintAvailable) ...[
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _skip,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('继续', style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}