import 'dart:convert';
import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'ble_packet.dart';
import 'ble_repository.dart';

// ============================================================================
// RoadScore — BLE 報告に基づく道路安全スコア算出
// ============================================================================
//
// 【スコア値】
//   1.0 → 安全（通行可3件以上）
//   0.5 → 中立（報告なし）
//   0.3 → 要注意（危険報告2件以上）
//   0.0 → 通行不可（通行不可1件以上）
//
// 【鮮度重み（発生時刻 packet.timestamp 基準）】
//   0〜30分: 1.0
//   30分〜2時間: 0.5
//   2時間超: 除外
//
// 【信頼度重み】
//   手動報告 (confidence未設定): 1.0
//   自動検知 (confidence=0.6): 0.6
//
// 【集計判定】
//   各 dataType ごとに重み付きカウントを合計して閾値判定する。
//
// ============================================================================

class RoadScore {
  static const double safe       = 1.0;
  static const double neutral    = 0.5;
  static const double caution    = 0.3;
  static const double impassable = 0.0;
}

class RoadScoreResult {
  final double score;
  final int    reportCount;
  final bool   hasAutoDetected;

  const RoadScoreResult({
    required this.score,
    required this.reportCount,
    this.hasAutoDetected = false,
  });

  bool get isSafe       => score >= 1.0;
  bool get isCaution    => score <= 0.3 && score > 0.0;
  bool get isImpassable => score <= 0.0;
}

class RoadScoreCalculator {
  /// 判定に使う近接半径 (m)
  static const double nearbyRadiusM = 30.0;

  /// [allReports] から [midpoint] 半径30m以内の報告を集計し、スコアを返す
  static RoadScoreResult calculate(
    List<ReceivedReport> allReports,
    LatLng midpoint,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // 近傍フィルタ
    final nearby = allReports.where((r) {
      return _distM(
            r.packet.lat, r.packet.lng,
            midpoint.latitude, midpoint.longitude,
          ) <=
          nearbyRadiusM;
    }).toList();

    if (nearby.isEmpty) return const RoadScoreResult(score: RoadScore.neutral, reportCount: 0);

    // 鮮度 × 信頼度で重み付きカウントを集計
    double passableW   = 0.0; // dataType=2
    double blockedW    = 0.0; // dataType=3
    double dangerW     = 0.0; // dataType=4
    bool   hasAuto     = false;

    for (final r in nearby) {
      final age = now - r.packet.timestamp;
      // 2時間超は除外
      if (age > 2 * 3600) continue;

      final freshnessW = age <= 30 * 60 ? 1.0 : 0.5;
      final confidence = _extractConfidence(r.packet.payload);
      final w = freshnessW * confidence;
      if (confidence < 1.0) hasAuto = true;

      switch (r.packet.dataType) {
        case BleDataType.passable:
          passableW += w;
        case BleDataType.blocked:
          blockedW += w;
        case BleDataType.danger:
          dangerW += w;
        case BleDataType.walk:
          break; // 歩行記録はスコアに影響しない
      }
    }

    // 判定（優先度: blocked > danger > passable > neutral）
    double score;
    if (blockedW >= 1.0) {
      score = RoadScore.impassable;
    } else if (dangerW >= 2.0) {
      score = RoadScore.caution;
    } else if (passableW >= 3.0) {
      score = RoadScore.safe;
    } else {
      score = RoadScore.neutral;
    }

    return RoadScoreResult(
      score:           score,
      reportCount:     nearby.length,
      hasAutoDetected: hasAuto,
    );
  }

  /// payload JSON から confidence を取得。未設定なら 1.0（手動報告）
  static double _extractConfidence(String payload) {
    if (payload.isEmpty) return 1.0;
    try {
      final map = jsonDecode(payload) as Map<String, dynamic>;
      return (map['confidence'] as num?)?.toDouble() ?? 1.0;
    } catch (_) {
      return 1.0;
    }
  }

  /// Haversine 距離 (m)
  static double _distM(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}
