import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../storage/database.dart';
import '../crypto/aes_gcm.dart';
import '../../constants/app_constants.dart';
import '../../utils/helpers.dart';
import '../models/image_model.dart';
import '../services/permission_service.dart';

/// 图片服务
/// 负责图片的添加、删除、加密、解密、缩略图生成
class ImageService {
  /// 保存图片
  /// 返回ImageModel，失败返回null
  static Future<ImageModel?> saveImage({
    required XFile imageFile,
    required String entryId,
    required Uint8List masterKey,
    int sortOrder = 0,
  }) async {
    try {
      // 修复1：检查图片数量限制
      final currentImages = await DatabaseHelper.getImagesByEntryId(entryId);
      if (currentImages.length >= AppConstants.maxImageCountPerEntry) {
        return null; // 已达上限
      }

      // 1. 读取原始图片字节
      final originalBytes = await imageFile.readAsBytes();

      // 2. 生成缩略图
      final thumbnailBytes = await _generateThumbnail(originalBytes);

      // 3. 生成唯一文件名
      final imageId = Helpers.generateUuid();
      final imageFilename = '$imageId.enc';
      final thumbnailFilename = '${imageId}_thumb.enc';

      // 4. 加密原始图片
      final encryptedImage = await AESGCMHelper.encryptBytes(originalBytes, masterKey);

      // 5. 加密缩略图
      final encryptedThumbnail = await AESGCMHelper.encryptBytes(thumbnailBytes, masterKey);

      // 6. 保存到文件
      final imagesDir = await _getImagesDir();
      await File('${imagesDir.path}/$imageFilename').writeAsBytes(encryptedImage);
      await File('${imagesDir.path}/$thumbnailFilename').writeAsBytes(encryptedThumbnail);

      // 7. 修复：使用XFile自带的mimeType
      final mimeType = imageFile.mimeType ?? _getMimeTypeFromPath(imageFile.path);

      // 8. 保存到数据库
      final imageModel = ImageModel(
        id: imageId,
        entryId: entryId,
        filename: imageFilename,
        thumbnailFilename: thumbnailFilename,
        fileSize: originalBytes.length,
        mimeType: mimeType,
        sortOrder: sortOrder,
        createdAt: Helpers.currentTimestamp(),
      );

      await DatabaseHelper.insertImage(imageModel);

      return imageModel;
    } catch (e) {
      return null;
    }
  }

  /// 批量保存图片
  static Future<List<ImageModel>> saveImages({
    required List<XFile> imageFiles,
    required String entryId,
    required Uint8List masterKey,
  }) async {
    final List<ImageModel> savedImages = [];
    int currentOrder = await _getNextSortOrder(entryId);

    for (final imageFile in imageFiles) {
      // 检查是否已达上限
      if (savedImages.length + (await DatabaseHelper.getImagesByEntryId(entryId)).length
          >= AppConstants.maxImageCountPerEntry) {
        break;
      }

      final image = await saveImage(
        imageFile: imageFile,
        entryId: entryId,
        masterKey: masterKey,
        sortOrder: currentOrder++,
      );

      if (image != null) {
        savedImages.add(image);
      }
    }

    return savedImages;
  }

  /// 删除图片
  static Future<bool> deleteImage(ImageModel image, Uint8List masterKey) async {
    try {
      final imagesDir = await _getImagesDir();

      // 删除加密文件
      final imageFile = File('${imagesDir.path}/${image.filename}');
      if (await imageFile.exists()) {
        await imageFile.delete();
      }

      // 删除缩略图文件
      if (image.thumbnailFilename != null) {
        final thumbFile = File('${imagesDir.path}/${image.thumbnailFilename}');
        if (await thumbFile.exists()) {
          await thumbFile.delete();
        }
      }

      // 删除数据库记录
      await DatabaseHelper.deleteImage(image.id);

      return true;
    } catch (e) {
      return false;
    }
  }

