import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import '../providers/compass_provider.dart';
import '../services/waypoint_magnet_manager.dart';
import '../utils/localization.dart';

/// ============================================================================
/// SafetyCompassView - Turn-by-Turn誘導型コンパスウィジェット
/// ============================================================================
/// 
/// 【設計思想】
/// 「地図が読めないパニック状態でも、矢印の方向へ進むだけで助かる」
/// 
/// - 巨大な矢印で視認性確保
/// - ルート逸脱時は赤色で警告
/// - 残り距離をシンプルに表示
/// - 到着時は緑色でフィードバック
/// ============================================================================
class SafetyCompassView extends StatelessWidget {
  final double size;
  final LatLng? userLocation;
  final LatLng? targetLocation;
  final VoidCallback? onArrived;
  
  const SafetyCompassView({
    super.key,
    this.size = 280,
    this.userLocation,
    this.targetLocation,
    this.onArrived,
  });
  
  @override
  Widget build(BuildContext context) {
    return Consumer<CompassProvider>(
      builder: (context, compass, _) {
        // ナビゲーション状態に応じた色を決定
        final stateColor = _getStateColor(compass.navigationState);
        
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
             // ナビゲーションステータス
            _buildStatusBadge(compass, stateColor),
            const SizedBox(height: 16),
            
            // コンパス本体
            _buildCompass(compass, stateColor),
            
            const SizedBox(height: 16),
            
            // 距離情報
            if (compass.isNavigating)
              _buildDistanceInfo(compass),
          ],
        );
      },
    );
  }
  
  /// ステータスバッジ
  Widget _buildStatusBadge(CompassProvider compass, Color color) {
    final message = compass.getNavigationMessage(GapLessL10n.lang);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _getStateIcon(compass.navigationState),
            color: color,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            message,
            style: GapLessL10n.safeStyle(TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            )),
          ),
        ],
      ),
    );
  }
  
  /// コンパス本体
  Widget _buildCompass(CompassProvider compass, Color stateColor) {
    // 表示角度を計算
    double displayAngle = 0.0;
    
    if (userLocation != null && targetLocation != null) {
      displayAngle = compass.getDisplayAngle(
        userLat: userLocation!.latitude,
        userLng: userLocation!.longitude,
        targetLat: targetLocation!.latitude,
        targetLng: targetLocation!.longitude
      );
    } else if (compass.isNavigating) {
      displayAngle = compass.magnetResult?.displayAngle ?? 0.0;
    }
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: stateColor.withValues(alpha: 0.2),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
        border: Border.all(
          color: stateColor.withValues(alpha: 0.3),
          width: 4,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 外周の方角マーカー
          _buildDirectionMarkers(),
          
          // 中心の円
          Container(
            width: size * 0.3,
            height: size * 0.3,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: stateColor.withValues(alpha: 0.1),
              border: Border.all(
                color: stateColor.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
          ),
          
          // ナビゲーション矢印（ターゲット方向を指す）
          AnimatedRotation(
            turns: displayAngle / (2 * math.pi),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: _buildNavigationArrow(stateColor),
          ),
        ],
      ),
    );
  }
  
  /// 方角マーカー
  Widget _buildDirectionMarkers() {
    return Stack(
      alignment: Alignment.center,
      children: [
        // 北
        Positioned(
          top: 12,
          child: Text(
            'N',
            style: TextStyle(
              color: Colors.red.shade700,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
        ),
        // 東
        Positioned(
          right: 12,
          child: Text(
            'E',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
              fontSize: 16,
            ),
          ),
        ),
        // 南
        Positioned(
          bottom: 12,
          child: Text(
            'S',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
              fontSize: 16,
            ),
          ),
        ),
        // 西
        Positioned(
          left: 12,
          child: Text(
            'W',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
              fontSize: 16,
            ),
          ),
        ),
      ],
    );
  }
  
  /// ナビゲーション矢印
  Widget _buildNavigationArrow(Color color) {
    final arrowSize = size * 0.6;
    
    return SizedBox(
      width: arrowSize,
      height: arrowSize,
      child: CustomPaint(
        painter: _ArrowPainter(color: color),
      ),
    );
  }
  
  /// 距離情報
  Widget _buildDistanceInfo(CompassProvider compass) {
    final distance = compass.magnetResult?.distanceToTarget ?? 0.0;
    final remaining = compass.magnetResult?.remainingDistance ?? 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 残り距離
          Column(
            children: [
              Text(
                _formatDistance(distance),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              Text(
                _getDistanceLabel(),
                style: GapLessL10n.safeStyle(TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                )),
              ),
            ],
          ),
          
          if (remaining > distance) ...[
            const SizedBox(width: 32),
            Container(
              width: 1,
              height: 40,
              color: Colors.grey.shade300,
            ),
            const SizedBox(width: 32),
            
            // 総距離
            Column(
              children: [
                Text(
                  _formatDistance(remaining),
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF6B7280),
                  ),
                ),
                Text(
                  _getTotalLabel(),
                  style: GapLessL10n.safeStyle(TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  )),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
  
  Color _getStateColor(NavigationState state) {
    switch (state) {
      case NavigationState.onRoute:
        return const Color(0xFF007AFF); // Apple Blue
      case NavigationState.offRoute:
        return const Color(0xFFFF3B30); // Apple Red
      case NavigationState.approaching:
        return const Color(0xFFFF9500); // Apple Orange
      case NavigationState.arrived:
        return const Color(0xFF34C759); // Apple Green
      case NavigationState.idle:
        return const Color(0xFF8E8E93); // Apple Gray
    }
  }
  
  IconData _getStateIcon(NavigationState state) {
    switch (state) {
      case NavigationState.onRoute:
        return Icons.navigation_rounded;
      case NavigationState.offRoute:
        return Icons.warning_rounded;
      case NavigationState.approaching:
        return Icons.flag_rounded;
      case NavigationState.arrived:
        return Icons.check_circle_rounded;
      case NavigationState.idle:
        return Icons.location_searching_rounded;
    }
  }
  
  String _formatDistance(double meters) {
    if (meters >= 1000) {
      return '${(meters / 1000).toStringAsFixed(1)}km';
    }
    return '${meters.round()}m';
  }
  
  String _getDistanceLabel() {
    switch (GapLessL10n.lang) {
      case 'ja':
        return '次のポイントまで';
      case 'th':
        return 'ถึงจุดถัดไป';
      default:
        return 'to next point';
    }
  }
  
  String _getTotalLabel() {
    switch (GapLessL10n.lang) {
      case 'ja':
        return '総距離';
      case 'th':
        return 'ระยะทางทั้งหมด';
      default:
        return 'total';
    }
  }
}

/// 矢印を描画するカスタムペインター
class _ArrowPainter extends CustomPainter {
  final Color color;
  
  _ArrowPainter({required this.color});
  
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    
    final path = ui.Path();
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    
    // 矢印の形状（上向き）
    final arrowWidth = size.width * 0.4;
    final arrowHeight = size.height * 0.8;
    final tailWidth = size.width * 0.15;
    final tailHeight = size.height * 0.3;
    
    // 上部の三角形
    path.moveTo(centerX, centerY - arrowHeight / 2);
    path.lineTo(centerX - arrowWidth / 2, centerY);
    path.lineTo(centerX - tailWidth / 2, centerY);
    path.lineTo(centerX - tailWidth / 2, centerY + arrowHeight / 2 - tailHeight);
    path.lineTo(centerX + tailWidth / 2, centerY + arrowHeight / 2 - tailHeight);
    path.lineTo(centerX + tailWidth / 2, centerY);
    path.lineTo(centerX + arrowWidth / 2, centerY);
    path.close();
    
    // 影
    canvas.drawPath(
      path.shift(const Offset(2, 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.1)
        ..style = PaintingStyle.fill,
    );
    
    // 本体
    canvas.drawPath(path, paint);
    
    // ハイライト
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawPath(path, highlightPaint);
  }
  
  @override
  bool shouldRepaint(covariant _ArrowPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
