import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';
import 'package:password_manager/core/models/image_model.dart';
import 'package:password_manager/core/services/image_service.dart';
import 'package:password_manager/providers/auth_provider.dart';

import '../utils/toast_utils.dart';

/// 图片查看器页面
///
/// 全屏查看图片，支持缩放、滑动切换
class ImageViewerPage extends ConsumerStatefulWidget {
  /// 图片模型列表
  final List<ImageModel> imageModels;

  /// 缩略图列表（用于快速显示）
  final List<Uint8List> thumbnails;

  /// 初始显示索引
  final int initialIndex;

  /// 关联的密码条目ID（用于加载原图）
  final String entryId;

  const ImageViewerPage({
    super.key,
    required this.imageModels,
    required this.thumbnails,
    this.initialIndex = 0,
    required this.entryId,
  });

  @override
  ConsumerState<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends ConsumerState<ImageViewerPage> {
  /// 当前显示的索引
  late int _currentIndex;

  /// 每个图片的加载状态：true=已加载原图，false=显示缩略图
  final Map<int, bool> _loadedMap = {};

  /// 缓存已加载的原图
  final Map<int, Uint8List> _imageCache = {};

  /// 是否正在加载
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.imageModels.length - 1);
    // 预加载当前图片的原图
    _loadFullImage(_currentIndex);
  }

  /// 加载原图
  Future<void> _loadFullImage(int index) async {
    // 如果已经加载过，跳过
    if (_loadedMap[index] == true) return;

    // 如果正在加载，跳过
    if (_isLoading) return;

    // 检查索引是否有效
    if (index >= widget.imageModels.length) return;

    setState(() => _isLoading = true);

    try {
      final masterKey = ref.read(masterKeyProvider);
      if (masterKey == null) {
        setState(() => _isLoading = false);
        return;
      }

      final imageModel = widget.imageModels[index];
      final fullImage = await ImageService.getImage(imageModel, masterKey);

      if (fullImage != null) {
        setState(() {
          _imageCache[index] = fullImage;
          _loadedMap[index] = true;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  /// 切换图片时加载原图
  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
    _loadFullImage(index);

    // 预加载相邻图片
    if (index > 0) _loadFullImage(index - 1);
    if (index < widget.imageModels.length - 1) _loadFullImage(index + 1);
  }

  /// 删除当前图片
  Future<void> _deleteImage() async {
    final confirmed = await ToastUtils.showConfirmDialog(
      context,
      title: '删除图片',
      content: '确定要删除这张图片吗？',
      confirmText: '删除',
      isDestructive: true,
    );

    if (confirmed != true) return;

    final masterKey = ref.read(masterKeyProvider);
    if (masterKey == null) {
      ToastUtils.showError(context, '请先解锁');
      return;
    }

    try {
      final imageModel = widget.imageModels[_currentIndex];
      final success = await ImageService.deleteImage(imageModel, masterKey);

      if (success && mounted) {
        // 从列表中移除
        final newModels = List<ImageModel>.from(widget.imageModels);
        final newThumbnails = List<Uint8List>.from(widget.thumbnails);
        newModels.removeAt(_currentIndex);
        newThumbnails.removeAt(_currentIndex);

        // 清除缓存
        _imageCache.remove(_currentIndex);
        _loadedMap.remove(_currentIndex);

        // 更新缓存索引
        final updatedCache = <int, Uint8List>{};
        final updatedLoaded = <int, bool>{};
        for (final entry in _imageCache.entries) {
          if (entry.key > _currentIndex) {
            updatedCache[entry.key - 1] = entry.value;
          } else if (entry.key < _currentIndex) {
            updatedCache[entry.key] = entry.value;
          }
        }
        for (final entry in _loadedMap.entries) {
          if (entry.key > _currentIndex) {
            updatedLoaded[entry.key - 1] = entry.value;
          } else if (entry.key < _currentIndex) {
            updatedLoaded[entry.key] = entry.value;
          }
        }
        _imageCache.clear();
        _imageCache.addAll(updatedCache);
        _loadedMap.clear();
        _loadedMap.addAll(updatedLoaded);

        // 如果列表为空，关闭页面
        if (newModels.isEmpty) {
          Navigator.pop(context, true);
          return;
        }

        // 更新当前索引
        final newIndex = _currentIndex >= newModels.length
            ? newModels.length - 1
            : _currentIndex;

        // 刷新页面（通过替换路由）
        Navigator.pop(context, true);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ImageViewerPage(
              imageModels: newModels,
              thumbnails: newThumbnails,
              initialIndex: newIndex,
              entryId: widget.entryId,
            ),
          ),
        );
      } else {
        ToastUtils.showError(context, '删除失败');
      }
    } catch (e) {
      ToastUtils.showError(context, '删除失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.imageModels.length;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.5),
        elevation: 0,
        foregroundColor: Colors.white,
        title: Text(
          '${_currentIndex + 1} / $total',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white),
            onPressed: _deleteImage,
          ),
        ],
      ),
      body: Stack(
        children: [
          // ========== 图片滑动查看 ==========
          PageView.builder(
            onPageChanged: _onPageChanged,
            controller: PageController(initialPage: _currentIndex),
            itemCount: total,
            itemBuilder: (context, index) {
              // 检查是否已加载原图
              final hasFullImage = _loadedMap[index] == true &&
                  _imageCache.containsKey(index);

              Uint8List? imageBytes;

              if (hasFullImage) {
                imageBytes = _imageCache[index];
              } else if (index < widget.thumbnails.length) {
                // 显示缩略图
                imageBytes = widget.thumbnails[index];
              }

              // 如果当前索引正在加载，显示加载指示器
              final isLoading = _isLoading &&
                  _loadedMap[index] != true &&
                  index == _currentIndex;

              if (imageBytes == null) {
                return Center(
                  child: isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Icon(
                    Icons.broken_image,
                    color: Colors.grey,
                    size: 64,
                  ),
                );
              }

              return PhotoView(
                imageProvider: MemoryImage(imageBytes),
                backgroundDecoration: const BoxDecoration(color: Colors.black),
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 2,
                // 双击缩放
                gestureDetectorBehavior: HitTestBehavior.opaque,
                // 显示进度指示器（加载大图时）
                loadingBuilder: (context, progress) => Center(
                  child: CircularProgressIndicator(
                    value: progress == null ? null : progress.cumulativeBytesLoaded / progress.expectedTotalBytes!,
                    color: Colors.white,
                  ),
                ),
                // 错误时显示
                errorBuilder: (context, error, stackTrace) => const Center(
                  child: Icon(
                    Icons.broken_image,
                    color: Colors.grey,
                    size: 64,
                  ),
                ),
              );
            },
          ),

          // ========== 底部操作提示 ==========
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  '双指缩放 · 左右滑动切换',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}