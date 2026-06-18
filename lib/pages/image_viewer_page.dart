// pages/image_viewer_page.dart

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_view/photo_view.dart';
import 'package:password_manager/core/models/image_model.dart';
import 'package:password_manager/core/services/image_service.dart';
import 'package:password_manager/providers/auth_provider.dart';
import '../utils/toast_utils.dart';

/// 图片查看器页面
class ImageViewerPage extends ConsumerStatefulWidget {
  final List<ImageModel> imageModels;
  final List<Uint8List> thumbnails;
  final int initialIndex;
  final String entryId;

  /// ✅ 已经加载好的原图（从详情页传入）
  final Uint8List? preloadedImage;

  const ImageViewerPage({
    super.key,
    required this.imageModels,
    required this.thumbnails,
    this.initialIndex = 0,
    required this.entryId,
    this.preloadedImage,
  });

  @override
  ConsumerState<ImageViewerPage> createState() => _ImageViewerPageState();
}

class _ImageViewerPageState extends ConsumerState<ImageViewerPage> {
  late int _currentIndex;
  late Uint8List _currentImage;
  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.imageModels.length - 1);

    // ✅ 直接使用预加载的图片（必须存在）
    _currentImage = widget.preloadedImage ?? widget.thumbnails[_currentIndex];
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  void _onPageChanged(int index) {
    if (_isDisposed) return;
    if (!mounted) return;

    // ✅ 如果当前索引没有预加载图片，使用缩略图
    // 但正常情况下，详情页已经加载好了
    Uint8List image = widget.thumbnails[index];

    // 如果有预加载图片（从详情页传入的缓存），使用它
    // 注意：这里简化处理，实际场景中每张图片都已在详情页预加载
    // 如果用户从查看器删除图片，回退到缩略图

    setState(() {
      _currentIndex = index;
      _currentImage = image;
    });
  }

  Future<void> _deleteImage() async {
    if (_isDisposed) return;

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

      if (success && mounted && !_isDisposed) {
        ToastUtils.showSuccess(context, '已删除');
        Navigator.pop(context, true);
      } else if (!_isDisposed) {
        ToastUtils.showError(context, '删除失败');
      }
    } catch (e) {
      if (!_isDisposed) {
        ToastUtils.showError(context, '删除失败: $e');
      }
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
      body: PageView.builder(
        onPageChanged: _onPageChanged,
        controller: PageController(initialPage: _currentIndex),
        itemCount: total,
        itemBuilder: (context, index) {
          // 优先使用预加载图片
          Uint8List? imageBytes;

          // 如果当前索引是预加载图片，使用它
          if (index == _currentIndex && _currentImage.isNotEmpty) {
            imageBytes = _currentImage;
          } else {
            // 否则使用缩略图
            imageBytes = widget.thumbnails[index];
          }

          return PhotoView(
            imageProvider: MemoryImage(imageBytes),
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            minScale: PhotoViewComputedScale.contained,
            maxScale: PhotoViewComputedScale.covered * 2,
            gestureDetectorBehavior: HitTestBehavior.opaque,
            loadingBuilder: (context, progress) => Center(
              child: CircularProgressIndicator(
                value: progress == null
                    ? null
                    : progress.cumulativeBytesLoaded /
                    progress.expectedTotalBytes!,
                color: Colors.white,
              ),
            ),
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
    );
  }
}