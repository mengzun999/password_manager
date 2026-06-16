import 'package:flutter/material.dart';
import 'dart:typed_data';

/// 图片网格组件
class ImageGrid extends StatefulWidget {
  final List<Uint8List> images;
  final VoidCallback onAddImage;
  final VoidCallback onTakePhoto;
  final VoidCallback onPickFile;
  final Function(int index) onDeleteImage;

  /// ✅ 新增：点击图片查看大图回调
  final Function(int index) onViewImage;

  final bool isLoading;
  final int maxImages;
  final int currentCount;

  const ImageGrid({
    super.key,
    required this.images,
    required this.onAddImage,
    required this.onTakePhoto,
    required this.onPickFile,
    required this.onDeleteImage,
    required this.onViewImage, // ✅ 新增
    this.isLoading = false,
    this.maxImages = 20,
    this.currentCount = 0,
  });

  @override
  State<ImageGrid> createState() => _ImageGridState();
}

class _ImageGridState extends State<ImageGrid> {
  @override
  Widget build(BuildContext context) {
    // 计算还能添加多少张
    final remainingSlots = widget.maxImages - widget.currentCount;

    // 显示的图片数量（已添加的图片 + 添加按钮）
    // 至少保留1个添加按钮位置
    final displayCount = widget.images.length + (remainingSlots > 0 ? 1 : 0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行
        Row(
          children: [
            const Text(
              '图片',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            Text(
              '${widget.currentCount}/${widget.maxImages}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 图片网格
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: displayCount,
          itemBuilder: (context, index) {
            // 如果索引超出图片列表，显示添加按钮
            if (index >= widget.images.length) {
              return _buildAddButton();
            }

            // 显示图片
            return _buildImageItem(widget.images[index], index);
          },
        ),

        if (widget.isLoading)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
      ],
    );
  }

  /// 添加按钮（点击弹出选择菜单）
  Widget _buildAddButton() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: PopupMenuButton<String>(
        onSelected: (value) {
          switch (value) {
            case 'gallery':
              widget.onAddImage();
              break;
            case 'camera':
              widget.onTakePhoto();
              break;
            case 'file':
              widget.onPickFile();
              break;
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: 'gallery',
            child: Row(
              children: [
                Icon(Icons.photo_library),
                SizedBox(width: 12),
                Text('从相册选择'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'camera',
            child: Row(
              children: [
                Icon(Icons.camera_alt),
                SizedBox(width: 12),
                Text('拍照'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'file',
            child: Row(
              children: [
                Icon(Icons.folder_open),
                SizedBox(width: 12),
                Text('从文件选择'),
              ],
            ),
          ),
        ],
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.grey.shade100,
          ),
          child: const Center(
            child: Icon(Icons.add, size: 32, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  /// 图片项
  Widget _buildImageItem(Uint8List imageBytes, int index) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 图片（点击查看大图）
        GestureDetector(
          onTap: () => widget.onViewImage(index),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              imageBytes,
              fit: BoxFit.cover,
            ),
          ),
        ),

        // 删除按钮
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => widget.onDeleteImage(index),
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}