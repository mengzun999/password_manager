import 'dart:convert';
import 'package:flutter_riverpod/legacy.dart';
import 'package:password_manager/constants/app_constants.dart';
import 'package:password_manager/core/crypto/pbkdf2.dart';
import 'package:password_manager/core/crypto/random.dart';
import 'package:password_manager/core/storage/secure_storage.dart';

/// 认证状态
class AuthState {
  final bool isInitialized; // 是否已完成首次设置（是否已设置主密码）
  final bool isUnlocked; // 当前是否已解锁（App是否处于解锁状态）
  final String? error; // 错误信息

  AuthState({
    required this.isInitialized,
    required this.isUnlocked,
    this.error,
  });

  /// 复制并修改部分字段（方便更新状态）
  AuthState copyWith({bool? isInitialized, bool? isUnlocked, String? error}) {
    return AuthState(
      isInitialized: isInitialized ?? this.isInitialized,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      error: error,
    );
  }
}

/// 认证状态管理类
class AuthProvider extends StateNotifier<AuthState> {
  AuthProvider() : super(AuthState(isInitialized: false, isUnlocked: false));

  /// 检查是否已完成首次设置
  /// 检查 secure_storage 中是否有 salt 和 masterPasswordHash
  Future<void> checkInitialized() async {
    final hasSalt = await SecureStorage.containsKey(AppConstants.keySalt);
    final hasMasterHash = await SecureStorage.containsKey(
      AppConstants.keyMasterPasswordHash,
    );

    state = state.copyWith(isInitialized: hasSalt && hasMasterHash);
  }

  /// 首次设置：创建主密码
  /// 1. 生成随机 salt
  /// 2. 计算密码哈希
  /// 3. 存储到 secure_storage
  Future<void> setupMasterPassword(String password) async {
    // 生成16字节随机 salt
    final salt = SecureRandom.generateBytes(AppConstants.saltLength);
    // 计算密码哈希
    final passwordHash = PBKDF2Helper.hashPassword(password, salt);

    // 存储 salt 和密码哈希
    await SecureStorage.write(AppConstants.keySalt, base64Encode(salt));
    await SecureStorage.write(AppConstants.keyMasterPasswordHash, passwordHash);

    await checkInitialized();
  }

  /// 验证主密码是否正确
  /// 返回 true 表示密码正确
  Future<bool> verifyMasterPassword(String password) async {
    // 读取存储的 salt 和密码哈希
    final saltBase64 = await SecureStorage.read(AppConstants.keySalt);
    final storedHash = await SecureStorage.read(
      AppConstants.keyMasterPasswordHash,
    );

    if (saltBase64 == null || storedHash == null) {
      return false;
    }

    final salt = base64Decode(saltBase64);
    return PBKDF2Helper.verifyPassword(password, salt, storedHash);
  }

  /// 解锁 App
  void unlock() {
    state = state.copyWith(isUnlocked: true, error: null);
  }

  /// 锁定 App
  void lock() {
    state = state.copyWith(isUnlocked: false);
  }

  /// 设置错误信息
  void setError(String error) {
    state = state.copyWith(error: error);
  }

  /// 清除错误信息
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// 重置所有数据（忘记主密码时使用）
  /// 清空 secure_storage 中的所有数据
  Future<void> resetAllData() async {
    await SecureStorage.clearAll();
    state = AuthState(isInitialized: false, isUnlocked: false);
  }
}

/// 提供给外部使用的 Provider
final authProvider = StateNotifierProvider<AuthProvider, AuthState>((ref) {
  return AuthProvider();
});
