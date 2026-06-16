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

  // ========== ✅ 新增：图片数据 ==========
  List<ImageModel> _imageModels = [];
  List<Uint8List> _imageThumbnails = [];
  bool _isLoadingImages = false;

  // ========== 生命周期方法 ==========

  @override
  void initState() {
    super.initState();
    _loadEntry();
  }

  // ========== 数据加载方法 ==========

  /// 从数据库加载密码条目
  Future<void> _loadEntry() async {

    setState(() {
      _isLoading = true;
      _decryptedPassword = null;
      _passwordHidden = true;
    });

    final entry = await DatabaseHelper.getEntryById(widget.entryId);

    setState(() {
      _entry = entry;
      _isLoading = false;
    });

    // ✅ 如果条目存在，加载关联的图片
    if (entry != null) {
      _loadImages();
    }
  }

  /// ✅ 新增：加载关联的图片
  Future<void> _loadImages() async {
    if (_entry == null) return;

    setState(() => _isLoadingImages = true);

    try {
      final masterKey = _getMasterKey();
      if (masterKey == null) {
        setState(() => _isLoadingImages = false);
        return;
      }

      // 获取图片元数据
      final images = await ImageService.getEntryImages(_entry!.id);

      // 获取缩略图
      final thumbnails = <Uint8List>[];
      for (final image in images) {
        final thumb = await ImageService.getThumbnail(image, masterKey);
        if (thumb != null) {
          thumbnails.add(thumb);
        }
      }

      setState(() {
        _imageModels = images;
        _imageThumbnails = thumbnails;
        _isLoadingImages = false;
      });
    } catch (e) {
      print('加载图片失败: $e');
      setState(() => _isLoadingImages = false);
    }
  }

  /// 获取主密钥
  Uint8List? _getMasterKey() {
    final authState = ref.read(authProvider);
    return authState.masterKey;
  }

  // ========== 密码操作 ==========

  /// 解密密码
  Future<void> _decryptPassword() async {

    final masterKey = _getMasterKey();
    if (masterKey == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未解锁，请重新登录')),
        );
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

      setState(() {
        _decryptedPassword = decrypted;
        _isDecrypting = false;
      });
    } catch (e) {
      setState(() {
        _isDecrypting = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('解密失败: $e')),
        );
      }
    }
  }

  /// 复制文本到剪贴板
  Future<void> _copyToClipboard(String text, String label) async {

    await Helpers.copyToClipboard(text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已复制 $label')),
      );
    }
  }

  /// 删除当前密码条目
  Future<void> _deleteEntry() async {


    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除'),
        content: Text('确定要删除 "${_entry?.title}" 吗？\n\n注意：关联的图片也会被删除。'),
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

    if (confirmed == true && _entry != null) {
      // 数据库外键级联删除会自动删除图片记录
      // 但图片文件需要手动删除
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

  /// ✅ 新增：查看大图
  void _viewImage(int index) {


    if (index >= _imageThumbnails.length) return;
    if (_entry == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ImageViewerPage(
          imageModels: _imageModels,
          thumbnails: _imageThumbnails,
          initialIndex: index,
          entryId: _entry!.id,
        ),
      ),
    ).then((_) {
      // 从查看器返回后刷新图片列表（可能有删除操作）
      _loadImages();
    });
  }

  // ========== 界面构建 ==========

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('密码详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {


              if (_entry != null) {
                Navigator.pushNamed(
                  context,
                  AppRoutes.addEdit,
                  arguments: _entry,
                ).then((_) {
                  _loadEntry();
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
          : _buildContent(),
    );
  }

  /// 错误状态
  Widget _buildErrorState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.grey),
          SizedBox(height: 16),
          Text('密码条目不存在'),
        ],
      ),
    );
  }

  /// 主要内容
  Widget _buildContent() {
    final entry = _entry!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          _buildSection(
            title: '标题',
            icon: Icons.title,
            content: entry.title,
          ),
          const SizedBox(height: 16),

          // 用户名（如果有）
          if (entry.username != null && entry.username!.isNotEmpty)
            _buildSection(
              title: '用户名',
              icon: Icons.person,
              content: entry.username!,
              onCopy: () => _copyToClipboard(entry.username!, '用户名'),
            ),

          if (entry.username != null && entry.username!.isNotEmpty)
            const SizedBox(height: 16),

          // 密码（如果有）
          if (entry.encryptedPassword != null && entry.encryptedPassword!.isNotEmpty)
            _buildPasswordSection(),

          if (entry.encryptedPassword != null && entry.encryptedPassword!.isNotEmpty)
            const SizedBox(height: 16),

          // 备注（如果有）
          if (entry.notes != null && entry.notes!.isNotEmpty)
            _buildSection(
              title: '备注',
              icon: Icons.note,
              content: entry.notes!,
            ),

          const SizedBox(height: 16),

          // ✅ 新增：图片区域
          _buildImageSection(),

          const SizedBox(height: 24),

          // 最后修改时间
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Text(
                  '最后修改：${Helpers.formatDate(entry.updatedAt)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 信息区块
  Widget _buildSection({
    required String title,
    required IconData icon,
    required String content,
    VoidCallback? onCopy,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const Spacer(),
              if (onCopy != null)
                IconButton(
                  icon: Icon(Icons.copy, size: 18, color: Colors.grey[600]),
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
            style: const TextStyle(fontSize: 16),
          ),
        ],
      ),
    );
  }

  /// 密码区块
  Widget _buildPasswordSection() {
    final entry = _entry!;

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
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock, size: 20, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Text(
                '密码',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(
                  _passwordHidden ? Icons.visibility_off : Icons.visibility,
                  size: 18,
                  color: Colors.grey[600],
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
                icon: Icon(Icons.copy, size: 18, color: Colors.grey[600]),
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
              style: const TextStyle(fontSize: 16),
            ),
        ],
      ),
    );
  }

  /// ✅ 新增：图片区域
  Widget _buildImageSection() {
    if (_isLoadingImages) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Row(
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('加载图片中...'),
          ],
        ),
      );
    }

    if (_imageThumbnails.isEmpty) {
      return const SizedBox.shrink(); // 没有图片时不显示
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题
        Row(
          children: [
            Icon(Icons.image, size: 20, color: Colors.grey[600]),
            const SizedBox(width: 8),
            Text(
              '图片（${_imageThumbnails.length}张）',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 图片网格
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4, // 每行4张缩略图
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: _imageThumbnails.length > 8 ? 9 : _imageThumbnails.length,
          itemBuilder: (context, index) {
            // 如果图片超过8张，第9个位置显示 "+N"
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

  /// 图片缩略图
  Widget _buildImageThumbnail(int index) {
    final imageBytes = _imageThumbnails[index];

    return GestureDetector(
      onTap: () => _viewImage(index),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            imageBytes,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: Colors.grey.shade200,
              child: const Icon(
                Icons.broken_image,
                color: Colors.grey,
                size: 32,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "+N" 更多图片按钮
  Widget _buildMoreImagesButton(int remaining) {
    return GestureDetector(
      onTap: () => _viewImage(8), // 跳转到第9张（索引8）
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey.shade200,
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.more_horiz,
                size: 24,
                color: Colors.grey.shade600,
              ),
              const SizedBox(height: 2),
              Text(
                '+$remaining',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}