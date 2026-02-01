import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/risk_radar_scanner.dart';
import '../services/offline_risk_scanner.dart';

/// ============================================================================
/// RiskRadarCompassWidget - リスクレーダー付きコンパスウィジェット
/// ============================================================================
/// 
/// 【設計思想】
/// 「画面の赤い方向・雷の方向さえ避ければ生き残れる」
/// という直感的なUIを提供します。
/// 
/// 【色コード】
/// - 黄色 ⚡ = 感電危険（送電線、電力設備）
/// - 青色 🌊 = 浸水危険（水深0.5m以上）
/// - 紫色 💨 = 激流危険（流速が速い）
/// - 緑色 ✅ = 安全方向（推奨進行方向）
/// ============================================================================

class RiskRadarCompassWidget extends StatefulWidget {
  /// レーダースキャン結果
  final RadarScanResult? scanResult;
  
  /// 端末の向き（真北基準、度）
  final double deviceHeading;
  
  /// ターゲット方位（ウェイポイントへの方向）
  final double? targetBearing;
  
  /// コンパスのサイズ
  final double size;
  
  /// 言語設定
  final String lang;
  
  /// スキャン中かどうか
  final bool isScanning;
  
  /// タップコールバック
  final VoidCallback? onTap;

  const RiskRadarCompassWidget({
    super.key,
    required this.scanResult,
    required this.deviceHeading,
    this.targetBearing,
    this.size = 300,
    this.lang = 'ja',
    this.isScanning = false,
    this.onTap,
  });

  @override
  State<RiskRadarCompassWidget> createState() => _RiskRadarCompassWidgetState();
}

