import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:password_manager/app.dart';
import 'package:password_manager/constants/app_constants.dart';
import 'package:password_manager/core/crypto/random.dart';
import 'package:password_manager/core/storage/secure_storage.dart';

/// 恢复密钥设置页面
///
/// 生成一长串随机字符串作为恢复密钥，用户需要抄写保存
/// 忘记主密码后，可以用这个密钥恢复数据
class SetupMnemonicPage extends ConsumerStatefulWidget {
  const SetupMnemonicPage({super.key});

  @override
  ConsumerState<SetupMnemonicPage> createState() => _SetupMnemonicPageState();
}

class _SetupMnemonicPageState extends ConsumerState<SetupMnemonicPage> {
  String _recoveryKey = '';      // 恢复密钥（一长串字符串）
  bool _hasConfirmed = false;    // 是否已确认抄写
  bool _isSaving = false;        // 是否正在保存
  bool _obscureKey = true;       // 是否隐藏密钥（默认隐藏）

  @override
  void initState() {
    super.initState();
    _generateRecoveryKey();
  }

  /// 生成恢复密钥（64字节随机数 → 十六进制字符串，共128个字符）
  void _generateRecoveryKey() {
    // 生成64字节随机数（256位）
    final bytes = SecureRandom.generateBytes(64);
    // 转为十六进制字符串（每个字节转2个十六进制字符，共128个字符）
    _recoveryKey = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// 保存恢复密钥哈希并继续
  Future<void> _saveAndContinue() async {
    if (!_hasConfirmed) return;

    setState(() {
      _isSaving = true;
    });

    // 将恢复密钥转为种子（用于生成密钥）
    final bytes = utf8.encode(_recoveryKey);
    final hash = sha256.convert(bytes).toString();
    await SecureStorage.write(AppConstants.keyMnemonicHash, hash);

    setState(() {
      _isSaving = false;
    });

    if (mounted) {
      Navigator.pushReplacementNamed(context, AppRoutes.setupGesture);
    }
  }

  /// 复制到剪贴板
  void _copyToClipboard() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制到剪贴板，请妥善保存')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('备份恢复密钥'),
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 警告提示框
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber, color: Colors.orange.shade700),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '请务必抄写下这串密钥，妥善保存！\n'
                                '忘记主密码后，需要这个密钥才能恢复数据。\n'
                                '不要截图保存，不要上传到云端！',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.orange.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  Text(
                    '你的恢复密钥',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey.shade700,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    '请按顺序抄写这串字符，共128位',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade500,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 密钥显示框
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.light
                          ? Colors.grey.shade100
                          : Colors.grey.shade800,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 密钥内容（可隐藏/显示）
                        SelectableText(
                          _obscureKey ? '•' * 32 + '（点击显示）' : _recoveryKey,
                          style: TextStyle(
                            fontSize: _obscureKey ? 20 : 14,
                            fontFamily: _obscureKey ? null : 'monospace',
                            letterSpacing: _obscureKey ? 4 : 0.5,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // 操作按钮行
                        Row(
                          children: [
                            // 显示/隐藏按钮
                            TextButton.icon(
                              onPressed: () {
                                setState(() {
                                  _obscureKey = !_obscureKey;
                                });
                              },
                              icon: Icon(
                                _obscureKey ? Icons.visibility_off : Icons.visibility,
                                size: 18,
                              ),
                              label: Text(_obscureKey ? '点击显示' : '隐藏'),
                            ),
                            const SizedBox(width: 8),
                            // 复制按钮
                            TextButton.icon(
                              onPressed: () {
                                _copyToClipboard();
                              },
                              icon: const Icon(Icons.copy, size: 18),
                              label: const Text('复制'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // 确认勾选框
                  Row(
                    children: [
                      Checkbox(
                        value: _hasConfirmed,
                        onChanged: (value) {
                          setState(() {
                            _hasConfirmed = value ?? false;
                          });
                        },
                      ),
                      Expanded(
                        child: Text(
                          '我已抄写并保存好这串密钥',
                          style: TextStyle(
                            fontSize: 14,
                            color: _hasConfirmed ? Colors.green : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // 下一步按钮
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: (_hasConfirmed && !_isSaving) ? _saveAndContinue : null,
                child: _isSaving
                    ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Text('下一步'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}