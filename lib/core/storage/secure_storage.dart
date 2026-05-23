import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStorage {
  // 创建单例实例
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      // Android 使用加密 SharedPreferences
    ),
  );

  // 存储字符串
  static Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  // 读取字符串，如果不存在返回 null
  static Future<String?> read(String key) async {
    return await _storage.read(key: key);
  }

  // 删除指定 key 的数据
  static Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }

  // 检查 key 是否存在
  static Future<bool> containsKey(String key) async {
    final value = await _storage.read(key: key);
    return value != null;
  }

  // 清空所有存储的数据
  static Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
