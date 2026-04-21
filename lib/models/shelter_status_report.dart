import 'dart:convert';
import 'dart:typed_data';

// ============================================================================
// ShelterStatusReport — BLE経由で伝播する避難所在避難者ステータス
// ============================================================================
//
// ワイヤーフォーマット（compact JSON、既存 PeerRoadReport と同一チャネル）:
//   v1: {"type":"sh","id":"abcd","a":35.68,"o":139.75,"st":1,"t":1741000,"v":"dev00000"}
//   v2 (署名付き): 上記 + ,"kid":<u8>,"sig":"<base64 64B>"
//
//   type : "sh" — 道路レポートと区別するための識別子
//   id   : 避難所ID（最大16文字）
//   a    : 緯度
//   o    : 経度
//   st   : 1=在避難者あり / 0=不明
//   t    : UNIXタイムスタンプ [秒]
//   v    : 送信端末ID（先頭8文字）
//   kid  : 信頼鍵セット内のキーID (1B int) — `TrustedShelterKeyset` で参照
//   sig  : Ed25519 署名 64B (canonicalBytes に対して)
//
// canonicalBytes: "sh|id|a|o|st|t" を UTF-8 エンコード (浮動小数点5桁丸め、
//                 stは0/1、deviceIdは含めない=端末非依存)
//
// 鍵モデル: SOS の端末バウンドと違い、避難所ステータスは公式運営者
//           (自治体・指定管理者) のみが署名可能。アプリにバンドルした
//           信頼鍵セットで検証する。市民端末は署名できない (= v1 wire)。
//
// ============================================================================

class ShelterStatusReport {
  final String shelterId;
  final double lat;
  final double lng;
  final bool isOccupied;
  final int timestamp;
  final String deviceId;
  final int? keyId;           // v2 のみ
  final Uint8List? signature; // v2 のみ
  final int hops;             // メッシュ中継ホップ数

  // 4時間で失効（道路レポートの2時間より長め）
  static const int _expirySeconds = 4 * 60 * 60;

  const ShelterStatusReport({
    required this.shelterId,
    required this.lat,
    required this.lng,
    required this.isOccupied,
    required this.timestamp,
    required this.deviceId,
    this.keyId,
    this.signature,
    this.hops = 0,
  });

  bool get isSigned => keyId != null && signature != null;

  bool get isExpired =>
      (DateTime.now().millisecondsSinceEpoch ~/ 1000) - timestamp >=
      _expirySeconds;

  /// 署名対象の正規化バイト列。送信側・受信側で必ず同一に。
  /// deviceId を含めない → 同じ避難所/同じステータスは誰が中継しても同一署名。
  Uint8List canonicalBytes() {
    final s = 'sh|$shelterId|'
        '${lat.toStringAsFixed(5)}|'
        '${lng.toStringAsFixed(5)}|'
        '${isOccupied ? 1 : 0}|'
        '$timestamp';
    return Uint8List.fromList(utf8.encode(s));
  }

  ShelterStatusReport withSignature({
    required int keyId,
    required Uint8List signature,
  }) =>
      ShelterStatusReport(
        shelterId: shelterId,
        lat: lat,
        lng: lng,
        isOccupied: isOccupied,
        timestamp: timestamp,
        deviceId: deviceId,
        keyId: keyId,
        signature: signature,
        hops: hops,
      );

  ShelterStatusReport withNextHop() => ShelterStatusReport(
        shelterId: shelterId,
        lat: lat,
        lng: lng,
        isOccupied: isOccupied,
        timestamp: timestamp,
        deviceId: deviceId,
        keyId: keyId,
        signature: signature,
        hops: hops + 1,
      );

  String toCompactJson() {
    final m = <String, dynamic>{
      'type': 'sh',
      'id': shelterId.length > 16 ? shelterId.substring(0, 16) : shelterId,
      'a': double.parse(lat.toStringAsFixed(5)),
      'o': double.parse(lng.toStringAsFixed(5)),
      'st': isOccupied ? 1 : 0,
      't': timestamp,
      'v': deviceId,
    };
    if (isSigned) {
      m['kid'] = keyId;
      m['sig'] = base64.encode(signature!);
    }
    if (hops > 0) m['h'] = hops;
    return jsonEncode(m);
  }

  factory ShelterStatusReport.fromJson(Map<String, dynamic> j) {
    if (j['a'] is! num || j['o'] is! num || j['t'] is! num) {
      throw const FormatException('ShelterStatusReport: a/o/t must be numeric');
    }
    int? kid;
    Uint8List? sig;
    if (j['kid'] is num && j['sig'] is String) {
      try {
        kid = (j['kid'] as num).toInt();
        sig = base64.decode(j['sig'] as String);
      } on FormatException {
        kid = null;
        sig = null;
      }
    }
    return ShelterStatusReport(
      shelterId: (j['id'] as String?) ?? '',
      lat: (j['a'] as num).toDouble(),
      lng: (j['o'] as num).toDouble(),
      isOccupied: (j['st'] is num ? (j['st'] as num).toInt() : 0) == 1,
      timestamp: (j['t'] as num).toInt(),
      deviceId: j['v'] as String? ?? '',
      keyId: kid,
      signature: sig,
      hops: (j['h'] is num ? (j['h'] as num).toInt() : 0),
    );
  }
}
