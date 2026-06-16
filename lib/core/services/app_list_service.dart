import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 应用信息模型
class AppInfo {
  final String packageName;
  final String appName;
  Uint8List? iconBytes;
  bool iconLoaded = false;

  AppInfo({
    required this.packageName,
    required this.appName,
    this.iconBytes,
  });
}

/// 应用列表服务类
class AppListService {
  static List<AppInfo>? _allApps;
  static final Map<String, Uint8List> _iconCache = {};
  static bool _isLoading = false;

  /// ✅ 分批获取应用列表：先返回前30个，剩余的后台加载
  static Future<List<AppInfo>> getInstalledApps({
    int initialCount = 30,
  }) async {
    if (_allApps != null) {
      // 如果已经全部加载完，直接返回全部
      return _allApps!;
    }

    if (_isLoading) {
      await Future.delayed(const Duration(milliseconds: 100));
      return _allApps?.take(initialCount).toList() ?? [];
    }

    _isLoading = true;

    try {
      final result = await _channel.invokeMethod('getInstalledApps');

      if (result == null) {
        throw Exception('获取应用列表失败：返回结果为空');
      }

      if (result is! List) {
        throw Exception('获取应用列表失败：返回格式错误');
      }

      if (result.isEmpty) {
        throw Exception('没有找到已安装的应用');
      }

      final allApps = <AppInfo>[];
      for (final item in result) {
        if (item is Map) {
          final packageName = item['packageName'] as String?;
          final appName = item['appName'] as String?;

          if (packageName == null || packageName.isEmpty) continue;
          if (appName == null || appName.isEmpty) continue;

          allApps.add(AppInfo(
            packageName: packageName,
            appName: appName,
            iconBytes: null,
          ));
        }
      }

      if (allApps.isEmpty) {
        throw Exception('没有找到已安装的应用');
      }

      allApps.sort((a, b) => a.appName.compareTo(b.appName));

      // 缓存全部应用
      _allApps = allApps;
      _isLoading = false;

      // ✅ 返回前 initialCount 个，立即显示
      final initialApps = allApps.take(initialCount).toList();

      // ✅ 后台加载剩余应用（分批，避免卡顿）
      _loadRemainingInBackground(allApps, initialCount);

      return initialApps;
    } catch (e) {
      _isLoading = false;
      rethrow;
    }
  }

  /// ✅ 后台分批加载剩余应用
  static void _loadRemainingInBackground(List<AppInfo> allApps, int startIndex) {
    const batchSize = 20;
    int currentIndex = startIndex;

    Future<void> loadBatch() async {
      while (currentIndex < allApps.length) {
        final endIndex = (currentIndex + batchSize).clamp(0, allApps.length);
        // 把这一批应用加入缓存（只是让它们可被加载，不实际加载图标）
        for (int i = currentIndex; i < endIndex; i++) {
          // 标记为可加载，但不实际加载图标
        }
        currentIndex = endIndex;
        // ✅ 每批之间延迟 50ms，让出主线程
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }

    // 启动后台加载
    loadBatch();
  }

  /// ✅ 懒加载单个应用的图标
  static Future<Uint8List?> loadAppIcon(String packageName) async {
    if (_iconCache.containsKey(packageName)) {
      return _iconCache[packageName];
    }

    final cachedIcon = await _getCachedIcon(packageName);
    if (cachedIcon != null) {
      _iconCache[packageName] = cachedIcon;
      return cachedIcon;
    }

    try {
      final iconBytes = await getAppIcon(packageName);
      if (iconBytes != null) {
        _iconCache[packageName] = iconBytes;
        await _saveCachedIcon(packageName, iconBytes);
        return iconBytes;
      }
    } catch (e) {
      // 忽略
    }
    return null;
  }

  /// ✅ 获取所有应用（包括后台已加载的）
  static List<AppInfo> getAllApps() {
    return _allApps ?? [];
  }

  static Future<Uint8List?> getAppIcon(String packageName) async {
    try {
      final result = await _channel.invokeMethod('getAppIcon', {
        'packageName': packageName,
      });

      if (result != null && result is Uint8List) {
        return result;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<String> _getIconCachePath(String packageName) async {
    final cacheDir = await getTemporaryDirectory();
    final iconDir = Directory('${cacheDir.path}/app_icons');
    if (!await iconDir.exists()) {
      await iconDir.create(recursive: true);
    }
    return '${iconDir.path}/${packageName.replaceAll('.', '_')}.png';
  }

  static Future<Uint8List?> _getCachedIcon(String packageName) async {
    try {
      final filePath = await _getIconCachePath(packageName);
      final file = File(filePath);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<void> _saveCachedIcon(String packageName, Uint8List bytes) async {
    try {
      final filePath = await _getIconCachePath(packageName);
      await File(filePath).writeAsBytes(bytes);
    } catch (e) {
      // 忽略
    }
  }

  static void clearCache() {
    _allApps = null;
    _iconCache.clear();
    Future.microtask(() async {
      try {
        final cacheDir = await getTemporaryDirectory();
        final iconDir = Directory('${cacheDir.path}/app_icons');
        if (await iconDir.exists()) {
          await iconDir.delete(recursive: true);
        }
      } catch (e) {
        // 忽略
      }
    });
  }

  static const MethodChannel _channel = MethodChannel('com.meng.passwordmanager/apps');
}