import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/app.dart';
import 'package:password_manager/core/models/password_entry.dart';
import 'package:password_manager/core/storage/shared_prefs.dart';
import 'package:password_manager/providers/auth_provider.dart';
import 'package:password_manager/providers/password_provider.dart';
import 'package:password_manager/utils/helpers.dart';
import 'package:password_manager/utils/toast_utils.dart';

/// 密码列表主页
class PasswordListPage extends ConsumerStatefulWidget {
  const PasswordListPage({super.key});

  @override
  ConsumerState<PasswordListPage> createState() => _PasswordListPageState();
}

class _PasswordListPageState extends ConsumerState<PasswordListPage> {
  Offset _fabPosition = const Offset(0, 0);
  bool _isDragging = false;
  bool _isPositionLoaded = false;
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void dispose() {
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadEntries();
      _loadFabPosition();
    });
  }

  /// 加载保存的按钮位置
  Future<void> _loadFabPosition() async {
    final position = await SharedPrefs.getFabPosition();
    if (position != null) {
      setState(() {
        _fabPosition = position;
        _isPositionLoaded = true;
      });
    } else {
      // ✅ 如果没有保存的位置，初始化
      _initFabPosition();
    }
  }

  /// ✅ 初始化按钮位置（右下角偏上）并保存
  void _initFabPosition() {
    final screenSize = MediaQuery.of(context).size;
    setState(() {
      _fabPosition = Offset(
        screenSize.width - 80,
        screenSize.height * 0.65,
      );
      _isPositionLoaded = true;
    });
    // ✅ 保存初始位置，避免下次启动时重新计算
    _saveFabPosition(_fabPosition);
  }

  /// 保存按钮位置
  Future<void> _saveFabPosition(Offset position) async {
    await SharedPrefs.saveFabPosition(position.dx, position.dy);
  }

  Future<void> _loadEntries() async {
    await ref.read(passwordProvider.notifier).loadEntries();
  }

  Future<void> _refresh() async {
    await _loadEntries();
  }

  Future<void> _deleteEntry(String id, String title) async {
    final confirmed = await ToastUtils.showDangerConfirmDialog(
      context,
      title: '删除',
      content: '确定要删除 "$title" 吗？此操作不可恢复。',
      confirmText: '删除',
    );

    if (confirmed == true) {
      await ref.read(passwordProvider.notifier).deleteEntry(id);
      if (!mounted) return;  // ✅ 添加检查
      ToastUtils.showSuccess(context, '已删除');
    }
  }

  Future<void> _copyToClipboard(String text, String label) async {
    await Helpers.copyToClipboard(text);
    if (!mounted) return;  // ✅ 添加检查
    ToastUtils.showSuccess(context, '已复制 $label');
  }

  Future<void> _copyPassword(PasswordEntry entry) async {
    final masterKey = ref.read(masterKeyProvider);
    if (masterKey == null) {
      if (!mounted) return;  // ✅ 添加检查
      ToastUtils.showError(context, '未解锁，请重新登录');
      return;
    }

    if (entry.encryptedPassword == null || entry.encryptedPassword!.isEmpty) {
      if (!mounted) return;  // ✅ 添加检查
      ToastUtils.showError(context, '没有保存密码');
      return;
    }

    try {
      final decrypted = await PasswordHelper.decryptPassword(entry, masterKey);
      if (decrypted == null) {
        if (!mounted) return;  // ✅ 添加检查
        ToastUtils.showError(context, '解密失败');
        return;
      }

      await Helpers.copyToClipboard(decrypted);
      if (!mounted) return;  // ✅ 添加检查
      ToastUtils.showSuccess(context, '已复制密码');
    } catch (e) {
      if (!mounted) return;  // ✅ 添加检查
      ToastUtils.showError(context, '解密失败: $e');
    }
  }

  void _goToAddEdit() {
    Navigator.pushNamed(context, AppRoutes.addEdit).then((_) {
      _loadEntries();
    });
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
              Navigator.pushNamed(context, AppRoutes.settings);
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              focusNode: _searchFocusNode,
              autofocus: false,  // ✅ 禁用自动焦点
              decoration: InputDecoration(
                hintText: '搜索标题、用户名或备注...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: searchKeyword.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
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
      body: Stack(
        children: [
          // 主内容
          isLoading
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
          // 可拖动的悬浮按钮
          if (_isPositionLoaded)
            Positioned(
              left: _fabPosition.dx,
              top: _fabPosition.dy,
              child: GestureDetector(
                onPanStart: (_) {
                  setState(() => _isDragging = true);
                },
                onPanUpdate: (details) {
                  final screenSize = MediaQuery.of(context).size;
                  final buttonSize = 56.0;
                  final padding = 16.0;

                  double newDx = _fabPosition.dx + details.delta.dx;
                  double newDy = _fabPosition.dy + details.delta.dy;

                  newDx = newDx.clamp(padding, screenSize.width - buttonSize - padding);
                  newDy = newDy.clamp(
                    padding + kToolbarHeight + 60,
                    screenSize.height - buttonSize - padding - 50,
                  );

                  setState(() {
                    _fabPosition = Offset(newDx, newDy);
                  });
                },
                onPanEnd: (_) {
                  setState(() => _isDragging = false);
                  _saveFabPosition(_fabPosition);
                },
                child: FloatingActionButton(
                  onPressed: _isDragging ? null : _goToAddEdit,
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  tooltip: '添加密码',
                  child: const Icon(Icons.add),
                ),
              ),
            ),
        ],
      ),
    );
  }

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
            '点击右下角 + 按钮添加你的第一个密码',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryCard(PasswordEntry entry, Uint8List? masterKey) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(
            context,
            AppRoutes.detail,
            arguments: entry.id,
          ).then((_) {
            // ✅ 返回时清除焦点
            if (mounted) {
              _searchFocusNode.unfocus();
              FocusScope.of(context).unfocus();
            }
          });
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