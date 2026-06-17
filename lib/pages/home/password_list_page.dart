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

  Future<void> _loadFabPosition() async {
    final position = await SharedPrefs.getFabPosition();
    if (position != null) {
      setState(() {
        _fabPosition = position;
        _isPositionLoaded = true;
      });
    } else {
      _initFabPosition();
    }
  }

  void _initFabPosition() {
    final screenSize = MediaQuery.of(context).size;
    setState(() {
      _fabPosition = Offset(
        screenSize.width - 80,
        screenSize.height * 0.65,
      );
      _isPositionLoaded = true;
    });
    _saveFabPosition(_fabPosition);
  }

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
      if (!mounted) return;
      ToastUtils.showSuccess(context, '已删除');
    }
  }

  Future<void> _copyToClipboard(String text, String label) async {
    await Helpers.copyToClipboard(text);
    if (!mounted) return;
    ToastUtils.showSuccess(context, '已复制 $label');
  }

  Future<void> _copyPassword(PasswordEntry entry) async {
    final masterKey = ref.read(masterKeyProvider);
    if (masterKey == null) {
      if (!mounted) return;
      ToastUtils.showError(context, '未解锁，请重新登录');
      return;
    }

    if (entry.encryptedPassword == null || entry.encryptedPassword!.isEmpty) {
      if (!mounted) return;
      ToastUtils.showError(context, '没有保存密码');
      return;
    }

    try {
      final decrypted = await PasswordHelper.decryptPassword(entry, masterKey);
      if (decrypted == null) {
        if (!mounted) return;
        ToastUtils.showError(context, '解密失败');
        return;
      }

      await Helpers.copyToClipboard(decrypted);
      if (!mounted) return;
      ToastUtils.showSuccess(context, '已复制密码');
    } catch (e) {
      if (!mounted) return;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final isLoading = passwordState.isLoading;
    final filteredEntries = passwordState.filteredEntries;
    final searchKeyword = passwordState.searchKeyword;

    return Scaffold(
      appBar: AppBar(
        title: const Text('密码管家'),
        centerTitle: false,
        backgroundColor: isDark ? Colors.grey.shade900 : null,
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
              autofocus: false,
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: '搜索标题、用户名或备注...',
                hintStyle: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
                suffixIcon: searchKeyword.isNotEmpty
                    ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                  onPressed: () {
                    ref.read(passwordProvider.notifier).clearSearch();
                  },
                )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: Theme.of(context).primaryColor,
                  ),
                ),
                filled: true,
                fillColor: isDark ? Colors.grey.shade800 : Colors.white,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_outline,
            size: 80,
            color: isDark ? Colors.grey.shade600 : Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            '还没有任何密码',
            style: TextStyle(
              fontSize: 18,
              color: isDark ? Colors.grey.shade300 : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '点击右下角 + 按钮添加你的第一个密码',
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.grey.shade500 : Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryCard(PasswordEntry entry, Uint8List? masterKey) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: isDark ? Colors.grey.shade800 : Colors.white,
      elevation: isDark ? 0 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isDark
            ? BorderSide(color: Colors.grey.shade700, width: 0.5)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () {
          Navigator.pushNamed(
            context,
            AppRoutes.detail,
            arguments: entry.id,
          ).then((_) {
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
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.15),
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
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black87,
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
                          color: isDark ? Colors.grey.shade400 : Colors.grey[600],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    Text(
                      Helpers.formatDate(entry.updatedAt),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.grey.shade500 : Colors.grey[500],
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
                      icon: Icon(
                        Icons.person_outline,
                        size: 20,
                        color: isDark ? Colors.grey.shade400 : Colors.grey[600],
                      ),
                      onPressed: () => _copyToClipboard(entry.username!, '用户名'),
                      tooltip: '复制用户名',
                    ),
                  IconButton(
                    icon: Icon(
                      Icons.copy,
                      size: 20,
                      color: isDark ? Colors.grey.shade400 : Colors.grey[600],
                    ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? Colors.grey.shade800 : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.edit, color: isDark ? Colors.white : null),
              title: Text(
                '编辑',
                style: TextStyle(color: isDark ? Colors.white : null),
              ),
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
                leading: Icon(Icons.copy, color: isDark ? Colors.white : null),
                title: Text(
                  '复制用户名',
                  style: TextStyle(color: isDark ? Colors.white : null),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _copyToClipboard(entry.username!, '用户名');
                },
              ),
            ListTile(
              leading: Icon(Icons.copy, color: isDark ? Colors.white : null),
              title: Text(
                '复制密码',
                style: TextStyle(color: isDark ? Colors.white : null),
              ),
              onTap: () {
                Navigator.pop(context);
                _copyPassword(entry);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text(
                '删除',
                style: TextStyle(color: Colors.red),
              ),
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