import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/constants/app_constants.dart';
import 'package:password_manager/core/crypto/pbkdf2.dart';
import 'package:password_manager/core/crypto/random.dart';
import 'package:password_manager/core/storage/secure_storage.dart';
import 'package:password_manager/core/storage/database.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 认证状态
class AuthState {
  final bool isInitialized;
  final bool isUnlocked;
  final bool isLoading;  // ✅ 新增
  final String? error;
  final Uint8List? masterKey;

  const AuthState({
    required this.isInitialized,
    required this.isUnlocked,
    this.isLoading = false,  // ✅ 默认 false
    this.error,
    this.masterKey,
  });

  AuthState copyWith({
    bool? isInitialized,
    bool? isUnlocked,
    bool? isLoading,
    String? error,
    Uint8List? masterKey,
  }) {
    return AuthState(
      isInitialized: isInitialized ?? this.isInitialized,
      isUnlocked: isUnlocked ?? this.isUnlocked,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      masterKey: masterKey ?? this.masterKey,
    );
  }
}

/// 认证状态提供者
final authProvider = NotifierProvider<AuthProvider, AuthState>(() {
  return AuthProvider();
});

/// 单独提供 masterKey
final masterKeyProvider = Provider<Uint8List?>((ref) {
  return ref.watch(authProvider).masterKey;
});

/// 解锁状态提供者
final isUnlockedProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isUnlocked;
});

/// 认证提供者
class AuthProvider extends Notifier<AuthState> {
  @override
  AuthState build() {
    // ✅ 初始状态为加载中
    _checkInitializedAsync();
    return const AuthState(
      isInitialized: false,
      isUnlocked: false,
      isLoading: true,  // ✅ 加载中
      masterKey: null,
    );
  }

  /// ✅ 异步检查初始化状态
  void _checkInitializedAsync() {
    // 使用 Future.microtask 避免在 build 中执行异步操作
    Future.microtask(() => checkInitialized());
  }

  /// 检查是否已完成首次设置
  Future<void> checkInitialized() async {
    final hasSalt = await SecureStorage.containsKey(AppConstants.keySalt);
    final hasMasterHash = await SecureStorage.containsKey(
      AppConstants.keyMasterPasswordHash,
    );
    state = state.copyWith(
      isInitialized: hasSalt && hasMasterHash,
      isLoading: false,  // ✅ 加载完成
    );
  }

  /// 首次设置：创建主密码
  Future<void> setupMasterPassword(String password) async {
    final salt = SecureRandom.generateBytes(AppConstants.saltLength);
    final passwordHash = PBKDF2Helper.hashPassword(password, salt);

    await SecureStorage.write(AppConstants.keySalt, base64Encode(salt));
    await SecureStorage.write(
      AppConstants.keyMasterPasswordHash,
      passwordHash,
    );

    await checkInitialized();
  }

  /// 仅验证主密码（使用 isolate，不阻塞 UI）
  Future<bool> verifyMasterPassword(String password) async {
    final key = await verifyAndGetKey(password);
    return key != null;
  }

  /// 验证主密码并返回主密钥
  Future<Uint8List?> verifyAndGetKey(String password) async {
    final saltBase64 = await SecureStorage.read(AppConstants.keySalt);
    final storedHash = await SecureStorage.read(
      AppConstants.keyMasterPasswordHash,
    );

    if (saltBase64 == null || storedHash == null) {
      return null;
    }

    final salt = base64Decode(saltBase64);

    // 使用 isolate 计算，不阻塞 UI
    final derivedKey = await PBKDF2Helper.deriveKeyIsolate(password, salt);
    final computedHash = base64Encode(derivedKey);

    if (computedHash == storedHash) {
      return derivedKey;
    }
    return null;
  }

  /// 解锁应用
  void unlock({Uint8List? masterKey}) {
    state = state.copyWith(
      isUnlocked: true,
      error: null,
      masterKey: masterKey,
    );
  }

  /// 锁定应用
  void lock() {
    state = state.copyWith(
      isUnlocked: false,
      masterKey: null,
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

  /// 重置所有数据
  Future<void> resetAllData() async {
    // 1. 清理数据库和图片文件
    await DatabaseHelper.clearAllData();

    // 2. 清理 SecureStorage
    await SecureStorage.clearAll();

    // 3. 清理 SharedPreferences（可选，但建议）
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    // 4. 重置状态
    state = const AuthState(
      isInitialized: false,
      isUnlocked: false,
      isLoading: false,
      masterKey: null,
    );
  }

  /// 保存恢复密钥
  /// ✅ 修改：使用 Hex 格式存储哈希，与验证保持一致
  Future<void> setupRecoveryKey(String recoveryKey) async {
    final bytes = utf8.encode(recoveryKey);
    final hash = sha256.convert(bytes).toString();  // ✅ Hex
    await SecureStorage.write(AppConstants.keyMnemonicHash, hash);
  }

  /// 验证恢复密钥
  Future<bool> verifyRecoveryKey(String recoveryKey) async {
    final storedHash = await SecureStorage.read(AppConstants.keyMnemonicHash);
    if (storedHash == null) return false;

    final bytes = utf8.encode(recoveryKey);
    final hash = sha256.convert(bytes).toString();  // ✅ Hex
    return hash == storedHash;
  }
}