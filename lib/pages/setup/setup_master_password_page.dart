import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/app.dart';
import 'package:password_manager/providers/auth_provider.dart';
import 'package:password_manager/constants/app_constants.dart';
import 'package:password_manager/core/storage/secure_storage.dart';
import 'package:password_manager/core/crypto/pbkdf2.dart';

/// 设置主密码页面
class SetupMasterPasswordPage extends ConsumerStatefulWidget {
  const SetupMasterPasswordPage({super.key});

  @override
  ConsumerState<SetupMasterPasswordPage> createState() =>
      _SetupMasterPasswordPageState();
}

class _SetupMasterPasswordPageState
    extends ConsumerState<SetupMasterPasswordPage> {

  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;
  bool _isLoading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final password = _passwordController.text.trim();
    final confirm = _confirmController.text.trim();

    if (password.isEmpty) {
      setState(() => _error = '请输入主密码');
      return;
    }

    if (password.length < 6) {
      setState(() => _error = '主密码至少6位');
      return;
    }

    if (password != confirm) {
      setState(() => _error = '两次输入的密码不一致');
      return;
    }

    setState(() {
      _error = null;
      _isLoading = true;
    });

    final authNotifier = ref.read(authProvider.notifier);
    await authNotifier.setupMasterPassword(password);

    final saltBase64 = await SecureStorage.read(AppConstants.keySalt);
    if (saltBase64 != null) {
      final salt = base64Decode(saltBase64);
      final masterKey = await PBKDF2Helper.deriveKeyIsolate(password, salt);
      authNotifier.unlock(masterKey: masterKey);
    }

    setState(() => _isLoading = false);

    if (mounted) {
      Navigator.pushReplacementNamed(context, AppRoutes.setupMnemonic);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置主密码'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text(
                '设置一个主密码来保护你的所有密码',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 10),
              const Text(
                '请记住这个密码，忘记后需要助记词才能恢复',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 40),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: '主密码',
                  hintText: '至少6位',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
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
              const SizedBox(height: 16),
              TextField(
                controller: _confirmController,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: '确认主密码',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureConfirm
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscureConfirm = !_obscureConfirm;
                      });
                    },
                  ),
                  border: const OutlineInputBorder(),
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
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _handleSubmit,
                  child: _isLoading
                      ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Text('下一步'),
                ),
              ),
              // ✅ 底部留白，防止键盘弹出时内容被遮挡
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}