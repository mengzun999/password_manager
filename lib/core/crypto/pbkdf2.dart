import 'dart:convert';
import 'dart:typed_data';
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
