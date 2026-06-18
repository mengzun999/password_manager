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
import '../storage/shared_prefs.dart';

// ========== isolate 参数类 ==========

/// 图片保存参数（用于 isolate）
class _SaveImagesParams {
  final List<String> imagePaths;
  final String entryId;
  final Uint8List masterKey;
  final int maxCount;
  final int compressLevel;

  _SaveImagesParams({
    required this.imagePaths,
    required this.entryId,
    required this.masterKey,
    required this.maxCount,
    required this.compressLevel,
  });
}

/// 单张图片保存结果
class _SingleImageResult {
  final Uint8List encryptedImage;
  final Uint8List encryptedThumbnail;
  final String? mimeType;
  final int fileSize;

  _SingleImageResult({
    required this.encryptedImage,
    required this.encryptedThumbnail,
    required this.mimeType,
    required this.fileSize,
  });
}

/// 批量解密缩略图参数
class _DecryptThumbnailsParams {
  final List<Uint8List> encryptedData;
  final Uint8List masterKey;

  _DecryptThumbnailsParams({
    required this.encryptedData,
    required this.masterKey,
  });
}

/// 解密图片参数
class _DecryptImageParams {
  final Uint8List encryptedData;
  final Uint8List masterKey;

  _DecryptImageParams({
    required this.encryptedData,
    required this.masterKey,
  });
}

// ========== ImageService ==========

/// 图片服务
class ImageService {
  /// 批量保存图片（使用 isolate）
  static Future<List<ImageModel>> saveImages({
    required List<XFile> imageFiles,
    required String entryId,
    required Uint8List masterKey,
  }) async {
    if (imageFiles.isEmpty) return [];

    // 1. 检查数量限制
    final currentImages = await DatabaseHelper.getImagesByEntryId(entryId);
    final availableSlots = AppConstants.maxImageCountPerEntry - currentImages.length;
    if (availableSlots <= 0) return [];

    // 2. 限制数量
    final limitedFiles = imageFiles.take(availableSlots).toList();

    // 3. 获取下一个排序序号
    int currentOrder = await _getNextSortOrder(entryId);

    // 4. 准备参数
    final paths = limitedFiles.map((f) => f.path).toList();

    // 5. 获取压缩档位
    final compressLevel = await SharedPrefs.getImageCompressLevel();

    // 6. 在 isolate 中处理所有图片加密
    final results = await compute(
      _processImagesInIsolate,
      _SaveImagesParams(
        imagePaths: paths,
        entryId: entryId,
        masterKey: masterKey,
        maxCount: limitedFiles.length,
        compressLevel: compressLevel,
      ),
    );

    // 7. 保存到文件系统和数据库
    final imagesDir = await _getImagesDir();
    final savedImages = <ImageModel>[];

    for (int i = 0; i < results.length; i++) {
      final result = results[i];
      final imageId = Helpers.generateUuid();
      final imageFilename = '$imageId.enc';
      final thumbnailFilename = '${imageId}_thumb.enc';

      await File('${imagesDir.path}/$imageFilename')
          .writeAsBytes(result.encryptedImage);
      await File('${imagesDir.path}/$thumbnailFilename')
          .writeAsBytes(result.encryptedThumbnail);

      final imageModel = ImageModel(
        id: imageId,
        entryId: entryId,
        filename: imageFilename,
        thumbnailFilename: thumbnailFilename,
        fileSize: result.fileSize,
        mimeType: result.mimeType,
        sortOrder: currentOrder + i,
        createdAt: Helpers.currentTimestamp(),
      );

      await DatabaseHelper.insertImage(imageModel);
      savedImages.add(imageModel);
    }

    return savedImages;
  }

  /// 在 isolate 中处理图片加密
  static List<_SingleImageResult> _processImagesInIsolate(_SaveImagesParams params) {
    final results = <_SingleImageResult>[];

    for (final path in params.imagePaths) {
      try {
        // 读取原始图片
        Uint8List originalBytes = File(path).readAsBytesSync();

        // 根据压缩档位处理原图
        Uint8List imageToEncrypt;
        final compressLevel = params.compressLevel;

        if (compressLevel == AppConstants.compressLevelOriginal) {
          // 原图：不压缩
          imageToEncrypt = originalBytes;
        } else {
          // 压缩：转 JPEG 格式
          try {
            final image = img.decodeImage(originalBytes);
            if (image != null) {
              int quality;
              switch (compressLevel) {
                case AppConstants.compressLevelHigh:
                  quality = AppConstants.compressQualityHigh;
                  break;
                case AppConstants.compressLevelMedium:
                  quality = AppConstants.compressQualityMedium;
                  break;
                default:
                  quality = AppConstants.compressQualityMedium;
              }
              imageToEncrypt = Uint8List.fromList(
                img.encodeJpg(image, quality: quality),
              );
            } else {
              imageToEncrypt = originalBytes;
            }
          } catch (e) {
            imageToEncrypt = originalBytes;
          }
        }

        // 生成缩略图（固定 200x200，质量 80%）
        final thumbnailBytes = _generateThumbnailSync(originalBytes);

        // 加密图片
        final encryptedImage = AESGCMHelper.encryptBytesSync(imageToEncrypt, params.masterKey);
        final encryptedThumbnail = AESGCMHelper.encryptBytesSync(thumbnailBytes, params.masterKey);

        final mimeType = _getMimeTypeFromPath(path);

        results.add(_SingleImageResult(
          encryptedImage: encryptedImage,
          encryptedThumbnail: encryptedThumbnail,
          mimeType: mimeType,
          fileSize: imageToEncrypt.length,
        ));
      } catch (e) {
        continue;
      }
    }

    return results;
  }

