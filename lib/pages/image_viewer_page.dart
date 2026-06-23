
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
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
  late PageController _pageController;
  late int _currentIndex;
  late Uint8List _currentImage;
  bool _isDisposed = false;

  // ✅ 控制 AppBar 显隐
  bool _showAppBar = true;

  // ✅ 缓存已加载的原图
  final Map<int, Uint8List> _imageCache = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.imageModels.length - 1);
    _pageController = PageController(initialPage: _currentIndex);

    _currentImage = widget.preloadedImage ?? widget.thumbnails[_currentIndex];

    // ✅ 缓存当前图片
    _imageCache[_currentIndex] = _currentImage;

    // ✅ 使用 immersiveSticky
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _pageController.dispose();
    _imageCache.clear();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ✅ 加载原图（异步，不阻塞滑动）
  Future<void> _loadFullImage(int index) async {
    if (_imageCache.containsKey(index)) return;
    if (index >= widget.imageModels.length) return;
    if (_isDisposed) return;

    try {
      final masterKey = ref.read(masterKeyProvider);
      if (masterKey == null) return;

      final imageModel = widget.imageModels[index];
      final fullImage = await ImageService.loadImageInIsolate(imageModel, masterKey);

      if (_isDisposed) return;
      if (fullImage != null && mounted) {
        setState(() {
          _imageCache[index] = fullImage;
        });
      }
    } catch (e) {
      // 静默失败
    }
  }

  void _onPageChanged(int index) {
    if (_isDisposed) return;
    if (!mounted) return;

    setState(() {
      _currentIndex = index;
      // ✅ 使用缓存或缩略图
      _currentImage = _imageCache[index] ?? widget.thumbnails[index];
      // ✅ 修复：不重置 _showAppBar，保持用户当前的显隐状态
    });

    // ✅ 预加载当前和相邻图片的原图
    _loadFullImage(index);
    if (index > 0) _loadFullImage(index - 1);
    if (index < widget.imageModels.length - 1) _loadFullImage(index + 1);
  }

  void _toggleAppBar() {
    setState(() {
      _showAppBar = !_showAppBar;
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
      if (mounted) {
        ToastUtils.showError(context, '请先解锁');
      }
      return;
    }

    try {
      final imageModel = widget.imageModels[_currentIndex];
      final success = await ImageService.deleteImage(imageModel, masterKey);

      if (success && mounted && !_isDisposed) {
        ToastUtils.showSuccess(context, '已删除');
        _imageCache.remove(_currentIndex);
        Navigator.pop(context, true);
      } else if (!_isDisposed) {
        if (mounted) {
          ToastUtils.showError(context, '删除失败');
        }
      }
    } catch (e) {
      if (!_isDisposed) {
        if (mounted) {
          ToastUtils.showError(context, '删除失败: $e');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.imageModels.length;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ✅ 使用 PhotoViewGallery
          GestureDetector(
            onTap: _toggleAppBar,
            child: PhotoViewGallery.builder(
              pageController: _pageController,
              itemCount: total,
              onPageChanged: _onPageChanged,
              scrollPhysics: const BouncingScrollPhysics(),
              builder: (context, index) {
                final imageBytes = _imageCache[index] ?? widget.thumbnails[index];

                return PhotoViewGalleryPageOptions(
                  imageProvider: MemoryImage(imageBytes),
                  initialScale: PhotoViewComputedScale.contained,
                  minScale: PhotoViewComputedScale.contained * 0.8,
                  maxScale: PhotoViewComputedScale.covered * 2,
                  heroAttributes: PhotoViewHeroAttributes(tag: 'image_$index'),
                  gestureDetectorBehavior: HitTestBehavior.opaque,
                );
              },
              loadingBuilder: (context, event) => Center(
                child: CircularProgressIndicator(
                  value: event == null
                      ? null
                      : event.cumulativeBytesLoaded / event.expectedTotalBytes!,
                  color: Colors.white,
                ),
              ),
              backgroundDecoration: const BoxDecoration(color: Colors.black),
            ),
          ),

          // ✅ 顶部 AppBar
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            top: _showAppBar ? 0 : -kToolbarHeight - 20,
            left: 0,
            right: 0,
            child: Container(
              height: kToolbarHeight + 40,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.6),
                    Colors.transparent,
                  ],
                ),
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    Text(
                      '${_currentIndex + 1} / $total',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        shadows: [
                          Shadow(color: Colors.black26, blurRadius: 4),
                        ],
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.white),
                      onPressed: _deleteImage,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ✅ 底部渐变遮罩
          if (_showAppBar)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                height: 60,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.3),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}