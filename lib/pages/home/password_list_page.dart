import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/app.dart';
import 'package:password_manager/core/models/password_entry.dart';
import 'package:password_manager/providers/auth_provider.dart';
import 'package:password_manager/providers/password_provider.dart';
import 'package:password_manager/utils/helpers.dart';

/// 密码列表主页
///
/// 显示所有保存的密码条目，支持搜索、添加、编辑、删除
/// 使用 password_provider 管理状态
class PasswordListPage extends ConsumerStatefulWidget {
  const PasswordListPage({super.key});

  @override
  ConsumerState<PasswordListPage> createState() => _PasswordListPageState();
}

class _PasswordListPageState extends ConsumerState<PasswordListPage> {
  // ========== 生命周期方法 ==========

  @override
  void initState() {
    super.initState();
    // 在下一帧加载数据，确保页面已构建完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEntries();
    });
  }

  // ========== 数据操作方法 ==========

  /// 加载密码列表
  Future<void> _loadEntries() async {
    await ref.read(passwordProvider.notifier).loadEntries();
  }

  /// 刷新列表（下拉刷新时调用）
  Future<void> _refresh() async {
    await _loadEntries();
  }

  /// 删除密码条目
  /// [id] 要删除的条目唯一标识
  /// [title] 条目标题（用于确认对话框显示）
  Future<void> _deleteEntry(String id, String title) async {
    // 弹出确认对话框
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
      // 调用 provider 删除
      await ref.read(passwordProvider.notifier).deleteEntry(id);

      // 显示删除成功的提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已删除')),
        );
      }
    }
  }

  /// 复制文本到系统剪贴板
  /// [text] 要复制的文本内容
  /// [label] 文本类型标签（如"用户名"），用于显示提示
  Future<void> _copyToClipboard(String text, String label) async {
    await Helpers.copyToClipboard(text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制 $label')),
      );
    }
  }

  /// 复制密码（需要先解密）
  /// [entry] 密码条目
  Future<void> _copyPassword(PasswordEntry entry) async {
    // 1. 获取主密钥
    final masterKey = ref.read(masterKeyProvider);

    if (masterKey == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('未解锁，请重新登录')),
      );
      return;
    }

    // 2. 检查是否有加密的密码
    if (entry.encryptedPassword == null || entry.encryptedPassword!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有保存密码')),
      );
      return;
    }

    try {
      // 3. 使用 PasswordHelper 解密密码
      final decrypted = await PasswordHelper.decryptPassword(entry, masterKey);

      if (decrypted == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('解密失败')),
        );
        return;
      }

      // 4. 复制到剪贴板
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

  // ========== 界面构建方法 ==========

  @override
  Widget build(BuildContext context) {
    // 监听密码状态
    final passwordState = ref.watch(passwordProvider);
    final masterKey = ref.watch(masterKeyProvider);

    // 从状态中获取数据
    final isLoading = passwordState.isLoading;
    final filteredEntries = passwordState.filteredEntries;
    final searchKeyword = passwordState.searchKeyword;

    return Scaffold(
      // ========== 顶部导航栏 ==========
      appBar: AppBar(
        title: const Text('密码管家'),
        centerTitle: false,
        actions: [
          // 设置按钮
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.pushNamed(context, AppRoutes.settings);
            },
          ),
        ],
        // 底部搜索栏
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: '搜索标题、用户名或备注...',
                prefixIcon: const Icon(Icons.search),
                // 有关键词时显示清除按钮
                suffixIcon: searchKeyword.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    // 调用 provider 清空搜索
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
              // 用户输入时实时搜索
              onChanged: (value) {
                ref.read(passwordProvider.notifier).search(value);
              },
            ),
          ),
        ),
      ),

      // ========== 主体内容 ==========
      body: isLoading
      // 加载中：显示转圈动画
          ? const Center(child: CircularProgressIndicator())
          : filteredEntries.isEmpty
      // 无数据：显示空状态页面
          ? _buildEmptyState()
      // 有数据：显示密码列表（支持下拉刷新）
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

      // ========== 底部添加按钮区域 ==========
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              // 按钮1：从应用列表添加
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(context, AppRoutes.appList).then((_) {
                      // 从应用列表返回后刷新
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

              // 按钮2：手动添加
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(context, AppRoutes.addEdit).then((_) {
                      // 从添加页面返回后刷新
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

  // ========== 子组件 ==========

  /// 空状态页面（没有密码时显示）
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
  /// [entry] 要显示的密码条目对象
  /// [masterKey] 主密钥（用于复制密码时解密）
  Widget _buildEntryCard(PasswordEntry entry, Uint8List? masterKey) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        // 单击：跳转到详情页
        onTap: () {
          Navigator.pushNamed(
            context,
            AppRoutes.detail,
            arguments: entry.id,
          );
        },
        // 长按：显示操作菜单
        onLongPress: () {
          _showBottomSheet(entry, masterKey);
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // ========== 左侧图标 ==========
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

              // ========== 中间内容（标题、用户名、时间） ==========
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题
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

                    // 用户名（如果有才显示）
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

                    // 最后更新时间
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

              // ========== 右侧操作按钮 ==========
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 复制用户名按钮
                  if (entry.username != null && entry.username!.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.person_outline, size: 20),
                      onPressed: () => _copyToClipboard(entry.username!, '用户名'),
                      tooltip: '复制用户名',
                    ),

                  // 复制密码按钮
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

  /// 显示底部操作菜单（长按卡片时触发）
  /// [entry] 当前操作的密码条目
  /// [masterKey] 主密钥
  void _showBottomSheet(PasswordEntry entry, Uint8List? masterKey) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 菜单项1：编辑
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(context); // 关闭菜单
                Navigator.pushNamed(
                  context,
                  AppRoutes.addEdit,
                  arguments: entry,
                ).then((_) {
                  _loadEntries(); // 返回后刷新
                });
              },
            ),

            // 菜单项2：复制用户名
            if (entry.username != null && entry.username!.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('复制用户名'),
                onTap: () {
                  Navigator.pop(context);
                  _copyToClipboard(entry.username!, '用户名');
                },
              ),

            // 菜单项3：复制密码
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('复制密码'),
              onTap: () {
                Navigator.pop(context);
                _copyPassword(entry);
              },
            ),

            // 菜单项4：删除
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