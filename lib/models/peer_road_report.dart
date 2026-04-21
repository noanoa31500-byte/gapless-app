import 'dart:convert';

// ============================================================================
// PeerRoadReport — BLEすれ違い通信で交換する道路通行可否レポート
// ============================================================================
//
// README準拠ワイヤーフォーマット:
//   {"type":"r","v":"devId","a":lat,"o":lng,"s":0-2,"c":count,"t":ts}
//
//   type : "r" 固定（type-dispatch 用）
//   v    : 送信端末ID（先頭8文字）
//   a    : 緯度 float5桁
//   o    : 経度 float5桁
//   s    : 状態 0=通行可 / 1=通行不可 / 2=危険
//   c    : 同一区間に対する累計報告件数（reportCount）
//   t    : UNIXタイムスタンプ [秒]
//
// 内部互換キー（BLE平文には乗らない / withNextHopなど内部リレー時のみ使用）:
//   i  : reportId（先頭8文字）
//   g  : segmentId
//   d  : DR稼働中
//   e  : DR推定誤差 [m]
//   h  : メッシュリレー hop
//   ca : accuracyMeters（旧"c"の互換読込み用、新"c"とは別）
//
// ============================================================================

enum RoadStatus {
  passable(0),
  blocked(1),
  danger(2);

  final int value;
  const RoadStatus(this.value);
  static RoadStatus fromValue(int v) => switch (v) {
        0 => RoadStatus.passable,
        1 => RoadStatus.blocked,
        2 => RoadStatus.danger,
        _ => RoadStatus.passable,
      };
}

class PeerRoadReport {
  /// レポートID（送信端末でUUID先頭8文字）
  final String id;

  /// 送信端末ID（短命ローテーションID推奨）
  final String deviceId;

  /// レポート地点の緯度
  final double lat;

  /// レポート地点の経度
  final double lng;

  /// 位置精度（メートル）— GPS/CoreLocation の horizontalAccuracy
  final double accuracyM;

  /// レポート時点でDRモード稼働中だったか
  final bool isDrActive;

  /// DRモード時の推定誤差半径（メートル）。GPS正常時は 0
  final double drErrorM;

  /// 報告時刻（UNIXタイムスタンプ秒）
  final int timestamp;

  /// メッシュリレーホップ数（0=発信元, max=3で中継停止）
  final int hops;

  /// 道路状態（README仕様）
  final RoadStatus status;

  /// 同一区間に対する累計報告件数（README "c"）
  final int reportCount;

  /// 道路セグメントID（緯度経度 3 桁グリッド: "lat3,lng3"）
  final String segmentId;

  const PeerRoadReport({
    required this.id,
    required this.deviceId,
    required this.lat,
    required this.lng,
    required this.accuracyM,
    this.isDrActive = false,
    this.drErrorM = 0.0,
    required this.timestamp,
    required this.status,
    required this.segmentId,
    this.reportCount = 1,
    this.hops = 0,
  });

  /// 旧API互換: passable は status==passable
  bool get passable => status == RoadStatus.passable;

  // ---------------------------------------------------------------------------
  // ファクトリ
  // ---------------------------------------------------------------------------

  factory PeerRoadReport.create({
    required String reportId,
    required String deviceId,
    required double lat,
    required double lng,
    required double accuracyM,
    required bool passable,
    bool isDrActive = false,
    double drErrorM = 0.0,
    RoadStatus? status,
    int reportCount = 1,
  }) {
    return PeerRoadReport(
      id: reportId.length > 8 ? reportId.substring(0, 8) : reportId,
      deviceId: deviceId.length > 8 ? deviceId.substring(0, 8) : deviceId,
      lat: lat,
      lng: lng,
      accuracyM: accuracyM,
      isDrActive: isDrActive,
      drErrorM: drErrorM,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      status: status ?? (passable ? RoadStatus.passable : RoadStatus.blocked),
      segmentId: _makeSegmentId(lat, lng),
      reportCount: reportCount,
      hops: 0,
    );
  }

  // ---------------------------------------------------------------------------
  // シリアライズ
  // ---------------------------------------------------------------------------

  /// BLE送信用コンパクトJSON文字列（README準拠）
  String toCompactJson() => jsonEncode({
        'type': 'r',
        'v': deviceId,
        'a': double.parse(lat.toStringAsFixed(5)),
        'o': double.parse(lng.toStringAsFixed(5)),
        's': status.value,
        'c': reportCount,
        't': timestamp,
        // 内部互換フィールド（README仕様外、リレー保持用）
        'i': id,
        'g': segmentId,
        'ca': accuracyM.round(),
        if (isDrActive) 'd': 1,
        if (drErrorM > 0) 'e': drErrorM.round(),
        if (hops > 0) 'h': hops,
      });

