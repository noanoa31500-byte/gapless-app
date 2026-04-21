import 'dart:convert';
import 'dart:typed_data';

// ============================================================================
// SosReport — BLE経由で近隣に発信するSOSビーコン
// ============================================================================
//
// ワイヤーフォーマット（コンパクトJSON）:
//   v1 (旧): {"type":"sos","v":"devId8","a":lat,"o":lng,"t":ts}
//   v2 (署名付き): 上記 + ,"pk":"<base64 32B>","sig":"<base64 64B>"
//
//   フィールド:
//     type : "sos" 固定（BleRoadReportServiceの type-dispatch に合わせる）
//     v    : 送信端末ID（hex 8文字 = SHA-256(pk)[:4]）
//     a    : 緯度 float5桁
//     o    : 経度 float5桁
//     t    : UNIXタイムスタンプ [秒]
//     pk   : Ed25519 公開鍵 32B (v2 のみ)
//     sig  : Ed25519 署名 64B   (v2 のみ。署名対象は canonicalBytes)
//
// canonicalBytes: "sos|v|a|o|t" を UTF-8 でエンコード (浮動小数点は5桁丸め)
//
// 有効期限: 1時間（受信後に地図マーカーから自動消去）
//
// ============================================================================

class SosReport {
  final String deviceId;
  final double lat;
  final double lng;
  final int timestamp;
  final Uint8List? publicKey; // v2 のみ
  final Uint8List? signature; // v2 のみ
  final int hops;             // メッシュ中継ホップ数

  const SosReport({
    required this.deviceId,
    required this.lat,
    required this.lng,
    required this.timestamp,
    this.publicKey,
    this.signature,
    this.hops = 0,
  });

  bool get isSigned => publicKey != null && signature != null;

  /// 署名対象の正規化バイト列。送信側・受信側で必ず同一に。
  Uint8List canonicalBytes() {
    final s = 'sos|$deviceId|'
        '${lat.toStringAsFixed(5)}|'
        '${lng.toStringAsFixed(5)}|'
        '$timestamp';
    return Uint8List.fromList(utf8.encode(s));
  }

  factory SosReport.create({
    required String deviceId,
    required double lat,
    required double lng,
    Uint8List? publicKey,
    Uint8List? signature,
  }) {
    return SosReport(
      deviceId: deviceId.length > 8 ? deviceId.substring(0, 8) : deviceId,
      lat: lat,
      lng: lng,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      publicKey: publicKey,
      signature: signature,
    );
  }

  /// 署名なしバージョン (v1 wire format)。署名は付与後に attachSignature で。
  SosReport withSignature({
    required Uint8List publicKey,
    required Uint8List signature,
  }) =>
      SosReport(
        deviceId: deviceId,
        lat: lat,
        lng: lng,
        timestamp: timestamp,
        publicKey: publicKey,
        signature: signature,
        hops: hops,
      );

  SosReport withNextHop() => SosReport(
        deviceId: deviceId,
        lat: lat,
        lng: lng,
        timestamp: timestamp,
        publicKey: publicKey,
        signature: signature,
        hops: hops + 1,
      );

  String toCompactJson() {
    final m = <String, dynamic>{
      'type': 'sos',
      'v': deviceId,
      'a': double.parse(lat.toStringAsFixed(5)),
      'o': double.parse(lng.toStringAsFixed(5)),
      't': timestamp,
    };
    if (isSigned) {
      m['pk'] = base64.encode(publicKey!);
      m['sig'] = base64.encode(signature!);
    }
    if (hops > 0) m['h'] = hops;
    return jsonEncode(m);
  }

  factory SosReport.fromJson(Map<String, dynamic> j) {
    if (j['a'] is! num || j['o'] is! num || j['t'] is! num) {
      throw const FormatException('SosReport: a/o/t must be numeric');
    }
    Uint8List? pk;
    Uint8List? sig;
    if (j['pk'] is String && j['sig'] is String) {
      try {
        pk = base64.decode(j['pk'] as String);
        sig = base64.decode(j['sig'] as String);
      } on FormatException {
        // 不正な base64 はそのまま無署名として扱う (受信側で reject されうる)
        pk = null;
        sig = null;
      }
    }
    return SosReport(
      deviceId: j['v'] as String? ?? '',
      lat: (j['a'] as num).toDouble(),
      lng: (j['o'] as num).toDouble(),
      timestamp: (j['t'] as num).toInt(),
      publicKey: pk,
      signature: sig,
      hops: (j['h'] is num ? (j['h'] as num).toInt() : 0),
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
