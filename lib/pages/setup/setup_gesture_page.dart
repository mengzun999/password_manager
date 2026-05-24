import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import 'package:password_manager/app.dart';
import 'package:password_manager/constants/app_constants.dart';
import 'package:password_manager/core/crypto/aes_gcm.dart';
import 'package:password_manager/core/storage/secure_storage.dart';
import 'package:crypto/crypto.dart';
import 'package:password_manager/core/storage/shared_prefs.dart';
import 'package:password_manager/providers/auth_provider.dart';

/// 手势图案设置页面
///
/// 首次设置时让用户绘制手势图案
/// 用于备用解锁方式
class SetupGesturePage extends ConsumerStatefulWidget {
  const SetupGesturePage({super.key});

  @override
  ConsumerState<SetupGesturePage> createState() => _SetupGesturePageState();
}

class _SetupGesturePageState extends ConsumerState<SetupGesturePage> {

  // ========== 状态变量 ==========

  /// 当前步骤：1=设置图案，2=确认图案
  int _step = 1;

  /// 第一次绘制的图案
  List<int>? _firstPattern;

  /// 当前正在绘制的图案
  List<int> _currentPattern = [];

  /// 错误提示
  String? _error;

  /// 是否正在保存
  bool _isSaving = false;

  // ========== 业务逻辑方法 ==========

  /// 保存手势图案哈希

  Future<void> _saveGesturePattern(List<int> pattern) async {
    setState(() {
      _isSaving = true;
    });

    // 1. 获取主密钥（从 AuthProvider）
    final authState = ref.read(authProvider);
    final masterKey = authState.masterKey;

    if (masterKey == null) {
      setState(() {
        _isSaving = false;
        _error = '未获取到主密钥';
      });
      return;
    }

    // 2. 计算手势图案的哈希（作为加密密钥）
    final patternString = pattern.join(',');
    final gestureHash = sha256.convert(utf8.encode(patternString)).toString();

    // 3. 使用手势哈希作为密钥，加密 masterKey
    final gestureKey = Uint8List.fromList(utf8.encode(gestureHash.substring(0, 32)));
    final encryptedMasterKey = await AESGCMHelper.encryptBytes(masterKey, gestureKey);

    // 4. 存储手势哈希和加密后的 masterKey
    await SecureStorage.write(AppConstants.keyGestureHash, gestureHash);
    await SecureStorage.write(AppConstants.keyEncryptedMasterKeyForGesture, base64Encode(encryptedMasterKey));
    await SharedPrefs.setHasGesture(true);

    setState(() {
      _isSaving = false;
    });

    if (mounted) {
      Navigator.pushReplacementNamed(context, AppRoutes.setupBiometric);
    }
  }

  /// 处理图案绘制完成
  void _onPatternComplete(List<int> pattern) {
    setState(() {
      _error = null;
    });

    if (_step == 1) {
      // 第一步：记录第一次绘制的图案
      if (pattern.length < 4) {
        setState(() {
          _error = '至少连接4个点';
        });
        return;
      }

      _firstPattern = pattern;
      setState(() {
        _step = 2;
        _currentPattern = [];
      });
    } else {
      // 第二步：验证两次绘制是否一致
      if (_firstPattern == null) {
        setState(() {
          _error = '请重新设置';
          _step = 1;
        });
        return;
      }

      if (_listEquals(_firstPattern!, pattern)) {
        // 一致，保存图案
        _saveGesturePattern(pattern);
      } else {
        setState(() {
          _error = '两次绘制的图案不一致，请重新设置';
          _step = 1;
          _firstPattern = null;
          _currentPattern = [];
        });
      }
    }
  }

  /// 比较两个列表是否相等
  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// 重置当前步骤
  void _reset() {
    setState(() {
      _step = 1;
      _firstPattern = null;
      _currentPattern = [];
      _error = null;
    });
  }

