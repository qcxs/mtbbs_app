import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 简单的饼图组件（零依赖，用 CustomPaint 绘制）
class PieChart extends StatelessWidget {
  final List<PieChartSegment> segments;
  final double size;
  final double strokeWidth;

  const PieChart({
    super.key,
    required this.segments,
    this.size = 160,
    this.strokeWidth = 40,
  });

  @override
  Widget build(BuildContext context) {
    final total = segments.fold<double>(0, (sum, s) => sum + s.value);
    if (total <= 0) return const SizedBox.shrink();

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PieChartPainter(segments, total, strokeWidth),
      ),
    );
  }
}

class PieChartSegment {
  final String label;
  final double value;
  final Color color;

  const PieChartSegment({
    required this.label,
    required this.value,
    required this.color,
  });
}

class _PieChartPainter extends CustomPainter {
  final List<PieChartSegment> segments;
  final double total;
  final double strokeWidth;

  _PieChartPainter(this.segments, this.total, this.strokeWidth);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    double startAngle = -math.pi / 2;

    for (final segment in segments) {
      if (segment.value <= 0) continue;
      final sweepAngle = (segment.value / total) * 2 * math.pi;

      final paint = Paint()
        ..color = segment.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _PieChartPainter oldDelegate) => true;
}
