import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:password_manager/constants/app_constants.dart';
import 'package:pointycastle/export.dart';

/// PBKDF2 密钥派生辅助类
class PBKDF2Helper {
  /// 将密码和盐派生出指定长度的密钥（默认为 32 字节）
  static Uint8List deriveKey(String password, Uint8List salt) {
    // 1. 创建 PBKDF2 派生器，使用 HMAC-SHA256
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(
        Pbkdf2Parameters(
          salt,
          AppConstants.pbkdf2Iterations,
          AppConstants.pbkdf2KeyLength,
        ),
      );
    // 2. 将密码字符串转换为字节数组 (UTF-8)
    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    // 3. 执行密钥派生过程
    final key = Uint8List.fromList(pbkdf2.process(passwordBytes) as List<int>);

    return key;
  }

  /// 在 Isolate 中异步派生密钥，避免阻塞主线程 UI
  static Future<Uint8List> deriveKeyIsolate(String password, Uint8List salt) {
    return compute(_deriveKeyInIsolate, _DeriveKeyParams(password, salt));
  }

  /// Isolate 内部调用的静态方法
  static Uint8List _deriveKeyInIsolate(_DeriveKeyParams params) {
    return deriveKey(params.password, params.salt);
  }

  /// 生成密码的哈希值（Base64 编码，用于存储和验证）
  static String hashPassword(String password, Uint8List salt) {
    final key = deriveKey(password, salt);
    return base64Encode(key);
  }

  /// 验证提供的密码与存储的哈希值是否匹配
  static bool verifyPassword(
    String password,
    Uint8List salt,
    String storedHash,
  ) {
    final hash = hashPassword(password, salt);
    return hash == storedHash;
  }
}

/// PBKDF2 参数包装类，用于 Isolate 间的数据传递
class _DeriveKeyParams {
  final String password;
  final Uint8List salt;

  _DeriveKeyParams(this.password, this.salt);
}
