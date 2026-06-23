import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:password_manager/core/crypto/aes_gcm.dart';
import 'package:password_manager/core/models/password_entry.dart';
import 'package:password_manager/core/models/image_model.dart';
import 'package:password_manager/core/services/image_service.dart';
import 'package:password_manager/core/storage/database.dart';
import 'package:password_manager/core/storage/shared_prefs.dart';
import 'package:password_manager/providers/auth_provider.dart';
import 'package:password_manager/utils/helpers.dart';
import 'package:password_manager/widgets/password_generator_button.dart';
import 'package:password_manager/pages/image_viewer_page.dart';
import 'package:photo_view/photo_view.dart';
import '../../utils/toast_utils.dart';

/// 添加/编辑密码页面
class AddEditPage extends ConsumerStatefulWidget {
  final PasswordEntry? entry;
  final String? presetTitle;

  const AddEditPage({super.key, this.entry, this.presetTitle});

  @override
  ConsumerState<AddEditPage> createState() => _AddEditPageState();
}

class _AddEditPageState extends ConsumerState<AddEditPage> with WidgetsBindingObserver {
  // ========== 控制器 ==========
  final _titleController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _notesController = TextEditingController();

  // ========== UI 状态 ==========
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _error;

  // ========== 悬浮球位置 ==========
  Offset _fabPosition = const Offset(0, 0);
  bool _isDragging = false;
  bool _isKeyboardVisible = false;

  // ========== 图片：待保存（内存中） ==========
  final List<XFile> _pendingImages = [];
  final List<Uint8List> _pendingThumbnails = [];

  // ========== 图片：已保存（编辑模式） ==========
  List<ImageModel> _savedImageModels = [];
  List<Uint8List> _savedImageThumbnails = [];
  bool _isLoadingImages = false;

  // ========== 生命周期 ==========

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadEntryData();
    if (widget.entry != null) {
      _loadSavedImages();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initFabPosition();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _titleController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final view = View.of(context);
    final bottomInset = view.viewInsets.bottom;
    final isKeyboardVisible = bottomInset > 0;
    if (_isKeyboardVisible != isKeyboardVisible) {
      setState(() {
        _isKeyboardVisible = isKeyboardVisible;
      });
    }
  }

  // ========== 悬浮球位置 ==========

  void _initFabPosition() {
    final screenSize = MediaQuery.of(context).size;
    setState(() {
      _fabPosition = Offset(
        screenSize.width - 80,
        screenSize.height * 0.35,
      );
    });
    _saveFabPosition(_fabPosition);
  }

  Future<void> _saveFabPosition(Offset position) async {
    await SharedPrefs.saveFabPosition(position.dx, position.dy);
  }

  // ========== 数据加载 ==========

