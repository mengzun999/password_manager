import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../storage/database.dart';
import '../crypto/aes_gcm.dart';
import '../../utils/helpers.dart';
import '../models/password_entry.dart';
import '../models/image_model.dart';

/// 备份服务
/// 负责导出和导入加密备份（包含密码条目和图片）
class BackupService {
  /// 导出备份（包含图片）
  /// 返回备份文件路径，失败返回null
  static Future<String?> exportBackup(Uint8List masterKey) async {
    try {
      // 1. 获取所有密码条目
      final entries = await DatabaseHelper.getAllEntries();

      // 2. 获取所有图片元数据
      final allImages = <ImageModel>[];
      for (final entry in entries) {
        final images = await DatabaseHelper.getImagesByEntryId(entry.id);
        allImages.addAll(images);
      }

      // 3. 读取并加密所有图片文件
      final imagesDir = await _getImagesDir();
      final encryptedImagesData = <Map<String, dynamic>>[];

      for (final image in allImages) {
        // 读取加密的图片文件
        final imageFile = File('${imagesDir.path}/${image.filename}');
        final thumbFile = File('${imagesDir.path}/${image.thumbnailFilename}');

        if (await imageFile.exists()) {
          // 图片文件已经是加密的，直接读取字节（不需要再次加密）
          final imageBytes = await imageFile.readAsBytes();
          final thumbBytes = thumbFile.existsSync()
              ? await thumbFile.readAsBytes()
              : null;

          encryptedImagesData.add({
            'imageModel': image.toMap(),
            'encryptedImageBytes': base64Encode(imageBytes),
            'encryptedThumbBytes': thumbBytes != null ? base64Encode(thumbBytes) : null,
          });
        }
      }

      // 4. 构建备份数据
      final backupData = {
        'version': 1,
        'exportTime': Helpers.currentTimestamp(),
        'entries': entries.map((e) => e.toMap()).toList(),
        'images': encryptedImagesData,
      };

      // 5. 转换为JSON字符串
      final jsonString = jsonEncode(backupData);

      // 6. 加密备份数据
      final encrypted = await AESGCMHelper.encrypt(jsonString, masterKey);

      // 7. 保存到文件
      final documentsDir = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${documentsDir.path}/backups');
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final fileName = 'backup_${Helpers.formatDate(Helpers.currentTimestamp())}.enc';
      final filePath = '${backupDir.path}/$fileName';
      await File(filePath).writeAsString(encrypted);

      return filePath;
    } catch (e) {
      return null;
    }
  }

  /// 导入备份（包含图片）
  /// 返回是否成功
  static Future<bool> importBackup(String filePath, Uint8List masterKey) async {
    try {
      // 1. 读取加密文件
      final encrypted = await File(filePath).readAsString();

      // 2. 解密
      final jsonString = await AESGCMHelper.decrypt(encrypted, masterKey);

      // 3. 解析JSON
      final backupData = jsonDecode(jsonString) as Map<String, dynamic>;

      // 4. 验证版本
      if (backupData['version'] != 1) {
        return false;
      }

      // 5. 恢复数据（先清空现有数据和图片文件）
      await DatabaseHelper.clearAllData();
      await _clearAllImageFiles();

      // 6. 恢复密码条目
      final entries = backupData['entries'] as List;
      for (final entryMap in entries) {
        final entry = PasswordEntry.fromMap(entryMap as Map<String, dynamic>);
        await DatabaseHelper.insertEntry(entry);
      }

      // 7. 恢复图片
      final imagesData = backupData['images'] as List? ?? [];
      final imagesDir = await _getImagesDir();

      for (final imageData in imagesData) {
        final imageModel = ImageModel.fromMap(imageData['imageModel'] as Map<String, dynamic>);

        // 恢复图片文件
        final imageBytes = base64Decode(imageData['encryptedImageBytes'] as String);
        await File('${imagesDir.path}/${imageModel.filename}').writeAsBytes(imageBytes);

        // 恢复缩略图文件
        if (imageData['encryptedThumbBytes'] != null) {
          final thumbBytes = base64Decode(imageData['encryptedThumbBytes'] as String);
          await File('${imagesDir.path}/${imageModel.thumbnailFilename}').writeAsBytes(thumbBytes);
        }

        // 恢复数据库记录
        await DatabaseHelper.insertImage(imageModel);
      }

      return true;
    } catch (e) {
      return false;
    }
  }

  /// 选择备份文件
  static Future<String?> pickBackupFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,  // ✅ 改为 any，让用户可以选所有文件
      dialogTitle: '选择备份文件',
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      // 手动检查扩展名
      if (path.endsWith('.enc')) {
        return path;
      } else {
        // 提示用户选择正确的文件
        print('请选择 .enc 格式的备份文件');
        return null;
      }
    }
    return null;
  }

  /// 获取图片目录
  static Future<Directory> _getImagesDir() async {
    final documentsDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${documentsDir.path}/images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    return imagesDir;
  }

  /// 清空所有图片文件
  static Future<void> _clearAllImageFiles() async {
    try {
      final imagesDir = await _getImagesDir();
      if (await imagesDir.exists()) {
        await imagesDir.delete(recursive: true);
        await imagesDir.create();
      }
    } catch (e) {
      // 忽略删除失败
    }
  }
}