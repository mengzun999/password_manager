import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';
import '../storage/database.dart';
import '../crypto/aes_gcm.dart';
import '../../utils/helpers.dart';
import '../models/password_entry.dart';
import '../models/image_model.dart';
import '../../core/storage/secure_storage.dart';
import '../../constants/app_constants.dart';

/// 备份服务
class BackupService {
  static Uint8List _deriveKeyFromRecovery(String recoveryKey) {
    return Uint8List.fromList(sha256.convert(utf8.encode(recoveryKey)).bytes);
  }

  static bool _isValidRecoveryKey(String key) {
    if (key.length != 128) return false;
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(key);
  }

  // ============================================================
  // 导出备份
  // ============================================================

  static Future<Map<String, dynamic>?> exportBackup(
      String recoveryKeyInput,
      Uint8List masterKey,  // ✅ 新增：当前主密钥
      ) async {
    try {
      final key = recoveryKeyInput.trim().replaceAll(RegExp(r'\s+'), '');

      if (!_isValidRecoveryKey(key)) {
        throw Exception('恢复密钥格式错误，请输入128字符的十六进制');
      }

      final storedHash = await SecureStorage.read(AppConstants.keyMnemonicHash);
      if (storedHash == null) {
        throw Exception('未找到恢复密钥，请先设置恢复密钥');
      }

      final inputHash = sha256.convert(utf8.encode(key)).toString();
      if (inputHash != storedHash) {
        throw Exception('恢复密钥错误');
      }

      // 从恢复密钥派生加密密钥
      final recoveryDerivedKey = _deriveKeyFromRecovery(key);

      final entries = await DatabaseHelper.getAllEntries();
      final allImages = <ImageModel>[];
      for (final entry in entries) {
        final images = await DatabaseHelper.getImagesByEntryId(entry.id);
        allImages.addAll(images);
      }

      final imagesDir = await _getImagesDir();
      final encryptedImagesData = <Map<String, dynamic>>[];

      // ✅ 导出：用 masterKey 解密，用 recoveryDerivedKey 加密
      // 处理密码条目
      final exportedEntries = <Map<String, dynamic>>[];
      for (final entry in entries) {
        String? reencryptedPassword;
        if (entry.encryptedPassword != null && entry.encryptedPassword!.isNotEmpty) {
          // 用主密钥解密
          final decryptedPassword = await AESGCMHelper.decrypt(
            entry.encryptedPassword!,
            masterKey,
          );
          // 用恢复密钥重新加密
          reencryptedPassword = await AESGCMHelper.encrypt(
            decryptedPassword,
            recoveryDerivedKey,
          );
        }

        exportedEntries.add({
          'id': entry.id,
          'title': entry.title,
          'username': entry.username,
          'encrypted_password': reencryptedPassword,
          'notes': entry.notes,
          'app_package_name': entry.appPackageName,
          'created_at': entry.createdAt,
          'updated_at': entry.updatedAt,
        });
      }

      // 处理图片
      for (final image in allImages) {
        final imageFile = File('${imagesDir.path}/${image.filename}');
        final thumbFile = File('${imagesDir.path}/${image.thumbnailFilename}');

        if (await imageFile.exists()) {
          // 用主密钥解密图片
          final encryptedImageBytes = await imageFile.readAsBytes();
          final decryptedImageBytes = await AESGCMHelper.decryptBytes(
            encryptedImageBytes,
            masterKey,
          );
          // 用恢复密钥重新加密
          final reencryptedImageBytes = await AESGCMHelper.encryptBytes(
            decryptedImageBytes,
            recoveryDerivedKey,
          );

          Uint8List? reencryptedThumbBytes;
          if (await thumbFile.exists()) {
            final encryptedThumbBytes = await thumbFile.readAsBytes();
            final decryptedThumbBytes = await AESGCMHelper.decryptBytes(
              encryptedThumbBytes,
              masterKey,
            );
            reencryptedThumbBytes = await AESGCMHelper.encryptBytes(
              decryptedThumbBytes,
              recoveryDerivedKey,
            );
          }

          encryptedImagesData.add({
            'imageModel': image.toMap(),
            'encryptedImageBytes': base64Encode(reencryptedImageBytes),
            'encryptedThumbBytes': reencryptedThumbBytes != null
                ? base64Encode(reencryptedThumbBytes)
                : null,
          });
        }
      }

      final backupData = {
        'version': 1,
        'exportTime': Helpers.currentTimestamp(),
        'entries': exportedEntries,
        'images': encryptedImagesData,
      };

      final jsonString = jsonEncode(backupData);
      // ✅ 用恢复密钥加密整个备份包
      final encrypted = await AESGCMHelper.encrypt(jsonString, recoveryDerivedKey);

      final documentsDir = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${documentsDir.path}/backups');
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final fileName = 'backup_${Helpers.formatDate(Helpers.currentTimestamp())}.enc';
      final filePath = '${backupDir.path}/$fileName';
      await File(filePath).writeAsString(encrypted);

      return {
        'filePath': filePath,
        'entryCount': entries.length,
        'imageCount': allImages.length,
        'exportTime': Helpers.formatDate(Helpers.currentTimestamp()),
      };
    } catch (e) {
      debugPrint('导出失败: $e');
      return null;
    }
  }

