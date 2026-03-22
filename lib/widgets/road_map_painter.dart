// ============================================================
// road_map_painter.dart
// 現在位置中心・デバイス向き回転の道路ミニマップ描画
// ============================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' hide Path;

import '../ble/ble_repository.dart';
import '../ble/road_score.dart';
import '../models/road_feature.dart';

// ────────────────────────────────────────
// 描画定数
// ────────────────────────────────────────
const double _kRadiusMeters = 500.0; // 表示半径
const double _kWideRoadThresh = 6.0; // 二重線になる幅員閾値 (m)
const double _kDoubleLineGap = 3.0; // 二重線の間隔 (logical px)
const double _kWideLineWidth = 2.0; // 太い道の1本線の幅
const double _kNarrowLineWidth = 1.5; // 細い道の1本線の幅
const Color _kBgColor = Color(0xFF111111);
const Color _kWideRoadColor = Color(0xFF3B6FE0);   // 青（幅≥6m）
const Color _kNarrowRoadColor = Color(0xFF888888); // グレー（幅<6m）
const Color _kCurrentLocColor = Color(0xFFFF4444); // 赤（現在地マーカー）
const Color _kImpassableColor = Color(0xFFE53935); // 赤（通行不可）
const Color _kCautionColor    = Color(0xFFFF6F00); // オレンジ（要注意）
const Color _kSafeColor       = Color(0xFF43A047); // 緑（安全確認済み）

// ────────────────────────────────────────
// 座標変換ヘルパー
// ────────────────────────────────────────

/// 緯度経度 → キャンバス上の (x, y) に変換する。
/// [center] が描画領域の中央に来るように正規化し、
/// [headingDeg] だけ回転させる（北上 → デバイス向き）。
Offset _toCanvas(
  LatLng point,
  LatLng center,
  double metersPerPixel,
  double headingRad,
  Offset canvasCenter,
) {
  const latMeters = 111320.0; // 緯度1度あたりのm
  final lngMeters =
      latMeters * math.cos(center.latitude * math.pi / 180);

  final dy = (point.latitude - center.latitude) * latMeters;
  final dx = (point.longitude - center.longitude) * lngMeters;

  // 北上座標 → ピクセル (Y軸は画面下向きなので dy を反転)
  final px = dx / metersPerPixel;
  final py = -dy / metersPerPixel;

  // デバイス向き分だけ回転（headingRad: 北=0, 時計回り正）
  final cosH = math.cos(-headingRad);
  final sinH = math.sin(-headingRad);
  final rx = px * cosH - py * sinH;
  final ry = px * sinH + py * cosH;

  return canvasCenter + Offset(rx, ry);
}

// ────────────────────────────────────────
// CustomPainter
// ────────────────────────────────────────

class RoadMapPainter extends CustomPainter {
  final List<RoadFeature> roads;
  final LatLng currentLocation;

  /// デバイスの向き（度、北=0、時計回り）
  final double headingDeg;

  /// BLE 受信報告（null なら危険描画なし）
  final List<ReceivedReport>? bleReports;

