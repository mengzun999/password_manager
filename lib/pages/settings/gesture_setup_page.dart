import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crypto/crypto.dart';
import 'package:password_manager/constants/app_constants.dart';
import 'package:password_manager/core/crypto/aes_gcm.dart';
import 'package:password_manager/core/storage/secure_storage.dart';
import 'package:password_manager/core/storage/shared_prefs.dart';
import 'package:password_manager/providers/auth_provider.dart';
import 'package:password_manager/utils/toast_utils.dart';
import 'package:password_manager/widgets/gesture_pattern_view.dart';

/// 手势图案设置页面
class GestureSetupPage extends ConsumerStatefulWidget {
  const GestureSetupPage({super.key});

  @override
  ConsumerState<GestureSetupPage> createState() => _GestureSetupPageState();
}

class _GestureSetupPageState extends ConsumerState<GestureSetupPage> {
  int _step = 1;
  List<int>? _firstPattern;
  List<int> _currentPattern = [];
  String? _error;
  bool _isSaving = false;
  final GlobalKey<GesturePatternViewState> _patternKey = GlobalKey();

  Future<void> _saveGesturePattern(List<int> pattern) async {
    setState(() => _isSaving = true);

    final authState = ref.read(authProvider);
    final masterKey = authState.masterKey;

    if (masterKey == null) {
      setState(() {
        _isSaving = false;
        _error = '未获取到主密钥';
      });
      ToastUtils.showError(context, '未获取到主密钥');
      return;
    }

    final patternString = pattern.join(',');
    final gestureHash = sha256.convert(utf8.encode(patternString)).toString();
    final gestureKey = Uint8List.fromList(utf8.encode(gestureHash.substring(0, 32)));
    final encryptedMasterKey = await AESGCMHelper.encryptBytes(masterKey, gestureKey);

    await SecureStorage.write(AppConstants.keyGestureHash, gestureHash);
    await SecureStorage.write(
      AppConstants.keyEncryptedMasterKeyForGesture,
      base64Encode(encryptedMasterKey),
    );
    await SharedPrefs.setHasGesture(true);

    setState(() => _isSaving = false);

    if (mounted) Navigator.pop(context, true);
  }

  void _onPatternComplete(List<int> pattern) {
    setState(() => _error = null);

    if (_step == 1) {
      if (pattern.length < 4) {
        setState(() => _error = '至少连接4个点');
        _patternKey.currentState?.clearPattern();
        return;
      }
      _firstPattern = pattern;
      setState(() {
        _step = 2;
        _currentPattern = [];
      });
      _patternKey.currentState?.clearPattern();
    } else {
      if (_firstPattern == null) {
        setState(() {
          _error = '请重新设置';
          _step = 1;
        });
        _patternKey.currentState?.clearPattern();
        return;
      }
      if (_listEquals(_firstPattern!, pattern)) {
        _saveGesturePattern(pattern);
      } else {
        setState(() {
          _error = '两次绘制的图案不一致，请重新设置';
          _step = 1;
          _firstPattern = null;
          _currentPattern = [];
        });
        _patternKey.currentState?.clearPattern();
      }
    }
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _reset() {
    setState(() {
      _step = 1;
      _firstPattern = null;
      _currentPattern = [];
      _error = null;
    });
    _patternKey.currentState?.clearPattern();
  }

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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
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
                      style: TextStyle(color: Colors.blue.shade800),
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
              const SizedBox(height: 20),
              Center(
                child: SizedBox(
                  width: 280,
                  height: 280,
                  child: GesturePatternView(
                    key: _patternKey,
                    onPatternComplete: _onPatternComplete,
                    onPatternChanged: (pattern) {
                      setState(() => _currentPattern = pattern);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (_isSaving)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator(),
                ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}