  /// 在 isolate 中批量解密缩略图
  static List<Uint8List> _decryptThumbnailsInIsolate(
      _DecryptThumbnailsParams params,
      ) {
    final results = <Uint8List>[];

    for (final encrypted in params.encryptedData) {
      try {
        if (encrypted.isEmpty) {
          results.add(Uint8List(0));
          continue;
        }
        final decrypted = AESGCMHelper.decryptBytesSync(encrypted, params.masterKey);
        results.add(decrypted);
      } catch (e) {
        results.add(Uint8List(0));
      }
    }

    return results;
  }

  /// 在 isolate 中解密图片
  static Uint8List _decryptImageInIsolate(_DecryptImageParams params) {
    try {
      return AESGCMHelper.decryptBytesSync(params.encryptedData, params.masterKey);
    } catch (e) {
      return Uint8List(0);
    }
  }

  /// 同步生成缩略图（供 isolate 使用）
  static Uint8List _generateThumbnailSync(Uint8List originalBytes) {
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
      return originalBytes;
    }
  }

  /// 保存单张图片（保留原方法）
  static Future<ImageModel?> saveImage({
    required XFile imageFile,
    required String entryId,
    required Uint8List masterKey,
    int sortOrder = 0,
  }) async {
    try {
      final currentImages = await DatabaseHelper.getImagesByEntryId(entryId);
      if (currentImages.length >= AppConstants.maxImageCountPerEntry) {
        return null;
      }

      final originalBytes = await imageFile.readAsBytes();
      final thumbnailBytes = await _generateThumbnail(originalBytes);

      final imageId = Helpers.generateUuid();
      final imageFilename = '$imageId.enc';
      final thumbnailFilename = '${imageId}_thumb.enc';

      final encryptedImage = await AESGCMHelper.encryptBytes(originalBytes, masterKey);
      final encryptedThumbnail = await AESGCMHelper.encryptBytes(thumbnailBytes, masterKey);

      final imagesDir = await _getImagesDir();
      await File('${imagesDir.path}/$imageFilename').writeAsBytes(encryptedImage);
      await File('${imagesDir.path}/$thumbnailFilename').writeAsBytes(encryptedThumbnail);

      final mimeType = imageFile.mimeType ?? _getMimeTypeFromPath(imageFile.path);

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

  /// 删除图片
  static Future<bool> deleteImage(ImageModel image, Uint8List masterKey) async {
    try {
      final imagesDir = await _getImagesDir();

      final imageFile = File('${imagesDir.path}/${image.filename}');
      if (await imageFile.exists()) {
        await imageFile.delete();
      }

      if (image.thumbnailFilename != null) {
        final thumbFile = File('${imagesDir.path}/${image.thumbnailFilename}');
        if (await thumbFile.exists()) {
          await thumbFile.delete();
        }
      }

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

  /// 获取图片（直接解密，用于查看器内部加载）
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

  /// 在 isolate 中加载原图（不阻塞 UI）
  static Future<Uint8List?> loadImageInIsolate(
      ImageModel image,
      Uint8List masterKey,
      ) async {
    try {
      final imagesDir = await _getImagesDir();
      final imageFile = File('${imagesDir.path}/${image.filename}');

      if (!await imageFile.exists()) return null;

      final encryptedBytes = await imageFile.readAsBytes();

      final decryptedBytes = await compute(
        _decryptImageInIsolate,
        _DecryptImageParams(
          encryptedData: encryptedBytes,
          masterKey: masterKey,
        ),
      );

      if (decryptedBytes.isEmpty) return null;
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

  /// 批量获取缩略图（使用 isolate）
  static Future<List<Uint8List>> getThumbnailsBatch(
      List<ImageModel> images,
      Uint8List masterKey,
      ) async {
    if (images.isEmpty) return [];

    final imagesDir = await _getImagesDir();
    final encryptedThumbnails = <Uint8List>[];

    for (final image in images) {
      try {
        final thumbFile = File('${imagesDir.path}/${image.thumbnailFilename}');
        if (await thumbFile.exists()) {
          final encrypted = await thumbFile.readAsBytes();
          encryptedThumbnails.add(encrypted);
        } else {
          encryptedThumbnails.add(Uint8List(0));
        }
      } catch (e) {
        encryptedThumbnails.add(Uint8List(0));
      }
    }

    return await compute(
      _decryptThumbnailsInIsolate,
      _DecryptThumbnailsParams(
        encryptedData: encryptedThumbnails,
        masterKey: masterKey,
      ),
    );
  }

  /// 获取条目的所有图片
  static Future<List<ImageModel>> getEntryImages(String entryId) async {
    return await DatabaseHelper.getImagesByEntryId(entryId);
  }

  /// 从相册选择图片
  static Future<List<XFile>> pickImages({int maxCount = 20}) async {
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
    final hasPermission = await PermissionService.requestCameraPermission();
    if (!hasPermission) {
      debugPrint('用户拒绝了相机权限');
      return null;
    }

    final picker = ImagePicker();
    final photo = await picker.pickImage(source: ImageSource.camera);
    return photo;
  }

  /// 生成缩略图（异步）
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
      return originalBytes;
    }
  }

  /// 生成图片缩略图（供外部预览使用）
  static Future<Uint8List> generateThumbnail(Uint8List originalBytes) async {
    return _generateThumbnail(originalBytes);
  }

  /// 获取图片目录
  static Future<Directory> _getImagesDir() async {
    final supportDir = await getApplicationSupportDirectory();
    final imagesDir = Directory('${supportDir.path}/images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    return imagesDir;
  }

  /// 根据路径获取MIME类型
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