  // ============================================================
  // 导入备份
  // ============================================================

  /// 导入备份
  ///
  /// [filePath] 备份文件路径
  /// [recoveryKeyInput] 用户输入的恢复密钥
  /// [currentMasterKey] 当前应用的主密钥（用于重新加密数据）
  static Future<bool> importBackup(
      String filePath,
      String recoveryKeyInput,
      Uint8List currentMasterKey,
      ) async {
    try {
      debugPrint('=== 开始导入备份 ===');

      final key = recoveryKeyInput.trim().replaceAll(RegExp(r'\s+'), '');
      debugPrint('输入密钥长度: ${key.length}');

      // 1. 验证格式（只验证格式，不验证哈希）
      if (!_isValidRecoveryKey(key)) {
        debugPrint('❌ 步骤1失败：密钥格式错误');
        return false;
      }
      debugPrint('✅ 步骤1通过：密钥格式正确');

      // 2. 派生密钥（直接从用户输入的密钥派生）
      final recoveryDerivedKey = _deriveKeyFromRecovery(key);
      debugPrint('✅ 步骤2通过：派生密钥成功，长度: ${recoveryDerivedKey.length}');

      // 3. 读取文件
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('❌ 步骤3失败：文件不存在');
        return false;
      }
      debugPrint('✅ 步骤3通过：文件存在');

      final encrypted = await file.readAsString();
      debugPrint('文件大小: ${encrypted.length} 字符');

      // 4. ✅ 用用户输入的恢复密钥尝试解密备份包
      //    如果密钥错误，这里会抛出异常
      debugPrint('开始解密...');
      final jsonString = await AESGCMHelper.decrypt(encrypted, recoveryDerivedKey);
      debugPrint('✅ 步骤4通过：解密成功，JSON大小: ${jsonString.length}');

      // 5. 解析JSON
      final backupData = jsonDecode(jsonString) as Map<String, dynamic>;
      debugPrint('✅ 步骤5通过：JSON解析成功');

      // 6. 验证版本
      final version = backupData['version'] as int?;
      if (version != 1) {
        debugPrint('❌ 步骤6失败：不支持的版本 $version');
        return false;
      }
      debugPrint('✅ 步骤6通过：版本 $version');

      // 7. 清空数据
      await DatabaseHelper.clearAllData();
      await _clearAllImageFiles();
      debugPrint('✅ 步骤7通过：已清空数据');

      // 确保 images 表被清空
      try {
        final db = await DatabaseHelper.database;
        await db.delete('images');
        debugPrint('✅ 步骤7.1：已清空 images 表');
      } catch (e) {
        debugPrint('⚠️ 清空 images 表失败: $e');
      }

      // 8. 恢复条目（用当前主密钥重新加密密码）
      final entries = backupData['entries'] as List? ?? [];
      debugPrint('恢复 ${entries.length} 条密码记录');

      for (final entryMap in entries) {
        final entry = PasswordEntry.fromMap(entryMap as Map<String, dynamic>);

        String? reencryptedPassword;
        if (entry.encryptedPassword != null && entry.encryptedPassword!.isNotEmpty) {
          // ✅ 用恢复密钥解密密码
          final decryptedPassword = await AESGCMHelper.decrypt(
            entry.encryptedPassword!,
            recoveryDerivedKey,
          );
          // ✅ 用当前主密钥重新加密密码
          reencryptedPassword = await AESGCMHelper.encrypt(
            decryptedPassword,
            currentMasterKey,
          );
        }

        final newEntry = entry.copyWith(
          encryptedPassword: reencryptedPassword,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        );
        await DatabaseHelper.insertEntry(newEntry);
      }
      debugPrint('✅ 步骤8通过：恢复 ${entries.length} 条记录');

      // 9. 恢复图片
      final imagesData = backupData['images'] as List? ?? [];
      debugPrint('恢复 ${imagesData.length} 张图片');
      final imagesDir = await _getImagesDir();

      for (final imageData in imagesData) {
        final imageModel = ImageModel.fromMap(imageData['imageModel'] as Map<String, dynamic>);

        // ✅ 用恢复密钥解密图片
        final encryptedImageBytes = base64Decode(imageData['encryptedImageBytes'] as String);
        final decryptedImageBytes = await AESGCMHelper.decryptBytes(
          encryptedImageBytes,
          recoveryDerivedKey,
        );
        // ✅ 用当前主密钥重新加密图片
        final reencryptedImageBytes = await AESGCMHelper.encryptBytes(
          decryptedImageBytes,
          currentMasterKey,
        );
        await File('${imagesDir.path}/${imageModel.filename}').writeAsBytes(reencryptedImageBytes);

        if (imageData['encryptedThumbBytes'] != null) {
          final encryptedThumbBytes = base64Decode(imageData['encryptedThumbBytes'] as String);
          final decryptedThumbBytes = await AESGCMHelper.decryptBytes(
            encryptedThumbBytes,
            recoveryDerivedKey,
          );
          final reencryptedThumbBytes = await AESGCMHelper.encryptBytes(
            decryptedThumbBytes,
            currentMasterKey,
          );
          await File('${imagesDir.path}/${imageModel.thumbnailFilename}')
              .writeAsBytes(reencryptedThumbBytes);
        }

        await DatabaseHelper.insertImage(imageModel);
      }
      debugPrint('✅ 步骤9通过：恢复 ${imagesData.length} 张图片');

      debugPrint('=== 导入完成 ===');
      return true;
    } catch (e, stack) {
      debugPrint('❌ 导入异常: $e');
      debugPrint('堆栈: $stack');
      // ✅ 根据异常类型给出更明确的错误信息
      if (e.toString().contains('MAC check failed') ||
          e.toString().contains('Bad state') ||
          e.toString().contains('decrypt')) {
        debugPrint('⚠️ 可能是恢复密钥错误或文件损坏');
      }
      return false;
    }
  }

  // ============================================================
  // 工具方法
  // ============================================================

  static Future<String?> pickBackupFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      dialogTitle: '选择备份文件',
    );

    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      if (path.endsWith('.enc')) {
        return path;
      }
      return null;
    }
    return null;
  }

  static Future<Directory> _getImagesDir() async {
    final supportDir = await getApplicationSupportDirectory();
    final imagesDir = Directory('${supportDir.path}/images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    return imagesDir;
  }

  static Future<void> _clearAllImageFiles() async {
    try {
      final imagesDir = await _getImagesDir();
      if (await imagesDir.exists()) {
        await imagesDir.delete(recursive: true);
        await imagesDir.create();
      }
    } catch (_) {}
  }
}