  // ========== 界面构建方法 ==========

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_step == 1 ? '设置手势图案' : '确认手势图案'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: _reset,
            child: const Text('重设'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // ========== 说明文字 ==========
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    _step == 1
                        ? '绘制你的手势图案（至少连接4个点）'
                        : '请再次绘制相同的手势图案',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.blue.shade800,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 40),

            // ========== 手势图案绘制组件 ==========
            Center(
              child: GesturePatternPainter(
                onPatternComplete: _onPatternComplete,
                currentPattern: _currentPattern,
                onPatternChanged: (pattern) {
                  setState(() {
                    _currentPattern = pattern;
                  });
                },
              ),
            ),

            const SizedBox(height: 40),

            // ========== 跳过按钮（可选） ==========
            TextButton(
              onPressed: () {
                // 跳过手势图案设置，直接到主页
                if (mounted) {
                  Navigator.pushReplacementNamed(context, AppRoutes.unlock);
                }
              },
              child: const Text('跳过'),
            ),
          ],
        ),
      ),
    );
  }
}

// ========== 手势图案绘制组件 ==========

/// 手势图案绘制器
/// 3x3 点阵，用户可以连接点来绘制图案
class GesturePatternPainter extends StatefulWidget {
  final void Function(List<int>) onPatternComplete;
  final List<int> currentPattern;
  final void Function(List<int>) onPatternChanged;

  const GesturePatternPainter({
    super.key,
    required this.onPatternComplete,
    required this.currentPattern,
    required this.onPatternChanged,
  });

  @override
  State<GesturePatternPainter> createState() => _GesturePatternPainterState();
}

class _GesturePatternPainterState extends State<GesturePatternPainter> {

  // 9个点的位置（0-8）
  // 0 1 2
  // 3 4 5
  // 6 7 8

  List<Offset> _points = [];
  List<int> _selectedPoints = [];
  Offset? _currentTouchPoint;

  @override
  void initState() {
    super.initState();
    _selectedPoints = List.from(widget.currentPattern);
  }

  @override
  void didUpdateWidget(GesturePatternPainter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentPattern != oldWidget.currentPattern) {
      _selectedPoints = List.from(widget.currentPattern);
    }
  }

  /// 获取点的中心位置
  List<Offset> _getPointPositions(Size size) {
    final positions = <Offset>[];
    final cellWidth = size.width / 3;
    final cellHeight = size.height / 3;

    for (int row = 0; row < 3; row++) {
      for (int col = 0; col < 3; col++) {
        final x = col * cellWidth + cellWidth / 2;
        final y = row * cellHeight + cellHeight / 2;
        positions.add(Offset(x, y));
      }
    }
    return positions;
  }

  /// 根据触摸点找到最近的点
  int? _findNearestPoint(Offset touchPoint, Size size) {
    final positions = _getPointPositions(size);
    int? nearestIndex;
    double minDistance = 50.0; // 最大识别距离

    for (int i = 0; i < positions.length; i++) {
      final distance = (touchPoint - positions[i]).distance;
      if (distance < minDistance) {
        minDistance = distance;
        nearestIndex = i;
      }
    }

    return nearestIndex;
  }

  /// 检查两个点之间是否有中间点需要自动连接
  List<int> _getPointsBetween(int from, int to) {
    final points = <int>[];

    // 计算行列
    final fromRow = from ~/ 3;
    final fromCol = from % 3;
    final toRow = to ~/ 3;
    final toCol = to % 3;

    // 同一行
    if (fromRow == toRow && (fromCol - toCol).abs() == 2) {
      points.add(fromRow * 3 + 1); // 中间点
    }
    // 同一列
    else if (fromCol == toCol && (fromRow - toRow).abs() == 2) {
      points.add(1 * 3 + fromCol); // 中间点
    }
    // 对角线
    else if ((fromRow - toRow).abs() == 2 && (fromCol - toCol).abs() == 2) {
      points.add(4); // 中心点
    }

    return points;
  }

  /// 添加选中的点
  void _addPoint(int index) {
    if (_selectedPoints.contains(index)) return;

    if (_selectedPoints.isNotEmpty) {
      final lastPoint = _selectedPoints.last;
      final betweenPoints = _getPointsBetween(lastPoint, index);

      // 自动添加中间点
      for (final between in betweenPoints) {
        if (!_selectedPoints.contains(between)) {
          _selectedPoints.add(between);
        }
      }
    }

    _selectedPoints.add(index);
    widget.onPatternChanged(_selectedPoints);
  }

  /// 处理触摸开始
  void _onPanStart(DragStartDetails details, Size size) {
    final touchPoint = details.localPosition;
    final nearestIndex = _findNearestPoint(touchPoint, size);

    if (nearestIndex != null) {
      _selectedPoints = [];
      _addPoint(nearestIndex);
    }

    setState(() {
      _currentTouchPoint = touchPoint;
    });
  }

  /// 处理触摸移动
  void _onPanUpdate(DragUpdateDetails details, Size size) {
    final touchPoint = details.localPosition;
    final nearestIndex = _findNearestPoint(touchPoint, size);

    if (nearestIndex != null && !_selectedPoints.contains(nearestIndex)) {
      _addPoint(nearestIndex);
    }

    setState(() {
      _currentTouchPoint = touchPoint;
    });
  }

  /// 处理触摸结束
  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _currentTouchPoint = null;
    });

    if (_selectedPoints.length >= 4) {
      widget.onPatternComplete(_selectedPoints);
    } else {
      // 图案太短，清除
      setState(() {
        _selectedPoints = [];
        widget.onPatternChanged([]);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxWidth);

        return GestureDetector(
          onPanStart: (details) => _onPanStart(details, size),
          onPanUpdate: (details) => _onPanUpdate(details, size),
          onPanEnd: _onPanEnd,
          child: CustomPaint(
            size: size,
            painter: _GesturePatternPainter(
              pointPositions: _getPointPositions(size),
              selectedPoints: _selectedPoints,
              currentTouchPoint: _currentTouchPoint,
            ),
          ),
        );
      },
    );
  }
}

