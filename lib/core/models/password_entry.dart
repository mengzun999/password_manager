class PasswordEntry {
  final String id; // 唯一标识（UUID）
  final String title; // 标题（必填，用户手动输入）
  final String? username; // 用户名（可选）
  final String? encryptedPassword; // 加密后的密码（可选）
  final String? notes; // 备注（可选）
  final String? appPackageName; // 关联的应用包名（用于显示图标）
  final int createdAt; // 创建时间戳
  final int updatedAt; // 更新时间戳

  PasswordEntry({
    required this.id,
    required this.title,
    this.username,
    this.encryptedPassword,
    this.notes,
    this.appPackageName,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 转换成 Map，用于插入数据库
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'username': username,
      'encrypted_password': encryptedPassword,
      'notes': notes,
      'app_package_name': appPackageName,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  /// 从 Map 创建 PasswordEntry 对象
  factory PasswordEntry.fromMap(Map<String, dynamic> map) {
    return PasswordEntry(
      id: map['id'],
      title: map['title'],
      username: map['username'],
      encryptedPassword: map['encrypted_password'],
      notes: map['notes'],
      appPackageName: map['app_package_name'],
      createdAt: map['created_at'],
      updatedAt: map['updated_at'],
    );
  }

  /// 复制并修改部分字段
  //比如你要修改一条密码的标题，可以用这个方法创建一个新的对象，只改标题，其他字段复制原来的。
  PasswordEntry copyWith({
    String? id,
    String? title,
    String? username,
    String? encryptedPassword,
    String? notes,
    String? appPackageName,
    int? createdAt,
    int? updatedAt,
  }) {
    return PasswordEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      username: username ?? this.username,
      encryptedPassword: encryptedPassword ?? this.encryptedPassword,
      notes: notes ?? this.notes,
      appPackageName: appPackageName ?? this.appPackageName,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