  const RoadMapPainter({
    required this.roads,
    required this.currentLocation,
    this.headingDeg = 0,
    this.bleReports,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final metersPerPixel = _kRadiusMeters / radius;
    final headingRad = headingDeg * math.pi / 180;

    // ── 背景：黒い円 ──────────────────────────────────────────────────────
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: center, radius: radius)));
    canvas.drawRect(Offset.zero & size, Paint()..color = _kBgColor);

    // ── 道路描画 ──────────────────────────────────────────────────────────
    for (final road in roads) {
      if (road.geometry.length < 2) continue;

      // 現在地から500m以内に少なくとも1点あるか簡易フィルタ
      bool inRange = false;
      const dist = Distance();
      for (final p in road.geometry) {
        if (dist(currentLocation, p) <= _kRadiusMeters * 1.5) {
          inRange = true;
          break;
        }
      }
      if (!inRange) continue;

      // キャンバス座標に変換
      final pts = road.geometry
          .map((p) => _toCanvas(p, currentLocation, metersPerPixel, headingRad, center))
          .toList();

      // BLE スコアで色を決定
      final midpoint = road.geometry[road.geometry.length ~/ 2];
      final scoreResult = bleReports != null
          ? RoadScoreCalculator.calculate(bleReports!, midpoint)
          : null;

      Color color;
      double opacity = 1.0;

      if (scoreResult != null && scoreResult.reportCount > 0) {
        // 受信時刻ベースの不透明度（30分超なら50%）
        final ageSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000 -
            (bleReports!.isNotEmpty ? bleReports!.last.receivedAt : 0);
        if (ageSeconds > 30 * 60) opacity = 0.5;

        if (scoreResult.isImpassable) {
          color = _kImpassableColor.withValues(alpha: opacity);
        } else if (scoreResult.isCaution) {
          color = _kCautionColor.withValues(alpha: opacity);
        } else if (scoreResult.isSafe) {
          color = _kSafeColor.withValues(alpha: opacity);
        } else {
          final isWide = (road.widthMeters ?? 0) >= _kWideRoadThresh;
          color = isWide ? _kWideRoadColor : _kNarrowRoadColor;
        }
      } else {
        final isWide = (road.widthMeters ?? 0) >= _kWideRoadThresh;
        color = isWide ? _kWideRoadColor : _kNarrowRoadColor;
      }

      final isWide = (road.widthMeters ?? 0) >= _kWideRoadThresh;
      if (isWide) {
        _drawDoubleLine(canvas, pts, color, _kWideLineWidth, _kDoubleLineGap);
      } else {
        _drawDoubleLine(canvas, pts, color, _kNarrowLineWidth, _kDoubleLineGap * 0.6);
      }

      // BLE ラベル描画
      if (scoreResult != null && scoreResult.reportCount > 0 && pts.isNotEmpty) {
        final labelPt = pts[pts.length ~/ 2];
        _drawSegmentLabel(canvas, labelPt, scoreResult);
      }
    }

    // ── 現在地マーカー（中央の点） ────────────────────────────────────────
    canvas.drawCircle(
      center,
      6,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      center,
      4,
      Paint()
        ..color = _kCurrentLocColor
        ..style = PaintingStyle.fill,
    );

    canvas.restore();
  }

  /// 二重線（平行2本）を描く
  void _drawDoubleLine(
    Canvas canvas,
    List<Offset> pts,
    Color color,
    double lineWidth,
    double gap,
  ) {
    final half = gap / 2;
    final paint = Paint()
      ..color = color
      ..strokeWidth = lineWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final sign in [-1.0, 1.0]) {
      final path = Path();
      for (int i = 0; i < pts.length; i++) {
        Offset p = pts[i];
        if (pts.length > 1) {
          // セグメント方向に直交するオフセットを加算
          final next = i < pts.length - 1 ? pts[i + 1] : pts[i];
          final prev = i > 0 ? pts[i - 1] : pts[i];
          final dir = next - prev;
          final len = dir.distance;
          if (len > 0) {
            final norm = Offset(-dir.dy, dir.dx) / len;
            p = p + norm * (sign * half);
          }
        }
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  /// セグメントラベル（通行不可 / 要注意 / 自動検知）を描画する
  void _drawSegmentLabel(Canvas canvas, Offset pos, RoadScoreResult result) {
    String text;
    Color bg;
    if (result.isImpassable) {
      text = result.hasAutoDetected ? '通行不可(自動検知)' : '通行不可';
      bg = _kImpassableColor;
    } else if (result.isCaution) {
      text = result.hasAutoDetected ? '要注意(自動検知)' : '要注意';
      bg = _kCautionColor;
    } else {
      return; // 安全・中立はラベル不要
    }

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          fontFamily: 'NotoSansJP',
          fontFamilyFallback: [
            'NotoSansSC', 'NotoSansTC', 'NotoSansKR',
            'NotoSansThai', 'NotoSansMyanmar', 'NotoSansSinhala',
            'NotoSansDevanagari', 'NotoSansBengali', 'NotoSans', 'sans-serif',
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 2);
    final rect = Rect.fromLTWH(
      pos.dx - tp.width / 2 - padding.horizontal / 2,
      pos.dy - tp.height - 10,
      tp.width + padding.horizontal,
      tp.height + padding.vertical,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = bg.withValues(alpha: 0.85),
    );
    tp.paint(canvas, Offset(rect.left + padding.left, rect.top + padding.top));
  }

  @override
  bool shouldRepaint(covariant RoadMapPainter old) =>
      old.currentLocation != currentLocation ||
      old.headingDeg != headingDeg ||
      !identical(old.roads, roads) ||
      !identical(old.bleReports, bleReports);
}

// ────────────────────────────────────────
// 使いやすいウィジェット
// ────────────────────────────────────────

class RoadMiniMap extends StatelessWidget {
  final List<RoadFeature> roads;
  final LatLng currentLocation;
  final double headingDeg;
  final double size;

  const RoadMiniMap({
    super.key,
    required this.roads,
    required this.currentLocation,
    this.headingDeg = 0,
    this.size = 200,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: RoadMapPainter(
          roads: roads,
          currentLocation: currentLocation,
          headingDeg: headingDeg,
        ),
      ),
    );
  }
}
