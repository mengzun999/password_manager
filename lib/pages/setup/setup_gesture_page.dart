import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:password_manager/app.dart';
import 'package:password_manager/constants/app_constants.dart';
import 'package:password_manager/core/crypto/aes_gcm.dart';
import 'package:password_manager/core/storage/secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:password_manager/core/storage/shared_prefs.dart';
import 'package:password_manager/providers/auth_provider.dart';
import 'package:password_manager/widgets/gesture_pattern_view.dart';

/// 手势图案设置页面
///
/// 首次设置时让用户绘制手势图案
/// 用于备用解锁方式
class SetupGesturePage extends ConsumerStatefulWidget {
  const SetupGesturePage({super.key});

  @override
  ConsumerState<SetupGesturePage> createState() => _SetupGesturePageState();
}

class _SetupGesturePageState extends ConsumerState<SetupGesturePage> {

  // ========== 状态变量 ==========

  /// 当前步骤：1=设置图案，2=确认图案
  int _step = 1;

  /// 第一次绘制的图案
  List<int>? _firstPattern;

  /// 当前正在绘制的图案（用于显示）
  List<int> _currentPattern = [];

  /// 错误提示
  String? _error;

  /// 是否正在保存
  bool _isSaving = false;

  /// 手势画板的 Key，用于调用 clearPattern 方法
  final GlobalKey<GesturePatternViewState> _gestureKey = GlobalKey();

  // ========== 业务逻辑方法 ==========

  /// 保存手势图案哈希
  Future<void> _saveGesturePattern(List<int> pattern) async {
    setState(() {
      _isSaving = true;
    });

    // 1. 获取主密钥（从 AuthProvider）
    final authState = ref.read(authProvider);
    final masterKey = authState.masterKey;

    if (masterKey == null) {
      setState(() {
        _isSaving = false;
        _error = '未获取到主密钥';
      });
      return;
    }

    // 2. 计算手势图案的哈希（作为加密密钥）
    final patternString = pattern.join(',');
    final gestureHash = sha256.convert(utf8.encode(patternString)).toString();

    // 3. 使用手势哈希作为密钥，加密 masterKey
    final gestureKey = Uint8List.fromList(utf8.encode(gestureHash.substring(0, 32)));
    final encryptedMasterKey = await AESGCMHelper.encryptBytes(masterKey, gestureKey);

    // 4. 存储手势哈希和加密后的 masterKey
    await SecureStorage.write(AppConstants.keyGestureHash, gestureHash);
    await SecureStorage.write(AppConstants.keyEncryptedMasterKeyForGesture, base64Encode(encryptedMasterKey));
    await SharedPrefs.setHasGesture(true);

    setState(() {
      _isSaving = false;
    });

    // ✅ 修正2：跳转到生物识别设置页，而不是解锁页
    if (mounted) {
      Navigator.pushReplacementNamed(context, AppRoutes.setupBiometric);
    }
  }

  /// 处理图案绘制完成
  void _onPatternComplete(List<int> pattern) {
    setState(() {
      _error = null;
    });

    if (_step == 1) {
      // 第一步：记录第一次绘制的图案
      if (pattern.length < 4) {
        setState(() {
          _error = '至少连接4个点';
        });
        // 清空画板，让用户重新绘制
        _gestureKey.currentState?.clearPattern();
        return;
      }

      _firstPattern = pattern;
      setState(() {
        _step = 2;
        _currentPattern = [];
      });
      // 清空画板，准备第二次绘制
      _gestureKey.currentState?.clearPattern();
    } else {
      // 第二步：验证两次绘制是否一致
      if (_firstPattern == null) {
        setState(() {
          _error = '请重新设置';
          _step = 1;
          _firstPattern = null;
          _currentPattern = [];
        });
        _gestureKey.currentState?.clearPattern();
        return;
      }

      if (_listEquals(_firstPattern!, pattern)) {
        // 一致，保存图案
        _saveGesturePattern(pattern);
      } else {
        setState(() {
          _error = '两次绘制的图案不一致，请重新设置';
          _step = 1;
          _firstPattern = null;
          _currentPattern = [];
        });
        _gestureKey.currentState?.clearPattern();
      }
    }
  }

  /// 比较两个列表是否相等
  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 重置当前步骤
  void _reset() {
    setState(() {
      _step = 1;
      _firstPattern = null;
      _currentPattern = [];
      _error = null;
    });
    _gestureKey.currentState?.clearPattern();
  }

  // ========== 界面构建方法 ==========

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_step == 1 ? '设置手势图案' : '确认手势图案'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _reset,
            child: const Text('重设'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // ========== 说明文字 ==========
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    _step == 1
                        ? '绘制你的手势图案（至少连接4个点）'
                        : '请再次绘制相同的手势图案',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.blue.shade800,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 40),

            // ========== ✅ 修正1：使用 GesturePatternView ==========
            Center(
              child: SizedBox(
                width: 280,
                height: 280,
                child: GesturePatternView(
                  key: _gestureKey,
                  onPatternComplete: _onPatternComplete,
                  onPatternChanged: (pattern) {
                    setState(() {
                      _currentPattern = pattern;
                    });
                  },
                ),
              ),
            ),

            const SizedBox(height: 40),

            // ========== 加载状态 ==========
            if (_isSaving)
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: CircularProgressIndicator(),
              ),

            // ========== 跳过按钮（可选） ==========
            if (!_isSaving)
              TextButton(
                onPressed: () {
                  // 跳过手势图案设置，进入生物识别设置
                  if (mounted) {
                    Navigator.pushReplacementNamed(context, AppRoutes.setupBiometric);
                  }
                },
                child: const Text('跳过'),
              ),
          ],
        ),
      ),
    );
  }
}