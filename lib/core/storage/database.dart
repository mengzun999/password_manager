import 'package:password_manager/constants/app_constants.dart';
import 'package:password_manager/core/models/password_entry.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

// 数据库操作类（单例模式）
// 负责创建数据库、建表、增删改查
class DatabaseHelper {
  // 数据库实例（静态变量，全局唯一）
  static Database? _database;

  // 获取数据库实例
  // 如果已存在则直接返回，否则创建新实例
  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // 初始化数据库
  // 1. 获取应用文档目录路径
  // 2. 拼接数据库文件完整路径
  // 3. 打开数据库（如不存在则创建）
  static Future<Database> _initDatabase() async {
    // 获取应用文档目录（Android: /data/data/包名/files）
    final documentsDir = await getApplicationDocumentsDirectory();
    // 拼接数据库文件完整路径
    final path = join(documentsDir.path, AppConstants.databaseFileName);

    // 打开数据库，如果不存在则创建
    return await openDatabase(
      path,
      version: AppConstants.databaseVersion,
      onCreate: _onCreate, // 首次创建时调用建表
    );
  }

  // 首次创建数据库时调用
  // 创建所有需要的表
  static Future<void> _onCreate(Database db, int version) async {
    // 创建密码条目表
    await db.execute('''
      CREATE TABLE entries (
        id TEXT PRIMARY KEY,           -- 唯一标识（UUID）
        title TEXT NOT NULL,           -- 标题
        username TEXT,                 -- 用户名
        encrypted_password TEXT,       -- 加密后的密码
        notes TEXT,                    -- 备注
        app_package_name TEXT,         -- 关联的应用包名
        created_at INTEGER NOT NULL,   -- 创建时间戳
        updated_at INTEGER NOT NULL    -- 更新时间戳
      )
    ''');

    // 创建图片表（为后期图片功能预留）
    await db.execute('''
      CREATE TABLE images (
        id TEXT PRIMARY KEY,                   -- 图片唯一标识
        entry_id TEXT NOT NULL,                -- 关联的密码条目ID
        filename TEXT NOT NULL,                -- 加密后的文件名
        thumbnail_filename TEXT,               -- 缩略图文件名
        file_size INTEGER,                     -- 文件大小（字节）
        mime_type TEXT,                        -- 图片类型（image/jpeg等）
        sort_order INTEGER DEFAULT 0,          -- 显示顺序
        created_at INTEGER NOT NULL,            -- 创建时间戳
        FOREIGN KEY (entry_id) REFERENCES entries (id) ON DELETE CASCADE
      )
    ''');
  }

  // 插入一条密码记录
  // [entry] 要插入的密码条目对象
  static Future<void> insertEntry(PasswordEntry entry) async {
    final db = await database;
    await db.insert('entries', entry.toMap());
  }

  // 更新一条密码记录
  // [entry] 要更新的密码条目对象（根据id更新）
  static Future<void> updateEntry(PasswordEntry entry) async {
    final db = await database;
    await db.update(
      'entries',
      entry.toMap(),
      where: 'id = ?',
      whereArgs: [entry.id],
    );
  }

  // 删除一条密码记录
  // [id] 要删除的密码条目ID
  static Future<void> deleteEntry(String id) async {
    final db = await database;
    await db.delete(
      'entries',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // 获取所有密码记录
  // 返回列表，按更新时间倒序（最新的在前面）
  static Future<List<PasswordEntry>> getAllEntries() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'entries',
      orderBy: 'updated_at DESC', // 倒序：最新的在前
    );
    return maps.map((map) => PasswordEntry.fromMap(map)).toList();
  }

  // 根据ID查询单条密码记录
  // [id] 要查询的密码条目ID
  // 返回密码条目对象，如果不存在返回null
  static Future<PasswordEntry?> getEntryById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'entries',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return PasswordEntry.fromMap(maps.first);
    }
    return null;
  }

  // 搜索密码记录
  // [keyword] 搜索关键词
  // 在标题、用户名、备注中模糊匹配，按更新时间倒序
  static Future<List<PasswordEntry>> searchEntries(String keyword) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'entries',
      where: 'title LIKE ? OR username LIKE ? OR notes LIKE ?',
      whereArgs: ['%$keyword%', '%$keyword%', '%$keyword%'],
      orderBy: 'updated_at DESC',
    );
    return maps.map((map) => PasswordEntry.fromMap(map)).toList();
  }

  // 清空所有数据（重置App时使用）
  // 1. 删除数据库中的所有记录
  // 2. 删除图片文件夹
  static Future<void> clearAllData() async {
    final db = await database;
    // 删除所有密码记录（图片表会因为外键级联自动清空）
    await db.delete('entries');

    // 删除图片文件夹
    final documentsDir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory(join(documentsDir.path, 'images'));
    if (await imagesDir.exists()) {
      await imagesDir.delete(recursive: true);
    }
  }
}