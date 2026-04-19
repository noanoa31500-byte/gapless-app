import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/accessibility.dart';

/// 超直感的ナビゲーション矢印
/// 
/// 防災UXの核心:
/// - 色が「正解」を教えてくれる
/// - 矢印が「どれだけずれているか」を教えてくれる
/// - 発光が「正しい方向を向いた」ことを祝福してくれる
/// 
/// パニック状態でも、スマホを回すだけで安全な道へ導かれる体験を提供。
class IntuitiveDynamicArrow extends StatefulWidget {
  /// 進むべき方向と現在の向きの差分（度数）
  final double angleDifference;
  
  /// 誘導色
  final Color guideColor;
  
  /// 発光強度（0.0-1.0）
  final double glowIntensity;
  
  /// 矢印サイズ
  final double size;
  
  const IntuitiveDynamicArrow({
    super.key,
    required this.angleDifference,
    required this.guideColor,
    this.glowIntensity = 0.3,
    this.size = 120.0,
  });

  @override
  State<IntuitiveDynamicArrow> createState() => _IntuitiveDynamicArrowState();
}

class _IntuitiveDynamicArrowState extends State<IntuitiveDynamicArrow>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    
    // 発光のパルスアニメーション
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = AppleAccessibility.reduceMotion(context);
    if (reduce && _pulseController.isAnimating) {
      _pulseController.stop();
    } else if (!reduce && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }
    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        return CustomPaint(
          size: Size(widget.size, widget.size),
          painter: _DynamicArrowPainter(
            angleDifference: widget.angleDifference,
            guideColor: widget.guideColor,
            glowIntensity: widget.glowIntensity,
            pulseValue: reduce ? 0.5 : _pulseController.value,
          ),
        );
      },
    );
  }
}

/// カスタムペインター：動的矢印描画
class _DynamicArrowPainter extends CustomPainter {
  final double angleDifference;
  final Color guideColor;
  final double glowIntensity;
  final double pulseValue;

  _DynamicArrowPainter({
    required this.angleDifference,
    required this.guideColor,
    required this.glowIntensity,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // === 1. 外側の円（方向感）===
    _drawOuterCircle(canvas, center, radius);

    // === 2. Glow効果（正解時に発光）===
    if (glowIntensity > 0.1) {
      _drawGlowEffect(canvas, center, radius);
    }

    // === 3. 矢印本体 ===
    _drawArrow(canvas, center, radius);

    // === 4. 中央の小さな円 ===
    _drawCenterDot(canvas, center);
  }

  /// 外側の円を描画
  void _drawOuterCircle(Canvas canvas, Offset center, double radius) {
    final paint = Paint()
      ..color = guideColor.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    canvas.drawCircle(center, radius * 0.9, paint);
  }

  /// Glow効果（ネオンライク発光）
  void _drawGlowEffect(Canvas canvas, Offset center, double radius) {
    // パルスで強度を変化
    final intensity = glowIntensity * (0.7 + 0.3 * pulseValue);
    
    // 複数レイヤーでグロー演出
    for (int i = 3; i >= 1; i--) {
      final paint = Paint()
        ..color = guideColor.withValues(alpha: intensity / (i * 2))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, i * 8.0);

      canvas.drawCircle(center, radius * 0.6, paint);
    }
  }

  /// 矢印を描画
  void _drawArrow(Canvas canvas, Offset center, double radius) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    
    // 矢印を回転（目的地の方向へ）
    canvas.rotate(angleDifference * (math.pi / 180));

    final arrowPath = Path();
    final arrowLength = radius * 0.7;
    final arrowWidth = radius * 0.3;

    // 矢印の形状
    arrowPath.moveTo(0, -arrowLength);        // 頂点
    arrowPath.lineTo(-arrowWidth, 0);          // 左
    arrowPath.lineTo(-arrowWidth * 0.3, 0);    // 左内側
    arrowPath.lineTo(-arrowWidth * 0.3, arrowLength * 0.3); // 左下
    arrowPath.lineTo(arrowWidth * 0.3, arrowLength * 0.3);  // 右下
    arrowPath.lineTo(arrowWidth * 0.3, 0);     // 右内側
    arrowPath.lineTo(arrowWidth, 0);           // 右
    arrowPath.close();

    // 矢印の塗りつぶし
    final fillPaint = Paint()
      ..color = guideColor
      ..style = PaintingStyle.fill;

    canvas.drawPath(arrowPath, fillPaint);

    // 矢印の縁取り（白で視認性向上）
    final strokePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawPath(arrowPath, strokePaint);

    canvas.restore();
  }

  /// 中央の小さな円
  void _drawCenterDot(Canvas canvas, Offset center) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, 4.0, paint);

    final strokePaint = Paint()
      ..color = guideColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(center, 4.0, strokePaint);
  }

  @override
  bool shouldRepaint(_DynamicArrowPainter oldDelegate) {
    return oldDelegate.angleDifference != angleDifference ||
        oldDelegate.guideColor != guideColor ||
        oldDelegate.glowIntensity != glowIntensity ||
        oldDelegate.pulseValue != pulseValue;
  }
}
