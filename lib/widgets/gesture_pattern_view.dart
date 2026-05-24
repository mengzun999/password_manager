import 'package:flutter/material.dart';

/// 手势图案绘制组件
///
/// 3x3 点阵，用户可以连接点来绘制图案
class GesturePatternView extends StatefulWidget {
  /// 图案绘制完成时的回调
  final void Function(List<int>) onPatternComplete;

  /// 图案变化时的回调
  final void Function(List<int>) onPatternChanged;

  const GesturePatternView({
    super.key,
    required this.onPatternComplete,
    required this.onPatternChanged,
  });

  @override
  GesturePatternViewState createState() => GesturePatternViewState();
}

class GesturePatternViewState extends State<GesturePatternView> {
  /// 已选中的点（按顺序）
  List<int> _selectedPoints = [];

  /// 当前触摸点的位置
  Offset? _currentTouchPoint;

  /// 清空当前图案（供外部调用）
  void clearPattern() {
    setState(() {
      _selectedPoints = [];
      _currentTouchPoint = null;
    });
  }

  /// 获取9个点的中心位置
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
    double minDistance = 50.0;

    for (int i = 0; i < positions.length; i++) {
      final distance = (touchPoint - positions[i]).distance;
      if (distance < minDistance) {
        minDistance = distance;
        nearestIndex = i;
      }
    }
    return nearestIndex;
  }

  /// 检查两点之间的中间点
  List<int> _getPointsBetween(int from, int to) {
    final points = <int>[];
    final fromRow = from ~/ 3;
    final fromCol = from % 3;
    final toRow = to ~/ 3;
    final toCol = to % 3;

    if (fromRow == toRow && (fromCol - toCol).abs() == 2) {
      points.add(fromRow * 3 + 1);
    } else if (fromCol == toCol && (fromRow - toRow).abs() == 2) {
      points.add(1 * 3 + fromCol);
    } else if ((fromRow - toRow).abs() == 2 && (fromCol - toCol).abs() == 2) {
      points.add(4);
    }
    return points;
  }

  /// 添加一个选中的点
  void _addPoint(int index) {
    if (_selectedPoints.contains(index)) return;

    if (_selectedPoints.isNotEmpty) {
      final lastPoint = _selectedPoints.last;
      final betweenPoints = _getPointsBetween(lastPoint, index);

      for (final between in betweenPoints) {
        if (!_selectedPoints.contains(between)) {
          _selectedPoints.add(between);
        }
      }
    }

    _selectedPoints.add(index);
    widget.onPatternChanged(_selectedPoints);
  }

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

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _currentTouchPoint = null;
    });

    if (_selectedPoints.length >= 4) {
      widget.onPatternComplete(_selectedPoints);
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

/// 手势图案绘制器
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

      if (currentTouchPoint != null && selectedPoints.isNotEmpty) {
        final lastPoint = pointPositions[selectedPoints.last];
        canvas.drawLine(lastPoint, currentTouchPoint!, paint);
      }
    }

    // 绘制9个点
    for (int i = 0; i < pointPositions.length; i++) {
      final isSelected = selectedPoints.contains(i);

      final outPaint = Paint()
        ..color = isSelected ? Colors.blue : Colors.grey.shade300
        ..style = PaintingStyle.fill;

      canvas.drawCircle(pointPositions[i], 28, outPaint);

      final innerPaint = Paint()
        ..color = isSelected ? Colors.white : Colors.grey.shade100
        ..style = PaintingStyle.fill;

      canvas.drawCircle(pointPositions[i], 20, innerPaint);

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