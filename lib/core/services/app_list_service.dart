import 'dart:io';
import 'package:flutter/material.dart';
/// 应用信息模型
/// 用来存储一个应用的基本信息
class AppInfo {
  /// 包名（Android 应用的唯一标识）
  /// 例如：com.tencent.mm 代表微信
  final String packageName;

  /// 应用名称（用户看得懂的名字）
  /// 例如：微信、QQ、支付宝
  final String appName;

  /// 应用图标（暂时用默认图标，后续可以读取真实图标）
  final IconData? icon;

  /// 构造函数
  /// required 表示这个参数必须传入
  AppInfo({
    required this.packageName,
    required this.appName,
    this.icon,
  });
}
/// 应用列表服务类
/// 负责读取手机中安装的所有应用
class AppListService {
  /// 获取常用应用列表（模拟数据）
  /// 返回一个包含常用应用的列表
  ///
  /// 使用示例：
  /// List<AppInfo> apps = AppListService.getCommonApps();
  static List<AppInfo> getCommonApps() {
    return [
      AppInfo(packageName: 'com.tencent.mm', appName: '微信'),
      AppInfo(packageName: 'com.tencent.mobileqq', appName: 'QQ'),
      AppInfo(packageName: 'com.taobao.taobao', appName: '淘宝'),
      AppInfo(packageName: 'com.alibaba.android.rimet', appName: '钉钉'),
      AppInfo(packageName: 'com.eg.android.AlipayGphone', appName: '支付宝'),
      AppInfo(packageName: 'com.sina.weibo', appName: '微博'),
      AppInfo(packageName: 'com.xingin.xhs', appName: '小红书'),
      AppInfo(packageName: 'com.ss.android.ugc.aweme', appName: '抖音'),
      AppInfo(packageName: 'com.kuaishou.nebula', appName: '快手'),
      AppInfo(packageName: 'com.netease.cloudmusic', appName: '网易云音乐'),
    ];
  }
}