class _RiskRadarCompassWidgetState extends State<RiskRadarCompassWidget>
    with TickerProviderStateMixin {
  // パルスアニメーション（危険ゾーンの点滅）
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  
  // レーダースイープアニメーション
  late AnimationController _sweepController;
  late Animation<double> _sweepAnimation;
  
  // 安全矢印の点滅アニメーション
  late AnimationController _arrowBlinkController;
  late Animation<double> _arrowBlinkAnimation;

  @override
  void initState() {
    super.initState();
    
    // パルスアニメーション（危険ゾーンの呼吸エフェクト）
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // レーダースイープアニメーション
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    
    _sweepAnimation = Tween<double>(begin: 0.0, end: 2 * math.pi).animate(
      CurvedAnimation(parent: _sweepController, curve: Curves.linear),
    );
    
    // 安全矢印の点滅アニメーション
    _arrowBlinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    
    _arrowBlinkAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _arrowBlinkController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _sweepController.dispose();
    _arrowBlinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: AnimatedBuilder(
          animation: Listenable.merge([
            _pulseAnimation,
            _sweepAnimation,
            _arrowBlinkAnimation,
          ]),
          builder: (context, child) {
            return Stack(
              alignment: Alignment.center,
              children: [
                // レイヤー1: 背景とグリッド
                _buildBackground(),
                
                // レイヤー2: レーダースイープ（スキャン中のみ）
                if (widget.isScanning) _buildRadarSweep(),
                
                // レイヤー3: 危険ゾーン
                if (widget.scanResult != null) _buildDangerZones(),
                
                // レイヤー4: 方位目盛り
                _buildCompassMarkers(),
                
                // レイヤー5: 安全方向の矢印
                if (_shouldShowSafetyArrow) _buildSafetyArrow(),
                
                // レイヤー6: 中央インジケーター
                _buildCenterIndicator(),
                
                // レイヤー7: リスクバッジ
                if (widget.scanResult != null && 
                    widget.scanResult!.overallRiskLevel > 0.2)
                  _buildRiskBadge(),
                  
                // レイヤー8: 補正ガイダンス
                if (widget.scanResult?.safetyGuidance?.needsCorrection == true)
                  _buildCorrectionGuidance(),
              ],
            );
          },
        ),
      ),
    );
  }

  bool get _shouldShowSafetyArrow =>
      widget.targetBearing != null || 
      widget.scanResult?.safetyGuidance != null;

  /// 背景とグリッド
  Widget _buildBackground() {
    return CustomPaint(
      size: Size(widget.size, widget.size),
      painter: _RadarBackgroundPainter(
        riskLevel: widget.scanResult?.overallRiskLevel ?? 0.0,
      ),
    );
  }

  /// レーダースイープ（スキャン中エフェクト）
  Widget _buildRadarSweep() {
    return Transform.rotate(
      angle: _sweepAnimation.value,
      child: CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _RadarSweepPainter(
          sweepAngle: math.pi / 3,
        ),
      ),
    );
  }

  /// 危険ゾーン
  Widget _buildDangerZones() {
    return CustomPaint(
      size: Size(widget.size, widget.size),
      painter: _DangerZonesPainter(
        dangerZones: widget.scanResult!.dangerZones,
        deviceHeading: widget.deviceHeading,
        pulseValue: _pulseAnimation.value,
      ),
    );
  }

  /// 方位目盛り
  Widget _buildCompassMarkers() {
    return Transform.rotate(
      angle: -widget.deviceHeading * math.pi / 180,
      child: CustomPaint(
        size: Size(widget.size, widget.size),
        painter: _CompassMarkersPainter(
          deviceHeading: widget.deviceHeading,
        ),
      ),
    );
  }

  /// 安全方向の矢印
  Widget _buildSafetyArrow() {
    final guidance = widget.scanResult?.safetyGuidance;
    final bearing = guidance?.recommendedBearing ?? widget.targetBearing!;
    final needsCorrection = guidance?.needsCorrection ?? false;
    
    // 端末の向きを考慮した相対角度
    final relativeBearing = (bearing - widget.deviceHeading + 360) % 360;
    
    // リスクがある場合はオレンジ、そうでなければ緑
    final hasRiskInDirection = widget.scanResult
        ?.getRisksAtBearing(bearing)
        .isNotEmpty ?? false;
    
    Color arrowColor;
    if (hasRiskInDirection) {
      arrowColor = Colors.orange;
    } else if (needsCorrection) {
      arrowColor = Colors.amber;
    } else {
      arrowColor = Colors.green;
    }
    
    return Transform.rotate(
      angle: relativeBearing * math.pi / 180,
      child: Container(
        width: widget.size,
        height: widget.size,
        alignment: Alignment.topCenter,
        padding: EdgeInsets.only(top: widget.size * 0.08),
        child: Opacity(
          opacity: _arrowBlinkAnimation.value,
          child: CustomPaint(
            size: Size(widget.size * 0.15, widget.size * 0.2),
            painter: _SafetyArrowPainter(
              color: arrowColor,
              needsCorrection: needsCorrection,
            ),
          ),
        ),
      ),
    );
  }

  /// 中央インジケーター
  Widget _buildCenterIndicator() {
    final riskLevel = widget.scanResult?.overallRiskLevel ?? 0.0;
    
    Color indicatorColor;
    if (riskLevel > 0.6) {
      indicatorColor = Colors.red;
    } else if (riskLevel > 0.3) {
      indicatorColor = Colors.orange;
    } else {
      indicatorColor = Colors.blue;
    }
    
    return Container(
      width: widget.size * 0.08,
      height: widget.size * 0.08,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: indicatorColor, width: 3),
        boxShadow: [
          BoxShadow(
            color: indicatorColor.withValues(alpha: 0.5),
            blurRadius: 15,
            spreadRadius: 3,
          ),
        ],
      ),
      child: Center(
        child: Container(
          width: widget.size * 0.04,
          height: widget.size * 0.04,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: indicatorColor,
          ),
        ),
      ),
    );
  }

  /// リスクバッジ
  Widget _buildRiskBadge() {
    final riskPercent = (widget.scanResult!.overallRiskLevel * 100).toInt();
    final isHighRisk = widget.scanResult!.overallRiskLevel > 0.6;
    
    return Positioned(
      top: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isHighRisk ? Colors.red : Colors.orange,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: (isHighRisk ? Colors.red : Colors.orange).withValues(alpha: 0.5),
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isHighRisk ? Icons.warning_rounded : Icons.error_outline,
              color: Colors.white,
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              _getRiskLevelText(riskPercent),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getRiskLevelText(int percent) {
    switch (widget.lang) {
      case 'ja':
        return '危険度 $percent%';
      case 'th':
        return 'ความเสี่ยง $percent%';
      default:
        return 'RISK $percent%';
    }
  }

  /// 補正ガイダンス
  Widget _buildCorrectionGuidance() {
    final guidance = widget.scanResult!.safetyGuidance!;
    
    return Positioned(
      bottom: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.amber.shade800,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          guidance.reason,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

/// ============================================================================
/// _RadarBackgroundPainter - レーダー背景描画
/// ============================================================================
class _RadarBackgroundPainter extends CustomPainter {
  final double riskLevel;

  _RadarBackgroundPainter({required this.riskLevel});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    
    // 背景グラデーション
    final bgPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          Color.lerp(Colors.grey.shade900, Colors.red.shade900, riskLevel * 0.5)!,
          Colors.black,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    
    canvas.drawCircle(center, radius, bgPaint);
    
    // 同心円グリッド
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    
    for (int i = 1; i <= 3; i++) {
      canvas.drawCircle(center, radius * i / 3, gridPaint);
    }
    
    // 十字線
    final crossPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.15)
      ..strokeWidth = 1;
    
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      crossPaint,
    );
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      crossPaint,
    );
    
    // 外枠
    final borderPaint = Paint()
      ..color = _getBorderColor()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    
    canvas.drawCircle(center, radius - 2, borderPaint);
  }

  Color _getBorderColor() {
    if (riskLevel > 0.6) return Colors.red;
    if (riskLevel > 0.3) return Colors.orange;
    return Colors.green;
  }

  @override
  bool shouldRepaint(covariant _RadarBackgroundPainter oldDelegate) =>
      oldDelegate.riskLevel != riskLevel;
}

