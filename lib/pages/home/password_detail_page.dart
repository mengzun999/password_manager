// password_detail_page.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/app.dart';
import 'package:password_manager/core/crypto/aes_gcm.dart';
import 'package:password_manager/core/models/password_entry.dart';
import 'package:password_manager/core/models/image_model.dart';
import 'package:password_manager/core/services/image_service.dart';
import 'package:password_manager/core/storage/database.dart';
import 'package:password_manager/providers/auth_provider.dart';
import 'package:password_manager/utils/helpers.dart';
import 'package:password_manager/pages/image_viewer_page.dart';
import '../../utils/toast_utils.dart';

/// 密码详情页面
class PasswordDetailPage extends ConsumerStatefulWidget {
  final String entryId;

  const PasswordDetailPage({super.key, required this.entryId});

  @override
  ConsumerState<PasswordDetailPage> createState() => _PasswordDetailPageState();
}

class _PasswordDetailPageState extends ConsumerState<PasswordDetailPage> {
  // ========== 密码数据 ==========
  PasswordEntry? _entry;
  bool _isLoading = true;

  // ========== 密码显示 ==========
  bool _passwordHidden = true;
  String? _decryptedPassword;
  bool _isDecrypting = false;

  // ========== 图片数据 ==========
  List<ImageModel> _imageModels = [];
  List<Uint8List> _imageThumbnails = [];
  bool _isLoadingImages = false;

  // ✅ 修复：使用 imageModel.id 作为缓存键，而不是 index
  final Map<String, Uint8List> _cachedFullImages = {};

  // ✅ 点击图片加载状态
  bool _isLoadingFullImage = false;

  // ✅ 页面是否已销毁
  bool _isDisposed = false;

  // ========== 生命周期方法 ==========

  @override
  void initState() {
    super.initState();
    _loadEntry();
  }

  @override
  void dispose() {
    _isDisposed = true;
    // ✅ 离开页面时清理所有缓存
    _cachedFullImages.clear();
    super.dispose();
  }

  // ========== 数据加载方法 ==========

  Future<void> _loadEntry() async {
    if (_isDisposed) return;

    setState(() {
      _isLoading = true;
      _decryptedPassword = null;
      _passwordHidden = true;
    });

    final entry = await DatabaseHelper.getEntryById(widget.entryId);

    if (_isDisposed) return;

    setState(() {
      _entry = entry;
      _isLoading = false;
    });

    if (entry != null) {
      _loadImages();
    }
  }

  Future<void> _loadImages() async {
    if (_entry == null || _isDisposed) return;

    setState(() => _isLoadingImages = true);

    try {
      final masterKey = _getMasterKey();
      if (masterKey == null) {
        if (!_isDisposed) {
          setState(() => _isLoadingImages = false);
        }
        return;
      }

      final images = await ImageService.getEntryImages(_entry!.id);
      if (_isDisposed) return;

      final thumbnails = <Uint8List>[];

      for (final image in images) {
        if (_isDisposed) break;
        final thumb = await ImageService.getThumbnail(image, masterKey);
        if (thumb != null) {
          thumbnails.add(thumb);
        }
      }

      if (_isDisposed) return;

      setState(() {
        _imageModels = images;
        _imageThumbnails = thumbnails;
        _isLoadingImages = false;
      });
    } catch (e) {
      print('加载图片失败: $e');
      if (!_isDisposed) {
        setState(() => _isLoadingImages = false);
      }
    }
  }

  Uint8List? _getMasterKey() {
    final authState = ref.read(authProvider);
    return authState.masterKey;
  }

  // ========== 密码操作 ==========

