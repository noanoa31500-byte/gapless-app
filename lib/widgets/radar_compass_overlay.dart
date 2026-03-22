import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/offline_risk_scanner.dart';

/// ============================================================================
/// RadarCompassOverlay - リスクレーダー付きコンパスウィジェット
/// ============================================================================
/// 
/// 【設計思想】
/// 「画面の赤い方向・雷の方向さえ避ければ生き残れる」
/// と直感的に理解できるUIを目指しています。
/// 
/// 【なぜこの機能が洪水時に有効なのか】
/// 
/// 1. **泥水で視界が悪い**
///    洪水時の水は濁っており、足元の危険（深い穴、流されている物）が
///    見えません。本機能は、予測データを使って「見えない危険」を
///    レーダーのように可視化します。
/// 
/// 2. **感電死は「見えない死」**
///    水没した電柱・電線からの漏電は目視できません。
///    タイでは洪水時の感電死が深刻な問題です。
///    電力設備の位置データから危険方向を事前に警告します。
/// 
/// 3. **パニック時の認知負荷軽減**
///    災害時、人は複雑な判断ができません。
///    「黄色=感電」「青=深水」「緑=安全」という
///    色だけで判断できるUIにしています。
/// 
/// 4. **360度全方位の危険を一目で把握**
///    地図アプリでは「前方」しか見えませんが、
///    本機能は背後からの危険（追い流される激流など）も
///    同時に把握できます。
/// ============================================================================

class RadarCompassOverlay extends StatelessWidget {
  /// リスクスキャン結果
  final RiskScanResult? scanResult;
  
  /// 端末の向き（真北基準、度）
  final double deviceHeading;
  
  /// ターゲット方位（ウェイポイントへの方向）
  final double? targetBearing;
  
  /// コンパスのサイズ
  final double size;
  
  /// 言語設定
  final String lang;
  
  /// アニメーション用コントローラー（点滅効果）
  final Animation<double>? pulseAnimation;

