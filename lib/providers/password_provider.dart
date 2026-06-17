import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/core/crypto/aes_gcm.dart';
import 'package:password_manager/core/models/password_entry.dart';
import 'package:password_manager/core/storage/database.dart';

/// 密码列表状态
class PasswordState {
  /// 密码条目列表（密码字段是加密的）
  final List<PasswordEntry> entries;

  /// 是否正在加载
  final bool isLoading;

  /// 错误信息
  final String? error;

  /// 搜索关键词
  final String searchKeyword;

  const PasswordState({
    this.entries = const [],
    this.isLoading = false,
    this.error,
    this.searchKeyword = '',
  });

  PasswordState copyWith({
    List<PasswordEntry>? entries,
    bool? isLoading,
    String? error,
    String? searchKeyword,
  }) {
    return PasswordState(
      entries: entries ?? this.entries,
      isLoading: isLoading ?? this.isLoading,
      error: error ?? this.error,
      searchKeyword: searchKeyword ?? this.searchKeyword,
    );
  }

  /// 获取过滤后的条目列表（根据搜索关键词过滤）
  /// 注意：这里只过滤标题、用户名、备注，不过滤密码内容
  List<PasswordEntry> get filteredEntries {
    if (searchKeyword.isEmpty) return entries;

    final keyword = searchKeyword.toLowerCase();
    return entries.where((entry) {
      return entry.title.toLowerCase().contains(keyword) ||
          (entry.username?.toLowerCase().contains(keyword) ?? false) ||
          (entry.notes?.toLowerCase().contains(keyword) ?? false);
    }).toList();
  }
}

/// 密码列表状态提供者
final passwordProvider = NotifierProvider<PasswordNotifier, PasswordState>(() {
  return PasswordNotifier();
});

/// 密码列表提供者（管理密码条目的增删改查）
class PasswordNotifier extends Notifier<PasswordState> {
  @override
  PasswordState build() {
    return const PasswordState();
  }

  /// 加载所有密码条目
  Future<void> loadEntries() async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final entries = await DatabaseHelper.getAllEntries();
      state = state.copyWith(entries: entries, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: '加载失败: $e',
      );
    }
  }

  /// 搜索（只改变关键词，过滤在 getter 中自动完成）
  void search(String keyword) {
    state = state.copyWith(searchKeyword: keyword);
  }

  /// 清空搜索
  void clearSearch() {
    state = state.copyWith(searchKeyword: '');
  }

  /// 添加密码条目
  Future<void> addEntry(PasswordEntry entry) async {
    await DatabaseHelper.insertEntry(entry);
    await loadEntries();  // 刷新列表
  }

  /// 更新密码条目
  Future<void> updateEntry(PasswordEntry entry) async {
    await DatabaseHelper.updateEntry(entry);
    await loadEntries();  // 刷新列表
  }

  /// 删除密码条目
  Future<void> deleteEntry(String id) async {
    await DatabaseHelper.deleteEntry(id);
    await loadEntries();  // 刷新列表
  }

  /// 刷新列表
  Future<void> refresh() async {
    await loadEntries();
  }
}

/// 密码解密辅助方法（供 UI 层使用）
/// 不放在 State 中是因为 masterKey 来自 authProvider
/// 使用方式：在 Widget 中调用 PasswordHelper.decryptPassword(entry, masterKey)
class PasswordHelper {
  /// 解密单个密码
  /// [entry] 密码条目（包含加密的密码）
  /// [masterKey] 主密钥（从 authProvider 获取）
  /// 返回解密后的密码明文，解密失败返回 null
  static Future<String?> decryptPassword(
      PasswordEntry entry,
      Uint8List masterKey,
      ) async {
    if (entry.encryptedPassword == null) return null;
    try {
      return await AESGCMHelper.decrypt(entry.encryptedPassword!, masterKey);
    } catch (e) {
      return null;
    }
  }

  /// 批量解密密码（使用并发执行，提升性能）
  /// 建议只在需要时使用，避免解密大量数据
  static Future<Map<String, String?>> batchDecrypt(
      List<PasswordEntry> entries,
      Uint8List masterKey,
      ) async {
    // 过滤出有加密密码的条目
    final entriesWithPassword = entries.where((e) => e.encryptedPassword != null).toList();

    if (entriesWithPassword.isEmpty) {
      return {};
    }

    // ✅ 使用 Future.wait 并发执行所有解密
    final results = await Future.wait(
      entriesWithPassword.map((entry) async {
        try {
          final plainText = await AESGCMHelper.decrypt(
            entry.encryptedPassword!,
            masterKey,
          );
          return MapEntry(entry.id, plainText);
        } catch (e) {
          return MapEntry(entry.id, null);
        }
      }),
    );

    // 将结果转换为 Map
    return Map.fromEntries(results);
  }
}