// pages/settings/about_page.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../utils/toast_utils.dart';

/// 关于页面
class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  final String _appVersion = '1.0.1';
  final String _author = '梦尊';
  final String _githubUrl = 'https://github.com/mengzun999/password_manager';

  Future<void> _launchUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ToastUtils.showError(context, '无法打开链接');
        }
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showError(context, '打开链接失败: $e');
      }
    }
  }

  void _copyGitHubUrl() {
    // 使用 Helpers.copyToClipboard 或直接实现
    Clipboard.setData(ClipboardData(text: _githubUrl));
    if (mounted) {
      ToastUtils.showSuccess(context, '已复制项目地址');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('关于'),
        backgroundColor: isDark ? Colors.grey.shade900 : null,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // ========== Logo / 图标 ==========
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.purple.shade800.withValues(alpha: 0.3)
                    : Colors.purple.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_outline,
                size: 50,
                color: isDark ? Colors.purple.shade300 : Colors.purple.shade700,
              ),
            ),
            const SizedBox(height: 16),

            // ========== 应用名称 ==========
            Text(
              '密码管理器',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),

            // ========== 版本号 ==========
            Text(
              '版本 $_appVersion',
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),

            // ========== 信息卡片 ==========
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                ),
              ),
              child: Column(
                children: [
                  _buildInfoRow(
                    context,
                    label: '作者',
                    value: _author,
                    isDark: isDark,
                  ),
                  const Divider(height: 16),
                  _buildInfoRow(
                    context,
                    label: '版本',
                    value: _appVersion,
                    isDark: isDark,
                  ),
                  const Divider(height: 16),
                  _buildInfoRow(
                    context,
                    label: '构建',
                    value: 'Release',
                    isDark: isDark,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ========== 项目地址卡片 ==========
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '项目地址',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => _launchUrl(_githubUrl),
                    onLongPress: _copyGitHubUrl,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey.shade700 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.code,
                            size: 20,
                            color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _githubUrl,
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
                                decoration: TextDecoration.underline,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(
                            Icons.open_in_new,
                            size: 16,
                            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '长按可复制项目地址',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ========== 版权信息 ==========
            Text(
              '© 2026 梦尊  ·  密码管理器',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '使用 Flutter 构建  ·  开源软件',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
      BuildContext context, {
        required String label,
        required String value,
        required bool isDark,
      }) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ],
    );
  }
}