/// ============================================================================
/// _RadarSweepPainter - レーダースイープ描画
/// ============================================================================
class _RadarSweepPainter extends CustomPainter {
  final double sweepAngle;

  _RadarSweepPainter({required this.sweepAngle});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: sweepAngle - math.pi / 2,
        colors: [
          Colors.green.withValues(alpha: 0.0),
          Colors.green.withValues(alpha: 0.3),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    
    final path = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweepAngle,
        false,
      )
      ..close();
    
    canvas.drawPath(path, sweepPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarSweepPainter oldDelegate) => true;
}

/// ============================================================================
/// _DangerZonesPainter - 危険ゾーン描画
/// ============================================================================
class _DangerZonesPainter extends CustomPainter {
  final List<DangerZone> dangerZones;
  final double deviceHeading;
  final double pulseValue;

  _DangerZonesPainter({
    required this.dangerZones,
    required this.deviceHeading,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2 - 5;
    
    for (final zone in dangerZones) {
      _drawDangerZone(canvas, center, outerRadius, zone);
    }
  }

  void _drawDangerZone(
    Canvas canvas,
    Offset center,
    double outerRadius,
    DangerZone zone,
  ) {
    // デバイスの向きを考慮した角度
    final startAngle = (zone.startBearing - deviceHeading - 90) * math.pi / 180;
    final endAngle = (zone.endBearing - deviceHeading - 90) * math.pi / 180;
    double sweepAngle = endAngle - startAngle;
    if (sweepAngle < 0) sweepAngle += 2 * math.pi;
    
    // リスクタイプに応じた色とアイコン
    Color baseColor;
    String icon;
    
    switch (zone.type) {
      case RiskType.electrocution:
        baseColor = Colors.yellow;
        icon = '⚡';
        break;
      case RiskType.deepWater:
        baseColor = Colors.blue;
        icon = '🌊';
        break;
      case RiskType.rapidFlow:
        baseColor = Colors.purple;
        icon = '💨';
        break;
    }
    
    // 重大度に応じた不透明度（パルスアニメーション付き）
    final opacity = (0.2 + zone.severity * 0.5) * pulseValue;
    
    // 扇形を描画
    final paint = Paint()
      ..color = baseColor.withValues(alpha: opacity)
      ..style = PaintingStyle.fill;
    
    final path = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: outerRadius),
        startAngle,
        sweepAngle,
        false,
      )
      ..lineTo(center.dx, center.dy)
      ..close();
    
    canvas.drawPath(path, paint);
    
