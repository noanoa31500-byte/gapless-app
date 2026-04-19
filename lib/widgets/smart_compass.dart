import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../utils/accessibility.dart';

/// ============================================================================
/// SmartCompass - ロケーション非依存型コンパスウィジェット
/// ============================================================================
/// 
/// 【設計思想】
/// 災害時に言語や地域に依存せず、色で直感的に方向を伝えるコンパス。
/// 磁気偏角を引数として受け取り、どの地域でも正確に動作する。
/// 
/// 【カラーコード】
/// - 緑 (Safe): 避難所の方角を向いている
/// - 赤 (Danger): 危険箇所の方角を向いている
/// - 黒/グレー (Neutral): どちらでもない
/// ============================================================================
class SmartCompass extends StatefulWidget {
  /// センサーの生データ（磁北基準 0-360度）
  final double heading;
  
  /// 避難所への真北基準の方位（null = 避難所未設定）
  final double? safeBearing;
  
  /// 危険箇所への真北基準の方位リスト
  final List<double> dangerBearings;
  
  /// 磁気偏角（磁北と真北のズレ）
  /// - 日本（大崎）: 約 -8.5° (西偏)
  /// - タイ（サトゥン）: 約 -0.6° (ほぼゼロ)
  /// 計算式: trueHeading = heading + magneticDeclination
  final double magneticDeclination;
  
  /// コンパスのサイズ
  final double size;
  
  /// 安全とみなす角度差のしきい値（度）
  final double safeThreshold;
  
  /// 危険とみなす角度差のしきい値（度）
  final double dangerThreshold;
  
  /// アニメーション時間
  final Duration animationDuration;

  const SmartCompass({
    super.key,
    required this.heading,
    this.safeBearing,
    this.dangerBearings = const [],
    this.magneticDeclination = 0.0,
    this.size = 280,
    this.safeThreshold = 30.0, // Increased for more stable green state
    this.dangerThreshold = 15.0,
    this.animationDuration = const Duration(milliseconds: 300),
  });

  @override
  State<SmartCompass> createState() => _SmartCompassState();
}