  /// 删除条目的所有图片
  static Future<bool> deleteAllImagesForEntry(String entryId, Uint8List masterKey) async {
    try {
      final images = await DatabaseHelper.getImagesByEntryId(entryId);
      for (final image in images) {
        await deleteImage(image, masterKey);
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// 获取图片
  static Future<Uint8List?> getImage(ImageModel image, Uint8List masterKey) async {
    try {
      final imagesDir = await _getImagesDir();
      final imageFile = File('${imagesDir.path}/${image.filename}');

      if (!await imageFile.exists()) return null;

      final encryptedBytes = await imageFile.readAsBytes();
      final decryptedBytes = await AESGCMHelper.decryptBytes(encryptedBytes, masterKey);

      return decryptedBytes;
    } catch (e) {
      return null;
    }
  }

  /// 获取缩略图
  static Future<Uint8List?> getThumbnail(ImageModel image, Uint8List masterKey) async {
    try {
      final imagesDir = await _getImagesDir();
      final thumbFile = File('${imagesDir.path}/${image.thumbnailFilename}');

      if (!await thumbFile.exists()) return null;

      final encryptedBytes = await thumbFile.readAsBytes();
      final decryptedBytes = await AESGCMHelper.decryptBytes(encryptedBytes, masterKey);

      return decryptedBytes;
    } catch (e) {
      return null;
    }
  }

  /// 获取条目的所有图片
  static Future<List<ImageModel>> getEntryImages(String entryId) async {
    return await DatabaseHelper.getImagesByEntryId(entryId);
  }

  /// 从相册选择图片
  static Future<List<XFile>> pickImages({int maxCount = 20}) async {
    // ✅ 请求权限
    final hasPermission = await PermissionService.requestImagePermission();
    if (!hasPermission) {
      debugPrint('用户拒绝了图片访问权限');
      return [];
    }

    final picker = ImagePicker();
    final images = await picker.pickMultiImage(limit: maxCount);
    return images;
  }

  /// 拍照
  static Future<XFile?> takePhoto() async {
    // ✅ 请求相机权限
    final hasPermission = await PermissionService.requestCameraPermission();
    if (!hasPermission) {
      debugPrint('用户拒绝了相机权限');
      return null;
    }

    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.camera);
    return photo;
  }

  /// 修复：生成缩略图（添加错误处理）
  static Future<Uint8List> _generateThumbnail(Uint8List originalBytes) async {
    try {
      final image = img.decodeImage(originalBytes);
      if (image == null) return originalBytes;

      final thumbnail = img.copyResize(
        image,
        width: AppConstants.thumbnailWidth,
        height: AppConstants.thumbnailHeight,
      );

      return Uint8List.fromList(img.encodeJpg(thumbnail, quality: AppConstants.thumbnailQuality));
    } catch (e) {
      // 解码失败，返回原始字节
      return originalBytes;
    }
  }

  /// 获取图片目录
  static Future<Directory> _getImagesDir() async {
    // 使用 ApplicationSupportDirectory，更符合 Android 数据存储规范
    // 路径：Android: /data/data/com.meng.passwordmanager/flutter_support
    final supportDir = await getApplicationSupportDirectory();
    final imagesDir = Directory('${supportDir.path}/images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    return imagesDir;
  }

  /// 生成图片缩略图（用于待保存图片的预览）
  static Future<Uint8List> generateThumbnail(Uint8List originalBytes) async {
    return _generateThumbnail(originalBytes);
  }

  /// 修复：根据路径获取MIME类型（备用方法）
  static String _getMimeTypeFromPath(String path) {
    final lowerPath = path.toLowerCase();
    if (lowerPath.endsWith('.jpg') || lowerPath.endsWith('.jpeg')) return 'image/jpeg';
    if (lowerPath.endsWith('.png')) return 'image/png';
    if (lowerPath.endsWith('.gif')) return 'image/gif';
    if (lowerPath.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  /// 获取下一个排序序号
  static Future<int> _getNextSortOrder(String entryId) async {
    final images = await DatabaseHelper.getImagesByEntryId(entryId);
    if (images.isEmpty) return 0;
    return images.map((e) => e.sortOrder).reduce((a, b) => a > b ? a : b) + 1;
  }
}