// unlock_page.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crypto/crypto.dart';
import 'package:password_manager/app.dart';
import 'package:password_manager/providers/auth_provider.dart';
import 'package:password_manager/core/crypto/aes_gcm.dart';
import 'package:password_manager/core/services/biometric_service.dart';
import 'package:password_manager/core/storage/shared_prefs.dart';
import 'package:password_manager/core/storage/secure_storage.dart';
import 'package:password_manager/constants/app_constants.dart';
import 'package:password_manager/utils/toast_utils.dart';
import 'package:password_manager/widgets/gesture_pattern_view.dart';

/// 解锁页面
class UnlockPage extends ConsumerStatefulWidget {
  const UnlockPage({super.key});

  @override
  ConsumerState<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends ConsumerState<UnlockPage> {
  final _passwordController = TextEditingController();
  final GlobalKey<GesturePatternViewState> _gestureKey = GlobalKey();

  int _unlockMode = 0;
  bool _obscurePassword = true;
  String? _error;
  bool _isLoading = false;
  bool _hasGesture = false;
  List<int> _currentPattern = [];
  bool _isChecking = true;
  bool _showForgotPassword = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _checkAndNavigate());
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _checkAndNavigate() async {
    setState(() => _isChecking = true);

    final hasSalt = await SecureStorage.containsKey(AppConstants.keySalt);
    final hasMasterHash = await SecureStorage.containsKey(
      AppConstants.keyMasterPasswordHash,
    );
    final isInitialized = hasSalt && hasMasterHash;

    if (!isInitialized) {
      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.setup);
      }
      return;
    }

    setState(() => _isChecking = false);
    await _loadSettings();
    _tryBiometricUnlock();
  }

  Future<void> _loadSettings() async {
    final hasGesture = await SharedPrefs.hasGesture();
    setState(() {
      _hasGesture = hasGesture;
    });
  }

  Future<void> _tryBiometricUnlock() async {
    final isEnabled = await SharedPrefs.isBiometricEnabled();
    if (!isEnabled) return;

    await Future.delayed(const Duration(milliseconds: 300));

    final isAuthenticated = await BiometricService.authenticate(
      reason: '验证身份以解锁应用',
    );

    if (!isAuthenticated || !mounted) return;

    final biometricKeyBase64 = await SecureStorage.read(
      AppConstants.keyBiometricKeyId,
    );
    final encryptedMasterKeyBase64 = await SecureStorage.read(
      AppConstants.keyEncryptedMasterKeyForBiometric,
    );

    if (biometricKeyBase64 == null || encryptedMasterKeyBase64 == null) {
      setState(() {
        _unlockMode = 0;
      });
      ToastUtils.showInfo(context, '请先输入主密码完成解锁');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final biometricKey = base64Decode(biometricKeyBase64);
      final encryptedMasterKey = base64Decode(encryptedMasterKeyBase64);
      final masterKey = await AESGCMHelper.decryptBytes(
        encryptedMasterKey,
        biometricKey,
      );

      final authNotifier = ref.read(authProvider.notifier);
      authNotifier.unlock(masterKey: masterKey);

      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.home,
              (route) => false,
        );
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _unlockMode = 0;
      });
      ToastUtils.showError(context, '解锁失败，请使用主密码');
    }
  }

  Future<void> _verifyGestureAndUnlock(List<int> pattern) async {
    if (pattern.length < 4) {
      setState(() {
        _error = '至少连接4个点';
        _currentPattern = [];
      });
      _gestureKey.currentState?.clearPattern();
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final storedGestureHash = await SecureStorage.read(
      AppConstants.keyGestureHash,
    );
    final encryptedMasterKeyBase64 = await SecureStorage.read(
      AppConstants.keyEncryptedMasterKeyForGesture,
    );

    if (storedGestureHash == null || encryptedMasterKeyBase64 == null) {
      setState(() {
        _error = '未设置手势图案';
        _isLoading = false;
        _currentPattern = [];
      });
      _gestureKey.currentState?.clearPattern();
      return;
    }

    final patternString = pattern.join(',');
    final currentHash = sha256.convert(utf8.encode(patternString)).toString();

    if (currentHash != storedGestureHash) {
      setState(() {
        _error = '手势图案错误';
        _isLoading = false;
        _currentPattern = [];
      });
      _gestureKey.currentState?.clearPattern();
      return;
    }

    try {
      final gestureKey = Uint8List.fromList(
        utf8.encode(storedGestureHash.substring(0, 32)),
      );
      final encryptedMasterKey = base64Decode(encryptedMasterKeyBase64);
      final masterKey = await AESGCMHelper.decryptBytes(
        encryptedMasterKey,
        gestureKey,
      );

      final authNotifier = ref.read(authProvider.notifier);
      authNotifier.unlock(masterKey: masterKey);

      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.home,
              (route) => false,
        );
      }
    } catch (e) {
      setState(() {
        _error = '解密失败，请使用主密码解锁';
        _isLoading = false;
        _currentPattern = [];
      });
      _gestureKey.currentState?.clearPattern();
    }
  }

  Future<void> _handleUnlock() async {
    final password = _passwordController.text.trim();

    if (password.isEmpty) {
      setState(() => _error = '请输入主密码');
      return;
    }

    setState(() {
      _error = null;
      _isLoading = true;
      _showForgotPassword = false;
    });

    final authNotifier = ref.read(authProvider.notifier);
    final masterKey = await authNotifier.verifyAndGetKey(password);

    setState(() => _isLoading = false);

    if (masterKey != null) {
      authNotifier.unlock(masterKey: masterKey);

      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.home,
              (route) => false,
        );
      }
    } else {
      setState(() {
        _error = '主密码错误';
        _passwordController.clear();
        _showForgotPassword = true;
      });
    }
  }

  void _showRecoveryDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('使用恢复密钥', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '输入128位恢复密钥解锁应用',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 2),
                const Text(
                  '（首次设置时抄写的128位十六进制字符串）',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: '输入恢复密钥...',
                    hintStyle: TextStyle(fontSize: 12),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    isDense: true,
                  ),
                  maxLines: 2,
                  minLines: 1,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('取消', style: TextStyle(fontSize: 14)),
          ),
          TextButton(
            onPressed: () => _unlockWithRecoveryKey(controller.text),
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('解锁', style: TextStyle(fontSize: 14)),
          ),
        ],
        actionsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      ),
    );
  }

  Future<void> _unlockWithRecoveryKey(String inputKey) async {
    if (inputKey.trim().isEmpty) {
      ToastUtils.showWarning(context, '请输入恢复密钥');
      return;
    }

    final key = inputKey.trim().replaceAll(RegExp(r'\s+'), '');

    if (key.length != 128) {
      ToastUtils.showError(context, '恢复密钥长度错误（应为128位）');
      return;
    }

    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(key)) {
      ToastUtils.showError(context, '恢复密钥格式错误');
      return;
    }

    final storedHash = await SecureStorage.read(AppConstants.keyMnemonicHash);
    if (storedHash == null) {
      ToastUtils.showError(context, '未设置恢复密钥');
      return;
    }

    final bytes = utf8.encode(key);
    final inputHash = sha256.convert(bytes).toString();

    if (inputHash != storedHash) {
      ToastUtils.showError(context, '恢复密钥错误');
      return;
    }

    final encryptedMasterKeyBase64 = await SecureStorage.read(
      AppConstants.keyEncryptedMasterKeyForRecovery,
    );

    if (encryptedMasterKeyBase64 == null) {
      ToastUtils.showError(context, '未找到加密的主密钥');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final recoveryBytes = utf8.encode(key);
      final recoveryHash = sha256.convert(recoveryBytes);
      final recoveryKey = Uint8List.fromList(recoveryHash.bytes);

      final encryptedMasterKey = base64Decode(encryptedMasterKeyBase64);
      final masterKey = await AESGCMHelper.decryptBytes(
        encryptedMasterKey,
        recoveryKey,
      );

      final authNotifier = ref.read(authProvider.notifier);
      authNotifier.unlock(masterKey: masterKey);

      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.home,
              (route) => false,
        );
      }

      // ✅ 移除重复弹窗
      // 用户已成功解锁，不需要额外弹窗提醒

    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ToastUtils.showError(context, '解锁失败: $e');
    }
  }

  void _switchToGesture() {
    setState(() {
      _unlockMode = 1;
      _error = null;
      _currentPattern = [];
      _showForgotPassword = false;
    });
    _gestureKey.currentState?.clearPattern();
  }

  void _switchToPassword() {
    setState(() {
      _unlockMode = 0;
      _error = null;
      _passwordController.clear();
      _showForgotPassword = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          title: const Text('解锁'),
          automaticallyImplyLeading: false,
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            if (_hasGesture)
              TextButton(
                onPressed: _unlockMode == 0 ? _switchToGesture : _switchToPassword,
                child: Text(_unlockMode == 0 ? '使用手势' : '使用密码'),
              ),
          ],
        ),
        body: SafeArea(
          bottom: true,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock,
                    size: 60,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 24),
                  _unlockMode == 0
                      ? _buildPasswordInput()
                      : _buildGestureInput(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPasswordInput() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          autofocus: true,
          onSubmitted: (_) => _handleUnlock(),
          decoration: InputDecoration(
            labelText: '主密码',
            hintText: '请输入主密码',
            prefixIcon: const Icon(Icons.key),
            suffixIcon: IconButton(
              icon: Icon(
                _obscurePassword ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
            border: const OutlineInputBorder(),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleUnlock,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).brightness == Brightness.dark
                  ? Colors.purple.shade400
                  : Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              elevation: 2,
              shadowColor: Colors.black.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
                : const Text('解锁', style: TextStyle(fontSize: 16)),
          ),
        ),
        if (_showForgotPassword) ...[
          const SizedBox(height: 10),
          TextButton(
            onPressed: _showRecoveryDialog,
            child: Text(
              '忘记主密码？',
              style: TextStyle(
                fontSize: 13,
                color: Colors.orange.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGestureInput() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '绘制你的手势图案解锁',
            style: TextStyle(color: Colors.blue.shade800),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: 280,
          height: 280,
          child: GesturePatternView(
            key: _gestureKey,
            onPatternComplete: (pattern) {
              _verifyGestureAndUnlock(pattern);
            },
            onPatternChanged: (pattern) {
              setState(() {
                _currentPattern = pattern;
              });
            },
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
      ],
    );
  }
}