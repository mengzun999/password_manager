import 'dart:math'; // 用于 Random 随机数
import 'dart:convert'; // 用于 base64 编解码

class Helpers {
  static String generateUuid() {
    // 1. 创建安全随机数生成器
    final random = Random.secure();
    // 2. 生成16字节（128位）的随机数
    final bytes = List.generate(16, (_) => random.nextInt(256));
    // 3. 设置版本位（version 4 的标识）
    //    bytes[6] 的第4位设为 0100（代表版本4）
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    // 4. 设置变体位（variant 1 的标识）
    //    bytes[8] 的前两位设为 10
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    // 5. 转换成十六进制字符串，按 8-4-4-4-12 的格式加连字符
    // 这里简化：先转成十六进制，再插入连字符
    String hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    // 插入连字符：8-4-4-4-12
    if (hex.length >= 32) {
      return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
    } else {
      return ''; // 实际不会执行，但 Dart 需要
    }
  }

  // 获取当前时间戳（毫秒）
  static int currentTimestamp() {
    return DateTime.now().millisecondsSinceEpoch;
  }

  // 格式化日期：2024-01-15
  static String formatDate(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final year = date.year;
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  // Base64 编码
  static String base64EncodeBytes(List<int> bytes) {
    return base64.encode(bytes);
  }

  // Base64 解码
  static List<int> base64DecodeBytes(String base64String) {
    return base64.decode(base64String);
  }
}
