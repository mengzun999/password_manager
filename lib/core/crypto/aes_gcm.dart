import 'dart:convert';
import 'dart:typed_data';
import 'package:password_manager/constants/app_constants.dart';
import 'package:password_manager/core/crypto/random.dart';
import 'package:pointycastle/export.dart' hide SecureRandom;

/// AES-256-GCM 加密辅助类
///
/// 提供字符串和字节数组的加密/解密功能
/// GCM模式提供认证加密（Authenticated Encryption），同时保证机密性和完整性
/// 每次加密自动生成随机IV，IV与密文组合存储，无需单独管理
class AESGCMHelper {
  /// 加密字符串，返回 Base64 格式的密文（包含 IV）
  ///
  /// [plainText] 要加密的明文字符串
  /// [key] 32字节的AES-256密钥
  /// 返回 Base64编码的字符串，格式为：Base64(IV + 密文)
  static Future<String> encrypt(String plainText, Uint8List key) async {
    // 将明文字符串转为UTF-8字节数组
    final plainBytes = Uint8List.fromList(utf8.encode(plainText));

    // 调用字节数组加密方法
    final encryptedBytes = await encryptBytes(plainBytes, key);

    // 将IV+密文的组合字节数组转为Base64字符串，便于存储和传输
    return base64Encode(encryptedBytes);
  }

  /// 解密字符串，返回明文
  ///
  /// [cipherTextBase64] Base64编码的密文（包含IV）
  /// [key] 32字节的AES-256密钥
  /// 返回解密后的明文字符串
  static Future<String> decrypt(String cipherTextBase64, Uint8List key) async {
    // Base64解码，得到IV+密文的组合字节数组
    final combined = base64Decode(cipherTextBase64);

    // 调用字节数组解密方法
    final plainBytes = await decryptBytes(combined, key);

    // 将UTF-8字节数组转回字符串
    return utf8.decode(plainBytes);
  }

  /// 加密字节数组，返回加密后的字节数组（包含 IV）
  ///
  /// [plainBytes] 要加密的明文字节数组
  /// [key] 32字节的AES-256密钥
  /// 返回字节数组，格式为：[IV(12字节)] + [密文(包含16字节认证标签)]
  static Future<Uint8List> encryptBytes(Uint8List plainBytes, Uint8List key) async {
    // 1. 生成随机IV（Initialization Vector）
    // GCM模式推荐使用12字节的IV
    final iv = SecureRandom.generateBytes(AppConstants.ivLength);

    // 2. 初始化GCM加密器
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        true, // true表示加密模式
        AEADParameters(
          KeyParameter(key), // AES密钥
          128,               // MAC大小（位），128位=16字节认证标签
          iv,                // 初始化向量
          Uint8List(0),      // 附加认证数据（AAD），本场景不需要
        ),
      );

    // 3. 创建临时缓冲区
    // getOutputSize() 返回加密后可能的最大字节数（包含认证标签）
    final tempBuffer = Uint8List(cipher.getOutputSize(plainBytes.length));

    // 4. 执行加密
    // processBytes() 处理大部分数据，返回写入缓冲区的字节数
    final processedLen = cipher.processBytes(
      plainBytes,  // 输入数据
      0,           // 输入起始位置
      plainBytes.length, // 输入长度
      tempBuffer,  // 输出缓冲区
      0,           // 输出起始位置
    );

    // 5. 完成加密，处理剩余数据并生成认证标签
    // doFinal() 返回写入缓冲区的字节数（通常是认证标签的长度）
    final finalLen = cipher.doFinal(tempBuffer, processedLen);

    // 6. 提取实际密文（只取有效的字节，丢弃缓冲区末尾未使用的空间）
    final actualCipherLen = processedLen + finalLen;
    final cipherText = Uint8List(actualCipherLen);
    cipherText.setAll(0, tempBuffer.sublist(0, actualCipherLen));

    // 7. 组合：IV + 密文
    // 这样存储后，解密时只需从开头取出IV即可
    final combined = Uint8List(iv.length + cipherText.length);
    combined.setAll(0, iv);                     // 前12字节放IV
    combined.setAll(iv.length, cipherText);     // 后面放密文

    return combined;
  }

  /// 解密字节数组，返回原始字节
  ///
  /// [combinedBytes] IV+密文的组合字节数组，格式与encryptBytes返回值一致
  /// [key] 32字节的AES-256密钥
  /// 返回解密后的明文字节数组
  static Future<Uint8List> decryptBytes(Uint8List combinedBytes, Uint8List key) async {
    // 1. 提取IV（前12字节）
    final iv = combinedBytes.sublist(0, AppConstants.ivLength);

    // 2. 提取密文（剩余部分）
    final cipherText = combinedBytes.sublist(AppConstants.ivLength);

    // 3. 初始化GCM解密器
    final cipher = GCMBlockCipher(AESEngine())
      ..init(
        false, // false表示解密模式
        AEADParameters(
          KeyParameter(key),
          128,
          iv,
          Uint8List(0),
        ),
      );

    // 4. 创建临时缓冲区
    // getOutputSize() 返回解密后可能的最大字节数
    final tempBuffer = Uint8List(cipher.getOutputSize(cipherText.length));

    // 5. 执行解密
    // processBytes() 处理大部分数据，返回写入缓冲区的字节数
    final processedLen = cipher.processBytes(
      cipherText,
      0,
      cipherText.length,
      tempBuffer,
      0,
    );

    // 6. 完成解密，验证认证标签
    // doFinal() 处理剩余数据并验证GCM认证标签
    // 如果认证失败（数据被篡改或密钥错误），会抛出异常
    final finalLen = cipher.doFinal(tempBuffer, processedLen);

    // 7. 提取实际明文（只取有效的字节）
    final actualPlainLen = processedLen + finalLen;
    return tempBuffer.sublist(0, actualPlainLen);
  }
}

