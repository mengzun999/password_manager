import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/app.dart';
import 'package:password_manager/core/models/password_entry.dart';
import 'package:password_manager/providers/auth_provider.dart';
import 'package:password_manager/providers/password_provider.dart';
import 'package:password_manager/utils/helpers.dart';

/// 密码列表主页
class PasswordListPage extends ConsumerStatefulWidget {
  const PasswordListPage({super.key});

  @override
  ConsumerState<PasswordListPage> createState() => _PasswordListPageState();
}

class _PasswordListPageState extends ConsumerState<PasswordListPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEntries();
    });
  }

  /// 加载密码列表
  Future<void> _loadEntries() async {
    // ✅ 用户执行操作，更新活动时间（防止自动锁定）
    await ref.read(passwordProvider.notifier).loadEntries();
  }

  /// 刷新列表（下拉刷新时调用）
  Future<void> _refresh() async {
    // ✅ 用户执行操作，更新活动时间
    await _loadEntries();
  }

  /// 删除密码条目
  Future<void> _deleteEntry(String id, String title) async {
    // ✅ 用户执行操作，更新活动时间

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除'),
        content: Text('确定要删除 "$title" 吗？此操作不可恢复。'),
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

    if (confirmed == true) {
      await ref.read(passwordProvider.notifier).deleteEntry(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已删除')),
        );
      }
    }
  }

  /// 复制文本到系统剪贴板
  Future<void> _copyToClipboard(String text, String label) async {
    await Helpers.copyToClipboard(text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制 $label')),
      );
    }
  }

  /// 复制密码（需要先解密）
  Future<void> _copyPassword(PasswordEntry entry) async {


    final masterKey = ref.read(masterKeyProvider);
    if (masterKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未解锁，请重新登录')),
      );
      return;
    }

    if (entry.encryptedPassword == null || entry.encryptedPassword!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有保存密码')),
      );
      return;
    }

    try {
      final decrypted = await PasswordHelper.decryptPassword(entry, masterKey);
      if (decrypted == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('解密失败')),
        );
        return;
      }

      await Helpers.copyToClipboard(decrypted);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已复制密码')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解密失败: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final passwordState = ref.watch(passwordProvider);
    final masterKey = ref.watch(masterKeyProvider);

    final isLoading = passwordState.isLoading;
    final filteredEntries = passwordState.filteredEntries;
    final searchKeyword = passwordState.searchKeyword;

    return Scaffold(
      appBar: AppBar(
        title: const Text('密码管家'),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              // ✅ 用户执行操作，更新活动时间
              Navigator.pushNamed(context, AppRoutes.settings);
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索标题、用户名或备注...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchKeyword.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    // ✅ 用户执行操作，更新活动时间
                    ref.read(passwordProvider.notifier).clearSearch();
                  },
                )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                filled: true,
                fillColor: Theme.of(context).brightness == Brightness.light
                    ? Colors.white
                    : Colors.grey[800],
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
              ),
              onChanged: (value) {
                ref.read(passwordProvider.notifier).search(value);
              },
            ),
          ),
        ),
      ),

      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : filteredEntries.isEmpty
          ? _buildEmptyState()
          : RefreshIndicator(
        onRefresh: _refresh,
        child: ListView.builder(
          itemCount: filteredEntries.length,
          itemBuilder: (context, index) {
            final entry = filteredEntries[index];
            return _buildEntryCard(entry, masterKey);
          },
        ),
      ),

      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(context, AppRoutes.appList).then((_) {
                      _loadEntries();
                    });
                  },
                  icon: const Icon(Icons.apps),
                  label: const Text('从应用列表添加'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    // ✅ 用户执行操作，更新活动时间
                    Navigator.pushNamed(context, AppRoutes.addEdit).then((_) {
                      _loadEntries();
                    });
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('手动添加'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 空状态页面
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_outline,
            size: 80,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '还没有任何密码',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击底部按钮添加你的第一个密码',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  /// 单个密码条目卡片
  Widget _buildEntryCard(PasswordEntry entry, Uint8List? masterKey) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(
            context,
            AppRoutes.detail,
            arguments: entry.id,
          );
        },
        onLongPress: () {
          _showBottomSheet(entry, masterKey);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.lock,
                  color: Theme.of(context).primaryColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    if (entry.username != null && entry.username!.isNotEmpty)
                      Text(
                        entry.username!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      Helpers.formatDate(entry.updatedAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (entry.username != null && entry.username!.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.person_outline, size: 20),
                      onPressed: () => _copyToClipboard(entry.username!, '用户名'),
                      tooltip: '复制用户名',
                    ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 20),
                    onPressed: () {
                      _copyPassword(entry);
                    },
                    tooltip: '复制密码',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示底部操作菜单
  void _showBottomSheet(PasswordEntry entry, Uint8List? masterKey) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(
                  context,
                  AppRoutes.addEdit,
                  arguments: entry,
                ).then((_) {
                  _loadEntries();
                });
              },
            ),
            if (entry.username != null && entry.username!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('复制用户名'),
                onTap: () {
                  Navigator.pop(context);
                  _copyToClipboard(entry.username!, '用户名');
                },
              ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制密码'),
              onTap: () {
                Navigator.pop(context);
                _copyPassword(entry);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete),
              title: const Text('删除'),
              onTap: () {
                Navigator.pop(context);
                _deleteEntry(entry.id, entry.title);
              },
            ),
          ],
        ),
      ),
    );
  }
}