  const RadarCompassOverlay({
    super.key,
    required this.scanResult,
    required this.deviceHeading,
    this.targetBearing,
    this.size = 300,
    this.lang = 'ja',
    this.pulseAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 背景円
          _buildBackgroundCircle(),
          
          // リスクゾーン（レーダー表示）
          if (scanResult != null) _buildRiskRadar(),
          
          // 方位目盛り
          _buildCompassMarkers(),
          
          // 安全方向の矢印
          if (targetBearing != null) _buildSafetyArrow(),
          
          // 中央の端末アイコン
          _buildDeviceIndicator(),
          
          // 警告バッジ
          if (scanResult != null && scanResult!.overallRisk > 0.3)
            _buildWarningBadge(),
        ],
      ),
    );
  }

  /// 背景円
  Widget _buildBackgroundCircle() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black87,
        border: Border.all(
          color: Colors.white24,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black45,
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
    );
  }

  /// リスクレーダー（危険ゾーンの扇形）
  Widget _buildRiskRadar() {
    return CustomPaint(
      size: Size(size, size),
      painter: _RiskRadarPainter(
        riskZones: scanResult!.riskZones,
        deviceHeading: deviceHeading,
        pulseValue: pulseAnimation?.value ?? 1.0,
      ),
    );
  }

  /// 方位目盛り
  Widget _buildCompassMarkers() {
    return Transform.rotate(
      angle: -deviceHeading * math.pi / 180,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // N/E/S/W マーカー
          ..._buildCardinalMarkers(),
          
          // 度数目盛り
          ..._buildDegreeMarkers(),
        ],
      ),
    );
  }

  List<Widget> _buildCardinalMarkers() {
    const cardinals = ['N', 'E', 'S', 'W'];
    const colors = [Colors.red, Colors.white70, Colors.white70, Colors.white70];
    
    return List.generate(4, (index) {
      final angle = index * 90 * math.pi / 180;
      final radius = size / 2 - 25;
      
      return Positioned(
        left: size / 2 + math.sin(angle) * radius - 12,
        top: size / 2 - math.cos(angle) * radius - 12,
        child: Transform.rotate(
          angle: deviceHeading * math.pi / 180,
          child: Text(
            cardinals[index],
            style: TextStyle(
              color: colors[index],
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    });
  }

  List<Widget> _buildDegreeMarkers() {
    final markers = <Widget>[];
    
    for (int i = 0; i < 360; i += 30) {
      if (i % 90 == 0) continue; // N/E/S/Wは別途描画
      
      final angle = i * math.pi / 180;
      final radius = size / 2 - 15;
      
      markers.add(
        Positioned(
          left: size / 2 + math.sin(angle) * radius - 10,
          top: size / 2 - math.cos(angle) * radius - 8,
          child: Transform.rotate(
            angle: deviceHeading * math.pi / 180,
            child: Text(
              '$i°',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 10,
              ),
            ),
          ),
        ),
      );
    }
    
    return markers;
  }

  /// 安全方向の矢印
  Widget _buildSafetyArrow() {
    final relativeBearing = (targetBearing! - deviceHeading + 360) % 360;
    
    // ターゲット方向にリスクがあるかチェック
    final hasRiskInTargetDirection = scanResult?.getRisksAtBearing(targetBearing!) ?? [];
    final isRisky = hasRiskInTargetDirection.isNotEmpty;
    
    return Transform.rotate(
      angle: relativeBearing * math.pi / 180,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.topCenter,
        padding: EdgeInsets.only(top: 30),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          child: Icon(
            Icons.navigation,
            size: 50,
            color: isRisky
                ? Colors.orange.withValues(alpha: 0.8)
                : Colors.green.withValues(alpha: 0.9),
            shadows: [
              Shadow(
                color: isRisky ? Colors.orange : Colors.green,
                blurRadius: 15,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 中央の端末インジケーター
  Widget _buildDeviceIndicator() {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: Colors.blue, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.5),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }

  /// 警告バッジ
  Widget _buildWarningBadge() {
    final riskPercent = (scanResult!.overallRisk * 100).toInt();
    final isHighRisk = scanResult!.overallRisk > 0.6;
    
    return Positioned(
      top: 10,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isHighRisk ? Colors.red : Colors.orange,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: isHighRisk ? Colors.red : Colors.orange,
              blurRadius: 10,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 4),
            Text(
              'RISK $riskPercent%',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ============================================================================
/// _RiskRadarPainter - リスクゾーンを描画するカスタムペインター
/// ============================================================================
class _RiskRadarPainter extends CustomPainter {
  final List<RiskZone> riskZones;
  final double deviceHeading;
  final double pulseValue;

  _RiskRadarPainter({
    required this.riskZones,
    required this.deviceHeading,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2 - 5;
    final innerRadius = outerRadius - 40;
    
    for (final zone in riskZones) {
      _drawRiskZone(canvas, center, outerRadius, innerRadius, zone);
    }
  }

  void _drawRiskZone(
    Canvas canvas,
    Offset center,
    double outerRadius,
    double innerRadius,
    RiskZone zone,
  ) {
    // デバイスの向きを考慮した角度（12時方向が上）
    final startAngle = (zone.startBearing - deviceHeading - 90) * math.pi / 180;
    final endAngle = (zone.endBearing - deviceHeading - 90) * math.pi / 180;
    double sweepAngle = endAngle - startAngle;
    if (sweepAngle < 0) sweepAngle += 2 * math.pi;
    
    // リスクタイプに応じた色
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
    
    // 重大度に応じた不透明度
    final opacity = 0.3 + zone.severity * 0.5 * pulseValue;
    
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
    _drawIcon(canvas, center, outerRadius - 20, startAngle + sweepAngle / 2, icon);
  }

  void _drawIcon(Canvas canvas, Offset center, double radius, double angle, String icon) {
    final x = center.dx + math.cos(angle) * radius;
    final y = center.dy + math.sin(angle) * radius;
    
    final textPainter = TextPainter(
      text: TextSpan(
        text: icon,
        style: const TextStyle(
          fontSize: 24,
          fontFamilyFallback: ['NotoSansJP', 'NotoSansThai', 'sans-serif'],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    
    textPainter.paint(
      canvas,
      Offset(x - textPainter.width / 2, y - textPainter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant _RiskRadarPainter oldDelegate) {
    return oldDelegate.riskZones != riskZones ||
        oldDelegate.deviceHeading != deviceHeading ||
        oldDelegate.pulseValue != pulseValue;
  }
}

/// ============================================================================
/// RadarCompassCard - カード形式のレーダーコンパス
/// ============================================================================
class RadarCompassCard extends StatefulWidget {
  final RiskScanResult? scanResult;
  final double deviceHeading;
  final double? targetBearing;
  final String lang;
  final VoidCallback? onTap;

  const RadarCompassCard({
    super.key,
    required this.scanResult,
    required this.deviceHeading,
    this.targetBearing,
    this.lang = 'ja',
    this.onTap,
  });

  @override
  State<RadarCompassCard> createState() => _RadarCompassCardState();
}

class _RadarCompassCardState extends State<RadarCompassCard>
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
    
    _pulseAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Card(
        color: Colors.grey[900],
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
              
              const SizedBox(height: 16),
              
              // レーダーコンパス
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return RadarCompassOverlay(
                    scanResult: widget.scanResult,
                    deviceHeading: widget.deviceHeading,
                    targetBearing: widget.targetBearing,
                    size: 250,
                    lang: widget.lang,
                    pulseAnimation: _pulseAnimation,
                  );
                },
              ),
              
              const SizedBox(height: 16),
              
              // 凡例
              _buildLegend(),
              
              // 警告メッセージ
              if (widget.scanResult != null && widget.scanResult!.riskZones.isNotEmpty)
                _buildWarningMessages(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isLoaded = widget.scanResult != null;
    
    return Row(
      children: [
        Icon(
          Icons.radar,
          color: isLoaded ? Colors.green : Colors.orange,
          size: 28,
        ),
        const SizedBox(width: 8),
        Text(
          _getTitle(),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        if (isLoaded)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'OFFLINE',
              style: TextStyle(
                color: Colors.green,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  String _getTitle() {
    switch (widget.lang) {
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
        _buildLegendItem('⚡', Colors.yellow, _getLegendText('electrocution')),
        const SizedBox(width: 24),
        _buildLegendItem('🌊', Colors.blue, _getLegendText('flood')),
        const SizedBox(width: 24),
        _buildLegendItem('➤', Colors.green, _getLegendText('safe')),
      ],
    );
  }

  Widget _buildLegendItem(String icon, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          icon,
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  String _getLegendText(String key) {
    const texts = {
      'electrocution': {'ja': '感電', 'en': 'Electric', 'th': 'ไฟฟ้า'},
      'flood': {'ja': '浸水', 'en': 'Flood', 'th': 'น้ำท่วม'},
      'safe': {'ja': '安全', 'en': 'Safe', 'th': 'ปลอดภัย'},
    };
    return texts[key]?[widget.lang] ?? texts[key]?['en'] ?? key;
  }

  Widget _buildWarningMessages() {
    final warnings = <String>[];
    
    for (final zone in widget.scanResult!.riskZones) {
      String warning;
      switch (widget.lang) {
        case 'ja':
          warning = zone.warningJa;
          break;
        case 'th':
          warning = zone.warningTh;
          break;
        default:
          warning = zone.warningEn;
      }
      if (!warnings.contains(warning)) {
        warnings.add(warning);
      }
    }
    
    if (warnings.isEmpty) return const SizedBox.shrink();
    
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
          children: warnings.take(3).map((w) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(
              w,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
              ),
            ),
          )).toList(),
        ),
      ),
    );
  }
}

/// ============================================================================
/// RadarCompassMini - ミニサイズのレーダーコンパス（マップ上表示用）
/// ============================================================================
class RadarCompassMini extends StatelessWidget {
  final RiskScanResult? scanResult;
  final double deviceHeading;
  final double? targetBearing;

  const RadarCompassMini({
    super.key,
    required this.scanResult,
    required this.deviceHeading,
    this.targetBearing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black87,
        border: Border.all(
          color: _getBorderColor(),
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: _getBorderColor().withValues(alpha: 0.5),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: RadarCompassOverlay(
        scanResult: scanResult,
        deviceHeading: deviceHeading,
        targetBearing: targetBearing,
        size: 74,
      ),
    );
  }

  Color _getBorderColor() {
    if (scanResult == null) return Colors.grey;
    if (scanResult!.overallRisk > 0.6) return Colors.red;
    if (scanResult!.overallRisk > 0.3) return Colors.orange;
    return Colors.green;
  }
}
