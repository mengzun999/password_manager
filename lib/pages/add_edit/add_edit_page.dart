import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:password_manager/core/crypto/aes_gcm.dart';
import 'package:password_manager/core/models/password_entry.dart';
import 'package:password_manager/core/models/image_model.dart';
import 'package:password_manager/core/services/image_service.dart';
import 'package:password_manager/core/storage/database.dart';
import 'package:password_manager/providers/auth_provider.dart';
import 'package:password_manager/utils/helpers.dart';
import 'package:password_manager/widgets/password_generator_button.dart';
import 'package:password_manager/pages/image_viewer_page.dart';

import '../../utils/toast_utils.dart';

/// 添加/编辑密码页面
///
/// 密码和图片互不依赖，可单独存在，也可组合
/// 保存条件：标题必填 + (密码 或 图片 至少有一个)
class AddEditPage extends ConsumerStatefulWidget {
  final PasswordEntry? entry;
  final String? presetTitle;

  const AddEditPage({super.key, this.entry, this.presetTitle});

  @override
  ConsumerState<AddEditPage> createState() => _AddEditPageState();
}

class _AddEditPageState extends ConsumerState<AddEditPage> {
  // ========== 控制器 ==========
  final _titleController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _notesController = TextEditingController();

  // ========== UI 状态 ==========
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _error;

  // ========== 图片：待保存（内存中） ==========
  final List<XFile> _pendingImages = [];

  // ========== 图片：已保存（编辑模式） ==========
  List<ImageModel> _savedImageModels = [];
  List<Uint8List> _savedImageThumbnails = [];
  bool _isLoadingImages = false;

  // ========== 生命周期 ==========