    // 境界線
    final borderPaint = Paint()
      ..color = baseColor.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: outerRadius),
      startAngle,
      sweepAngle,
      false,
      borderPaint,
    );
    
    // アイコンを描画
    _drawIcon(canvas, center, outerRadius - 25, startAngle + sweepAngle / 2, icon);
  }

  void _drawIcon(Canvas canvas, Offset center, double radius, double angle, String icon) {
    final x = center.dx + math.cos(angle) * radius;
    final y = center.dy + math.sin(angle) * radius;
    
    final textPainter = TextPainter(
      text: TextSpan(
        text: icon,
        style: const TextStyle(fontSize: 22),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    
    textPainter.paint(
      canvas,
      Offset(x - textPainter.width / 2, y - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _DangerZonesPainter oldDelegate) =>
      oldDelegate.dangerZones != dangerZones ||
      oldDelegate.deviceHeading != deviceHeading ||
      oldDelegate.pulseValue != pulseValue;
}

/// ============================================================================
/// _CompassMarkersPainter - 方位目盛り描画
/// ============================================================================
class _CompassMarkersPainter extends CustomPainter {
  final double deviceHeading;

  _CompassMarkersPainter({required this.deviceHeading});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 15;
    
    // 主要方位（N/E/S/W）
    const cardinals = ['N', 'E', 'S', 'W'];
    const cardinalColors = [Colors.red, Colors.white70, Colors.white70, Colors.white70];
    
    for (int i = 0; i < 4; i++) {
      final angle = i * 90 * math.pi / 180 - math.pi / 2;
      final x = center.dx + math.cos(angle) * radius;
      final y = center.dy + math.sin(angle) * radius;
      
      // 回転補正
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(deviceHeading * math.pi / 180);
      
      final textPainter = TextPainter(
        text: TextSpan(
          text: cardinals[i],
          style: TextStyle(
            color: cardinalColors[i],
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2),
      );
      
      canvas.restore();
    }
    
    // 30度刻みの目盛り
    final tickPaint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1;
    
    for (int deg = 0; deg < 360; deg += 30) {
      if (deg % 90 == 0) continue;
      
      final angle = deg * math.pi / 180 - math.pi / 2;
      final innerRadius = radius - 8;
      
      canvas.drawLine(
        Offset(
          center.dx + math.cos(angle) * innerRadius,
          center.dy + math.sin(angle) * innerRadius,
        ),
        Offset(
          center.dx + math.cos(angle) * (radius + 2),
          center.dy + math.sin(angle) * (radius + 2),
        ),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CompassMarkersPainter oldDelegate) =>
      oldDelegate.deviceHeading != deviceHeading;
}

/// ============================================================================
/// _SafetyArrowPainter - 安全方向矢印描画
/// ============================================================================
class _SafetyArrowPainter extends CustomPainter {
  final Color color;
  final bool needsCorrection;

  _SafetyArrowPainter({
    required this.color,
    required this.needsCorrection,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    
    // 矢印の形状
    path.moveTo(size.width / 2, 0); // 先端
    path.lineTo(size.width, size.height * 0.7);
    path.lineTo(size.width / 2, size.height * 0.5);
    path.lineTo(0, size.height * 0.7);
    path.close();
    
    // グロー効果
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawPath(path, glowPaint);
    
    // 本体
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, paint);
    
    // 境界線
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(path, borderPaint);
    
    // 補正が必要な場合は警告マーク
    if (needsCorrection) {
      final textPainter = TextPainter(
        text: const TextSpan(
          text: '!',
          style: TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      
      textPainter.paint(
        canvas,
        Offset(
          size.width / 2 - textPainter.width / 2,
          size.height * 0.25,
        ),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SafetyArrowPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.needsCorrection != needsCorrection;
}

/// ============================================================================
/// RiskRadarCompassCard - カード形式のウィジェット
/// ============================================================================
class RiskRadarCompassCard extends StatelessWidget {
  final RadarScanResult? scanResult;
  final double deviceHeading;
  final double? targetBearing;
  final String lang;
  final bool isScanning;
  final VoidCallback? onTap;
  final VoidCallback? onScanPressed;

  const RiskRadarCompassCard({
    super.key,
    required this.scanResult,
    required this.deviceHeading,
    this.targetBearing,
    this.lang = 'ja',
    this.isScanning = false,
    this.onTap,
    this.onScanPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.grey.shade900,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ヘッダー
            _buildHeader(),
            
            const SizedBox(height: 12),
            
            // レーダーコンパス
            RiskRadarCompassWidget(
              scanResult: scanResult,
              deviceHeading: deviceHeading,
              targetBearing: targetBearing,
              size: 250,
              lang: lang,
              isScanning: isScanning,
              onTap: onTap,
            ),
            
            const SizedBox(height: 12),
            
            // 凡例
            _buildLegend(),
            
            // 警告メッセージ
            if (scanResult != null && scanResult!.dangerZones.isNotEmpty)
              _buildWarnings(),
              
            // スキャンボタン
            if (onScanPressed != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ElevatedButton.icon(
                  onPressed: isScanning ? null : onScanPressed,
                  icon: Icon(
                    isScanning ? Icons.radar : Icons.refresh,
                    size: 20,
                  ),
                  label: Text(_getScanButtonText()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isLoaded = scanResult != null;
    final riskLevel = scanResult?.overallRiskLevel ?? 0.0;
    
    return Row(
      children: [
        Icon(
          Icons.radar,
          color: _getStatusColor(riskLevel),
          size: 26,
        ),
        const SizedBox(width: 8),
        Text(
          _getTitle(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isLoaded
                ? Colors.green.withValues(alpha: 0.2)
                : Colors.orange.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            isLoaded ? 'READY' : 'LOADING',
            style: TextStyle(
              color: isLoaded ? Colors.green : Colors.orange,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(double riskLevel) {
    if (riskLevel > 0.6) return Colors.red;
    if (riskLevel > 0.3) return Colors.orange;
    return Colors.green;
  }

  String _getTitle() {
    switch (lang) {
      case 'ja':
        return 'リスクレーダー';
      case 'th':
        return 'เรดาร์ความเสี่ยง';
      default:
        return 'Risk Radar';
    }
  }

  Widget _buildLegend() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildLegendItem('⚡', Colors.yellow, _getLegendText('shock')),
        const SizedBox(width: 16),
        _buildLegendItem('🌊', Colors.blue, _getLegendText('flood')),
        const SizedBox(width: 16),
        _buildLegendItem('✅', Colors.green, _getLegendText('safe')),
      ],
    );
  }

  Widget _buildLegendItem(String icon, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(color: color, fontSize: 11),
        ),
      ],
    );
  }

  String _getLegendText(String key) {
    const texts = {
      'shock': {'ja': '感電', 'en': 'Shock', 'th': 'ไฟฟ้า'},
      'flood': {'ja': '浸水', 'en': 'Flood', 'th': 'น้ำท่วม'},
      'safe': {'ja': '安全', 'en': 'Safe', 'th': 'ปลอดภัย'},
    };
    return texts[key]?[lang] ?? texts[key]?['en'] ?? key;
  }

  Widget _buildWarnings() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final zone in scanResult!.dangerZones.take(3))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Text(
                      _getZoneIcon(zone.type),
                      style: const TextStyle(fontSize: 14),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _getWarningText(zone),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _getZoneIcon(RiskType type) {
    switch (type) {
      case RiskType.electrocution:
        return '⚡';
      case RiskType.deepWater:
        return '🌊';
      case RiskType.rapidFlow:
        return '💨';
    }
  }

  String _getWarningText(DangerZone zone) {
    final direction = '${zone.startBearing.toInt()}°-${zone.endBearing.toInt()}°';
    final distance = zone.distance.toInt();
    
    switch (lang) {
      case 'ja':
        return '${zone.name} ($direction方向, ${distance}m)';
      case 'th':
        return '${zone.name} ($direction, ${distance}m)';
      default:
        return '${zone.name} ($direction, ${distance}m)';
    }
  }

  String _getScanButtonText() {
    if (isScanning) {
      switch (lang) {
        case 'ja':
          return 'スキャン中...';
        case 'th':
          return 'กำลังสแกน...';
        default:
          return 'Scanning...';
      }
    }
    switch (lang) {
      case 'ja':
        return '再スキャン';
      case 'th':
        return 'สแกนอีกครั้ง';
      default:
        return 'Rescan';
    }
  }
}
