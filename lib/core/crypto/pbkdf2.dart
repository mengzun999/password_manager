import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:password_manager/constants/app_constants.dart';
import 'package:pointycastle/export.dart';

class PBKDF2Helper {
  // 将密码和盐派生出32字节密钥
  static Uint8List deriveKey(String password, Uint8List salt) {
    // 1. 创建 PBKDF2 派生器，使用 SHA256 哈希算法
    final pbkdf2 = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(
        Pbkdf2Parameters(
          salt,
          AppConstants.pbkdf2Iterations,
          AppConstants.pbkdf2KeyLength,
        ),
      );
    // 2. 把密码字符串转成字节数组
    final passwordBytes = Uint8List.fromList(utf8.encode(password));
    // 3. 派生密钥
    final key = Uint8List.fromList(pbkdf2.process(passwordBytes) as List<int>);

    return key;
  }
  // ✅ 新增：用于 isolate 的包装方法
  static Future<Uint8List> deriveKeyIsolate(String password, Uint8List salt) {
    return compute(_deriveKeyInIsolate, _DeriveKeyParams(password, salt));
  }
  // 必须是顶层函数或静态方法，不能是闭包
  static Uint8List _deriveKeyInIsolate(_DeriveKeyParams params) {
    return deriveKey(params.password, params.salt);
  }

  // 生成密码的哈希值（用于存储和验证）
  static String hashPassword(String password, Uint8List salt) {
    final key = deriveKey(password, salt);
    return base64Encode(key);
  }

  //验证密码是否正确
  static bool verifyPassword(
    String password,
    Uint8List salt,
    String storedHash,
  ) {
    final hash = hashPassword(password, salt);
    return hash == storedHash;
  }
}
// ✅ 新增：参数传递类（必须可序列化）
class _DeriveKeyParams {
  final String password;
  final Uint8List salt;

  _DeriveKeyParams(this.password, this.salt);
}