class _SmartCompassState extends State<SmartCompass>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  /// 磁気偏角を適用して真の方角を計算
  double get trueHeading {
    return _normalizeAngle(widget.heading + widget.magneticDeclination);
  }

  /// 角度を0-360に正規化
  double _normalizeAngle(double angle) {
    angle = angle % 360;
    if (angle < 0) angle += 360;
    return angle;
  }

  /// 2つの角度間の最短距離を計算（-180 ~ 180）
  /// 例: 350度と10度の差 → 20度（-20ではなく絶対値20）
  double _shortestAngleDiff(double from, double to) {
    double diff = to - from;
    while (diff > 180) diff -= 360;
    while (diff < -180) diff += 360;
    return diff.abs();
  }

  /// 現在の状態を判定
  CompassState _evaluateState() {
    // デバッグ出力
    debugPrint('🧭 SmartCompass: heading=${widget.heading.toStringAsFixed(1)}, trueHeading=${trueHeading.toStringAsFixed(1)}, safeBearing=${widget.safeBearing?.toStringAsFixed(1)}');
    
    // 安全方向のチェック（最優先: 緑のターゲットに向かっているなら、それが正解）
    if (widget.safeBearing != null) {
      final diff = _shortestAngleDiff(trueHeading, widget.safeBearing!);
      debugPrint('🧭 Safe check: diff=${diff.toStringAsFixed(1)}, threshold=${widget.safeThreshold}');
      if (diff < widget.safeThreshold) {
        debugPrint('🧭 ✅ STATE: SAFE');
        return CompassState.safe;
      }
    } else {
      debugPrint('🧭 ⚠️ safeBearing is NULL - no target set!');
    }

    // 危険方向のチェック（安全方向でない場合のみチェック）
    for (final dangerBearing in widget.dangerBearings) {
      final diff = _shortestAngleDiff(trueHeading, dangerBearing);
      if (diff < widget.dangerThreshold) {
        return CompassState.danger;
      }
    }
    
    return CompassState.neutral;
  }

  /// 状態に応じた色を取得
  Color _getStateColor(CompassState state) {
    switch (state) {
      case CompassState.safe:
        return const Color(0xFF34C759); // Apple Green
      case CompassState.danger:
        return const Color(0xFFFF3B30); // Apple Red
      case CompassState.neutral:
        return const Color(0xFF8E8E93); // Apple Gray
    }
  }

  /// 状態に応じたグラデーションを取得
  RadialGradient _getStateGradient(CompassState state) {
    final color = _getStateColor(state);
    return RadialGradient(
      center: Alignment.center,
      radius: 0.8,
      colors: [
        color.withValues(alpha: 0.3),
        color.withValues(alpha: 0.1),
        Colors.transparent,
      ],
      stops: const [0.0, 0.5, 1.0],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = _evaluateState();
    final stateColor = _getStateColor(state);
    final reduce = AppleAccessibility.reduceMotion(context);
    if (reduce && _pulseController.isAnimating) {
      _pulseController.stop();
    } else if (!reduce && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: state == CompassState.safe ? _pulseAnimation.value : 1.0,
          child: AnimatedContainer(
            duration: widget.animationDuration,
            curve: Curves.easeInOut,
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: _getStateGradient(state),
              border: Border.all(
                color: stateColor.withValues(alpha: 0.5),
                width: 3,
              ),
              boxShadow: [
                BoxShadow(
                  color: stateColor.withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // === 回転するダイアログ部分（N, E, S, W + ターゲット）===
                // ワールドロック: 方位磁針の文字盤とターゲットを世界の方角に固定
                Transform.rotate(
                  angle: -trueHeading * (math.pi / 180),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // 背景の目盛り（オプション: 必要ならここに追加）
                      
                      // 方位マーカー（N, E, S, W）
                      _buildCardinalMarkers(stateColor),
                      
                      // 目的地インジケーター（リング上のターゲット）
                      if (widget.safeBearing != null)
                        Transform.rotate(
                          angle: widget.safeBearing! * (math.pi / 180),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              margin: const EdgeInsets.only(top: 1),
                              width: 24, // 少し大きく
                              height: 24,
                              decoration: BoxDecoration(
                                color: const Color(0xFF34C759), // Safety Green
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 3.0),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF34C759).withValues(alpha: 0.8),
                                    blurRadius: 15,
                                    spreadRadius: 4,
                                  ),
                                  const BoxShadow(
                                    color: Colors.black26,
                                    blurRadius: 4,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Icon(
                                  Icons.keyboard_arrow_down,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // 固定されたコンパス針（常にスマホの先端を指す）
                _buildCompassNeedle(stateColor),
                
                // 中央のドット（ハプティック・ターゲット）
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: stateColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: stateColor.withValues(alpha: 0.5),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                ),
                
                // 状態インジケーター（画面側のインジケーターと重複するためコメントアウトまたは削除）
                /*
                Positioned(
                  bottom: 20,
                  child: _buildStateIndicator(state),
                ),
                */
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCardinalMarkers(Color accentColor) {
    const markers = ['N', 'E', 'S', 'W'];
    return Stack(
      alignment: Alignment.center,
      children: List.generate(4, (index) {
        final angle = index * 90.0;
        final isNorth = index == 0;
        return Transform.rotate(
          angle: angle * (math.pi / 180),
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 15),
              child: Text(
                markers[index],
                style: TextStyle(
                  fontSize: isNorth ? 24 : 18,
                  fontWeight: FontWeight.bold,
                  color: isNorth ? accentColor : Colors.white.withValues(alpha: 0.7), // グレーから白系へ（視認性向上）
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCompassNeedle(Color accentColor) {
    return SizedBox(
      width: widget.size * 0.8,
      height: widget.size * 0.8,
      child: CustomPaint(
        painter: _NeedlePainter(accentColor: accentColor),
      ),
    );
  }

  /*
  Widget _buildStateIndicator(CompassState state) {
    IconData icon;
    String label;
    Color color = _getStateColor(state);
    
    switch (state) {
      case CompassState.safe:
        icon = Icons.check_circle;
        label = 'SAFE';
        break;
      case CompassState.danger:
        icon = Icons.warning;
        label = 'DANGER';
        break;
      case CompassState.neutral:
        icon = Icons.explore;
        label = 'NAVIGATE';
        break;
    }
    
    return AnimatedContainer(
      duration: widget.animationDuration,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 14,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
  */
}

/// コンパスの状態
enum CompassState {
  safe,    // 避難所方向
  danger,  // 危険方向
  neutral, // その他
}

/// コンパス針のペインター
class _NeedlePainter extends CustomPainter {
  final Color accentColor;
  
  _NeedlePainter({required this.accentColor});
  
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final needleLength = size.height * 0.45; // 少し長めに
    
    // 1. ガイダンス・ビーム（背後の光るライン）
    final beamPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
      
    canvas.drawLine(
      Offset(center.dx, center.dy),
      Offset(center.dx, center.dy - needleLength),
      beamPaint,
    );

    // 2. 前方向を指すメインの針（スマホの先端を指す）
    final mainNeedlePaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;
    
    final path = Path()
      ..moveTo(center.dx, center.dy - needleLength) // 先端
      ..lineTo(center.dx - 10, center.dy - needleLength + 25)
      ..lineTo(center.dx - 3, center.dy - 10)
      ..lineTo(center.dx + 3, center.dy - 10)
      ..lineTo(center.dx + 10, center.dy - needleLength + 25)
      ..close();
    
    // 針のドロップシャドウ
    canvas.drawShadow(path, Colors.black, 4, true);
    canvas.drawPath(path, mainNeedlePaint);
    
    // 3. 針の先端に「進行方向」を示す矢印を追加
    final tipPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final tipPath = Path()
      ..moveTo(center.dx - 6, center.dy - needleLength + 12)
      ..lineTo(center.dx, center.dy - needleLength + 5)
      ..lineTo(center.dx + 6, center.dy - needleLength + 12);

    canvas.drawPath(tipPath, tipPaint);
  }
  
  @override
  bool shouldRepaint(covariant _NeedlePainter oldDelegate) {
    return oldDelegate.accentColor != accentColor;
  }
}

/// ============================================================================
/// 使用例
/// ============================================================================
/// 
/// // 日本モード（大崎市）
/// SmartCompass(
///   heading: sensorHeading,
///   safeBearing: 45.0,  // 避難所は北東
///   dangerBearings: [120.0, 200.0],  // ブロック塀の方角
///   magneticDeclination: -8.5,  // 日本の磁気偏角
/// )
/// 
/// // タイモード（サトゥン）
/// SmartCompass(
///   heading: sensorHeading,
///   safeBearing: 180.0,  // 避難所は南
///   dangerBearings: [90.0],  // 浸水エリアの方角
///   magneticDeclination: -0.6,  // タイの磁気偏角
/// )
/// ============================================================================
