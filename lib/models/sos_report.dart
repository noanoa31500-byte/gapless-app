import 'dart:convert';

// ============================================================================
// SosReport — BLE経由で近隣に発信するSOSビーコン
// ============================================================================
//
// ワイヤーフォーマット（コンパクトJSON）:
//   {"type":"sos","v":"devId8","a":lat,"o":lng,"t":ts}
//
//   フィールド:
//     type : "sos" 固定（BleRoadReportServiceの type-dispatch に合わせる）
//     v    : 送信端末ID（先頭8文字）
//     a    : 緯度 float5桁
//     o    : 経度 float5桁
//     t    : UNIXタイムスタンプ [秒]
//
// 有効期限: 1時間（受信後に地図マーカーから自動消去）
//
// ============================================================================

class SosReport {
  final String deviceId;
  final double lat;
  final double lng;
  final int timestamp;

  const SosReport({
    required this.deviceId,
    required this.lat,
    required this.lng,
    required this.timestamp,
  });

  factory SosReport.create({
    required String deviceId,
    required double lat,
    required double lng,
  }) {
    return SosReport(
      deviceId: deviceId.length > 8 ? deviceId.substring(0, 8) : deviceId,
      lat: lat,
      lng: lng,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    );
  }

  String toCompactJson() => jsonEncode({
        'type': 'sos',
        'v': deviceId,
        'a': double.parse(lat.toStringAsFixed(5)),
        'o': double.parse(lng.toStringAsFixed(5)),
        't': timestamp,
      });

  factory SosReport.fromJson(Map<String, dynamic> j) {
    if (j['a'] is! num || j['o'] is! num || j['t'] is! num) {
      throw const FormatException('SosReport: a/o/t must be numeric');
    }
    return SosReport(
      deviceId: j['v'] as String? ?? '',
      lat: (j['a'] as num).toDouble(),
      lng: (j['o'] as num).toDouble(),
      timestamp: (j['t'] as num).toInt(),
    );
  }

  int get ageSeconds =>
      (DateTime.now().millisecondsSinceEpoch ~/ 1000) - timestamp;

  bool get isExpired => ageSeconds >= 3600;

  double get displayOpacity {
    final minutes = ageSeconds / 60.0;
    if (minutes >= 60) return 0.0;
    if (minutes >= 30) return 0.4;
    return 1.0 - (minutes / 30.0) * 0.6;
  }

  @override
  String toString() =>
      'SosReport(device=$deviceId, $lat/$lng, age=${ageSeconds}s)';
}
