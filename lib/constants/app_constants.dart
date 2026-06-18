class AppConstants {
  //应用名称
  static const String appName = '密码管理器';

  //包名
  static const String packageName = 'com.meng.passwordmanager';

  //数据库文件名
  static const String databaseFileName = 'password_manager.db';

  //数据库版本号
  static const int databaseVersion = 1;

  // PBKDF2 迭代次数：20万次（越高越安全，但越慢）
  static const int pbkdf2Iterations = 200000;

  // 派生出的密钥长度：32字节 = 256位
  static const int pbkdf2KeyLength = 32;

  // Salt 长度：16字节（随机值，用于防止彩虹表攻击）
  static const int saltLength = 16;

  // IV 长度：12字节（GCM模式推荐值）
  static const int ivLength = 12;



  // 图片相关
  static const int maxImageCountPerEntry = 20; // 每条密码最多能添加多少张图片
  static const int thumbnailWidth = 200; // 缩略图的宽度（像素）
  static const int thumbnailHeight = 200; // 缩略图的高度（像素）
  static const int thumbnailQuality = 80; // 缩略图质量（0-100，80是质量和体积的平衡点）

  // ========== SharedPreferences 键名 ==========
  // 是否首次启动（第一次打开App时用）
  static const String keyIsFirstLaunch = 'is_first_launch';

  // 暗黑模式开关（true=暗黑模式，false=亮色模式）
  // ========== SharedPreferences 键名 ==========
  static const String keyDarkMode = 'dark_mode';
  static const String keyDarkModeFollowSystem = 'dark_mode_follow_system';  // ✅ 新增


  // 生物识别开关（true=启用指纹/人脸解锁）
  static const String keyBiometricEnabled = 'biometric_enabled';


  // 是否设置过手势图案
  static const String keyHasGesture = 'has_gesture';

  // ========== flutter_secure_storage 键名 ==========
  // Salt（密钥派生用的随机数）
  static const String keySalt = 'crypto_salt';

  // 主密码的哈希值（用于验证主密码是否正确，不存原密码）
  static const String keyMasterPasswordHash = 'master_password_hash';

  // 助记词的哈希值（用于验证助记词是否正确）
  static const String keyMnemonicHash = 'mnemonic_hash';

  // 手势图案的哈希值（用于验证手势是否正确）
  static const String keyGestureHash = 'gesture_hash';

  // 加密存储的 masterKey（用于手势）
  static const String keyEncryptedMasterKeyForGesture =
      'encrypted_master_key_for_gesture';

  // 生物识别密钥标识符
  static const String keyBiometricKeyId = 'biometric_key_id';

  // 加密存储的 masterKey（用于生物识别）
  static const String keyEncryptedMasterKeyForBiometric =
      'encrypted_master_key_for_biometric';

  // 加密存储的 masterKey（用于恢复密钥）
  static const String keyEncryptedMasterKeyForRecovery =
      'encrypted_master_key_for_recovery';
  // ========== 背景图相关 SharedPreferences 键名 ==========
  static const String keyBackgroundImagePath = 'background_image_path';  // 背景图本地路径
  static const String keyBackgroundOpacity = 'background_opacity';      // 卡片透明度 (0-100)
  static const String keyBackgroundBlur = 'background_blur';            // 背景模糊度 (0-30)
  static const String keyTextColor = 'background_text_color';           // 文字颜色 (ARGB int)

  // ========== ✅ 图片压缩相关 ==========
// 压缩档位键名
  static const String keyImageCompressLevel = 'image_compress_level';

// 压缩档位值
  static const int compressLevelOriginal = 0;
  static const int compressLevelHigh = 1;
  static const int compressLevelMedium = 2;

// 各档位对应的 JPEG 质量 (0-100)
  static const int compressQualityHigh = 90;
  static const int compressQualityMedium = 75;

// 档位名称
  static const String compressLevelNameOriginal = '原图';
  static const String compressLevelNameHigh = '高';
  static const String compressLevelNameMedium = '中';

// 档位副标题
  static const String compressLevelSubtitleOriginal = '不压缩，保留原始画质';
  static const String compressLevelSubtitleHigh = 'JPEG 90%，画质几乎无损';
  static const String compressLevelSubtitleMedium = 'JPEG 75%，画质良好';
}
