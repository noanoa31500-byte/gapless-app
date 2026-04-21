import 'dart:convert';
import 'package:latlong2/latlong.dart';

// ============================================================================
// GpsTrackSnapshot — BLE経由で伝播する最近のGPS軌跡スナップショット
// ============================================================================
//
// ワイヤーフォーマット (compact JSON):
//   {"type":"tr","v":"dev00000","t":1741000,"pts":[[35.68950,139.75000,1741000],...]}
//
//   type : "tr" — 道路/避難所レポートと区別
//   v    : 送信端末ID先頭8文字
//   t    : 最終点のUNIXタイムスタンプ
//   pts  : [[lat5, lng5, unixTs], ...] 最大15点
//
// 用途: 災害時の捜索救助支援。周囲のBLE端末が受信し、
//       送信者がどの経路を通ってきたかを地図上で把握できる。
//
// ============================================================================

class GpsPoint {
  final double lat;
  final double lng;
  final int ts;

  const GpsPoint(this.lat, this.lng, this.ts);

  LatLng get latLng => LatLng(lat, lng);
}

class GpsTrackSnapshot {
  final String deviceId;
  final int timestamp; // 最終点のUNIXタイムスタンプ
  final List<GpsPoint> points;

  static const int _expirySeconds = 4 * 60 * 60; // 4時間

  const GpsTrackSnapshot({
    required this.deviceId,
    required this.timestamp,
    required this.points,
  });

  bool get isExpired =>
      (DateTime.now().millisecondsSinceEpoch ~/ 1000) - timestamp >=
      _expirySeconds;

  List<LatLng> get latLngs => points.map((p) => p.latLng).toList();

  String toCompactJson() {
    final encoded = points
        .map((p) => [
              double.parse(p.lat.toStringAsFixed(5)),
              double.parse(p.lng.toStringAsFixed(5)),
              p.ts,
            ])
        .toList();
    return jsonEncode({
      'type': 'tr',
      'v': deviceId,
      't': timestamp,
      'pts': encoded,
    });
  }

  factory GpsTrackSnapshot.fromJson(Map<String, dynamic> j) {
    final rawPts = (j['pts'] as List?) ?? [];
    final points = rawPts
        .map((arr) {
          final a = arr as List;
          if (a.length < 3) return null;
          return GpsPoint(
            (a[0] as num).toDouble(),
            (a[1] as num).toDouble(),
            (a[2] as num).toInt(),
          );
        })
        .whereType<GpsPoint>()
        .toList();
    return GpsTrackSnapshot(
      deviceId: j['v'] as String? ?? '',
      timestamp: (j['t'] as num?)?.toInt() ?? 0,
      points: points,
    );
  }
}