  @override
  void initState() {
    super.initState();
    _loadEntryData();
    if (widget.entry != null) {
      _loadSavedImages();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  // ========== 数据加载 ==========

  void _loadEntryData() {
    if (widget.entry != null) {
      _titleController.text = widget.entry!.title;
      _usernameController.text = widget.entry!.username ?? '';
      _notesController.text = widget.entry!.notes ?? '';
    } else if (widget.presetTitle != null) {
      _titleController.text = widget.presetTitle!;
    }
  }

  /// 加载已保存的图片（编辑模式）
  Future<void> _loadSavedImages() async {
    if (widget.entry == null) return;

    setState(() => _isLoadingImages = true);

    try {
      final masterKey = _getMasterKey();
      if (masterKey == null) {
        setState(() => _isLoadingImages = false);
        return;
      }

      final images = await ImageService.getEntryImages(widget.entry!.id);
      final thumbnails = <Uint8List>[];

      for (final image in images) {
        final thumb = await ImageService.getThumbnail(image, masterKey);
        if (thumb != null) {
          thumbnails.add(thumb);
        }
      }

      setState(() {
        _savedImageModels = images;
        _savedImageThumbnails = thumbnails;
        _isLoadingImages = false;
      });
    } catch (e) {
      setState(() => _isLoadingImages = false);
    }
  }

  // ========== 图片操作方法 ==========

  /// 添加图片（从相册）
  Future<void> _addPendingImages() async {
    final totalCount = _savedImageModels.length + _pendingImages.length;
    if (totalCount >= 20) {
      _showSnackBar('最多添加20张图片');
      return;
    }

    final maxCount = 20 - totalCount;

    final picked = await ImageService.pickImages(maxCount: maxCount);
    if (picked.isNotEmpty) {
      setState(() {
        _pendingImages.addAll(picked);
      });
      _showSnackBar('已选择 ${picked.length} 张图片，点击保存后上传');
    }
  }

  /// 拍照添加图片
  Future<void> _takePhotoAndAdd() async {
    final totalCount = _savedImageModels.length + _pendingImages.length;
    if (totalCount >= 20) {
      _showSnackBar('最多添加20张图片');
      return;
    }

    final photo = await ImageService.takePhoto();
    if (photo != null) {
      setState(() {
        _pendingImages.add(photo);
      });
      _showSnackBar('已拍照，点击保存后上传');
    }
  }

  /// 从文件选择图片
  Future<void> _pickFileAndAdd() async {
    await _addPendingImages();
  }

  /// 获取待保存图片的缩略图
  Future<Uint8List> _getPendingThumbnail(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      return bytes;
    } catch (e) {
      return Uint8List(0);
    }
  }

  /// 删除待保存的图片
  void _deletePendingImage(int index) {
    setState(() {
      _pendingImages.removeAt(index);
    });
    _showSnackBar('已移除');
  }

  /// 删除已保存的图片
  Future<void> _deleteSavedImage(int index) async {
    if (index >= _savedImageModels.length) return;

    final image = _savedImageModels[index];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除图片'),
        content: const Text('确定要删除这张图片吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final masterKey = _getMasterKey();
    if (masterKey == null) {
      _showSnackBar('未解锁');
      return;
    }

    setState(() => _isLoadingImages = true);

    try {
      await ImageService.deleteImage(image, masterKey);
      setState(() {
        _savedImageModels.removeAt(index);
        _savedImageThumbnails.removeAt(index);
        _isLoadingImages = false;
      });
      _showSnackBar('已删除');
    } catch (e) {
      _showSnackBar('删除失败: $e');
      setState(() => _isLoadingImages = false);
    }
  }

  /// 查看已保存图片的大图
  void _viewSavedImage(int index) {
    if (index >= _savedImageThumbnails.length) return;
    if (widget.entry == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageViewerPage(
          imageModels: _savedImageModels,
          thumbnails: _savedImageThumbnails,
          initialIndex: index,
          entryId: widget.entry!.id,
        ),
      ),
    ).then((_) {
      _loadSavedImages();
    });
  }

  /// 查看待保存图片的大图（预览）
  void _viewPendingImage(int index) async {
    if (index >= _pendingImages.length) return;

    try {
      final bytes = await _pendingImages[index].readAsBytes();
      if (!mounted) return;

      showDialog(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.black,
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Stack(
              children: [
                Center(
                  child: Image.memory(
                    bytes,
                    fit: BoxFit.contain,
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
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
                        '点击关闭',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      _showSnackBar('预览失败');
    }
  }

  // ========== 密码操作 ==========

  void _generatePassword() {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*()';
    final random = Helpers.generateRandomString(16, chars);
    _passwordController.text = random;
  }

  void _clearPassword() {
    _passwordController.clear();
  }

  // ========== 核心：保存逻辑 ==========

  Future<void> _save() async {
    // 1. 验证标题（必填）
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = '请输入标题');
      return;
    }

    // 2. 检查：密码 或 图片 至少有一个
    final hasPassword = _passwordController.text.trim().isNotEmpty;
    final hasImages = _savedImageModels.isNotEmpty || _pendingImages.isNotEmpty;

    if (!hasPassword && !hasImages) {
      setState(() => _error = '请至少填写密码或添加一张图片');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final now = Helpers.currentTimestamp();
    final masterKey = _getMasterKey();
    if (masterKey == null) {
      setState(() {
        _isLoading = false;
        _error = '未解锁，请重新登录';
      });
      return;
    }

    try {
      // 3. 加密密码（如果有）
      String? encryptedPassword;
      final plainPassword = _passwordController.text.trim();
      if (plainPassword.isNotEmpty) {
        encryptedPassword = await AESGCMHelper.encrypt(plainPassword, masterKey);
      }

      // 4. 如果是编辑模式，更新条目
      if (widget.entry != null) {
        final updatedEntry = widget.entry!.copyWith(
          title: title,
          username: _usernameController.text.trim().isEmpty
              ? null
              : _usernameController.text.trim(),
          encryptedPassword: encryptedPassword,
          notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
          updatedAt: now,
        );
        await DatabaseHelper.updateEntry(updatedEntry);

        // 5. 保存待保存的图片（关联到已有条目）
        if (_pendingImages.isNotEmpty) {
          final savedImages = await ImageService.saveImages(
            imageFiles: _pendingImages,
            entryId: widget.entry!.id,
            masterKey: masterKey,
          );
          _showSnackBar('已保存 ${savedImages.length} 张图片');
          _pendingImages.clear();
        }

        setState(() => _isLoading = false);
        if (mounted) {
          Navigator.pop(context, true);
        }
        return;
      }

      // 6. 添加模式：先创建条目
      final entry = PasswordEntry(
        id: Helpers.generateUuid(),
        title: title,
        username: _usernameController.text.trim().isEmpty
            ? null
            : _usernameController.text.trim(),
        encryptedPassword: encryptedPassword,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        appPackageName: null,
        createdAt: now,
        updatedAt: now,
      );
      await DatabaseHelper.insertEntry(entry);

      // 7. 保存图片（如果有）
      if (_pendingImages.isNotEmpty) {
        final savedImages = await ImageService.saveImages(
          imageFiles: _pendingImages,
          entryId: entry.id,
          masterKey: masterKey,
        );
        _showSnackBar('已保存 ${savedImages.length} 张图片');
        _pendingImages.clear();
      }

      setState(() => _isLoading = false);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = '保存失败: $e';
      });
    }
  }

  // ========== 辅助方法 ==========

  Uint8List? _getMasterKey() {
    final authState = ref.read(authProvider);
    return authState.masterKey;
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ToastUtils.showSnackBar(context, message);
  }

  // ========== 界面构建 ==========

  @override
  Widget build(BuildContext context) {
    final isEditMode = widget.entry != null;

    // 合并图片数量
    final allImageCount = _savedImageModels.length + _pendingImages.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditMode ? '编辑密码' : '添加密码'),
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 标题
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: '标题 *',
                    hintText: '例如：微信、支付宝',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // 用户名
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: '用户名',
                    hintText: '手机号/邮箱/账号',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),

                // 密码（可选）
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: '密码（可选）',
                    hintText: '留空表示不保存密码',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // 备注
                TextField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: '备注（可选）',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),

                // ========== 图片区域 ==========
                const Divider(),
                const SizedBox(height: 8),

                // 已保存的图片
                if (_savedImageThumbnails.isNotEmpty) ...[
                  _buildSavedImagesSection(),
                  const SizedBox(height: 8),
                ],

                // 待保存的图片
                if (_pendingImages.isNotEmpty) ...[
                  _buildPendingImagesSection(),
                  const SizedBox(height: 8),
                ],

                // 添加图片按钮
                _buildAddImageButtons(),

                const SizedBox(height: 8),
                Text(
                  '${allImageCount}/20 张',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
                const SizedBox(height: 8),

                // 错误提示
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],

                const SizedBox(height: 80),
              ],
            ),
          ),

          // 悬浮球
          Positioned(
            bottom: 80,
            right: 16,
            child: PasswordGeneratorButton(
              onGenerate: _generatePassword,
              onClear: _clearPassword,
            ),
          ),
        ],
      ),
    );
  }

  // ========== 图片子组件 ==========

  /// 已保存图片区域
  Widget _buildSavedImagesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '已保存图片（${_savedImageThumbnails.length}张）',
          style: TextStyle(fontSize: 13, color: Colors.green.shade700),
        ),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: _savedImageThumbnails.length,
          itemBuilder: (context, index) {
            return Stack(
              children: [
                GestureDetector(
                  onTap: () => _viewSavedImage(index),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      _savedImageThumbnails[index],
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.broken_image, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => _deleteSavedImage(index),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 4,
                  left: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '已保存',
                      style: TextStyle(fontSize: 9, color: Colors.white),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// 待保存图片区域
  Widget _buildPendingImagesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '待保存图片（${_pendingImages.length}张）',
          style: TextStyle(fontSize: 13, color: Colors.orange.shade700),
        ),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: _pendingImages.length,
          itemBuilder: (context, index) {
            return FutureBuilder<Uint8List>(
              future: _getPendingThumbnail(_pendingImages[index]),
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                return Stack(
                  children: [
                    GestureDetector(
                      onTap: () => _viewPendingImage(index),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: bytes != null && bytes.isNotEmpty
                            ? Image.memory(bytes, fit: BoxFit.cover)
                            : Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.image, color: Colors.grey),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () => _deletePendingImage(index),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '待保存',
                          style: TextStyle(fontSize: 9, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }

  /// 添加图片按钮
  Widget _buildAddImageButtons() {
    final totalCount = _savedImageModels.length + _pendingImages.length;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: totalCount >= 20 ? null : _addPendingImages,
            icon: const Icon(Icons.photo_library, size: 20),
            label: const Text('从相册选择'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: totalCount >= 20 ? null : _takePhotoAndAdd,
            icon: const Icon(Icons.camera_alt, size: 20),
            label: const Text('拍照'),
          ),
        ),
      ],
    );
  }
}