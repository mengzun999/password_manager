import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

class SecureRandom {
  // 生成指定长度的随机字节数组
  static Uint8List generateBytes(int length) {
    final random = Random.secure();
    final bytes = Uint8List(length);
    for (int i = 0; i < length; i++) {
      bytes[i] = random.nextInt(256);
    }
    return bytes;
  }

  //生成随机十六进制字符串
  static String generateHex(int length) {
    final bytes = generateBytes(length);
    return bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  }

  //生成随机 Base64 字符串
  static String generateBase64(int length) {
    final bytes = generateBytes(length);
    return base64.encode(bytes);
  }
}