  void _loadEntryData() {
    if (widget.entry != null) {
      _titleController.text = widget.entry!.title;
      _usernameController.text = widget.entry!.username ?? '';
      _notesController.text = widget.entry!.notes ?? '';

      // ✅ 如果有加密密码，解密后填充
      _loadPasswordForEditing();
    } else if (widget.presetTitle != null) {
      _titleController.text = widget.presetTitle!;
    }
  }

// ✅ 新增：加载密码（解密后填充）
  Future<void> _loadPasswordForEditing() async {
    if (widget.entry == null) return;
    if (widget.entry!.encryptedPassword == null) return;

    final masterKey = _getMasterKey();
    if (masterKey == null) return;

    try {
      final decrypted = await AESGCMHelper.decrypt(
        widget.entry!.encryptedPassword!,
        masterKey,
      );
      if (mounted) {
        _passwordController.text = decrypted;
      }
    } catch (e) {
      // 解密失败，留空
      debugPrint('解密密码失败: $e');
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

  /// 从相册选择图片
  Future<void> _pickFromGallery() async {
    final totalCount = _savedImageModels.length + _pendingImages.length;
    if (totalCount >= 20) {
      _showSnackBar('最多添加20张图片');
      return;
    }

    final maxCount = 20 - totalCount;
    final picked = await ImageService.pickImages(maxCount: maxCount);
    if (picked.isNotEmpty) {
      // ✅ 立即生成缩略图并缓存
      final thumbnails = <Uint8List>[];
      for (final file in picked) {
        try {
          final bytes = await file.readAsBytes();
          final thumb = await ImageService.generateThumbnail(bytes);
          thumbnails.add(thumb);
        } catch (e) {
          thumbnails.add(Uint8List(0));
        }
      }

      setState(() {
        _pendingImages.addAll(picked);
        _pendingThumbnails.addAll(thumbnails);
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
      // ✅ 立即生成缩略图并缓存
      Uint8List thumb = Uint8List(0);
      try {
        final bytes = await photo.readAsBytes();
        thumb = await ImageService.generateThumbnail(bytes);
      } catch (e) {
        // ignore
      }

      setState(() {
        _pendingImages.add(photo);
        _pendingThumbnails.add(thumb);
      });
      _showSnackBar('已拍照，点击保存后上传');
    }
  }

  /// 删除待保存的图片
  void _deletePendingImage(int index) {
    setState(() {
      _pendingImages.removeAt(index);
      _pendingThumbnails.removeAt(index);
    });
    _showSnackBar('已移除');
  }

  /// 删除已保存的图片
  Future<void> _deleteSavedImage(int index) async {
    if (index >= _savedImageModels.length) return;

    final image = _savedImageModels[index];

    final confirmed = await ToastUtils.showDangerConfirmDialog(
      context,
      title: '删除图片',
      content: '确定要删除这张图片吗？',
      confirmText: '删除',
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

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              title: const Text(
                '预览图片',
                style: TextStyle(color: Colors.white),
              ),
            ),
            body: Center(
              child: PhotoView(
                imageProvider: MemoryImage(bytes),
                backgroundDecoration: const BoxDecoration(color: Colors.black),
                maxScale: PhotoViewComputedScale.covered * 3,
                minScale: PhotoViewComputedScale.contained,
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        _showSnackBar('预览失败');
      }
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

    // ✅ 显示加载对话框（透明背景转圈，无文字）
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.3),
      builder: (context) => Center(
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(
            child: SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );

    // ✅ 让 UI 先渲染
    await Future.delayed(Duration.zero);

    final now = Helpers.currentTimestamp();
    final masterKey = _getMasterKey();
    if (masterKey == null) {
      if (mounted) {
        Navigator.pop(context); // 关闭加载对话框
      }
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

        // 5. ✅ 保存图片（使用 isolate 版本，不会卡 UI）
        if (_pendingImages.isNotEmpty) {
          final savedImages = await ImageService.saveImages(
            imageFiles: _pendingImages,
            entryId: widget.entry!.id,
            masterKey: masterKey,
          );
          // ✅ 清空待保存列表和缓存
          _pendingImages.clear();
          _pendingThumbnails.clear();
        }

        // ✅ 修复：关闭加载对话框，然后返回结果
        if (mounted) {
          Navigator.pop(context); // 关闭加载对话框
          Navigator.pop(context, true); // 返回上一页，传递成功标志
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

      // 7. ✅ 保存图片（使用 isolate 版本）
      if (_pendingImages.isNotEmpty) {
        final savedImages = await ImageService.saveImages(
          imageFiles: _pendingImages,
          entryId: entry.id,
          masterKey: masterKey,
        );
        // ✅ 清空待保存列表和缓存
        _pendingImages.clear();
        _pendingThumbnails.clear();
      }

      // ✅ 修复：关闭加载对话框，然后返回结果
      if (mounted) {
        Navigator.pop(context); // 关闭加载对话框
        Navigator.pop(context, true); // 返回上一页，传递成功标志
      }
    } catch (e) {
      // ✅ 异常时关闭加载对话框
      if (mounted) {
        Navigator.pop(context); // 关闭加载对话框
      }
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

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

                // ✅ 待保存的图片（使用缓存的缩略图）
                if (_pendingThumbnails.isNotEmpty) ...[
                  _buildPendingImagesSection(),
                  const SizedBox(height: 8),
                ],

                // 添加图片按钮
                _buildAddImageButtons(),

                const SizedBox(height: 8),
                Text(
                  '${allImageCount}/20 张',
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.grey.shade400 : Colors.grey.shade500),
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

          // ✅ 悬浮球 - 键盘弹出时隐藏
          if (!_isKeyboardVisible)
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

                  final minY = padding + kToolbarHeight + 60;
                  final maxY = screenSize.height - buttonSize - padding - 20;

                  newDx = newDx.clamp(padding, screenSize.width - buttonSize - padding);
                  newDy = newDy.clamp(minY, maxY);

                  setState(() {
                    _fabPosition = Offset(newDx, newDy);
                  });
                },
                onPanEnd: (_) {
                  setState(() => _isDragging = false);
                  _saveFabPosition(_fabPosition);
                },
                child: PasswordGeneratorButton(
                  onGenerate: _generatePassword,
                  onClear: _clearPassword,
                  isDark: isDark,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ========== 图片子组件 ==========

  /// 已保存图片区域
  Widget _buildSavedImagesSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '已保存图片（${_savedImageThumbnails.length}张）',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.green.shade300 : Colors.green.shade700,
          ),
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
                        color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                        child: Icon(Icons.broken_image, color: isDark ? Colors.grey.shade500 : Colors.grey),
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

  /// ✅ 待保存图片区域（使用缓存的缩略图）
  Widget _buildPendingImagesSection() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '待保存图片（${_pendingThumbnails.length}张）',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? Colors.orange.shade300 : Colors.orange.shade700,
          ),
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
          itemCount: _pendingThumbnails.length,
          itemBuilder: (context, index) {
            final bytes = _pendingThumbnails[index];
            return Stack(
              children: [
                GestureDetector(
                  onTap: () => _viewPendingImage(index),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: bytes.isNotEmpty
                        ? Image.memory(bytes, fit: BoxFit.cover)
                        : Container(
                      color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                      child: Icon(Icons.image, color: isDark ? Colors.grey.shade500 : Colors.grey),
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
        ),
      ],
    );
  }

  /// 添加图片按钮
  Widget _buildAddImageButtons() {
    final totalCount = _savedImageModels.length + _pendingImages.length;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: totalCount >= 20 ? null : _pickFromGallery,
            icon: const Icon(Icons.photo_library, size: 20),
            label: const Text('从相册选择'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: totalCount >= 20 ? null : _takePhotoAndAdd,
            icon: const Icon(Icons.camera_alt, size: 20),
            label: const Text('拍照'),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
              ),
            ),
          ),
        ),
      ],
    );
  }
}