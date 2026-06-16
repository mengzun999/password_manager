import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// 应用信息模型
class AppInfo {
  final String packageName;
  final String appName;
  Uint8List? iconBytes;

  AppInfo({
    required this.packageName,
    required this.appName,
    this.iconBytes,
  });
}

/// 应用列表服务类
/// 异步加载 + 本地缓存图标
class AppListService {
  static List<AppInfo>? _cachedApps;
  static final Map<String, Uint8List> _iconCache = {};
  static bool _isLoading = false;

  /// 获取手机中所有已安装的应用（非系统应用）
  static Future<List<AppInfo>> getInstalledApps() async {
    // 如果有缓存，直接返回
    if (_cachedApps != null) {
      return _cachedApps!;
    }

    if (_isLoading) {
      // 如果正在加载，等待完成
      await Future.delayed(const Duration(milliseconds: 100));
      return _cachedApps ?? [];
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

      final apps = <AppInfo>[];
      for (final item in result) {
        if (item is Map) {
          final packageName = item['packageName'] as String?;
          final appName = item['appName'] as String?;

          if (packageName == null || packageName.isEmpty) continue;
          if (appName == null || appName.isEmpty) continue;

          // 先不加载图标，只存包名和名称
          apps.add(AppInfo(
            packageName: packageName,
            appName: appName,
            iconBytes: null,
          ));
        }
      }

      if (apps.isEmpty) {
        throw Exception('没有找到已安装的应用');
      }

      apps.sort((a, b) => a.appName.compareTo(b.appName));

      // 缓存列表（不含图标）
      _cachedApps = apps;

      // 异步加载所有图标（不阻塞返回）
      _loadAllIconsInBackground(apps);

      _isLoading = false;
      return apps;
    } catch (e) {
      _isLoading = false;
      rethrow;
    }
  }

  /// 后台异步加载所有图标
  static void _loadAllIconsInBackground(List<AppInfo> apps) {
    // 延迟执行，让 UI 先渲染
    Future.microtask(() async {
      for (final app in apps) {
        await _loadIconForApp(app);
        // 每加载一个图标后，延迟 5ms 让出主线程
        await Future.delayed(const Duration(milliseconds: 5));
      }
    });
  }

  /// 为单个应用加载图标（优先从内存缓存，其次从文件缓存）
  static Future<void> _loadIconForApp(AppInfo app) async {
    // 1. 检查内存缓存
    if (_iconCache.containsKey(app.packageName)) {
      app.iconBytes = _iconCache[app.packageName];
      return;
    }

    // 2. 检查文件缓存
    final cachedIcon = await _getCachedIcon(app.packageName);
    if (cachedIcon != null) {
      _iconCache[app.packageName] = cachedIcon;
      app.iconBytes = cachedIcon;
      return;
    }

    // 3. 从系统获取图标
    try {
      final iconBytes = await getAppIcon(app.packageName);
      if (iconBytes != null) {
        _iconCache[app.packageName] = iconBytes;
        app.iconBytes = iconBytes;
        // 保存到文件缓存
        await _saveCachedIcon(app.packageName, iconBytes);
      }
    } catch (e) {
      // 忽略单个图标加载失败
    }
  }

  /// 获取应用图标
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

  /// 获取缓存图标文件路径
  static Future<String> _getIconCachePath(String packageName) async {
    final cacheDir = await getTemporaryDirectory();
    final iconDir = Directory('${cacheDir.path}/app_icons');
    if (!await iconDir.exists()) {
      await iconDir.create(recursive: true);
    }
    return '${iconDir.path}/${packageName.replaceAll('.', '_')}.png';
  }

  /// 从文件缓存加载图标
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

  /// 保存图标到文件缓存
  static Future<void> _saveCachedIcon(String packageName, Uint8List bytes) async {
    try {
      final filePath = await _getIconCachePath(packageName);
      await File(filePath).writeAsBytes(bytes);
    } catch (e) {
      // 忽略保存失败
    }
  }

  /// 获取应用图标（带缓存，供 UI 层调用）
  static Future<Uint8List?> getCachedAppIcon(String packageName) async {
    // 1. 内存缓存
    if (_iconCache.containsKey(packageName)) {
      return _iconCache[packageName];
    }

    // 2. 文件缓存
    final cached = await _getCachedIcon(packageName);
    if (cached != null) {
      _iconCache[packageName] = cached;
      return cached;
    }

    // 3. 从系统获取（同步等待）
    final icon = await getAppIcon(packageName);
    if (icon != null) {
      _iconCache[packageName] = icon;
      await _saveCachedIcon(packageName, icon);
      return icon;
    }

    return null;
  }

  /// 清除缓存（当应用安装/卸载时调用）
  static void clearCache() {
    _cachedApps = null;
    _iconCache.clear();
    // 清除文件缓存（可选）
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

  /// 平台通道
  static const MethodChannel _channel = MethodChannel('com.meng.passwordmanager/apps');
}