import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/constants/app_constants.dart';
import 'package:password_manager/core/crypto/pbkdf2.dart';
import 'package:password_manager/core/crypto/random.dart';
import 'package:password_manager/core/storage/secure_storage.dart';

/// 认证状态
class AuthState {
  /// 是否已完成首次设置（已设置主密码）
  final bool isInitialized;

  /// 是否已解锁（应用是否处于解锁状态）
  final bool isUnlocked;

  /// 错误信息（验证失败时）
  final String? error;

  /// 主密钥（32字节，仅在解锁后存在于内存中）
  /// 锁屏或退出应用后会被清除
  final Uint8List? masterKey;

  const AuthState({
    required this.isInitialized,
    required this.isUnlocked,
    this.error,
    this.masterKey,
  });

  /// 复制并修改部分字段
  AuthState copyWith({
    bool? isInitialized,
    bool? isUnlocked,
    String? error,
    Uint8List? masterKey,
  }) {
    return AuthState(
      isInitialized: isInitialized ?? this.isInitialized,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      error: error ?? this.error,
      masterKey: masterKey ?? this.masterKey,
    );
  }
}

/// 认证状态提供者
final authProvider = NotifierProvider<AuthProvider, AuthState>(() {
  return AuthProvider();
});

/// 单独提供 masterKey，方便其他 provider 依赖
/// 使用方式：ref.watch(masterKeyProvider)
final masterKeyProvider = Provider<Uint8List?>((ref) {
  return ref.watch(authProvider).masterKey;
});


/// 认证提供者（管理主密码验证、解锁、锁定）
class AuthProvider extends Notifier<AuthState> {
  @override
  AuthState build() {
    return const AuthState(
      isInitialized: false,
      isUnlocked: false,
      masterKey: null,
    );
  }

  /// 检查是否已完成首次设置
  /// 读取 secure_storage 中是否有 salt 和密码哈希
  Future<void> checkInitialized() async {
    final hasSalt = await SecureStorage.containsKey(AppConstants.keySalt);
    final hasMasterHash = await SecureStorage.containsKey(
      AppConstants.keyMasterPasswordHash,
    );
    state = state.copyWith(
      isInitialized: hasSalt && hasMasterHash,
    );
  }

  /// 首次设置：创建主密码
  /// 1. 生成随机盐
  /// 2. 计算密码哈希并存储
  /// [password] 用户设置的主密码
  Future<void> setupMasterPassword(String password) async {
    // 生成16字节随机盐
    final salt = SecureRandom.generateBytes(AppConstants.saltLength);

    // 计算密码哈希（用于验证）
    final passwordHash = PBKDF2Helper.hashPassword(password, salt);

    // 存储到安全存储
    await SecureStorage.write(AppConstants.keySalt, base64Encode(salt));
    await SecureStorage.write(
      AppConstants.keyMasterPasswordHash,
      passwordHash,
    );

    // 更新初始化状态
    await checkInitialized();
  }

  /// 仅验证主密码是否正确（不返回密钥）
  /// [password] 用户输入的主密码
  Future<bool> verifyMasterPassword(String password) async {
    final saltBase64 = await SecureStorage.read(AppConstants.keySalt);
    final storedHash = await SecureStorage.read(
      AppConstants.keyMasterPasswordHash,
    );
    if (saltBase64 == null || storedHash == null) return false;

    final salt = base64Decode(saltBase64);
    return PBKDF2Helper.verifyPassword(password, salt, storedHash);
  }

  /// 验证主密码并返回主密钥
  /// 用于解锁场景：验证密码正确后，派生密钥用于后续加解密
  /// [password] 用户输入的主密码
  /// 返回主密钥（32字节），密码错误返回 null
  Future<Uint8List?> verifyAndGetKey(String password) async {
    // 1. 读取存储的 salt
    final saltBase64 = await SecureStorage.read(AppConstants.keySalt);
    // 2. 读取存储的密码哈希
    final storedHash = await SecureStorage.read(
      AppConstants.keyMasterPasswordHash,
    );

    // 3. 如果数据不存在，返回 null
    if (saltBase64 == null || storedHash == null) {
      return null;
    }

    // 4. 解码 salt
    final salt = base64Decode(saltBase64);

    // 5. 验证密码是否正确
    final isValid = PBKDF2Helper.verifyPassword(password, salt, storedHash);

    // 6. 如果密码正确，派生主密钥并返回
    if (isValid) {
      return PBKDF2Helper.deriveKey(password, salt);
    }

    // 7. 密码错误，返回 null
    return null;
  }

  /// 解锁应用
  /// [masterKey] 可选，如果传入则直接使用；否则需要先调用 verifyAndGetKey
  void unlock({Uint8List? masterKey}) {
    state = state.copyWith(
      isUnlocked: true,
      error: null,
      masterKey: masterKey,
    );
  }

  /// 锁定应用（清除内存中的主密钥）
  void lock() {
    state = state.copyWith(
      isUnlocked: false,
      masterKey: null,  // 锁定时清除主密钥，保护数据安全
    );
  }

  /// 设置错误信息
  void setError(String error) {
    state = state.copyWith(error: error);
  }

  /// 清除错误信息
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// 重置所有数据（清空安全存储）
  /// 调用后应用会回到首次设置状态
  Future<void> resetAllData() async {
    await SecureStorage.clearAll();
    state = const AuthState(
      isInitialized: false,
      isUnlocked: false,
      masterKey: null,
    );
  }

  /// 保存恢复密钥（首次设置时调用）
  Future<void> setupRecoveryKey(String recoveryKey) async {
    // 计算恢复密钥的哈希并存储
    final bytes = utf8.encode(recoveryKey);
    final hash = base64Encode(sha256.convert(bytes).bytes);
    await SecureStorage.write(AppConstants.keyMnemonicHash, hash);
  }

  /// 验证恢复密钥（忘记密码时调用）
  Future<bool> verifyRecoveryKey(String recoveryKey) async {
    final storedHash = await SecureStorage.read(AppConstants.keyMnemonicHash);
    if (storedHash == null) return false;

    final bytes = utf8.encode(recoveryKey);
    final hash = base64Encode(sha256.convert(bytes).bytes);
    return hash == storedHash;
  }
}