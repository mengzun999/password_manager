// password_detail_page.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/scheduler.dart';
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
  final PasswordEntry entry;  // ✅ 直接接收 Entry 对象

  const PasswordDetailPage({super.key, required this.entry});

  @override
  ConsumerState<PasswordDetailPage> createState() => _PasswordDetailPageState();
}

class _PasswordDetailPageState extends ConsumerState<PasswordDetailPage> with WidgetsBindingObserver {
  // ========== 数据 ==========
  late PasswordEntry _entry;

  // ========== 密码显示 ==========
  bool _passwordHidden = true;
  String? _decryptedPassword;
  bool _isDecrypting = false;

  // ========== 图片 ==========
  List<ImageModel> _imageModels = [];
  List<Uint8List> _imageThumbnails = [];
  bool _isLoadingImages = false;
  bool _isDisposed = false;

  // ✅ 缓存
  final Map<String, Uint8List> _cachedFullImages = {};
  bool _isLoadingFullImage = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _entry = widget.entry;

    // ✅ 延迟加载图片，让第一帧先渲染
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_isDisposed) {
        _loadImagesAsync();
      }
    });
  }

  @override
  void dispose() {
    _isDisposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _cachedFullImages.clear();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isDisposed) {
      _refreshImages();
    }
  }

  // ========== ✅ 图片加载 ==========

  Future<void> _loadImagesAsync() async {
    if (_isDisposed) return;

    setState(() => _isLoadingImages = true);

    try {
      final masterKey = _getMasterKey();
      if (masterKey == null) {
        setState(() => _isLoadingImages = false);
        return;
      }

      // ✅ 查询图片列表（轻量操作）
      final images = await DatabaseHelper.getImagesByEntryId(_entry.id);
      if (_isDisposed) return;

      if (images.isEmpty) {
        setState(() {
          _imageModels = [];
          _imageThumbnails = [];
          _isLoadingImages = false;
        });
        return;
      }

      // ✅ 先显示占位，再分批加载缩略图
      setState(() {
        _imageModels = images;
        _imageThumbnails = List.generate(images.length, (_) => Uint8List(0));
        _isLoadingImages = false;
      });

      // ✅ 分批加载缩略图（每批 3 张）
      await _loadThumbnailsBatch(images, masterKey);

    } catch (e) {
      if (!_isDisposed) {
        setState(() => _isLoadingImages = false);
      }
    }
  }

  // ✅ 分批加载缩略图
  Future<void> _loadThumbnailsBatch(List<ImageModel> images, Uint8List masterKey) async {
    const batchSize = 3;
    final total = images.length;

    for (int start = 0; start < total; start += batchSize) {
      if (_isDisposed) return;

      final end = (start + batchSize).clamp(0, total);
      final batch = images.sublist(start, end);

      // ✅ 并发解密当前批次
      final results = await Future.wait(
        batch.map((image) async {
          try {
            final thumb = await ImageService.getThumbnail(image, masterKey);
            return thumb ?? Uint8List(0);
          } catch (_) {
            return Uint8List(0);
          }
        }),
      );

      if (_isDisposed) return;

      // ✅ 更新 UI
      setState(() {
        for (int i = 0; i < results.length; i++) {
          final index = start + i;
          if (index < _imageThumbnails.length) {
            _imageThumbnails[index] = results[i];
          }
        }
      });

      // ✅ 每批之间让出 UI 线程
      if (end < total) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  // ✅ 刷新图片
  Future<void> _refreshImages() async {
    if (_isDisposed) return;

    try {
      final masterKey = _getMasterKey();
      if (masterKey == null) return;

      final images = await DatabaseHelper.getImagesByEntryId(_entry.id);
      if (_isDisposed) return;

      final currentIds = images.map((e) => e.id).toSet();
      _cachedFullImages.removeWhere((key, value) => !currentIds.contains(key));

      setState(() {
        _imageModels = images;
        _imageThumbnails = List.generate(images.length, (_) => Uint8List(0));
      });

      if (images.isNotEmpty) {
        await _loadThumbnailsBatch(images, masterKey);
      }
    } catch (_) {}
  }

  // ========== ✅ 查看大图 ==========

  void _viewImage(int index) async {
    if (_isDisposed) return;
    if (index >= _imageModels.length) return;

    final masterKey = _getMasterKey();
    if (masterKey == null) {
      ToastUtils.showError(context, '未解锁，请重新登录');
      return;
    }

    final imageModel = _imageModels[index];
    final imageId = imageModel.id;

    // ✅ 检查缓存
    if (_cachedFullImages.containsKey(imageId)) {
      _navigateToViewer(index, _cachedFullImages[imageId]!);
      return;
    }

    // ✅ 加载原图
    setState(() => _isLoadingFullImage = true);
    await Future.delayed(Duration.zero);

    final fullImage = await ImageService.loadImageInIsolate(imageModel, masterKey);

    if (_isDisposed) return;
    setState(() => _isLoadingFullImage = false);

    if (fullImage == null) {
      ToastUtils.showError(context, '加载图片失败');
      return;
    }

    _cachedFullImages[imageId] = fullImage;
    _navigateToViewer(index, fullImage);
  }

  void _navigateToViewer(int index, Uint8List fullImage) {
    if (!mounted || _isDisposed) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageViewerPage(
          imageModels: _imageModels,
          thumbnails: _imageThumbnails,
          initialIndex: index,
          entryId: _entry.id,
          preloadedImage: fullImage,
        ),
      ),
    ).then((_) {
      if (!_isDisposed) {
        _refreshImages();
      }
    });
  }

  // ========== ✅ 密码操作 ==========

  Uint8List? _getMasterKey() {
    return ref.read(authProvider).masterKey;
  }

  Future<void> _decryptPassword() async {
    if (_isDisposed) return;

    final masterKey = _getMasterKey();
    if (masterKey == null) {
      ToastUtils.showError(context, '未解锁，请重新登录');
      return;
    }

    if (_entry.encryptedPassword == null || _entry.encryptedPassword!.isEmpty) {
      return;
    }

    if (_decryptedPassword != null) return;

    setState(() => _isDecrypting = true);

    try {
      final decrypted = await AESGCMHelper.decrypt(
        _entry.encryptedPassword!,
        masterKey,
      );
      if (!_isDisposed) {
        setState(() {
          _decryptedPassword = decrypted;
          _isDecrypting = false;
        });
      }
    } catch (e) {
      if (!_isDisposed) {
        setState(() => _isDecrypting = false);
        ToastUtils.showError(context, '解密失败: $e');
      }
    }
  }

  Future<void> _copyToClipboard(String text, String label) async {
    await Helpers.copyToClipboard(text);
    if (mounted) {
      ToastUtils.showSuccess(context, '已复制 $label');
    }
  }

  Future<void> _deleteEntry() async {
    if (_isDisposed) return;

    final confirmed = await ToastUtils.showDangerConfirmDialog(
      context,
      title: '删除',
      content: '确定要删除 "${_entry.title}" 吗？\n\n关联的图片也会被删除。',
      confirmText: '删除',
    );

    if (confirmed == true) {
      final masterKey = _getMasterKey();
      if (masterKey != null) {
        await ImageService.deleteAllImagesForEntry(_entry.id, masterKey);
      }
      await DatabaseHelper.deleteEntry(_entry.id);
      if (mounted) {
        Navigator.pop(context, true);
      }
    }
  }

  // ========== ✅ UI 构建 ==========

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
              if (!_isDisposed) {
                Navigator.pushNamed(
                  context,
                  AppRoutes.addEdit,
                  arguments: _entry,
                ).then((_) {
                  if (!_isDisposed) {
                    // ✅ 编辑返回后刷新
                    _refreshImages();
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
      body: Stack(
        children: [
          _buildContent(),
          // ✅ 加载遮罩
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

  Widget _buildContent() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection(
            title: '标题',
            icon: Icons.title,
            content: _entry.title,
          ),
          const SizedBox(height: 16),

          if (_entry.username != null && _entry.username!.isNotEmpty)
            _buildSection(
              title: '用户名',
              icon: Icons.person,
              content: _entry.username!,
              onCopy: () => _copyToClipboard(_entry.username!, '用户名'),
            ),

          if (_entry.username != null && _entry.username!.isNotEmpty)
            const SizedBox(height: 16),

          if (_entry.encryptedPassword != null && _entry.encryptedPassword!.isNotEmpty)
            _buildPasswordSection(),

          if (_entry.encryptedPassword != null && _entry.encryptedPassword!.isNotEmpty)
            const SizedBox(height: 16),

          if (_entry.notes != null && _entry.notes!.isNotEmpty)
            _buildSection(
              title: '备注',
              icon: Icons.note,
              content: _entry.notes!,
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
                  '最后修改：${Helpers.formatDate(_entry.updatedAt)}',
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
              Icon(icon, size: 20, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    String displayPassword;
    if (_decryptedPassword == null || _passwordHidden) {
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
              Icon(Icons.lock, size: 20, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
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
                  setState(() => _passwordHidden = !_passwordHidden);
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
            Icon(Icons.image, size: 20, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
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
              return _buildMoreImagesButton(_imageThumbnails.length - 8);
            }

            final imageBytes = _imageThumbnails[index];
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
                  child: imageBytes.isNotEmpty
                      ? Image.memory(imageBytes, fit: BoxFit.cover)
                      : Container(
                    color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                    child: Icon(
                      Icons.image,
                      color: isDark ? Colors.grey.shade500 : Colors.grey,
                      size: 32,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
      ],
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