/// 自定义绘制器
class _GesturePatternPainter extends CustomPainter {
  final List<Offset> pointPositions;
  final List<int> selectedPoints;
  final Offset? currentTouchPoint;

  _GesturePatternPainter({
    required this.pointPositions,
    required this.selectedPoints,
    this.currentTouchPoint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制线条
    if (selectedPoints.length >= 2) {
      final paint = Paint()
        ..color = Colors.blue
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      for (int i = 0; i < selectedPoints.length - 1; i++) {
        final from = pointPositions[selectedPoints[i]];
        final to = pointPositions[selectedPoints[i + 1]];
        canvas.drawLine(from, to, paint);
      }

      // 绘制到当前触摸点的线条
      if (currentTouchPoint != null && selectedPoints.isNotEmpty) {
        final lastPoint = pointPositions[selectedPoints.last];
        canvas.drawLine(lastPoint, currentTouchPoint!, paint);
      }
    }

    // 绘制9个点
    for (int i = 0; i < pointPositions.length; i++) {
      final isSelected = selectedPoints.contains(i);

      // 外圈：选中为蓝色渐变，未选中为浅灰色
      final outPaint = Paint()
        ..color = isSelected ? Colors.blue : Colors.grey.shade300
        ..style = PaintingStyle.fill;

      canvas.drawCircle(pointPositions[i], 28, outPaint);

      // 内圈：选中为白色，未选中为白色带阴影
      final innerPaint = Paint()
        ..color = isSelected ? Colors.white : Colors.grey.shade100
        ..style = PaintingStyle.fill;

      canvas.drawCircle(pointPositions[i], 20, innerPaint);

      // 如果有阴影效果（可选）
      if (isSelected) {
        final shadowPaint = Paint()
          ..color = Colors.blue.withValues(alpha: 0.3)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(pointPositions[i], 32, shadowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GesturePatternPainter oldDelegate) {
    return oldDelegate.selectedPoints != selectedPoints ||
        oldDelegate.currentTouchPoint != currentTouchPoint;
  }
}

