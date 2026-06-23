import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:password_manager/providers/settings_provider.dart';
import '../../utils/toast_utils.dart';

/// 背景图设置页面
class BackgroundSettingsPage extends ConsumerStatefulWidget {
  const BackgroundSettingsPage({super.key});

  @override
  ConsumerState<BackgroundSettingsPage> createState() => _BackgroundSettingsPageState();
}

class _BackgroundSettingsPageState extends ConsumerState<BackgroundSettingsPage> {
  bool _isLoading = false;

  /// 从相册选择图片
  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return;

    setState(() => _isLoading = true);

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'background_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = '${appDir.path}/$fileName';

      final file = File(image.path);
      await file.copy(filePath);

      await ref.read(settingsProvider.notifier).setBackgroundEnabled(true);
      await ref.read(settingsProvider.notifier).setBackgroundImage(filePath);

      if (mounted) {
        ToastUtils.showSuccess(context, '背景图已设置');
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showError(context, '设置失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 恢复默认
  Future<void> _resetBackground() async {
    final confirmed = await ToastUtils.showConfirmDialog(
      context,
      title: '恢复默认',
      content: '确定要清除背景图，恢复默认纯色背景吗？',
      confirmText: '恢复',
      isDestructive: false,
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);

    try {
      final settings = ref.read(settingsProvider);
      if (settings.backgroundImagePath != null) {
        final file = File(settings.backgroundImagePath!);
        if (await file.exists()) {
          await file.delete();
        }
      }

      await ref.read(settingsProvider.notifier).resetBackgroundSettings();

      if (mounted) {
        ToastUtils.showSuccess(context, '已恢复默认背景');
      }
    } catch (e) {
      if (mounted) {
        ToastUtils.showError(context, '恢复失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// ✅ 打开色盘选择颜色（底部弹出）- 带滚动
  Future<void> _showColorPicker() async {
    final settings = ref.read(settingsProvider);
    Color currentColor = settings.textColorValue;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final screenHeight = MediaQuery.of(context).size.height;
            final bottomPadding = MediaQuery.of(context).padding.bottom;

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark
                    ? Colors.grey.shade900
                    : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '选择文字颜色',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  // ✅ 使用 SingleChildScrollView 包裹色盘
                  SizedBox(
                    height: screenHeight * 0.45,
                    child: SingleChildScrollView(
                      child: ColorPicker(
                        pickerColor: currentColor,
                        onColorChanged: (color) {
                          setState(() {
                            currentColor = color;
                          });
                          ref.read(settingsProvider.notifier).setTextColor(color.toARGB32());
                        },
                        pickerAreaHeightPercent: 0.6,
                        portraitOnly: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: currentColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Text(
                      '预览文字颜色',
                      style: TextStyle(
                        color: currentColor.computeLuminance() > 0.5
                            ? Colors.black
                            : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('确定'),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: bottomPadding + 8),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('背景图设置'),
      ),
      body: SafeArea(  // ✅ 添加
          bottom: true,  // ✅ 添加
          child:_isLoading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ✅ 总开关
                _buildEnableSwitch(settings, isDark),

                const SizedBox(height: 16),

                // ✅ 只有开关打开时才显示下面的内容
                if (settings.backgroundEnabled) ...[
                  // 当前背景预览
                  _buildPreviewSection(settings, isDark),

                  const SizedBox(height: 24),

                  // 操作按钮
                  _buildActionButtons(settings),

                  const SizedBox(height: 24),

                  // 调节滑块
                  _buildSliders(settings, isDark),

                  const SizedBox(height: 24),

                  // ✅ 文字颜色选择 - 使用色盘
                  _buildColorPickerSection(settings),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: Text(
                        '开启后可以自定义密码列表页背景',
                        style: TextStyle(
                          color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 40),
              ],
            ),
          ),
      )
    );
  }

  Widget _buildEnableSwitch(SettingsState settings, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade800 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
        ),
      ),
      child: SwitchListTile(
        title: Text(
          '启用背景图',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        subtitle: Text(
          settings.backgroundEnabled
              ? '当前已启用自定义背景'
              : '关闭后恢复默认纯色背景',
          style: TextStyle(
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
          ),
        ),
        value: settings.backgroundEnabled,
        onChanged: (value) {
          ref.read(settingsProvider.notifier).setBackgroundEnabled(value);
          if (!value) {
            if (settings.backgroundImagePath != null) {
              final file = File(settings.backgroundImagePath!);
              if (file.existsSync()) {
                file.deleteSync();
              }
            }
            ref.read(settingsProvider.notifier).setBackgroundImage(null);
          }
        },
        secondary: Icon(
          settings.backgroundEnabled ? Icons.image : Icons.image_outlined,
          color: settings.backgroundEnabled
              ? Theme.of(context).primaryColor
              : (isDark ? Colors.grey.shade500 : Colors.grey.shade400),
        ),
      ),
    );
  }

  Widget _buildPreviewSection(SettingsState settings, bool isDark) {
    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isDark ? Colors.grey.shade900 : Colors.grey.shade200,
        image: settings.backgroundImagePath != null
            ? DecorationImage(
          image: FileImage(File(settings.backgroundImagePath!)),
          fit: BoxFit.cover,
        )
            : null,
      ),
      child: settings.backgroundImagePath != null
          ? Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isDark
              ? Colors.black.withValues(alpha: 0.6)
              : Colors.white.withValues(alpha: 0.3),
        ),
        child: Center(
          child: Text(
            '预览效果',
            style: TextStyle(
              color: settings.textColorValue,
              fontSize: 18,
              fontWeight: FontWeight.w500,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
        ),
      )
          : Center(
        child: Text(
          '请选择一张背景图',
          style: TextStyle(
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(SettingsState settings) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.photo_library),
            label: const Text('选择背景图'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: settings.backgroundImagePath != null ? _resetBackground : null,
            icon: const Icon(Icons.restore),
            label: const Text('恢复默认'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSliders(SettingsState settings, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '卡片透明度',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: settings.backgroundOpacity.toDouble(),
                min: 5,
                max: 100,
                divisions: 19,
                label: '${settings.backgroundOpacity}%',
                onChanged: (value) {
                  ref
                      .read(settingsProvider.notifier)
                      .setBackgroundOpacity(value.round());
                },
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                '${settings.backgroundOpacity}%',
                style: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        Text(
          '背景模糊度',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: settings.backgroundBlur.toDouble(),
                min: 0,
                max: 30,
                divisions: 30,
                label: '${settings.backgroundBlur}',
                onChanged: (value) {
                  ref
                      .read(settingsProvider.notifier)
                      .setBackgroundBlur(value.round());
                },
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                '${settings.backgroundBlur}',
                style: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// ✅ 使用色盘选择文字颜色
  Widget _buildColorPickerSection(SettingsState settings) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '文字颜色（亮色模式）',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        // ✅ 使用 Wrap 替代 Row，自动换行防止溢出
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ..._buildPresetColors(settings, isDark),

            // ✅ 自定义色盘按钮
            GestureDetector(
              onTap: _showColorPicker,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.grey.shade400,
                    width: 2,
                  ),
                  gradient: const LinearGradient(
                    colors: [Colors.red, Colors.green, Colors.blue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Icon(
                  Icons.color_lens,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '当前颜色：',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: settings.textColorValue,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isDark ? Colors.grey.shade600 : Colors.grey.shade300,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '#${settings.textColorValue.value.toRadixString(16).padLeft(8, '0').toUpperCase()}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _buildPresetColors(SettingsState settings, bool isDark) {
    final colors = [
      Colors.white,
      Colors.black,
      Colors.grey.shade700,
      Colors.blue.shade700,
      Colors.red.shade700,
      Colors.green.shade700,
      Colors.orange.shade700,
      Colors.purple.shade700,
    ];

    return colors.map((color) {
      final isSelected = settings.textColorValue == color;
      return GestureDetector(
        onTap: () {
          ref.read(settingsProvider.notifier).setTextColor(color.toARGB32());
        },
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: isSelected ? Colors.blue : (isDark ? Colors.grey.shade600 : Colors.grey.shade300),
              width: isSelected ? 3 : 1,
            ),
          ),
          child: isSelected
              ? Icon(
            Icons.check,
            color: color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
            size: 16,
          )
              : null,
        ),
      );
    }).toList();
  }
}