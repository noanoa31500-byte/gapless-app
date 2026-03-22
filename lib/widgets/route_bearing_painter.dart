import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;

// ============================================================================
// RouteBearingPainter — 経路ポリライン＋方位線をリアルタイム回転描画
// ============================================================================
//
// 【座標系】
//  画面中心 = 現在地。経路の各点を _toOffset() で相対ピクセルに変換し、
//  heading の分だけ全体を回転させて描画する。
//  方位線は画面中心から上方向（進行方向）に伸びる矢印。
//
// ============================================================================

/// 1メートルを何ピクセルに対応させるか（ズームレベル相当）
const double _metersPerPixel = 1.5;

class RouteBearingPainter extends CustomPainter {
  /// 現在地（マップ中心）
  final ll.LatLng currentPosition;

  /// 表示する経路ウェイポイント列
  final List<ll.LatLng> waypoints;

  /// フュージョン後の確定方位 [0, 360)
  final double headingDeg;

  /// 次のウェイポイントインデックス
  final int currentWaypointIndex;

  const RouteBearingPainter({
    required this.currentPosition,
    required this.waypoints,
    required this.headingDeg,
    this.currentWaypointIndex = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final headingRad = headingDeg * math.pi / 180;

    // キャンバスを heading 分回転（北が上 → 進行方向が上）
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-headingRad);

    _drawRoute(canvas);
    _drawBearingArrow(canvas);

    canvas.restore();

    // 現在地マーカー（回転なし、常に中央）
    _drawCurrentPositionMarker(canvas, center);
  }

  // ── 経路ポリライン ─────────────────────────────────────────────────────────

  void _drawRoute(Canvas canvas) {
    if (waypoints.length < 2) return;

    final passedPaint = Paint()
      ..color = const Color(0xFF9E9E9E)
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final remainPaint = Paint()
      ..color = const Color(0xFF2E7D32)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final passedPath = Path();
    final remainPath = Path();

    for (int i = 0; i < waypoints.length - 1; i++) {
      final from = _toOffset(waypoints[i]);
      final to = _toOffset(waypoints[i + 1]);

      if (i < currentWaypointIndex) {
        if (i == 0) {
          passedPath.moveTo(from.dx, from.dy);
        }
        passedPath.lineTo(to.dx, to.dy);
      } else {
        if (i == currentWaypointIndex) {
          remainPath.moveTo(from.dx, from.dy);
        }
        remainPath.lineTo(to.dx, to.dy);
      }
    }

    canvas.drawPath(passedPath, passedPaint);
    canvas.drawPath(remainPath, remainPaint);

    // ウェイポイントドット
    final dotPaint = Paint()
      ..color = const Color(0xFFFF6F00)
      ..style = PaintingStyle.fill;

    for (int i = currentWaypointIndex; i < waypoints.length; i++) {
      final r = i == waypoints.length - 1 ? 8.0 : 5.0;
      canvas.drawCircle(_toOffset(waypoints[i]), r, dotPaint);
    }
  }

  // ── 方位矢印 ──────────────────────────────────────────────────────────────

  void _drawBearingArrow(Canvas canvas) {
    const arrowLength = 60.0;
    const arrowHeadSize = 14.0;

    final linePaint = Paint()
      ..color = const Color(0xFFFF6F00)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    final headPaint = Paint()
      ..color = const Color(0xFFFF6F00)
      ..style = PaintingStyle.fill;

    // 上方向（y 軸負方向）= 進行方向
    const tip = Offset(0, -arrowLength);
    canvas.drawLine(Offset.zero, tip, linePaint);

    // 矢頭
    final arrowHead = Path()
      ..moveTo(0, -arrowLength)
      ..lineTo(-arrowHeadSize / 2, -arrowLength + arrowHeadSize)
      ..lineTo(arrowHeadSize / 2, -arrowLength + arrowHeadSize)
      ..close();
    canvas.drawPath(arrowHead, headPaint);
  }

  // ── 現在地マーカー ────────────────────────────────────────────────────────

  void _drawCurrentPositionMarker(Canvas canvas, Offset center) {
    canvas.drawCircle(center, 28,
        Paint()..color = const Color(0x332E7D32));
    canvas.drawCircle(center, 14,
        Paint()..color = Colors.white);
    canvas.drawCircle(center, 10,
        Paint()..color = const Color(0xFF2E7D32));
  }

  // ── 座標変換 ──────────────────────────────────────────────────────────────

  /// ll.LatLng → 現在地を原点とした相対ピクセル Offset
  Offset _toOffset(ll.LatLng point) {
    final dist = ll.Distance();

    final northM = dist(
      currentPosition,
      ll.LatLng(point.latitude, currentPosition.longitude),
    ) * (point.latitude > currentPosition.latitude ? 1 : -1);

    final eastM = dist(
      currentPosition,
      ll.LatLng(currentPosition.latitude, point.longitude),
    ) * (point.longitude > currentPosition.longitude ? 1 : -1);

    return Offset(
      eastM / _metersPerPixel,
      -northM / _metersPerPixel,
    );
  }

  @override
  bool shouldRepaint(RouteBearingPainter old) =>
      old.headingDeg != headingDeg ||
      old.currentPosition != currentPosition ||
      old.currentWaypointIndex != currentWaypointIndex ||
      old.waypoints != waypoints;
}

// ============================================================================
// RouteBearingView — RouteBearingPainter を包む Widget
// ============================================================================

class RouteBearingView extends StatelessWidget {
  final ll.LatLng currentPosition;
  final List<ll.LatLng> waypoints;
  final double headingDeg;
  final int currentWaypointIndex;

  /// オーバーレイとして重ねる子 Widget（UI ボタン等）
  final Widget? child;

  const RouteBearingView({
    super.key,
    required this.currentPosition,
    required this.waypoints,
    required this.headingDeg,
    this.currentWaypointIndex = 0,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CustomPaint(
          painter: RouteBearingPainter(
            currentPosition: currentPosition,
            waypoints: waypoints,
            headingDeg: headingDeg,
            currentWaypointIndex: currentWaypointIndex,
          ),
          child: const SizedBox.expand(),
        ),
        if (child != null) child!,
      ],
    );
  }
}
