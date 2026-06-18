import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
      // 保存到应用私有目录
      final appDir = await getApplicationDocumentsDirectory();
      final fileName = 'background_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final filePath = '${appDir.path}/$fileName';

      final file = File(image.path);
      await file.copy(filePath);

      // ✅ 设置背景图时自动开启开关
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
      // 删除本地文件
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

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('背景图设置'),
      ),
      body: _isLoading
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

              // 文字颜色选择
              _buildColorPicker(settings),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? Colors.grey.shade800 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.image_outlined,
                      size: 48,
                      color: isDark ? Colors.grey.shade600 : Colors.grey.shade400,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '开启后可以自定义密码列表页背景',
                      style: TextStyle(
                        color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
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
          // 如果关闭，同时清除背景图
          if (!value) {
            // 删除本地文件
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.image,
                size: 48,
                color: Colors.white.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 8),
              Text(
                '预览效果',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      )
          : const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_outlined,
              size: 48,
              color: Colors.grey,
            ),
            SizedBox(height: 8),
            Text(
              '请选择一张背景图',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
          ],
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

  Widget _buildColorPicker(SettingsState settings) {
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
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildColorOption(Colors.white, settings),
            _buildColorOption(Colors.black, settings),
            _buildColorOption(Colors.grey.shade700, settings),
            _buildColorOption(Colors.blue.shade700, settings),
            _buildColorOption(Colors.red.shade700, settings),
            _buildColorOption(Colors.green.shade700, settings),
            _buildColorOption(Colors.orange.shade700, settings),
            _buildColorOption(Colors.purple.shade700, settings),
            _buildCustomColorOption(settings),
          ],
        ),
      ],
    );
  }

  Widget _buildColorOption(Color color, SettingsState settings) {
    final isSelected = settings.textColorValue == color;
    return GestureDetector(
      onTap: () {
        ref.read(settingsProvider.notifier).setTextColor(color.value);
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey.shade300,
            width: isSelected ? 3 : 1,
          ),
        ),
        child: isSelected
            ? const Icon(Icons.check, color: Colors.white, size: 20)
            : null,
      ),
    );
  }

  Widget _buildCustomColorOption(SettingsState settings) {
    return GestureDetector(
      onTap: () async {
        final color = await showDialog<Color>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('选择颜色'),
            content: SizedBox(
              width: 300,
              height: 300,
              child: ColorPicker(
                initialColor: settings.textColorValue,
                onColorChanged: (color) {
                  ref.read(settingsProvider.notifier).setTextColor(color.value);
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: settings.textColorValue,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.grey.shade300,
            width: 1,
          ),
          gradient: const LinearGradient(
            colors: [Colors.red, Colors.green, Colors.blue],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const Center(
          child: Icon(Icons.color_lens, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

// 简单颜色选择器
class ColorPicker extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorChanged;

  const ColorPicker({
    super.key,
    required this.initialColor,
    required this.onColorChanged,
  });

  @override
  State<ColorPicker> createState() => _ColorPickerState();
}

class _ColorPickerState extends State<ColorPicker> {
  late Color _selectedColor;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            color: _selectedColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Center(
            child: Text(
              '预览',
              style: TextStyle(
                color: _selectedColor.computeLuminance() > 0.5
                    ? Colors.black
                    : Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildPresetColor(Colors.white),
            _buildPresetColor(Colors.black),
            _buildPresetColor(Colors.grey),
            _buildPresetColor(Colors.red),
            _buildPresetColor(Colors.blue),
            _buildPresetColor(Colors.green),
            _buildPresetColor(Colors.orange),
            _buildPresetColor(Colors.purple),
            _buildPresetColor(Colors.pink),
            _buildPresetColor(Colors.teal),
            _buildPresetColor(Colors.brown),
            _buildPresetColor(Colors.deepPurple),
          ],
        ),
        const SizedBox(height: 16),
        const Text('自定义颜色', style: TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        _buildSlider('R', Colors.red, _selectedColor.red, (v) {
          setState(() {
            _selectedColor = Color.fromARGB(
              _selectedColor.alpha,
              v.round(),
              _selectedColor.green,
              _selectedColor.blue,
            );
            widget.onColorChanged(_selectedColor);
          });
        }),
        _buildSlider('G', Colors.green, _selectedColor.green, (v) {
          setState(() {
            _selectedColor = Color.fromARGB(
              _selectedColor.alpha,
              _selectedColor.red,
              v.round(),
              _selectedColor.blue,
            );
            widget.onColorChanged(_selectedColor);
          });
        }),
        _buildSlider('B', Colors.blue, _selectedColor.blue, (v) {
          setState(() {
            _selectedColor = Color.fromARGB(
              _selectedColor.alpha,
              _selectedColor.red,
              _selectedColor.green,
              v.round(),
            );
            widget.onColorChanged(_selectedColor);
          });
        }),
      ],
    );
  }

  Widget _buildPresetColor(Color color) {
    final isSelected = _selectedColor == color;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedColor = color;
          widget.onColorChanged(color);
        });
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey.shade300,
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
  }

  Widget _buildSlider(String label, Color color, int value, ValueChanged<double> onChanged) {
    return Row(
      children: [
        SizedBox(
          width: 20,
          child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            divisions: 255,
            activeColor: color,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 35,
          child: Text(
            value.toString(),
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}