  /// 厳格バリデーション付き fromJson。型違反は [FormatException] を投げる。
  factory PeerRoadReport.fromCompactJson(Map<String, dynamic> j) {
    if (j['a'] is! num || j['o'] is! num || j['t'] is! num) {
      throw const FormatException('PeerRoadReport: a/o/t must be numeric');
    }
    final lat = (j['a'] as num).toDouble();
    final lng = (j['o'] as num).toDouble();
    final ts = (j['t'] as num).toInt();

    // 旧フォーマット互換:
    //   - "p" (boolean as 0/1) → status
    //   - 旧 "c" は accuracyMeters だった。新仕様 "c" は reportCount。
    //     新フォーマットには "ca" を別途付加するため、それを優先。
    final RoadStatus status;
    if (j.containsKey('s')) {
      if (j['s'] is! num) {
        throw const FormatException('PeerRoadReport: s must be numeric');
      }
      status = RoadStatus.fromValue((j['s'] as num).toInt());
    } else if (j.containsKey('p')) {
      status = (j['p'] as num).toInt() == 1
          ? RoadStatus.passable
          : RoadStatus.blocked;
    } else {
      status = RoadStatus.passable;
    }

    final double accuracy;
    if (j['ca'] is num) {
      accuracy = (j['ca'] as num).toDouble();
    } else if (!j.containsKey('s') && j['c'] is num) {
      // 旧フォーマット: "c" は accuracy
      accuracy = (j['c'] as num).toDouble();
    } else {
      accuracy = 0.0;
    }

    final int reportCount;
    if (j.containsKey('s') && j['c'] is num) {
      reportCount = (j['c'] as num).toInt();
    } else {
      reportCount = 1;
    }

    return PeerRoadReport(
      id: (j['i'] as String?) ?? '',
      deviceId: (j['v'] as String?) ?? '',
      lat: lat,
      lng: lng,
      accuracyM: accuracy,
      isDrActive: (j['d'] is num ? (j['d'] as num).toInt() : 0) == 1,
      drErrorM: (j['e'] is num ? (j['e'] as num).toDouble() : 0.0),
      timestamp: ts,
      status: status,
      segmentId: (j['g'] as String?) ?? _makeSegmentId(lat, lng),
      reportCount: reportCount,
      hops: (j['h'] is num ? (j['h'] as num).toInt() : 0),
    );
  }

  PeerRoadReport withNextHop() => PeerRoadReport(
        id: id,
        deviceId: deviceId,
        lat: lat,
        lng: lng,
        accuracyM: accuracyM,
        isDrActive: isDrActive,
        drErrorM: drErrorM,
        timestamp: timestamp,
        status: status,
        segmentId: segmentId,
        reportCount: reportCount,
        hops: hops + 1,
      );

  factory PeerRoadReport.fromCompactJsonString(String s) =>
      PeerRoadReport.fromCompactJson(jsonDecode(s) as Map<String, dynamic>);

  // ---------------------------------------------------------------------------
  // 時間ベースの有効性判定
  // ---------------------------------------------------------------------------

  int get ageSeconds =>
      (DateTime.now().millisecondsSinceEpoch ~/ 1000) - timestamp;

  /// 表示用不透明度（時間減衰）
  double get displayOpacity {
    final minutes = ageSeconds / 60.0;
    if (minutes >= 360) return 0.0;
    if (minutes >= 120) return 0.15;
    if (minutes >= 30) return 0.5 - 0.35 * (minutes - 30) / 90.0;
    return 1.0 - (minutes / 30.0) * 0.5;
  }

  /// 表示から除外すべきか（README: 道路レポート TTL=24h）
  bool get isExpired => ageSeconds >= 24 * 3600;

  // ---------------------------------------------------------------------------
  // ユーティリティ
  // ---------------------------------------------------------------------------

  static String _makeSegmentId(double lat, double lng) {
    final la = lat.toStringAsFixed(3);
    final lo = lng.toStringAsFixed(3);
    return '$la,$lo';
  }

  @override
  String toString() => 'PeerRoadReport(id=$id, seg=$segmentId, status=$status, '
      'count=$reportCount, age=${ageSeconds}s)';
}
