import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:password_manager/constants/app_constants.dart';
import 'package:password_manager/core/crypto/aes_gcm.dart';
import 'package:password_manager/core/crypto/random.dart';
import 'package:password_manager/core/services/biometric_service.dart';
import 'package:password_manager/core/storage/secure_storage.dart';
import 'package:password_manager/core/storage/shared_prefs.dart';
import 'package:password_manager/providers/auth_provider.dart';
import 'package:password_manager/providers/settings_provider.dart';

/// 生物识别设置页面
class BiometricSetupPage extends ConsumerStatefulWidget {
  const BiometricSetupPage({super.key});

  @override
  ConsumerState<BiometricSetupPage> createState() => _BiometricSetupPageState();
}

class _BiometricSetupPageState extends ConsumerState<BiometricSetupPage> {
  bool _isEnabled = false;
  bool _isLoading = true;
  List<BiometricType> _availableTypes = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    _isEnabled = await SharedPrefs.isBiometricEnabled();
    _availableTypes = await BiometricService.getAvailableTypes();

    setState(() => _isLoading = false);
  }

  /// 添加生物识别（不需要再验证主密码，因为开启开关时已验证过）
  Future<void> _addBiometric() async {
    // 如果开关未开启，提示先开启
    if (!_isEnabled) {
      _showSnackBar('请先开启生物识别解锁开关');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 弹出生物识别验证（只验证生物识别本身）
      final isAuthenticated = await BiometricService.authenticate(
        reason: '添加新的${_getBiometricTypeName()}用于解锁',
      );

      if (isAuthenticated) {
        final authState = ref.read(authProvider);
        final masterKey = authState.masterKey;

        if (masterKey != null) {
          final biometricKeyId = SecureRandom.generateHex(32);
          final biometricKey = Uint8List.fromList(utf8.encode(biometricKeyId));
          final encryptedMasterKey = await AESGCMHelper.encryptBytes(masterKey, biometricKey);

          final existingKeys = await _getBiometricKeys();
          existingKeys.add({
            'id': biometricKeyId,
            'type': _getBiometricTypeName(),
            'createdAt': DateTime.now().millisecondsSinceEpoch,
          });
          await _saveBiometricKeys(existingKeys);

          await SecureStorage.write(
            '${AppConstants.keyEncryptedMasterKeyForBiometric}_$biometricKeyId',
            base64Encode(encryptedMasterKey),
          );

          _showSnackBar('添加成功');
          await _loadData();
        }
      } else {
        _showSnackBar('验证失败，请重试');
      }
    } catch (e) {
      _showSnackBar('添加失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 删除生物识别
  Future<void> _removeBiometric(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除'),
        content: const Text('确定要删除这个生物识别吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await SecureStorage.delete('${AppConstants.keyEncryptedMasterKeyForBiometric}_$id');

    final existingKeys = await _getBiometricKeys();
    existingKeys.removeWhere((key) => key['id'] == id);
    await _saveBiometricKeys(existingKeys);

    if (existingKeys.isEmpty && _isEnabled) {
      await ref.read(settingsProvider.notifier).toggleBiometric(false);
      setState(() => _isEnabled = false);
    }

    _showSnackBar('删除成功');
    await _loadData();
  }

  /// 验证主密码（仅用于开启开关时）
  Future<bool> _verifyMasterPassword() async {
    final password = await _showPasswordDialog();
    if (password == null || password.isEmpty) return false;

    final authNotifier = ref.read(authProvider.notifier);
    return await authNotifier.verifyMasterPassword(password);
  }

  /// 获取生物识别类型名称
  String _getBiometricTypeName() {
    if (_availableTypes.contains(BiometricType.face)) return '人脸';
    if (_availableTypes.contains(BiometricType.fingerprint)) return '指纹';
    if (_availableTypes.contains(BiometricType.iris)) return '虹膜';
    return '生物识别';
  }

  /// 获取已存储的生物识别列表
  Future<List<Map<String, dynamic>>> _getBiometricKeys() async {
    final keysJson = await SecureStorage.read(AppConstants.keyBiometricKeysList);
    if (keysJson == null) return [];
    return List<Map<String, dynamic>>.from(jsonDecode(keysJson));
  }

  /// 保存生物识别列表
  Future<void> _saveBiometricKeys(List<Map<String, dynamic>> keys) async {
    await SecureStorage.write(AppConstants.keyBiometricKeysList, jsonEncode(keys));
  }

  /// 显示密码对话框
  Future<String?> _showPasswordDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('验证身份'),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: const InputDecoration(
            hintText: '请输入主密码',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('确定')),
        ],
      ),
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  /// 切换生物识别开关
  Future<void> _toggleEnabled(bool value) async {
    if (value) {
      // 开启时需要验证主密码
      final verified = await _verifyMasterPassword();
      if (!verified) {
        _showSnackBar('验证失败');
        return;
      }
    }

    await ref.read(settingsProvider.notifier).toggleBiometric(value);
    setState(() => _isEnabled = value);

    if (!value) {
      _showSnackBar('生物识别解锁已关闭');
    } else {
      _showSnackBar('生物识别解锁已开启');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('生物识别设置'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // 开关区域
          SwitchListTile(
            title: const Text('启用生物识别解锁'),
            subtitle: const Text('开启后可以用指纹/人脸快速解锁应用'),
            value: _isEnabled,
            onChanged: _toggleEnabled,
          ),
          const Divider(),

          // 已添加的生物识别列表标题
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text(
                  '已添加的生物识别',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),

          // 列表区域
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _getBiometricKeys(),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.fingerprint, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        Text(
                          _isEnabled ? '暂未添加生物识别' : '请先开启生物识别解锁',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isEnabled ? '点击下方按钮添加' : '开启后即可添加',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) {
                    final item = snapshot.data![index];
                    return ListTile(
                      leading: Icon(
                        item['type'] == '人脸' ? Icons.face : Icons.fingerprint,
                        color: Colors.blue,
                      ),
                      title: Text(item['type']),
                      subtitle: Text(
                        '添加于 ${DateTime.fromMillisecondsSinceEpoch(item['createdAt']).toString().substring(0, 16)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _removeBiometric(item['id']),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // 添加按钮 - 只在开关开启时显示
          if (_isEnabled)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _addBiometric,
                  icon: Icon(_availableTypes.contains(BiometricType.face) ? Icons.face : Icons.fingerprint),
                  label: Text('添加${_getBiometricTypeName()}'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}