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
  // ========== 控制器 ==========

  final _passwordController = TextEditingController();

  final GlobalKey<GesturePatternViewState> _gestureKey = GlobalKey();

  // ========== UI 状态变量 ==========

  int _unlockMode = 0;
  bool _obscurePassword = true;
  String? _error;
  bool _isLoading = false;
  bool _hasGesture = false;
  List<int> _currentPattern = [];
  bool _isChecking = true;

  /// ✅ 是否显示"忘记密码"按钮（密码验证失败后显示）
  bool _showForgotPassword = false;

  // ========== 生命周期方法 ==========

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

  // ========== 初始化检查 ==========

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

  // ========== 设置加载方法 ==========

  Future<void> _loadSettings() async {
    final hasGesture = await SharedPrefs.hasGesture();
    setState(() {
      _hasGesture = hasGesture;
    });
  }

  // ========== 生物识别解锁 ==========

  Future<void> _tryBiometricUnlock() async {
    final isEnabled = await SharedPrefs.isBiometricEnabled();
    if (!isEnabled) return;

    await Future.delayed(const Duration(milliseconds: 300));

    final isAuthenticated = await BiometricService.authenticate(
      reason: '验证身份以解锁应用',
    );

    if (!isAuthenticated || !mounted) return;

    final biometricKeyBase64 = await SecureStorage.read(AppConstants.keyBiometricKeyId);
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
      final masterKey = await AESGCMHelper.decryptBytes(encryptedMasterKey, biometricKey);

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

  // ========== 手势解锁 ==========

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

    final storedGestureHash = await SecureStorage.read(AppConstants.keyGestureHash);
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
      final gestureKey = Uint8List.fromList(utf8.encode(storedGestureHash.substring(0, 32)));
      final encryptedMasterKey = base64Decode(encryptedMasterKeyBase64);
      final masterKey = await AESGCMHelper.decryptBytes(encryptedMasterKey, gestureKey);

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

  // ========== 主密码解锁 ==========

  Future<void> _handleUnlock() async {
    final password = _passwordController.text.trim();

    if (password.isEmpty) {
      setState(() => _error = '请输入主密码');
      return;
    }

    // ✅ 每次输入时隐藏忘记密码按钮
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
      // ✅ 验证失败，显示错误并显示"忘记密码"按钮
      setState(() {
        _error = '主密码错误';
        _passwordController.clear();
        _showForgotPassword = true;
      });
    }
  }

  // ========== ✅ 恢复密钥解锁 ==========

  /// 显示恢复密钥输入对话框
  void _showRecoveryDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: const Text('使用恢复密钥'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '输入128位恢复密钥解锁应用',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '输入恢复密钥...',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => _unlockWithRecoveryKey(controller.text),
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange,
            ),
            child: const Text('解锁'),
          ),
        ],
      ),
    );
  }

  /// 使用恢复密钥解锁
  Future<void> _unlockWithRecoveryKey(String inputKey) async {
    if (inputKey.trim().isEmpty) {
      ToastUtils.showWarning(context, '请输入恢复密钥');
      return;
    }

    // 去除空格和换行
    final key = inputKey.trim().replaceAll(RegExp(r'\s+'), '');

    // 验证格式
    if (key.length != 128) {
      ToastUtils.showError(context, '恢复密钥长度错误（应为128位）');
      return;
    }

    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(key)) {
      ToastUtils.showError(context, '恢复密钥格式错误');
      return;
    }

    // 验证哈希
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

    // ✅ 验证通过，解密 masterKey
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
      // 从恢复密钥派生解密密钥
      final recoveryBytes = utf8.encode(key);
      final recoveryHash = sha256.convert(recoveryBytes);
      final recoveryKey = Uint8List.fromList(recoveryHash.bytes);

      final encryptedMasterKey = base64Decode(encryptedMasterKeyBase64);
      final masterKey = await AESGCMHelper.decryptBytes(encryptedMasterKey, recoveryKey);

      final authNotifier = ref.read(authProvider.notifier);
      authNotifier.unlock(masterKey: masterKey);

      // ✅ 关闭对话框
      if (mounted) {
        Navigator.pop(context);
      }

      // ✅ 跳转到主页，并显示提示
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil(
          AppRoutes.home,
              (route) => false,
        );
        // 延迟显示提示，等页面加载完成
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _showRecoveryWarningDialog();
          }
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ToastUtils.showError(context, '解锁失败: $e');
    }
  }

  /// ✅ 显示恢复密钥警告提示
  void _showRecoveryWarningDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            const Text('⚠️ 重要提醒'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '您正在使用恢复密钥解锁应用。',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            SizedBox(height: 12),
            Text(
              '请尽快将主密码记在安全的地方！\n\n'
                  '• 主密码是您唯一能正常解锁的方式\n'
                  '• 恢复密钥仅作为备用，不建议日常使用\n'
                  '• 如果忘记主密码，请立即重新设置',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  // ========== 模式切换方法 ==========

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

  // ========== 界面构建方法 ==========

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('解锁'),
        automaticallyImplyLeading: false,
        actions: [
          if (_hasGesture)
            TextButton(
              onPressed: _unlockMode == 0 ? _switchToGesture : _switchToPassword,
              child: Text(_unlockMode == 0 ? '使用手势' : '使用密码'),
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock,
                size: 80,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 40),

              _unlockMode == 0
                  ? _buildPasswordInput()
                  : _buildGestureInput(),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // ========== 密码输入界面 ==========

  Widget _buildPasswordInput() {
    return Column(
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
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _isLoading ? null : _handleUnlock,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
            ),
            child: _isLoading
                ? const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 12),
                Text('验证中...', style: TextStyle(fontSize: 16, color: Colors.white)),
              ],
            )
                : const Text('解锁', style: TextStyle(fontSize: 16)),
          ),
        ),
        // ✅ 只在密码输入错误后显示"忘记密码？"
        if (_showForgotPassword) ...[
          const SizedBox(height: 12),
          TextButton(
            onPressed: _showRecoveryDialog,
            child: Text(
              '忘记主密码？',
              style: TextStyle(
                fontSize: 14,
                color: Colors.orange.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ========== 手势输入界面 ==========

  Widget _buildGestureInput() {
    return Column(
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
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
      ],
    );
  }
}