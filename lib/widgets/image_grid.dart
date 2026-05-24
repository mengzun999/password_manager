import 'package:flutter/material.dart';
import 'dart:typed_data';

/// 图片网格组件
///
/// 显示图片网格，支持添加、删除、查看大图
class ImageGrid extends StatefulWidget {
  /// 图片列表（Uint8List格式）
  final List<Uint8List> images;

  /// 添加图片回调
  final VoidCallback onAddImage;

  /// 拍照回调
  final VoidCallback onTakePhoto;

  /// 从文件选择回调
  final VoidCallback onPickFile;

  /// 删除图片回调
  final Function(int index) onDeleteImage;

  /// 是否正在加载
  final bool isLoading;

  const ImageGrid({
    super.key,
    required this.images,
    required this.onAddImage,
    required this.onTakePhoto,
    required this.onPickFile,
    required this.onDeleteImage,
    this.isLoading = false,
  });

  @override
  State<ImageGrid> createState() => _ImageGridState();
}

class _ImageGridState extends State<ImageGrid> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        const Text(
          '图片',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
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
          itemCount: widget.images.length + 3, // 3个添加按钮
          itemBuilder: (context, index) {
            // 添加按钮区域
            if (index >= widget.images.length) {
              return _buildAddButton(index - widget.images.length);
            }

            // 图片显示
            return _buildImageItem(widget.images[index], index);
          },
        ),
      ],
    );
  }

  /// 添加按钮
  Widget _buildAddButton(int buttonIndex) {
    final icons = [Icons.add, Icons.camera_alt, Icons.folder_open];
    final labels = ['相册', '拍照', '文件'];
    final onTaps = [widget.onAddImage, widget.onTakePhoto, widget.onPickFile];

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: InkWell(
        onTap: onTaps[buttonIndex],
        borderRadius: BorderRadius.circular(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icons[buttonIndex], size: 32, color: Colors.grey.shade600),
            const SizedBox(height: 4),
            Text(
              labels[buttonIndex],
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  /// 图片项
  Widget _buildImageItem(Uint8List imageBytes, int index) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 图片
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            imageBytes,
            fit: BoxFit.cover,
          ),
        ),

        // 删除按钮
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            onTap: () => widget.onDeleteImage(index),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.close,
                size: 20,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}