import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';
import '../utils/accessibility.dart';
import '../utils/localization.dart';

// ============================================================================
// CalibrationOverlay — 磁気センサー精度低下時の「八の字補正」オーバーレイ
// ============================================================================
//
// 【表示契機】
//   SensorFusionBearingController.calibrationNeededStream が true を流したとき
//   → このWidgetを Stack の最上層に重ねる。
//   false を流したとき → 非表示に戻す。
//
// 【案内内容】
//   「磁気センサーに乱れを検知しました」
//   「端末を八の字に振って補正してください」
//   + 八の字アニメーション
//   + 「案内を一時停止中」バナー
//
// ============================================================================

/// センサー補正オーバーレイ本体
///
/// [visible] が true のとき画面全体に半透明オーバーレイを表示する。
/// [onDismiss] は「スキップ」ボタンが押されたときのコールバック。
class CalibrationOverlay extends StatefulWidget {
  final bool visible;
  final VoidCallback? onDismiss;

  const CalibrationOverlay({
    super.key,
    required this.visible,
    this.onDismiss,
  });

  @override
  State<CalibrationOverlay> createState() => _CalibrationOverlayState();
}

class _CalibrationOverlayState extends State<CalibrationOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _figureEightCtrl;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();

    // 八の字アニメーション（3秒周期でループ）
    _figureEightCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    // 警告パルス（1秒周期）
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _figureEightCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>(); // rebuild on language change
    if (!widget.visible) return const SizedBox.shrink();
    final reduce = AppleAccessibility.reduceMotion(context);
    for (final c in [_figureEightCtrl, _pulseCtrl]) {
      if (reduce && c.isAnimating) {
        c.stop();
      } else if (!reduce && !c.isAnimating) {
        c.repeat(reverse: c == _pulseCtrl);
      }
    }

    return AnimatedOpacity(
      opacity: widget.visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Material(
        color: Colors.transparent,
        child: Container(
          color: const Color(0xCC000000), // 80% 不透明の黒
          child: SafeArea(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _PausedBanner(),
                const SizedBox(height: 32),
                _FigureEightAnimation(controller: _figureEightCtrl),
                const SizedBox(height: 32),
                _MessageCard(pulseCtrl: _pulseCtrl),
                const SizedBox(height: 40),
                if (widget.onDismiss != null) _SkipButton(onTap: widget.onDismiss!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── 「案内一時停止中」バナー ─────────────────────────────────────────────────

class _PausedBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6F00),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.pause_circle_outline, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(
            GapLessL10n.t('cal_paused'),
            style: GapLessL10n.safeStyle(const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            )),
          ),
        ],
      ),
    );
  }
}

// ── 八の字アニメーション ──────────────────────────────────────────────────────

class _FigureEightAnimation extends StatelessWidget {
  final AnimationController controller;

  const _FigureEightAnimation({required this.controller});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, child) {
        final t = controller.value * 2 * math.pi;
        // Lissajous曲線 (a=1, b=2) で八の字を表現
        final x = math.sin(t) * 50;
        final y = math.sin(2 * t) * 30;

        return SizedBox(
          width: 140,
          height: 100,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // 軌跡（静的な八の字輪郭）
              CustomPaint(
                size: const Size(140, 100),
                painter: _FigureEightTrailPainter(),
              ),
              // 移動する端末アイコン
              Transform.translate(
                offset: Offset(x, y),
                child: child,
              ),
            ],
          ),
        );
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF6F00).withOpacity(0.8),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(Icons.smartphone, size: 20, color: Color(0xFF2E7D32)),
      ),
    );
  }
}

/// 八の字の軌跡を描くPainter
class _FigureEightTrailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.25)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    const steps = 120;
    final cx = size.width / 2;
    final cy = size.height / 2;

    for (int i = 0; i <= steps; i++) {
      final t = i / steps * 2 * math.pi;
      final x = cx + math.sin(t) * 50;
      final y = cy + math.sin(2 * t) * 30;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_FigureEightTrailPainter _) => false;
}

// ── メッセージカード ──────────────────────────────────────────────────────────

class _MessageCard extends StatelessWidget {
  final AnimationController pulseCtrl;

  const _MessageCard({required this.pulseCtrl});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          AnimatedBuilder(
            animation: pulseCtrl,
            builder: (_, child) => Opacity(
              opacity: 0.6 + pulseCtrl.value * 0.4,
              child: child,
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFFF6F00),
              size: 48,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            GapLessL10n.t('cal_sensor_warning'),
            textAlign: TextAlign.center,
            style: GapLessL10n.safeStyle(const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              height: 1.4,
            )),
          ),
          const SizedBox(height: 12),
          Text(
            GapLessL10n.t('cal_instruction'),
            textAlign: TextAlign.center,
            style: GapLessL10n.safeStyle(const TextStyle(
              color: Color(0xFFB0BEC5),
              fontSize: 14,
              height: 1.6,
            )),
          ),
        ],
      ),
    );
  }
}

// ── スキップボタン ────────────────────────────────────────────────────────────

class _SkipButton extends StatelessWidget {
  final VoidCallback onTap;

  const _SkipButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child: Text(
        GapLessL10n.t('cal_skip'),
        style: GapLessL10n.safeStyle(const TextStyle(
          color: Color(0xFF90A4AE),
          fontSize: 13,
          decoration: TextDecoration.underline,
          decorationColor: Color(0xFF90A4AE),
        )),
      ),
    );
  }
}

// ============================================================================
// DivergenceWarningBanner — GPS・コンパス乖離 ≥ 30° の警告バナー
// ============================================================================

/// 画面上部に表示するインライン警告バナー。
/// [visible] が true のとき表示、false で非表示にアニメーション。
class DivergenceWarningBanner extends StatelessWidget {
  final bool visible;
  final double divergenceDeg;

  const DivergenceWarningBanner({
    super.key,
    required this.visible,
    this.divergenceDeg = 0,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: visible ? Offset.zero : const Offset(0, -1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: visible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          width: double.infinity,
          color: const Color(0xFFB71C1C),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.explore_off, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  GapLessL10n.t('cal_divergence').replaceAll('@deg', divergenceDeg.toStringAsFixed(0)),
                  style: GapLessL10n.safeStyle(const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  )),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
