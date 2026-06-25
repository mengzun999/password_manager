import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/app.dart';
import 'package:password_manager/constants/app_constants.dart';
import 'package:password_manager/core/crypto/aes_gcm.dart';
import 'package:password_manager/core/services/backup_service.dart';
import 'package:password_manager/core/storage/shared_prefs.dart';
import 'package:password_manager/core/storage/secure_storage.dart';
import 'package:password_manager/core/storage/database.dart';
import 'package:password_manager/providers/auth_provider.dart';
import 'package:password_manager/providers/password_provider.dart';
import 'package:password_manager/providers/settings_provider.dart';
import 'package:password_manager/widgets/gesture_pattern_view.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/toast_utils.dart';
import 'about_page.dart';
import 'background_settings_page.dart';
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

  /// 完全自定义的、不受键盘和 viewInsets 顶推干扰的绝对居中二次确认对话框
  Future<bool> _showCustomConfirmDialog({
    required String title,
    required String content,
    required String confirmText,
    bool isDanger = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      useRootNavigator: true, // 强制使用根路由
      builder: (context) {
        return Material(
          type: MaterialType.transparency, // 透明遮罩
          child: Center( // 👈 核心：绝对物理居中
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).dialogBackgroundColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    content,
                    style: TextStyle(
                        fontSize: 15,
                        color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.8)
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        // 如果是高危操作（清空所有），确认按钮使用红色
                        child: Text(
                          confirmText,
                          style: TextStyle(
                            color: isDanger ? Colors.red : Theme.of(context).primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    return result ?? false;
  }

  Future<void> _loadSettings() async {
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _reEncryptForGesture(Uint8List newMasterKey) async {
    final storedGestureHash = await SecureStorage.read(
      AppConstants.keyGestureHash,
    );
    if (storedGestureHash != null) {
      final gestureKey = Uint8List.fromList(
        utf8.encode(storedGestureHash.substring(0, 32)),
      );
      final newEncryptedMasterKey = await AESGCMHelper.encryptBytes(
        newMasterKey,
        gestureKey,
      );
      await SecureStorage.write(
        AppConstants.keyEncryptedMasterKeyForGesture,
        base64Encode(newEncryptedMasterKey),
      );
    }
  }

  Future<void> _reEncryptForBiometric(Uint8List newMasterKey) async {
    final biometricKeyBase64 = await SecureStorage.read(
      AppConstants.keyBiometricKeyId,
    );
    if (biometricKeyBase64 != null) {
      final biometricKey = base64Decode(biometricKeyBase64);
      final newEncryptedMasterKey = await AESGCMHelper.encryptBytes(
        newMasterKey,
        biometricKey,
      );
      await SecureStorage.write(
        AppConstants.keyEncryptedMasterKeyForBiometric,
        base64Encode(newEncryptedMasterKey),
      );
    }
  }

  // ========== 手势图案 ==========
  Future<void> _changeGesture() async {
    final hasGesture = await SharedPrefs.hasGesture();
    bool verified = false;

    if (hasGesture) {
      verified = await _verifyExistingGesture();
    } else {
      final password = await _showPasswordDialog('验证身份', '请输入主密码');
      if (password != null && password.isNotEmpty) {
        verified = await ref
            .read(authProvider.notifier)
            .verifyMasterPassword(password);
        if (!verified && mounted) {
          ToastUtils.showError(context, '主密码错误，请重试');
        }
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
    final patternKey = GlobalKey<GesturePatternViewState>();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('验证手势'),
        content: SizedBox(
          width: 250,
          height: 250,
          child: GesturePatternView(
            key: patternKey,
            onPatternComplete: (pattern) async {
              final isValid = await _verifyGesturePattern(pattern);
              if (isValid) {
                Navigator.pop(context);
                if (!completer.isCompleted) {
                  completer.complete(true);
                }
              } else {
                patternKey.currentState?.clearPattern();
                ToastUtils.showError(context, '手势错误，请重试');
              }
            },
            onPatternChanged: (_) {},
          ),
        ),
      ),
    );

    if (!completer.isCompleted) {
      completer.complete(false);
    }

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

  // ========== 导出备份 ==========
  Future<void> _exportBackup() async {
    final recoveryKey = await _showRecoveryKeyDialog(
      title: '验证恢复密钥',
      hint: '请输入128位恢复密钥',
    );
    if (recoveryKey == null || recoveryKey.isEmpty) {
      ToastUtils.showWarning(context, '已取消导出');
      return;
    }

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
          text:
              '密码管理器备份文件，请妥善保管\n'
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
      hint: '请输入备份文件对应的恢复密钥（128个十六进制字符）',
    );
    if (recoveryKey == null || recoveryKey.isEmpty) {
      ToastUtils.showWarning(context, '已取消导入');
      return;
    }

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
        currentMasterKey,
      );

      if (success && mounted) {
        ToastUtils.showSuccess(context, '导入成功！');
        ref.read(passwordProvider.notifier).loadEntries();
        if (mounted) {
          Navigator.pop(context);
        }
      } else {
        ToastUtils.showError(context, '导入失败：\n• 恢复密钥错误\n• 备份文件已损坏\n• 或文件版本不兼容');
      }
    } catch (e) {
      ToastUtils.showError(context, '导入失败: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<String?> _showRecoveryKeyDialog({
    String title = '输入恢复密钥',
    String hint = '请输入128位的恢复密钥',
  }) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (context) {
        return Material(
          type: MaterialType.transparency,
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).dialogBackgroundColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    autofocus: false,  // ✅ 不自动弹出键盘
                    textInputAction: TextInputAction.done,
                    maxLength: 128,
                    maxLines: 3,
                    minLines: 2,
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: const TextStyle(fontSize: 14),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onSubmitted: (_) {
                      // 按回车键时触发确定
                      Navigator.pop(context, controller.text);
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(context, controller.text),
                        child: const Text('确定'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ========== 清空数据 ==========
  Future<void> _clearAllData() async {
    final confirmed = await _showCustomConfirmDialog(
      title: '危险操作',
      content: '确定要清空所有数据吗？此操作不可恢复！',
      confirmText: '清空',
      isDanger: true,
    );

    if (confirmed == true) {
      setState(() => _isLoading = true);
      try {
        // 1. 清空数据库和图片文件
        await DatabaseHelper.clearAllData();

        // 2. 清空 SecureStorage
        await SecureStorage.clearAll();

        // 3. ✅ 清空 SharedPreferences（包括背景图设置、暗黑模式等）
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();

        // 4. 重置认证状态
        ref.read(authProvider.notifier).resetAllData();

        // 5. 重置设置状态
        ref.read(settingsProvider.notifier).resetAllSettings();

        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            AppRoutes.setup,
                (route) => false,
          );
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
      // 强制使用 RootNavigator，有时非 Root 在 Insets 混乱时更难感知物理高宽
      useRootNavigator: true,
      builder: (context) {
        return Material(
          type: MaterialType.transparency, // 保证遮罩层透明
          child: Center( // 👈 强制让内容在全局居中，不再受默认 AlertDialog 的 insetPadding 摆布
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                // 模拟系统的 AlertDialog 样式，可以根据你的主题调整颜色
                color: Theme.of(context).dialogBackgroundColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min, // 👈 关键：包裹内容
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    autofocus: true, // 让它主动聚焦
                    decoration: InputDecoration(
                      hintText: hint,
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () => Navigator.pop(context, controller.text),
                        child: const Text('确定'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<Directory> _getImagesDir() async {
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
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade600,
          ),
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
      title: Text(
        title,
        style: isDestructive ? const TextStyle(color: Colors.red) : null,
      ),
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

  // ✅ 生物识别设置项 - 直接从 SettingsState 读取，不进行任何耗时操作
  Widget _buildBiometricSection(SettingsState settings) {
    return SizedBox(
      height: 72,
      child: ListTile(
        leading: const Icon(Icons.fingerprint),
        title: const Text('生物识别解锁'),
        subtitle: Text(settings.isBiometricEnabled ? '已开启' : '未开启'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (settings.isBiometricAvailable && settings.isBiometricEnabled)
              const Icon(Icons.check_circle, color: Colors.green, size: 20),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () {
          // ✅ 如果设备不支持生物识别，给出提示
          if (!settings.isBiometricAvailable) {
            ToastUtils.showInfo(context, '当前设备不支持生物识别');
            return;
          }
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BiometricSetupPage()),
          ).then((_) => _loadSettings());
        },
      ),
    );
  }

// ========== 图片压缩档位选择 ==========
  Future<void> _showCompressLevelDialog() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return showDialog(
      context: context,
      useRootNavigator: true,  // ✅ 加上
      builder: (context) {
        return Material(
          type: MaterialType.transparency,
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).dialogBackgroundColor,
                borderRadius: BorderRadius.circular(12),
              ),
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '图片压缩',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _buildCompressOption(
                    context,
                    level: AppConstants.compressLevelOriginal,
                    name: AppConstants.compressLevelNameOriginal,
                    subtitle: AppConstants.compressLevelSubtitleOriginal,
                    isDark: isDark,
                  ),
                  _buildCompressOption(
                    context,
                    level: AppConstants.compressLevelHigh,
                    name: AppConstants.compressLevelNameHigh,
                    subtitle: AppConstants.compressLevelSubtitleHigh,
                    isDark: isDark,
                  ),
                  _buildCompressOption(
                    context,
                    level: AppConstants.compressLevelMedium,
                    name: AppConstants.compressLevelNameMedium,
                    subtitle: AppConstants.compressLevelSubtitleMedium,
                    isDark: isDark,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompressOption(
    BuildContext context, {
    required int level,
    required String name,
    required String subtitle,
    required bool isDark,
  }) {
    final currentLevel = ref.watch(settingsProvider).imageCompressLevel;
    final isSelected = level == currentLevel;

    return InkWell(
      onTap: () {
        ref.read(settingsProvider.notifier).setImageCompressLevel(level);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                    ? Colors.blue.shade800.withValues(alpha: 0.3)
                    : Colors.blue.shade50)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? Colors.blue
                : (isDark ? Colors.grey.shade700 : Colors.grey.shade300),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Radio<int>(
              value: level,
              groupValue: currentLevel,
              onChanged: (value) {
                ref
                    .read(settingsProvider.notifier)
                    .setImageCompressLevel(level);
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle, color: Colors.blue, size: 20),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);

    if (_isLoading || settings.isLoading) {
      return Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(title: const Text('设置')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final List<Widget> items = [
      _buildSectionHeader('安全'),
      _buildMenuItem(icon: Icons.draw, title: '修改手势图案', onTap: _changeGesture),
      _buildBiometricSection(settings),
      const Divider(),
      _buildSectionHeader('数据'),
      _buildMenuItem(
        icon: Icons.backup,
        title: '导出备份',
        subtitle: '将数据导出到加密文件',
        onTap: _exportBackup,
      ),
      _buildMenuItem(
        icon: Icons.restore,
        title: '导入备份',
        subtitle: '从备份文件恢复数据',
        onTap: _importBackup,
      ),
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
        onChanged: (value) => ref
            .read(settingsProvider.notifier)
            .toggleDarkModeFollowSystem(value),
      ),
      _buildSwitchItem(
        icon: Icons.dark_mode,
        title: '深色模式',
        subtitle: settings.darkModeFollowSystem ? '已跟随系统，手动切换无效' : '开启后使用深色主题',
        value: settings.isDarkMode,
        onChanged: settings.darkModeFollowSystem
            ? (_) {}
            : (value) =>
                  ref.read(settingsProvider.notifier).toggleDarkMode(value),
      ),
      _buildMenuItem(
        icon: Icons.image,
        title: '背景图设置',
        subtitle: '自定义密码列表页背景',
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const BackgroundSettingsPage()),
          );
        },
      ),
      const Divider(),
      _buildSectionHeader('图片'),
      _buildMenuItem(
        icon: Icons.compress,
        title: '图片压缩',
        subtitle:
            '当前: ${settings.compressLevelName} - ${settings.compressLevelSubtitle}',
        onTap: () {
          _showCompressLevelDialog();
        },
      ),
      const Divider(),
      _buildSectionHeader('其他'),
      _buildMenuItem(
        icon: Icons.info_outline,
        title: '关于',
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AboutPage()),
          );
        },
      ),
      const SizedBox(height: 40),
    ];

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text('设置')),
      body: SafeArea(
        bottom: true,
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(delegate: SliverChildListDelegate(items)),
            ),
            const SliverPadding(padding: EdgeInsets.only(bottom: 40)),
          ],
        ),
      ),
    );
  }
}
