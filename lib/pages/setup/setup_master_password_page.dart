import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:password_manager/app.dart';
import 'package:password_manager/providers/auth_provider.dart';

/// 设置主密码页面
///
/// 这是用户第一次打开 App 时看到的页面
/// 用户需要在这里设置一个主密码，用于保护所有保存的密码
/// 这个密码需要记住，忘记后需要用到助记词才能恢复
class SetupMasterPasswordPage extends ConsumerStatefulWidget {
  const SetupMasterPasswordPage({super.key});

  @override
  ConsumerState<SetupMasterPasswordPage> createState() =>
      _SetupMasterPasswordPageState();
}

/// 页面的状态类
///
/// State 存放页面中会变化的数据，比如输入框内容、错误提示、加载状态等
class _SetupMasterPasswordPageState
    extends ConsumerState<SetupMasterPasswordPage> {

  // ========== 控制器（用于获取输入框的内容） ==========

  /// 主密码输入框控制器
  final _passwordController = TextEditingController();

  /// 确认密码输入框控制器
  final _confirmController = TextEditingController();

  // ========== UI 状态变量 ==========

  /// 主密码是否隐藏（true=显示为黑点，false=显示明文）
  bool _obscurePassword = true;

  /// 确认密码是否隐藏
  bool _obscureConfirm = true;

  /// 错误提示文字（如果为 null 则不显示）
  String? _error;

  /// 是否正在保存中（显示加载动画，防止重复提交）
  bool _isLoading = false;

  // ========== 生命周期方法 ==========

  /// 页面销毁时调用
  ///
  /// 释放控制器资源，避免内存泄漏
  @override
  void dispose() {
    _passwordController.dispose();  // 释放密码控制器
    _confirmController.dispose();   // 释放确认密码控制器
    super.dispose();
  }

  // ========== 业务逻辑方法 ==========

  /// 处理提交（用户点击"下一步"按钮时调用）
  ///
  /// 流程：
  /// 1. 获取输入框的内容
  /// 2. 验证密码是否合法（非空、长度≥6、两次一致）
  /// 3. 调用 AuthProvider 保存主密码
  /// 4. 跳转到助记词页面
  Future<void> _handleSubmit() async {
    // 1. 获取输入框内容，trim() 去掉首尾空格
    final password = _passwordController.text.trim();
    final confirm = _confirmController.text.trim();

    // 2. 验证：不能为空
    if (password.isEmpty) {
      setState(() => _error = '请输入主密码');  // setState 会触发界面重新构建
      return;  // 停止执行
    }

    // 3. 验证：长度至少6位
    if (password.length < 6) {
      setState(() => _error = '主密码至少6位');
      return;
    }

    // 4. 验证：两次输入的密码一致
    if (password != confirm) {
      setState(() => _error = '两次输入的密码不一致');
      return;
    }

    // 5. 清除错误提示，显示加载状态
    setState(() {
      _error = null;      // 清除错误
      _isLoading = true;  // 显示加载动画
    });

    // 6. 获取 AuthProvider 并保存主密码
    // ref.read 可以获取 Provider 的实例
    // .notifier 可以获取 Provider 的控制器，用来调用方法
    final authNotifier = ref.read(authProvider.notifier);
    await authNotifier.setupMasterPassword(password);  // 保存主密码

    // 7. 保存完成，隐藏加载状态
    setState(() => _isLoading = false);

    // 8. 跳转到下一个页面（助记词页面）
    // mounted 检查页面是否还存在（避免跳转失败）
    if (mounted) {
      // pushReplacementNamed 替换当前页面，用户无法返回
      Navigator.pushReplacementNamed(context, AppRoutes.setupMnemonic);
    }
  }

  // ========== 界面构建方法 ==========

  /// 构建页面界面
  ///
  /// Widget 是 Flutter 界面的基本单位
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // 顶部导航栏
      appBar: AppBar(
        title: const Text('设置主密码'),
        // 不显示返回按钮，因为这是第一次设置，不应该让用户返回
        automaticallyImplyLeading: false,
      ),

      // 页面主体内容
      body: Padding(
        padding: const EdgeInsets.all(24.0),  // 四周留白24像素
        child: Column(
          // 主轴（垂直方向）靠左对齐
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 垂直间距20像素
            const SizedBox(height: 20),

            // ========== 说明文字 ==========
            const Text(
              '设置一个主密码来保护你的所有密码',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 10),
            const Text(
              '请记住这个密码，忘记后需要助记词才能恢复',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),

            const SizedBox(height: 40),

            // ========== 主密码输入框 ==========
            TextField(
              controller: _passwordController,        // 绑定控制器
              obscureText: _obscurePassword,           // 是否隐藏输入
              decoration: InputDecoration(
                labelText: '主密码',                    // 输入框标签
                hintText: '至少6位',                   // 提示文字
                suffixIcon: IconButton(
                  // 根据隐藏状态显示不同图标
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off   // 隐藏状态：闭眼图标
                        : Icons.visibility,      // 显示状态：睁眼图标
                  ),
                  onPressed: () {
                    // 点击后切换隐藏/显示状态
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
                border: const OutlineInputBorder(),    // 边框样式
              ),
            ),

            const SizedBox(height: 16),

            // ========== 确认密码输入框 ==========
            TextField(
              controller: _confirmController,
              obscureText: _obscureConfirm,
              decoration: InputDecoration(
                labelText: '确认主密码',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureConfirm
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscureConfirm = !_obscureConfirm;
                    });
                  },
                ),
                border: const OutlineInputBorder(),
              ),
            ),

            // ========== 错误提示 ==========
            // 使用 if 条件判断：只有当 _error 不为 null 时才显示
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,  // ! 表示确信不为 null
                style: const TextStyle(color: Colors.red),
              ),
            ],

            const SizedBox(height: 32),

            // ========== 下一步按钮 ==========
            SizedBox(
              width: double.infinity,  // 宽度占满父容器
              height: 50,              // 高度50像素
              child: ElevatedButton(
                // 如果正在加载中，按钮禁用（onPressed = null）
                onPressed: _isLoading ? null : _handleSubmit,
                child: _isLoading
                // 加载中：显示转圈动画
                    ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                // 正常状态：显示文字
                    : const Text('下一步'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}