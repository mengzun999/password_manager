import 'dart:convert';
import 'dart:typed_data';
import 'package:password_manager/constants/app_constants.dart';
import 'package:password_manager/core/crypto/random.dart';
import 'package:pointycastle/export.dart' hide SecureRandom;

/// AES-256-GCM 加密辅助类
class AESGCMHelper {
  /// 加密字符串，返回 Base64 格式的密文（包含 IV）
  static Future<String> encrypt(String plainText, Uint8List key) async {
    final plainBytes = Uint8List.fromList(utf8.encode(plainText));
    final encryptedBytes = await encryptBytes(plainBytes, key);
    return base64Encode(encryptedBytes);
  }

  /// 解密字符串，返回明文
  static Future<String> decrypt(String cipherTextBase64, Uint8List key) async {
    final combined = base64Decode(cipherTextBase64);
    final plainBytes = await decryptBytes(combined, key);
    return utf8.decode(plainBytes);
  }

  /// 加密字节数组，返回加密后的字节数组（包含 IV）
  static Future<Uint8List> encryptBytes(Uint8List plainBytes, Uint8List key) async {
    final iv = SecureRandom.generateBytes(AppConstants.ivLength);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(key),
          128,
          iv,
          Uint8List(0),
        ),
      );

    final tempBuffer = Uint8List(cipher.getOutputSize(plainBytes.length));
    final processedLen = cipher.processBytes(
      plainBytes,
      0,
      plainBytes.length,
      tempBuffer,
      0,
    );
    final finalLen = cipher.doFinal(tempBuffer, processedLen);

    final actualCipherLen = processedLen + finalLen;
    final cipherText = Uint8List(actualCipherLen);
    cipherText.setAll(0, tempBuffer.sublist(0, actualCipherLen));

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
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          128,
          iv,
          Uint8List(0),
        ),
      );

    final tempBuffer = Uint8List(cipher.getOutputSize(cipherText.length));
    final processedLen = cipher.processBytes(
      cipherText,
      0,
      cipherText.length,
      tempBuffer,
      0,
    );
    final finalLen = cipher.doFinal(tempBuffer, processedLen);

    final actualPlainLen = processedLen + finalLen;
    return tempBuffer.sublist(0, actualPlainLen);
  }

  // ========== ✅ 同步方法（供 isolate 使用） ==========

  /// 同步加密字节数组（供 isolate 使用）
  static Uint8List encryptBytesSync(Uint8List plainBytes, Uint8List key) {
    final iv = SecureRandom.generateBytes(AppConstants.ivLength);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true,
        AEADParameters(
          KeyParameter(key),
          128,
          iv,
          Uint8List(0),
        ),
      );

    final tempBuffer = Uint8List(cipher.getOutputSize(plainBytes.length));
    final processedLen = cipher.processBytes(
      plainBytes,
      0,
      plainBytes.length,
      tempBuffer,
      0,
    );
    final finalLen = cipher.doFinal(tempBuffer, processedLen);

    final actualCipherLen = processedLen + finalLen;
    final cipherText = Uint8List(actualCipherLen);
    cipherText.setAll(0, tempBuffer.sublist(0, actualCipherLen));

    final combined = Uint8List(iv.length + cipherText.length);
    combined.setAll(0, iv);
    combined.setAll(iv.length, cipherText);

    return combined;
  }

  /// 同步解密字节数组（供 isolate 使用）
  static Uint8List decryptBytesSync(Uint8List combinedBytes, Uint8List key) {
    final iv = combinedBytes.sublist(0, AppConstants.ivLength);
    final cipherText = combinedBytes.sublist(AppConstants.ivLength);

    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false,
        AEADParameters(
          KeyParameter(key),
          128,
          iv,
          Uint8List(0),
        ),
      );

    final tempBuffer = Uint8List(cipher.getOutputSize(cipherText.length));
    final processedLen = cipher.processBytes(
      cipherText,
      0,
      cipherText.length,
      tempBuffer,
      0,
    );
    final finalLen = cipher.doFinal(tempBuffer, processedLen);

    final actualPlainLen = processedLen + finalLen;
    return tempBuffer.sublist(0, actualPlainLen);
  }
}