  Future<void> _decryptPassword() async {
    if (_isDisposed) return;

    final masterKey = _getMasterKey();
    if (masterKey == null) {
      if (mounted) {
        ToastUtils.showError(context, '未解锁，请重新登录');
      }
      return;
    }

    if (_entry?.encryptedPassword == null || _entry!.encryptedPassword!.isEmpty) {
      return;
    }

    if (_decryptedPassword != null) {
      return;
    }

    setState(() {
      _isDecrypting = true;
    });

    try {
      final decrypted = await AESGCMHelper.decrypt(
        _entry!.encryptedPassword!,
        masterKey,
      );

      if (_isDisposed) return;

      setState(() {
        _decryptedPassword = decrypted;
        _isDecrypting = false;
      });
    } catch (e) {
      if (_isDisposed) return;
      setState(() {
        _isDecrypting = false;
      });
      if (mounted) {
        ToastUtils.showError(context, '解密失败: $e');
      }
    }
  }

  Future<void> _copyToClipboard(String text, String label) async {
    await Helpers.copyToClipboard(text);
    if (mounted && !_isDisposed) {
      ToastUtils.showSuccess(context, '已复制 $label');
    }
  }

  Future<void> _deleteEntry() async {
    if (_isDisposed) return;

    final confirmed = await ToastUtils.showDangerConfirmDialog(
      context,
      title: '删除',
      content: '确定要删除 "${_entry?.title}" 吗？\n\n注意：关联的图片也会被删除。',
      confirmText: '删除',
    );

    if (confirmed == true && _entry != null) {
      final masterKey = _getMasterKey();
      if (masterKey != null) {
        await ImageService.deleteAllImagesForEntry(_entry!.id, masterKey);
      }
      await DatabaseHelper.deleteEntry(_entry!.id);
      if (mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  // ✅ 查看大图 - 使用 imageModel.id 作为缓存键
  void _viewImage(int index) async {
    if (_isDisposed) return;
    if (index >= _imageThumbnails.length) return;
    if (_entry == null) return;

    final masterKey = _getMasterKey();
    if (masterKey == null) {
      ToastUtils.showError(context, '未解锁，请重新登录');
      return;
    }

    final imageModel = _imageModels[index];
    final imageId = imageModel.id;

    // ✅ 使用 imageModel.id 作为缓存键
    Uint8List? fullImage = _cachedFullImages[imageId];
    if (fullImage != null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImageViewerPage(
            imageModels: _imageModels,
            thumbnails: _imageThumbnails,
            initialIndex: index,
            entryId: _entry!.id,
            preloadedImage: fullImage,
          ),
        ),
      ).then((_) {
        if (!_isDisposed) {
          _refreshImages();
        }
      });
      return;
    }

    // ✅ 没有缓存：先显示转圈，在 isolate 中加载
    setState(() => _isLoadingFullImage = true);
    await Future.delayed(Duration.zero);

    fullImage = await ImageService.loadImageInIsolate(imageModel, masterKey);

    if (_isDisposed) return;

    setState(() => _isLoadingFullImage = false);

    if (fullImage == null) {
      if (mounted && !_isDisposed) {
        ToastUtils.showError(context, '加载图片失败，请重试');
      }
      return;
    }

    // ✅ 存入缓存（使用 imageModel.id 作为键）
    _cachedFullImages[imageId] = fullImage;

    // ✅ 直接进入查看器（转圈已结束）
    if (mounted && !_isDisposed) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImageViewerPage(
            imageModels: _imageModels,
            thumbnails: _imageThumbnails,
            initialIndex: index,
            entryId: _entry!.id,
            preloadedImage: fullImage,
          ),
        ),
      ).then((_) {
        if (!_isDisposed) {
          _refreshImages();
        }
      });
    }
  }

  // ✅ 刷新缩略图，同时清理已删除图片的缓存
  Future<void> _refreshImages() async {
    if (_entry == null || _isDisposed) return;

    try {
      final masterKey = _getMasterKey();
      if (masterKey == null) return;

      final images = await ImageService.getEntryImages(_entry!.id);
      if (_isDisposed) return;

      // ✅ 获取当前图片 ID 列表
      final currentImageIds = images.map((e) => e.id).toSet();

      // ✅ 清理缓存中已被删除的图片
      _cachedFullImages.removeWhere((key, value) => !currentImageIds.contains(key));

      final thumbnails = <Uint8List>[];
      for (final image in images) {
        if (_isDisposed) break;
        final thumb = await ImageService.getThumbnail(image, masterKey);
        if (thumb != null) {
          thumbnails.add(thumb);
        }
      }

      if (_isDisposed) return;

      setState(() {
        _imageModels = images;
        _imageThumbnails = thumbnails;
      });
    } catch (e) {
      // 静默失败
    }
  }

  // ========== 界面构建 ==========

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('密码详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              if (_entry != null && !_isDisposed) {
                Navigator.pushNamed(
                  context,
                  AppRoutes.addEdit,
                  arguments: _entry,
                ).then((_) {
                  if (!_isDisposed) {
                    _loadEntry();
                  }
                });
              }
            },
          ),
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
          : Stack(
        children: [
          _buildContent(),
          // ✅ 加载转圈（覆盖整个页面）
          if (_isLoadingFullImage)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: const Center(
                child: SizedBox(
                  width: 50,
                  height: 50,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color: isDark ? Colors.grey.shade500 : Colors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            '密码条目不存在',
            style: TextStyle(
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final entry = _entry!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection(
            title: '标题',
            icon: Icons.title,
            content: entry.title,
          ),
          const SizedBox(height: 16),

          if (entry.username != null && entry.username!.isNotEmpty)
            _buildSection(
              title: '用户名',
              icon: Icons.person,
              content: entry.username!,
              onCopy: () => _copyToClipboard(entry.username!, '用户名'),
            ),

          if (entry.username != null && entry.username!.isNotEmpty)
            const SizedBox(height: 16),

          if (entry.encryptedPassword != null && entry.encryptedPassword!.isNotEmpty)
            _buildPasswordSection(),

          if (entry.encryptedPassword != null && entry.encryptedPassword!.isNotEmpty)
            const SizedBox(height: 16),

          if (entry.notes != null && entry.notes!.isNotEmpty)
            _buildSection(
              title: '备注',
              icon: Icons.note,
              content: entry.notes!,
            ),

          const SizedBox(height: 16),

          _buildImageSection(),

          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 16,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Text(
                  '最后修改：${Helpers.formatDate(entry.updatedAt)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required String content,
    VoidCallback? onCopy,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 20,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              const Spacer(),
              if (onCopy != null)
                IconButton(
                  icon: Icon(
                    Icons.copy,
                    size: 18,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
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
            style: TextStyle(
              fontSize: 16,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordSection() {
    final entry = _entry!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

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
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lock,
                size: 20,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
              const SizedBox(width: 8),
              Text(
                '密码',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  _passwordHidden ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
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
              IconButton(
                icon: Icon(
                  Icons.copy,
                  size: 18,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
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
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImageSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoadingImages) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade800 : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              '加载图片中...',
              style: TextStyle(
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    if (_imageThumbnails.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.image,
              size: 20,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
            const SizedBox(width: 8),
            Text(
              '图片（${_imageThumbnails.length}张）',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: _imageThumbnails.length > 8 ? 9 : _imageThumbnails.length,
          itemBuilder: (context, index) {
            if (_imageThumbnails.length > 8 && index == 8) {
              final remaining = _imageThumbnails.length - 8;
              return _buildMoreImagesButton(remaining);
            }
            return _buildImageThumbnail(index);
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildImageThumbnail(int index) {
    final imageBytes = _imageThumbnails[index];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => _viewImage(index),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            imageBytes,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
              child: Icon(
                Icons.broken_image,
                color: isDark ? Colors.grey.shade500 : Colors.grey,
                size: 32,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMoreImagesButton(int remaining) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => _viewImage(8),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
          border: Border.all(
            color: isDark ? Colors.grey.shade600 : Colors.grey.shade300,
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.more_horiz,
                size: 24,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
              const SizedBox(height: 2),
              Text(
                '+$remaining',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}