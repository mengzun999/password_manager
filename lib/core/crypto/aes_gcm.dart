import 'dart:convert';
import 'dart:typed_data';
import 'package:password_manager/constants/app_constants.dart';
import 'package:password_manager/core/crypto/random.dart';
import 'package:pointycastle/export.dart' hide SecureRandom;

class AESGCMHelper {
  // 加密字符串，返回 Base64 格式的密文（包含 IV）
  static Future<String> encrypt(String plainText, Uint8List key) async {
    // 1. 把明文转成字节
    final plainBytes = Uint8List.fromList(utf8.encode(plainText));

    // 2. 生成随机 IV（12字节）
    final iv = SecureRandom.generateBytes(AppConstants.ivLength);

    // 3. 创建加密器
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));

    // 4. 执行加密
    final cipherText = Uint8List(cipher.getOutputSize(plainBytes.length));
    final len = cipher.processBytes(
      plainBytes,
      0,
      plainBytes.length,
      cipherText,
      0,
    );
    cipher.doFinal(cipherText, len);

    // 5. 组合：IV + 密文，然后转 Base64
    final combined = Uint8List(iv.length + cipherText.length);
    combined.setAll(0, iv);
    combined.setAll(iv.length, cipherText);

    return base64Encode(combined);
  }

  // 解密字符串，返回明文
  static Future<String> decrypt(String cipherTextBase64, Uint8List key) async {
    // 1. Base64 解码
    final combined = base64Decode(cipherTextBase64);

    // 2. 提取 IV（前12字节）和密文（剩余部分）
    final iv = combined.sublist(0, AppConstants.ivLength);
    final cipherText = combined.sublist(AppConstants.ivLength);

    // 3. 创建解密器
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));

    // 4. 执行解密
    final plainBytes = Uint8List(cipher.getOutputSize(cipherText.length));
    final len = cipher.processBytes(
      cipherText,
      0,
      cipherText.length,
      plainBytes,
      0,
    );
    final finalLen = cipher.doFinal(plainBytes, len);

    // 5. 截取有效部分并转成字符串
    final result = plainBytes.sublist(0, len + finalLen);
    return utf8.decode(result);
  }

  //加密字节数组，返回加密后的字节数组（包含 IV）
  static Future<Uint8List> encryptBytes(Uint8List plainBytes, Uint8List key) async {
    final iv = SecureRandom.generateBytes(AppConstants.ivLength);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));
    final cipherText = Uint8List(cipher.getOutputSize(plainBytes.length));
    final len = cipher.processBytes(
      plainBytes,
      0,
      plainBytes.length,
      cipherText,
      0,
    );
    cipher.doFinal(cipherText, len);
    final combined = Uint8List(iv.length + cipherText.length);
    combined.setAll(0, iv);
    combined.setAll(iv.length, cipherText);
    return combined;
  }

  /// 解密字节数组，返回原始字节
  static Future<Uint8List> decryptBytes(Uint8List combinedBytes, Uint8List key) async {
    final iv = combinedBytes.sublist(0, AppConstants.ivLength);
    final cipherText = combinedBytes.sublist(AppConstants.ivLength);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, iv, Uint8List(0)));

    final plainBytes = Uint8List(cipher.getOutputSize(cipherText.length));
    final len = cipher.processBytes(cipherText, 0, cipherText.length, plainBytes, 0);
    final finalLen = cipher.doFinal(plainBytes, len);

    return plainBytes.sublist(0, len + finalLen);
  }
}
