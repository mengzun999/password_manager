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
  final Map<int, bool> _loadedMap = {};
  final Map<int, Uint8List> _imageCache = {};
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.imageModels.length - 1);

    // ✅ 如果有预加载的图片，直接使用
    if (widget.preloadedImage != null) {
      _imageCache[_currentIndex] = widget.preloadedImage!;
      _loadedMap[_currentIndex] = true;
    } else {
      _loadFullImage(_currentIndex);
    }
  }

  @override
  void dispose() {
    _imageCache.clear();
    _loadedMap.clear();
    super.dispose();
  }

  Future<void> _loadFullImage(int index) async {
    if (_loadedMap[index] == true) return;
    if (_isLoading) return;
    if (index >= widget.imageModels.length) return;
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final masterKey = ref.read(masterKeyProvider);
      if (masterKey == null) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      final imageModel = widget.imageModels[index];
      final fullImage = await ImageService.getImage(imageModel, masterKey);

      if (!mounted) return;

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
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _onPageChanged(int index) {
    if (!mounted) return;

    setState(() {
      _currentIndex = index;
    });

    if (_loadedMap[index] != true) {
      _loadFullImage(index);
    }

    if (index > 0 && _loadedMap[index - 1] != true) {
      _loadFullImage(index - 1);
    }
    if (index < widget.imageModels.length - 1 && _loadedMap[index + 1] != true) {
      _loadFullImage(index + 1);
    }
  }

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
        ToastUtils.showSuccess(context, '已删除');
        Navigator.pop(context, true);
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
      body: PageView.builder(
        onPageChanged: _onPageChanged,
        controller: PageController(initialPage: _currentIndex),
        itemCount: total,
        itemBuilder: (context, index) {
          final hasFullImage = _loadedMap[index] == true &&
              _imageCache.containsKey(index);

          Uint8List? imageBytes;

          if (hasFullImage) {
            imageBytes = _imageCache[index];
          } else if (index < widget.thumbnails.length) {
            imageBytes = widget.thumbnails[index];
          }

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