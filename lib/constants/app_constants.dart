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

  // 助记词
  static const int mnemonicWordCount = 24;

  // 自动锁定选项（分钟）
  static const List<int> autoLockOptions = [0, 1, 5, 15, 30];

  // 图片相关
  static const int maxImageCountPerEntry = 20; // 每条密码最多能添加多少张图片
  static const int thumbnailWidth = 200; // 缩略图的宽度（像素）
  static const int thumbnailHeight = 200; // 缩略图的高度（像素）
  static const int thumbnailQuality = 80; // 缩略图质量（0-100，80是质量和体积的平衡点）

  // ========== SharedPreferences 键名 ==========
  // 是否首次启动（第一次打开App时用）
  static const String keyIsFirstLaunch = 'is_first_launch';

  // 暗黑模式开关（true=暗黑模式，false=亮色模式）
  static const String keyDarkMode = 'dark_mode';

  // 应用列表视图模式（'grid'=网格视图，'list'=列表视图）
  static const String keyAppListViewMode = 'app_list_view_mode';

  // 生物识别开关（true=启用指纹/人脸解锁）
  static const String keyBiometricEnabled = 'biometric_enabled';

  // 自动锁定时间（存储用户选择的分钟数）
  static const String keyAutoLockMinutes = 'auto_lock_minutes';

  // 是否设置过手势图案
  static const String keyHasGesture = 'has_gesture';

  // ========== 管理员密码（硬编码）==========
  // 你自己定一个记得住但不容易猜的密码
  // 在解锁页快速按音量减键3次后输入这个密码，可以直接重置主密码
  static const String adminPassword = 'MyAdminReset2024';

  // ========== flutter_secure_storage 键名 ==========
  // Salt（密钥派生用的随机数）
  static const String keySalt = 'crypto_salt';

  // 主密码的哈希值（用于验证主密码是否正确，不存原密码）
  static const String keyMasterPasswordHash = 'master_password_hash';

  // 助记词的哈希值（用于验证助记词是否正确）
  static const String keyMnemonicHash = 'mnemonic_hash';

  // 手势图案的哈希值（用于验证手势是否正确）
  static const String keyGestureHash = 'gesture_hash';
}
