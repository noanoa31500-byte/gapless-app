import 'dart:convert';

// ============================================================================
// ShelterStatusReport — BLE経由で伝播する避難所在避難者ステータス
// ============================================================================
//
// ワイヤーフォーマット（compact JSON、既存 PeerRoadReport と同一チャネル）:
//   {"type":"sh","id":"abcd","a":35.68,"o":139.75,"st":1,"t":1741000,"v":"dev00000"}
//
//   type : "sh" — 道路レポートと区別するための識別子
//   id   : 避難所ID（最大16文字）
//   a    : 緯度
//   o    : 経度
//   st   : 1=在避難者あり / 0=不明
//   t    : UNIXタイムスタンプ [秒]
//   v    : 送信端末ID（先頭8文字）
//
// ============================================================================

class ShelterStatusReport {
  final String shelterId;
  final double lat;
  final double lng;
  final bool isOccupied;
  final int timestamp;
  final String deviceId;

  // 4時間で失効（道路レポートの2時間より長め）
  static const int _expirySeconds = 4 * 60 * 60;

  const ShelterStatusReport({
    required this.shelterId,
    required this.lat,
    required this.lng,
    required this.isOccupied,
    required this.timestamp,
    required this.deviceId,
  });

  bool get isExpired =>
      (DateTime.now().millisecondsSinceEpoch ~/ 1000) - timestamp >=
      _expirySeconds;

  String toCompactJson() => jsonEncode({
        'type': 'sh',
        'id': shelterId.length > 16 ? shelterId.substring(0, 16) : shelterId,
        'a': double.parse(lat.toStringAsFixed(5)),
        'o': double.parse(lng.toStringAsFixed(5)),
        'st': isOccupied ? 1 : 0,
        't': timestamp,
        'v': deviceId,
      });

  factory ShelterStatusReport.fromJson(Map<String, dynamic> j) =>
      ShelterStatusReport(
        shelterId: (j['id'] as String?) ?? '',
        lat: (j['a'] as num).toDouble(),
        lng: (j['o'] as num).toDouble(),
        isOccupied: (j['st'] as int? ?? 0) == 1,
        timestamp: (j['t'] as num).toInt(),
        deviceId: j['v'] as String? ?? '',
      );
}
