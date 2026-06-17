import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:password_manager/app.dart';
import 'package:password_manager/constants/app_constants.dart';
import 'package:password_manager/core/crypto/aes_gcm.dart';
import 'package:password_manager/core/crypto/random.dart';
import 'package:password_manager/core/storage/secure_storage.dart';
import 'package:password_manager/providers/auth_provider.dart';
import 'package:password_manager/utils/toast_utils.dart';
import 'package:password_manager/utils/helpers.dart';
import 'package:password_manager/core/widgets/no_back_page.dart';

/// 恢复密钥设置页面
class SetupMnemonicPage extends NoBackPage {
  const SetupMnemonicPage({super.key});

  @override
  String get title => '备份恢复密钥';

  @override
  Widget buildContent(BuildContext context) {
    return const _SetupMnemonicContent();
  }
}

class _SetupMnemonicContent extends ConsumerStatefulWidget {
  const _SetupMnemonicContent();

  @override
  ConsumerState<_SetupMnemonicContent> createState() =>
      _SetupMnemonicContentState();
}

class _SetupMnemonicContentState extends ConsumerState<_SetupMnemonicContent> {
  String _recoveryKey = '';
  bool _hasConfirmed = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _generateRecoveryKey();
  }

  void _generateRecoveryKey() {
    final bytes = SecureRandom.generateBytes(64);
    _recoveryKey = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> _saveAndContinue() async {
    if (!_hasConfirmed) return;

    setState(() => _isSaving = true);

    try {
      final authState = ref.read(authProvider);
      final masterKey = authState.masterKey;

      if (masterKey == null) {
        ToastUtils.showError(context, '未获取到主密钥');
        setState(() => _isSaving = false);
        return;
      }

      final bytes = utf8.encode(_recoveryKey);
      final hash = sha256.convert(bytes).toString();
      await SecureStorage.write(AppConstants.keyMnemonicHash, hash);

      final recoveryKey = _deriveKeyFromRecovery(_recoveryKey);
      final encryptedMasterKey = await AESGCMHelper.encryptBytes(masterKey, recoveryKey);

      await SecureStorage.write(
        AppConstants.keyEncryptedMasterKeyForRecovery,
        base64Encode(encryptedMasterKey),
      );

      setState(() => _isSaving = false);

      if (mounted) {
        Navigator.pushReplacementNamed(context, AppRoutes.setupGesture);
      }
    } catch (e) {
      ToastUtils.showError(context, '保存失败: $e');
      setState(() => _isSaving = false);
    }
  }

  Uint8List _deriveKeyFromRecovery(String recoveryKey) {
    final bytes = utf8.encode(recoveryKey);
    final hash = sha256.convert(bytes);
    return Uint8List.fromList(hash.bytes);
  }

  void _copyToClipboard() {
    Helpers.copyToClipboard(_recoveryKey);
    ToastUtils.showSuccess(context, '已复制到剪贴板，请妥善保存');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                              '忘记主密码后，可以用这个密钥解锁应用。\n'
                              '这是一串128字符的十六进制字符串，共512位。\n'
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
                GestureDetector(
                  onTap: _copyToClipboard,
                  child: Container(
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
                        Text(
                          _recoveryKey,
                          style: TextStyle(
                            fontSize: 14,
                            fontFamily: 'monospace',
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '👆 点击任意位置复制',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
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
    );
  }
}