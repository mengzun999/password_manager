import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/app.dart';
import 'package:password_manager/constants/app_constants.dart';
import 'package:password_manager/core/crypto/aes_gcm.dart';
import 'package:password_manager/core/crypto/pbkdf2.dart';
import 'package:password_manager/core/crypto/random.dart';
import 'package:password_manager/core/models/image_model.dart';
import 'package:password_manager/core/services/backup_service.dart';
import 'package:password_manager/core/services/biometric_service.dart';
import 'package:password_manager/core/storage/shared_prefs.dart';
import 'package:password_manager/core/storage/secure_storage.dart';
import 'package:password_manager/core/storage/database.dart';
import 'package:password_manager/providers/auth_provider.dart';
import 'package:password_manager/providers/password_provider.dart';
import 'package:password_manager/providers/settings_provider.dart';
import 'package:password_manager/widgets/gesture_pattern_view.dart';
import '../../utils/toast_utils.dart';
import 'biometric_setup.dart';
import 'gesture_setup_page.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    if (mounted) setState(() => _isLoading = false);
  }

  // ========== 主密码修改 ==========
  Future<void> _changeMasterPassword() async {
    final currentPassword = await _showPasswordDialog('验证身份', '请输入当前主密码');
    if (currentPassword == null || currentPassword.isEmpty) return;

    final authNotifier = ref.read(authProvider.notifier);
    final isValid = await authNotifier.verifyMasterPassword(currentPassword);
    if (!isValid) {
      ToastUtils.showError(context, '当前密码错误');
      return;
    }

    final newPassword = await _showPasswordDialog('设置新密码', '请输入新主密码（至少6位）');
    if (newPassword == null || newPassword.length < 6) {
      ToastUtils.showError(context, '密码至少6位');
      return;
    }

    final confirmPassword = await _showPasswordDialog('确认新密码', '请再次输入新主密码');
    if (newPassword != confirmPassword) {
      ToastUtils.showError(context, '两次输入的密码不一致');
      return;
    }

    final oldSaltBase64 = await SecureStorage.read(AppConstants.keySalt);
    final oldMasterKey = await authNotifier.verifyAndGetKey(currentPassword);
    if (oldSaltBase64 == null || oldMasterKey == null) {
      ToastUtils.showError(context, '获取密钥失败');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final entries = await DatabaseHelper.getAllEntries();
      final allImages = <ImageModel>[];
      for (final entry in entries) {
        allImages.addAll(await DatabaseHelper.getImagesByEntryId(entry.id));
      }

      final newSalt = SecureRandom.generateBytes(AppConstants.saltLength);
      final newMasterKey = PBKDF2Helper.deriveKey(newPassword, newSalt);
      final newPasswordHash = PBKDF2Helper.hashPassword(newPassword, newSalt);

      for (final entry in entries) {
        String? newEncryptedPassword;
        if (entry.encryptedPassword != null && entry.encryptedPassword!.isNotEmpty) {
          final decrypted = await AESGCMHelper.decrypt(entry.encryptedPassword!, oldMasterKey);
          newEncryptedPassword = await AESGCMHelper.encrypt(decrypted, newMasterKey);
        }
        await DatabaseHelper.updateEntry(
          entry.copyWith(
            encryptedPassword: newEncryptedPassword,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      }

      final imagesDir = await _getImagesDir();
      for (final image in allImages) {
        final imageFile = File('${imagesDir.path}/${image.filename}');
        final thumbFile = File('${imagesDir.path}/${image.thumbnailFilename}');

        if (await imageFile.exists()) {
          final encryptedImageBytes = await imageFile.readAsBytes();
          final decryptedImageBytes = await AESGCMHelper.decryptBytes(encryptedImageBytes, oldMasterKey);
          await imageFile.writeAsBytes(await AESGCMHelper.encryptBytes(decryptedImageBytes, newMasterKey));
        }

        if (await thumbFile.exists()) {
          final encryptedThumbBytes = await thumbFile.readAsBytes();
          final decryptedThumbBytes = await AESGCMHelper.decryptBytes(encryptedThumbBytes, oldMasterKey);
          await thumbFile.writeAsBytes(await AESGCMHelper.encryptBytes(decryptedThumbBytes, newMasterKey));
        }
      }

      await SecureStorage.write(AppConstants.keySalt, base64Encode(newSalt));
      await SecureStorage.write(AppConstants.keyMasterPasswordHash, newPasswordHash);

      await _reEncryptForGesture(newMasterKey);
      await _reEncryptForBiometric(newMasterKey);


      authNotifier.unlock(masterKey: newMasterKey);
      ToastUtils.showSuccess(context, '主密码修改成功');

// ✅ 刷新密码列表，确保 UI 与数据库同步
      ref.read(passwordProvider.notifier).loadEntries();
    } catch (e) {
      ToastUtils.showError(context, '修改失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _reEncryptForGesture(Uint8List newMasterKey) async {
    final storedGestureHash = await SecureStorage.read(AppConstants.keyGestureHash);
    if (storedGestureHash != null) {
      final gestureKey = Uint8List.fromList(utf8.encode(storedGestureHash.substring(0, 32)));
      final newEncryptedMasterKey = await AESGCMHelper.encryptBytes(newMasterKey, gestureKey);
      await SecureStorage.write(
        AppConstants.keyEncryptedMasterKeyForGesture,
        base64Encode(newEncryptedMasterKey),
      );
    }
  }

  Future<void> _reEncryptForBiometric(Uint8List newMasterKey) async {
    final biometricKeyBase64 = await SecureStorage.read(AppConstants.keyBiometricKeyId);
    if (biometricKeyBase64 != null) {
      final biometricKey = base64Decode(biometricKeyBase64);
      final newEncryptedMasterKey = await AESGCMHelper.encryptBytes(newMasterKey, biometricKey);
      await SecureStorage.write(
        AppConstants.keyEncryptedMasterKeyForBiometric,
        base64Encode(newEncryptedMasterKey),
      );
    }
  }

  Uint8List _deriveKeyFromRecovery(String recoveryKey) {
    final bytes = utf8.encode(recoveryKey);
    final hash = sha256.convert(bytes);
    return Uint8List.fromList(hash.bytes);
  }

  // ========== 手势图案 ==========
  Future<void> _changeGesture() async {
    final hasGesture = await SharedPrefs.hasGesture();
    bool verified = false;

    if (hasGesture) {
      verified = await _verifyExistingGesture();
    } else {
      final password = await _showPasswordDialog('验证身份', '请输入主密码');
      if (password != null) {
        verified = await ref.read(authProvider.notifier).verifyMasterPassword(password);
      }
    }

    if (!verified) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GestureSetupPage()),
    );
    if (result == true && mounted) {
      ToastUtils.showSuccess(context, '手势图案设置成功');
    }
  }

  Future<bool> _verifyExistingGesture() async {
    final completer = Completer<bool>();
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('验证手势'),
        content: SizedBox(
          width: 250,
          height: 250,
          child: GesturePatternView(
            onPatternComplete: (pattern) async {
              final isValid = await _verifyGesturePattern(pattern);
              if (mounted) {
                Navigator.pop(context);
                completer.complete(isValid);
                if (!isValid) ToastUtils.showError(context, '手势错误');
              }
            },
            onPatternChanged: (_) {},
          ),
        ),
      ),
    );
    return completer.future;
  }

  Future<bool> _verifyGesturePattern(List<int> pattern) async {
    if (pattern.length < 4) return false;
    final storedHash = await SecureStorage.read(AppConstants.keyGestureHash);
    if (storedHash == null) return false;
    final patternString = pattern.join(',');
    final currentHash = sha256.convert(utf8.encode(patternString)).toString();
    return currentHash == storedHash;
  }

  // ========== 方案B：导出备份 ==========
  Future<void> _exportBackup() async {
    final recoveryKey = await _showRecoveryKeyDialog(
      title: '验证恢复密钥',
      hint: '请输入128位恢复密钥（128个十六进制字符）',
    );
    if (recoveryKey == null || recoveryKey.isEmpty) {
      ToastUtils.showWarning(context, '已取消导出');
      return;
    }

    // ✅ 获取当前主密钥
    final authState = ref.read(authProvider);
    final masterKey = authState.masterKey;
    if (masterKey == null) {
      ToastUtils.showError(context, '请先解锁应用');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final result = await BackupService.exportBackup(recoveryKey, masterKey);
      if (result != null && mounted) {
        final filePath = result['filePath'] as String;
        final entryCount = result['entryCount'] ?? 0;
        final imageCount = result['imageCount'] ?? 0;
        final exportTime = result['exportTime'] ?? '';

        final file = File(filePath);
        ToastUtils.showSuccess(
          context,
          '备份成功！包含 $entryCount 条密码，$imageCount 张图片',
        );

        await Share.shareXFiles(
          [XFile(file.path)],
          text: '密码管理器备份文件，请妥善保管\n'
              '导出时间：$exportTime\n'
              '包含 $entryCount 条密码记录',
        );
      } else {
        ToastUtils.showError(context, '导出失败：恢复密钥错误或未设置');
      }
    } catch (e) {
      ToastUtils.showError(context, '导出失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _importBackup() async {
    final filePath = await BackupService.pickBackupFile();
    if (filePath == null) return;

    if (!filePath.endsWith('.enc')) {
      ToastUtils.showError(context, '请选择 .enc 格式的备份文件');
      return;
    }

    final recoveryKey = await _showRecoveryKeyDialog(
      title: '输入恢复密钥',
      hint: '请输入128位恢复密钥（128个十六进制字符）',
    );
    if (recoveryKey == null || recoveryKey.isEmpty) {
      ToastUtils.showWarning(context, '已取消导入');
      return;
    }

    // ✅ 获取当前主密钥
    final authState = ref.read(authProvider);
    final currentMasterKey = authState.masterKey;
    if (currentMasterKey == null) {
      ToastUtils.showError(context, '请先解锁应用');
      return;
    }

    final confirmed = await ToastUtils.showDangerConfirmDialog(
      context,
      title: '导入备份',
      content: '导入备份将覆盖当前所有数据，确定继续吗？',
      confirmText: '导入',
    );
    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final success = await BackupService.importBackup(
        filePath,
        recoveryKey,
        currentMasterKey,  // ✅ 传入当前主密钥
      );

      if (success && mounted) {
        ToastUtils.showSuccess(context, '导入成功');
        ref.read(passwordProvider.notifier).loadEntries();
      } else {
        ToastUtils.showError(context, '导入失败：恢复密钥错误或文件损坏');
      }
    } catch (e) {
      ToastUtils.showError(context, '导入失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _showRecoveryKeyDialog({
    String title = '输入恢复密钥',
    String hint = '请输入32字符的恢复密钥（128位）',
  }) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 16)),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hint,
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  '（首次设置时抄写的128位十六进制字符串）',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(
                    hintText: '输入恢复密钥...',
                    hintStyle: TextStyle(fontSize: 12),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    isDense: true,
                  ),
                  maxLines: 2,
                  minLines: 1,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('取消', style: TextStyle(fontSize: 14)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange,
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('确认', style: TextStyle(fontSize: 14)),
          ),
        ],
        actionsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      ),
    );
  }

  // ========== 清空数据 ==========
  Future<void> _clearAllData() async {
    final confirmed = await ToastUtils.showDangerConfirmDialog(
      context,
      title: '危险操作',
      content: '确定要清空所有数据吗？此操作不可恢复！',
      confirmText: '清空',
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        await DatabaseHelper.clearAllData();
        await SecureStorage.clearAll();
        ref.read(authProvider.notifier).resetAllData();
        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(context, AppRoutes.setup, (route) => false);
        }
      } catch (e) {
        ToastUtils.showError(context, '清空失败: $e');
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  // ========== 辅助方法 ==========
  Future<String?> _showPasswordDialog(String title, String hint) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            obscureText: true,
            decoration: InputDecoration(
              hintText: hint,
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('确定')),
        ],
      ),
    );
  }

  Future<Directory> _getImagesDir() async {
    // ✅ 与 image_service.dart 保持一致，使用 ApplicationSupportDirectory
    final supportDir = await getApplicationSupportDirectory();
    final imagesDir = Directory('${supportDir.path}/images');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }
    return imagesDir;
  }

  // ========== UI 组件 ==========
  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          title,
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey.shade600),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Icon(icon, color: isDestructive ? Colors.red : null),
      title: Text(title, style: isDestructive ? const TextStyle(color: Colors.red) : null),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }

  Widget _buildSwitchItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      secondary: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildBiometricSection(SettingsState settings) {
    return SizedBox(
      height: 72,
      child: FutureBuilder<bool>(
        future: BiometricService.isAvailable(),
        builder: (context, snapshot) {
          final isAvailable = snapshot.data ?? false;

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)));
          }

          if (!isAvailable) {
            return Container(
              color: Colors.grey.shade50,
              child: const ListTile(
                leading: Icon(Icons.fingerprint, color: Colors.grey),
                title: Text('生物识别解锁'),
                subtitle: Text('当前设备不支持生物识别'),
                trailing: Icon(Icons.info_outline, color: Colors.grey),
              ),
            );
          }

          return ListTile(
            leading: const Icon(Icons.fingerprint),
            title: const Text('生物识别解锁'),
            subtitle: Text(settings.isBiometricEnabled ? '已开启' : '未开启'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (settings.isBiometricEnabled) const Icon(Icons.check_circle, color: Colors.green, size: 20),
                const Icon(Icons.chevron_right),
              ],
            ),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const BiometricSetupPage()))
                  .then((_) => _loadSettings());
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('设置')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final List<Widget> items = [
      _buildSectionHeader('安全'),
      _buildMenuItem(icon: Icons.lock, title: '修改主密码', onTap: _changeMasterPassword),
      _buildMenuItem(icon: Icons.draw, title: '修改手势图案', onTap: _changeGesture),
      _buildBiometricSection(settings),
      const Divider(),
      _buildSectionHeader('数据'),
      _buildMenuItem(icon: Icons.backup, title: '导出备份', subtitle: '将数据导出到加密文件', onTap: _exportBackup),
      _buildMenuItem(icon: Icons.restore, title: '导入备份', subtitle: '从备份文件恢复数据', onTap: _importBackup),
      _buildMenuItem(
        icon: Icons.delete_sweep,
        title: '清空所有数据',
        subtitle: '删除所有密码和设置',
        onTap: _clearAllData,
        isDestructive: true,
      ),
      const Divider(),
      _buildSectionHeader('外观'),
      _buildSwitchItem(
        icon: Icons.settings_suggest,
        title: '跟随系统',
        subtitle: '自动跟随系统深色/浅色模式',
        value: settings.darkModeFollowSystem,
        onChanged: (value) => ref.read(settingsProvider.notifier).toggleDarkModeFollowSystem(value),
      ),
      _buildSwitchItem(
        icon: Icons.dark_mode,
        title: '深色模式',
        subtitle: settings.darkModeFollowSystem ? '已跟随系统，手动切换无效' : '开启后使用深色主题',
        value: settings.isDarkMode,
        onChanged: settings.darkModeFollowSystem
            ? (_) {}
            : (value) => ref.read(settingsProvider.notifier).toggleDarkMode(value),
      ),
      const SizedBox(height: 40),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildListDelegate(items),
              ),
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
          ],
        ),
      ),
    );
  }
}