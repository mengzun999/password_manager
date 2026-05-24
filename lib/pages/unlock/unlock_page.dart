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
import 'package:password_manager/widgets/gesture_pattern_view.dart';

/// 解锁页面
///
/// 用户每次打开 App 时看到的页面
/// 支持三种解锁方式：
/// 1. 生物识别（指纹/人脸）- 优先弹出，成功后直接解锁
/// 2. 手势图案 - 验证成功后直接解锁
/// 3. 主密码 - 最终 fallback 方式
///
/// 设计原理：
/// - 首次设置时，将 masterKey 用手势哈希/生物识别密钥加密后存储
/// - 解锁时，验证通过后解密获取 masterKey，直接解锁
class UnlockPage extends ConsumerStatefulWidget {
  const UnlockPage({super.key});

  @override
  ConsumerState<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends ConsumerState<UnlockPage> {
  // ========== 控制器 ==========

  /// 主密码输入框控制器
  final _passwordController = TextEditingController();

  // ========== UI 状态变量 ==========

  /// 当前解锁模式
  /// 0 = 主密码输入模式
  /// 1 = 手势图案模式
  int _unlockMode = 0;

  /// 密码是否隐藏（true=显示为黑点，false=显示明文）
  bool _obscurePassword = true;

  /// 错误提示文字
  String? _error;

  /// 是否正在验证中（显示加载动画，防止重复提交）
  bool _isLoading = false;

  /// 是否已启用手势解锁（从 SharedPreferences 读取）
  bool _hasGesture = false;

  /// 当前手势图案选中的点（用于显示）
  List<int> _currentPattern = [];

  // ========== 生命周期方法 ==========

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _tryBiometricUnlock();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  // ========== 设置加载方法 ==========

  /// 加载设置（检查是否启用手势）
  Future<void> _loadSettings() async {
    final hasGesture = await SharedPrefs.hasGesture();
    setState(() {
      _hasGesture = hasGesture;
    });
  }

  // ========== 生物识别解锁（直接解锁） ==========

  /// 尝试生物识别解锁
  ///
  /// 流程：
  /// 1. 检查用户是否开启了生物识别开关
  /// 2. 延迟 300ms 让页面显示出来
  /// 3. 弹出系统生物识别验证对话框
  /// 4. 验证成功后，解密获取 masterKey 并直接解锁
  Future<void> _tryBiometricUnlock() async {
    // 1. 检查是否开启生物识别
    final isEnabled = await SharedPrefs.isBiometricEnabled();
    if (!isEnabled) return;

    // 2. 延迟一下让页面显示出来
    await Future.delayed(const Duration(milliseconds: 300));

    // 3. 弹出生物识别验证
    final isAuthenticated = await BiometricService.authenticate(
      reason: '验证身份以解锁应用',
    );

    if (!isAuthenticated || !mounted) return;

    // 4. 生物识别成功，获取加密的 masterKey 并解密
    final biometricKeyId = await SecureStorage.read(AppConstants.keyBiometricKeyId);
    final encryptedMasterKeyBase64 = await SecureStorage.read(
      AppConstants.keyEncryptedMasterKeyForBiometric,
    );

    if (biometricKeyId == null || encryptedMasterKeyBase64 == null) {
      // 没有存储加密的 masterKey，切换到密码模式
      setState(() {
        _unlockMode = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先输入主密码完成解锁')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 解密 masterKey
      final biometricKey = Uint8List.fromList(utf8.encode(biometricKeyId));
      final encryptedMasterKey = base64Decode(encryptedMasterKeyBase64);
      final masterKey = await AESGCMHelper.decryptBytes(encryptedMasterKey, biometricKey);

      // 解锁成功
      final authNotifier = ref.read(authProvider.notifier);
      authNotifier.unlock(masterKey: masterKey);

      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _unlockMode = 0;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('解锁失败，请使用主密码')),
      );
    }
  }

  // ========== 手势解锁（直接解锁） ==========

  /// 验证手势图案并直接解锁
  ///
  /// 流程：
  /// 1. 检查图案长度（至少4个点）
  /// 2. 从 SecureStorage 读取存储的手势哈希和加密的 masterKey
  /// 3. 计算当前图案的 SHA-256 哈希
  /// 4. 比较两个哈希值是否一致
  /// 5. 一致则解密 masterKey 并直接解锁
  Future<void> _verifyGestureAndUnlock(List<int> pattern) async {
    // 1. 检查长度：至少连接4个点
    if (pattern.length < 4) {
      setState(() {
        _error = '至少连接4个点';
        _currentPattern = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    // 2. 获取存储的手势哈希和加密的 masterKey
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
      return;
    }

    // 3. 计算当前图案的哈希
    final patternString = pattern.join(',');
    final currentHash = sha256.convert(utf8.encode(patternString)).toString();

    // 4. 验证手势是否正确
    if (currentHash != storedGestureHash) {
      setState(() {
        _error = '手势图案错误';
        _isLoading = false;
        _currentPattern = [];
      });
      return;
    }

    // 5. 手势正确，解密 masterKey
    try {
      // 使用手势哈希的前32字节作为解密密钥
      final gestureKey = Uint8List.fromList(utf8.encode(storedGestureHash.substring(0, 32)));
      final encryptedMasterKey = base64Decode(encryptedMasterKeyBase64);
      final masterKey = await AESGCMHelper.decryptBytes(encryptedMasterKey, gestureKey);

      // 6. 解锁成功
      final authNotifier = ref.read(authProvider.notifier);
      authNotifier.unlock(masterKey: masterKey);

      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      }
    } catch (e) {
      setState(() {
        _error = '解密失败，请使用主密码解锁';
        _isLoading = false;
        _currentPattern = [];
      });
    }
  }

  // ========== 主密码解锁 ==========

  /// 处理主密码解锁
  ///
  /// 流程：
  /// 1. 获取用户输入的密码
  /// 2. 验证密码不为空
  /// 3. 调用 AuthProvider 验证密码并获取主密钥
  /// 4. 验证成功则解锁并跳转到主页
  /// 5. 验证失败则显示错误并清空输入框
  Future<void> _handleUnlock() async {
    final password = _passwordController.text.trim();

    if (password.isEmpty) {
      setState(() => _error = '请输入主密码');
      return;
    }

    setState(() {
      _error = null;
      _isLoading = true;
    });

    final authNotifier = ref.read(authProvider.notifier);
    final masterKey = await authNotifier.verifyAndGetKey(password);

    setState(() => _isLoading = false);

    if (masterKey != null) {
      authNotifier.unlock(masterKey: masterKey);

      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      }
    } else {
      setState(() {
        _error = '主密码错误';
        _passwordController.clear();
      });
    }
  }

  // ========== 模式切换方法 ==========

  /// 切换到手势解锁模式
  void _switchToGesture() {
    setState(() {
      _unlockMode = 1;
      _error = null;
      _currentPattern = [];
    });
  }

  /// 切换到密码解锁模式
  void _switchToPassword() {
    setState(() {
      _unlockMode = 0;
      _error = null;
      _passwordController.clear();
    });
  }

  // ========== 界面构建方法 ==========

  @override
  Widget build(BuildContext context) {
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
      body: Padding(
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
          ],
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
        GesturePatternView(
          onPatternComplete: (pattern) {
            _verifyGestureAndUnlock(pattern);
          },
          onPatternChanged: (pattern) {
            setState(() {
              _currentPattern = pattern;
            });
          },
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 20),
        TextButton(
          onPressed: () {
            setState(() {
              _currentPattern = [];
              _error = null;
            });
          },
          child: const Text('重绘'),
        ),
      ],
    );
  }
}