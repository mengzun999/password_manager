import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/core/crypto/aes_gcm.dart';
import 'package:password_manager/core/models/password_entry.dart';
import 'package:password_manager/core/storage/database.dart';
import 'package:password_manager/providers/auth_provider.dart';
import 'package:password_manager/utils/helpers.dart';

/// 添加/编辑密码页面
class AddEditPage extends ConsumerStatefulWidget {
  final PasswordEntry? entry;   // 有值表示编辑模式，null表示添加模式
  final String? presetTitle;    // 新增：从应用列表传来的预设标题

  const AddEditPage({super.key, this.entry, this.presetTitle});

  @override
  ConsumerState<AddEditPage> createState() => _AddEditPageState();
}

class _AddEditPageState extends ConsumerState<AddEditPage> {
  // ========== 控制器 ==========
  final _titleController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _notesController = TextEditingController();

  // ========== UI 状态 ==========
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _error;

  // ========== 生命周期 ==========
  @override
  void initState() {
    super.initState();
    _loadEntryData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// 加载编辑模式下的数据
  void _loadEntryData() {
    if (widget.entry != null) {
      // 编辑模式：加载已有数据
      _titleController.text = widget.entry!.title;
      _usernameController.text = widget.entry!.username ?? '';
      // 密码需要解密，暂时留空
      _notesController.text = widget.entry!.notes ?? '';
    } else if (widget.presetTitle != null) {
      // 从应用列表添加模式：预设标题
      _titleController.text = widget.presetTitle!;
    }
  }

  /// 生成随机密码
  void _generatePassword() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*()';
    final random = Helpers.generateRandomString(16, chars);
    _passwordController.text = random;
  }

  /// 清空密码框
  void _clearPassword() {
    _passwordController.clear();
  }

  /// 保存密码
  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '请输入标题');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final now = Helpers.currentTimestamp();

    // ========== 加密密码 ==========
    String? encryptedPassword;
    final plainPassword = _passwordController.text.trim();

    if (plainPassword.isNotEmpty) {
      // 1. 获取主密钥
      final masterKey = _getMasterKey();

      if (masterKey == null) {
        setState(() {
          _isLoading = false;
          _error = '未解锁，请重新登录';
        });
        return;
      }

      // 2. 加密密码
      try {
        encryptedPassword = await AESGCMHelper.encrypt(plainPassword, masterKey);
      } catch (e) {
        setState(() {
          _isLoading = false;
          _error = '加密失败: $e';
        });
        return;
      }
    }

    // ========== 保存到数据库 ==========
    if (widget.entry == null) {
      // 添加模式
      final entry = PasswordEntry(
        id: Helpers.generateUuid(),
        title: title,
        username: _usernameController.text.trim().isEmpty
            ? null
            : _usernameController.text.trim(),
        encryptedPassword: encryptedPassword,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        appPackageName: null,
        createdAt: now,
        updatedAt: now,
      );
      await DatabaseHelper.insertEntry(entry);
    } else {
      // 编辑模式
      final updatedEntry = widget.entry!.copyWith(
        title: title,
        username: _usernameController.text.trim().isEmpty
            ? null
            : _usernameController.text.trim(),
        encryptedPassword: encryptedPassword,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        updatedAt: now,
      );
      await DatabaseHelper.updateEntry(updatedEntry);
    }

    setState(() => _isLoading = false);

    if (mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditMode = widget.entry != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditMode ? '编辑密码' : '添加密码'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // 标题输入框
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: '标题 *',
                    hintText: '例如：微信、支付宝',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // 用户名输入框
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: '用户名',
                    hintText: '手机号/邮箱/账号',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // 密码输入框（带生成器悬浮球）
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: '密码',
                    hintText: '留空表示不保存密码',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 备注输入框
                TextField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: '备注',
                    hintText: '可选',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),

          // 悬浮球（密码生成器）
          Positioned(
            bottom: 80,
            right: 16,
            child: GestureDetector(
              onTap: _generatePassword,
              onLongPress: _clearPassword,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha:0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 获取主密钥（从 AuthProvider）
  Uint8List? _getMasterKey() {
    final authState = ref.read(authProvider);
    return authState.masterKey;
  }


}