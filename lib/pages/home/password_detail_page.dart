import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/app.dart';
import 'package:password_manager/core/crypto/aes_gcm.dart';
import 'package:password_manager/core/models/password_entry.dart';
import 'package:password_manager/core/storage/database.dart';
import 'package:password_manager/providers/auth_provider.dart';
import 'package:password_manager/utils/helpers.dart';

/// 密码详情页面
///
/// 显示单条密码的完整信息
/// 支持复制用户名、复制密码、编辑、删除
class PasswordDetailPage extends ConsumerStatefulWidget {
  /// 密码条目ID（从列表页传递过来）
  final String entryId;

  const PasswordDetailPage({super.key, required this.entryId});

  @override
  ConsumerState<PasswordDetailPage> createState() => _PasswordDetailPageState();
}

class _PasswordDetailPageState extends ConsumerState<PasswordDetailPage> {
  /// 密码条目数据
  PasswordEntry? _entry;

  /// 是否正在加载
  bool _isLoading = true;

  /// 密码是否隐藏（true=隐藏，false=显示）
  bool _passwordHidden = true;

  /// 解密后的密码（用于显示和复制）
  String? _decryptedPassword;

  /// 是否正在解密密码
  bool _isDecrypting = false;

  // ========== 生命周期方法 ==========

  @override
  void initState() {
    super.initState();
    _loadEntry();
  }

  // ========== 数据操作方法 ==========

  /// 从数据库加载密码条目
  Future<void> _loadEntry() async {
    setState(() {
      _isLoading = true;
      // 重置解密状态（因为条目可能已更新）
      _decryptedPassword = null;
      _passwordHidden = true;
    });

    final entry = await DatabaseHelper.getEntryById(widget.entryId);

    setState(() {
      _entry = entry;
      _isLoading = false;
    });
  }

  /// 解密密码
  Future<void> _decryptPassword() async {
    // 1. 获取主密钥
    final authState = ref.read(authProvider);
    final masterKey = authState.masterKey;

    if (masterKey == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未解锁，请重新登录')),
        );
      }
      return;
    }

    // 2. 检查是否有加密的密码
    if (_entry?.encryptedPassword == null || _entry!.encryptedPassword!.isEmpty) {
      return;
    }

    // 3. 如果已经解密过，直接返回
    if (_decryptedPassword != null) {
      return;
    }

    setState(() {
      _isDecrypting = true;
    });

    try {
      // 4. 解密密码
      final decrypted = await AESGCMHelper.decrypt(
        _entry!.encryptedPassword!,
        masterKey,
      );

      setState(() {
        _decryptedPassword = decrypted;
        _isDecrypting = false;
      });
    } catch (e) {
      setState(() {
        _isDecrypting = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解密失败: $e')),
        );
      }
    }
  }

  /// 复制文本到剪贴板
  Future<void> _copyToClipboard(String text, String label) async {
    await Helpers.copyToClipboard(text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制 $label')),
      );
    }
  }

  /// 删除当前密码条目
  Future<void> _deleteEntry() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除'),
        content: Text('确定要删除 "${_entry?.title}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && _entry != null) {
      await DatabaseHelper.deleteEntry(_entry!.id);
      if (mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  // ========== 界面构建方法 ==========

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('密码详情'),
        actions: [
          // 编辑按钮
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              if (_entry != null) {
                Navigator.pushNamed(
                  context,
                  AppRoutes.addEdit,
                  arguments: _entry,
                ).then((_) {
                  _loadEntry();
                });
              }
            },
          ),
          // 删除按钮
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _deleteEntry,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _entry == null
          ? _buildErrorState()
          : _buildContent(),
    );
  }

  /// 错误状态（数据不存在）
  Widget _buildErrorState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('密码条目不存在'),
        ],
      ),
    );
  }

  /// 主要内容
  Widget _buildContent() {
    final entry = _entry!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题区域
          _buildSection(
            title: '标题',
            icon: Icons.title,
            content: entry.title,
          ),

          const SizedBox(height: 16),

          // 用户名区域（如果有）
          if (entry.username != null && entry.username!.isNotEmpty)
            _buildSection(
              title: '用户名',
              icon: Icons.person,
              content: entry.username!,
              onCopy: () => _copyToClipboard(entry.username!, '用户名'),
            ),

          if (entry.username != null && entry.username!.isNotEmpty)
            const SizedBox(height: 16),

          // 密码区域（如果有）
          if (entry.encryptedPassword != null && entry.encryptedPassword!.isNotEmpty)
            _buildPasswordSection(),

          if (entry.encryptedPassword != null && entry.encryptedPassword!.isNotEmpty)
            const SizedBox(height: 16),

          // 备注区域（如果有）
          if (entry.notes != null && entry.notes!.isNotEmpty)
            _buildSection(
              title: '备注',
              icon: Icons.note,
              content: entry.notes!,
            ),

          const SizedBox(height: 24),

          // 最后修改时间
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Text(
                  '最后修改：${Helpers.formatDate(entry.updatedAt)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 信息区块（标题、用户名、备注共用）
  Widget _buildSection({
    required String title,
    required IconData icon,
    required String content,
    VoidCallback? onCopy,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: Colors.grey[600]),  // 改用 Colors.grey[600]
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),  // 改用 Colors.grey[600]
              ),
              const Spacer(),
              if (onCopy != null)
                IconButton(
                  icon: Icon(Icons.copy, size: 18, color: Colors.grey[600]),  // 改用 Colors.grey[600]
                  onPressed: onCopy,
                  tooltip: '复制',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }

  /// 密码区块（带显示/隐藏切换）
  Widget _buildPasswordSection() {
    final entry = _entry!;

    // 确定显示的密码
    String displayPassword;
    if (_decryptedPassword == null) {
      displayPassword = '********';
    } else if (_passwordHidden) {
      displayPassword = '********';
    } else {
      displayPassword = _decryptedPassword!;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题行
          Row(
            children: [
              Icon(Icons.lock, size: 20, color: Colors.grey[600]),  // 改用 Colors.grey[600]
              const SizedBox(width: 8),
              Text(
                '密码',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),  // 改用 Colors.grey[600]
              ),
              const Spacer(),
              // 显示/隐藏按钮
              IconButton(
                icon: Icon(
                  _passwordHidden ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                  color: Colors.grey[600],  // 改用 Colors.grey[600]
                ),
                onPressed: () async {
                  if (_decryptedPassword == null && !_isDecrypting) {
                    await _decryptPassword();
                  }
                  setState(() {
                    _passwordHidden = !_passwordHidden;
                  });
                },
                tooltip: _passwordHidden ? '显示密码' : '隐藏密码',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 8),
              // 复制按钮
              IconButton(
                icon: Icon(Icons.copy, size: 18, color: Colors.grey[600]),  // 改用 Colors.grey[600]
                onPressed: () async {
                  if (_decryptedPassword == null && !_isDecrypting) {
                    await _decryptPassword();
                  }
                  if (_decryptedPassword != null) {
                    await _copyToClipboard(_decryptedPassword!, '密码');
                  }
                },
                tooltip: '复制密码',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 密码内容
          if (_isDecrypting)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            SelectableText(
              displayPassword,
              style: const TextStyle(fontSize: 16),
            ),
        ],
      ),
    );
  }
}