import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/localization.dart';

// ============================================================================
// ReturnHomeCompass — 帰還支援モードのコンパスウィジェット
// ============================================================================
//
// 【表示内容】
//   ・コンパス中央に帰還方向の大きな矢印
//   ・残距離（メートル / キロメートル）
//   ・「帰還支援モード」ラベル
//   ・方位線は headingDeg に応じてリアルタイム回転
//
// 【バックトラックボタン】
//   [onBacktrackPressed] が渡された場合にバックトラックボタンを表示する。
//
// ============================================================================

class ReturnHomeCompass extends StatefulWidget {
  /// 帰還目標への方位 [0, 360)
  final double returnBearingDeg;

  /// 帰還目標までの距離（メートル）
  final double returnDistanceM;

  /// 現在のデバイス方位（SensorFusionBearingController から）
  final double headingDeg;

  /// バックトラックボタンが押されたときのコールバック（null = ボタン非表示）
  final VoidCallback? onBacktrackPressed;

  const ReturnHomeCompass({
    super.key,
    required this.returnBearingDeg,
    required this.returnDistanceM,
    required this.headingDeg,
    this.onBacktrackPressed,
  });

  @override
  State<ReturnHomeCompass> createState() => _ReturnHomeCompassState();
}

class _ReturnHomeCompassState extends State<ReturnHomeCompass>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 矢印の回転角: デバイス方位を除いた相対方位
    final arrowAngle =
        (widget.returnBearingDeg - widget.headingDeg) * math.pi / 180;

    return Container(
      color: Colors.black,
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildLabel(),
            const SizedBox(height: 24),
            _buildCompassDial(arrowAngle),
            const SizedBox(height: 28),
            _buildDistanceText(),
            const SizedBox(height: 40),
            if (widget.onBacktrackPressed != null) _buildBacktrackButton(),
          ],
        ),
      ),
    );
  }

  // ── ラベル ────────────────────────────────────────────────────────────────

  Widget _buildLabel() {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (_, child) => Opacity(
        opacity: 0.7 + _pulseCtrl.value * 0.3,
        child: child,
      ),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFF6F00),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              GapLessL10n.t('return_mode_label'),
              style: GapLessL10n.safeStyle(const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              )),
            ),
          ],
        ),
      ),
    );
  }

  // ── コンパスダイアル ───────────────────────────────────────────────────────

  Widget _buildCompassDial(double arrowAngle) {
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 外側リング
          CustomPaint(
            size: const Size(240, 240),
            painter: _CompassRingPainter(),
          ),
          // 帰還矢印（回転）
          Transform.rotate(
            angle: arrowAngle,
            child: CustomPaint(
              size: const Size(200, 200),
              painter: _ReturnArrowPainter(),
            ),
          ),
          // 中心ドット
          Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }

  // ── 距離テキスト ──────────────────────────────────────────────────────────

  Widget _buildDistanceText() {
    final d = widget.returnDistanceM;
    final text = d >= 1000
        ? '${(d / 1000).toStringAsFixed(1)} km'
        : '${d.round()} m';

    return Column(
      children: [
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 48,
            fontWeight: FontWeight.w700,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          GapLessL10n.t('return_dist_label'),
          style: GapLessL10n.safeStyle(const TextStyle(
            color: Color(0xFF90A4AE),
            fontSize: 13,
          )),
        ),
      ],
    );
  }

  // ── バックトラックボタン ───────────────────────────────────────────────────

  Widget _buildBacktrackButton() {
    return ElevatedButton.icon(
      onPressed: widget.onBacktrackPressed,
      icon: const Icon(Icons.undo),
      label: Text(
        GapLessL10n.t('return_backtrack_btn'),
        style: GapLessL10n.safeStyle(const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
        )),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF2E7D32),
        foregroundColor: Colors.white,
        padding:
            const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30),
        ),
      ),
    );
  }
}

// ============================================================================
// _CompassRingPainter — コンパスの外リング（目盛り付き）
// ============================================================================

class _CompassRingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 外リング
    canvas.drawCircle(
      center,
      radius - 4,
      Paint()
        ..color = const Color(0xFF37474F)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );

    // 目盛り（8方位）
    final tickPaint = Paint()
      ..color = const Color(0xFF607D8B)
      ..strokeWidth = 1.5;
    const labels = ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];

    for (int i = 0; i < 8; i++) {
      final angle = i * math.pi / 4 - math.pi / 2;
      final outer = Offset(
        center.dx + (radius - 4) * math.cos(angle),
        center.dy + (radius - 4) * math.sin(angle),
      );
      final inner = Offset(
        center.dx + (radius - 18) * math.cos(angle),
        center.dy + (radius - 18) * math.sin(angle),
      );
      canvas.drawLine(outer, inner, tickPaint);

      // 方位ラベル
      final textPainter = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            color: labels[i] == 'N'
                ? const Color(0xFFFF6F00)
                : const Color(0xFF78909C),
            fontSize: 11,
            fontWeight: labels[i] == 'N'
                ? FontWeight.bold
                : FontWeight.normal,
            fontFamily: GapLessL10n.currentFont,
            fontFamilyFallback: GapLessL10n.fallbackFonts,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final labelPos = Offset(
        center.dx + (radius - 34) * math.cos(angle) -
            textPainter.width / 2,
        center.dy + (radius - 34) * math.sin(angle) -
            textPainter.height / 2,
      );
      textPainter.paint(canvas, labelPos);
    }
  }

  @override
  bool shouldRepaint(_CompassRingPainter _) => false;
}

// ============================================================================
// _ReturnArrowPainter — 帰還方向の大矢印
// ============================================================================

class _ReturnArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // 矢幹
    const shaftWidth = 12.0;
    const headLength = 40.0;
    const headWidth = 30.0;
    final tipY = center.dy - radius + 20;
    final shaftBottom = center.dy + radius * 0.3;

    final shaftPaint = Paint()
      ..color = const Color(0xFFFF6F00)
      ..style = PaintingStyle.fill;

    // 矢幹（長方形）
    final shaftRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(center.dx, (tipY + headLength + shaftBottom) / 2),
        width: shaftWidth,
        height: shaftBottom - tipY - headLength,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(shaftRect, shaftPaint);

    // 矢頭（三角形）
    final head = Path()
      ..moveTo(center.dx, tipY)
      ..lineTo(center.dx - headWidth / 2, tipY + headLength)
      ..lineTo(center.dx + headWidth / 2, tipY + headLength)
      ..close();
    canvas.drawPath(head, shaftPaint);

    // 末端丸
    canvas.drawCircle(
      Offset(center.dx, shaftBottom),
      shaftWidth / 2,
      shaftPaint,
    );
  }

  @override
  bool shouldRepaint(_ReturnArrowPainter _) => false;
}
