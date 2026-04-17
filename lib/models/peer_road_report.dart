import 'dart:convert';

// ============================================================================
// PeerRoadReport — BLEすれ違い通信で交換する道路通行可否レポート
// ============================================================================
//
// 【BLE パケット仕様】
//   コンパクトJSON形式（MTU 20〜180バイト想定）:
//   {"i":"8ch","a":35.68,"o":139.75,"c":5.0,"t":1741000,"p":1,"g":"seg8ch","d":1,"e":45}
//
//   フィールド:
//     i  : report ID（先頭8文字）
//     a  : 緯度 float5桁
//     o  : 経度 float5桁
//     c  : 位置精度 [m] (accuracy)
//     t  : UNIXタイムスタンプ [秒]
//     p  : 通行可 1 / 不可 0
//     g  : セグメントID（緯度経度を3桁でグリッド化した識別子）
//     d  : DR稼働中 1 / GPS正常 0（省略時=0）
//     e  : DR推定誤差 [m]（省略時=0）
//
// ============================================================================

class PeerRoadReport {
  /// レポートID（送信端末でUUID先頭8文字）
  final String id;

  /// 送信端末ID
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

  /// 通行可否（true = 通れる、false = 通れない）
  final bool passable;

  /// 道路セグメントID（緯度経度 3 桁グリッド: "lat3,lng3"）
  /// 同一区間の報告をグルーピングするために使用
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
    required this.passable,
    required this.segmentId,
  });

  // ---------------------------------------------------------------------------
  // ファクトリ
  // ---------------------------------------------------------------------------

  /// 現在地からレポートを生成する
  factory PeerRoadReport.create({
    required String reportId,
    required String deviceId,
    required double lat,
    required double lng,
    required double accuracyM,
    required bool passable,
    bool isDrActive = false,
    double drErrorM = 0.0,
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
      passable: passable,
      segmentId: _makeSegmentId(lat, lng),
    );
  }

  // ---------------------------------------------------------------------------
  // シリアライズ
  // ---------------------------------------------------------------------------

  /// BLE送信用コンパクトJSON文字列
  String toCompactJson() => jsonEncode({
        'i': id,
        'v': deviceId,
        'a': double.parse(lat.toStringAsFixed(5)),
        'o': double.parse(lng.toStringAsFixed(5)),
        'c': accuracyM.round(),
        't': timestamp,
        'p': passable ? 1 : 0,
        'g': segmentId,
        if (isDrActive) 'd': 1,
        if (drErrorM > 0) 'e': drErrorM.round(),
      });

  factory PeerRoadReport.fromCompactJson(Map<String, dynamic> j) =>
      PeerRoadReport(
        id: j['i'] as String,
        deviceId: j['v'] as String? ?? '',
        lat: (j['a'] as num).toDouble(),
        lng: (j['o'] as num).toDouble(),
        accuracyM: (j['c'] as num).toDouble(),
        isDrActive: (j['d'] as int? ?? 0) == 1,
        drErrorM: (j['e'] as num? ?? 0).toDouble(),
        timestamp: (j['t'] as num).toInt(),
        passable: (j['p'] as int) == 1,
        segmentId: j['g'] as String,
      );

  factory PeerRoadReport.fromCompactJsonString(String s) =>
      PeerRoadReport.fromCompactJson(
          jsonDecode(s) as Map<String, dynamic>);

  // ---------------------------------------------------------------------------
  // 時間ベースの有効性判定
  // ---------------------------------------------------------------------------

  /// レポートの経過時間（秒）
  int get ageSeconds =>
      (DateTime.now().millisecondsSinceEpoch ~/ 1000) - timestamp;

  /// 表示用不透明度（時間減衰）
  ///   0 〜 30 分  → 1.0 〜 0.5（線形）
  ///  30 〜 120 分 → 0.5 〜 0.0（線形）
  /// 120 分以上   → 0.0（除外）
  double get displayOpacity {
    final minutes = ageSeconds / 60.0;
    if (minutes >= 120) return 0.0;
    if (minutes >= 30) return 0.5 * (1.0 - (minutes - 30) / 90.0);
    return 1.0 - (minutes / 30.0) * 0.5;
  }

  /// 表示から除外すべきか（2時間経過）
  bool get isExpired => ageSeconds >= 120 * 60;

  // ---------------------------------------------------------------------------
  // ユーティリティ
  // ---------------------------------------------------------------------------

  /// 緯度経度から道路セグメントIDを生成（3桁グリッド ≈ 111m 単位）
  static String _makeSegmentId(double lat, double lng) {
    final la = lat.toStringAsFixed(3);
    final lo = lng.toStringAsFixed(3);
    return '$la,$lo';
  }

  @override
  String toString() =>
      'PeerRoadReport(id=$id, seg=$segmentId, passable=$passable, '
      'accuracy=${accuracyM}m, age=${ageSeconds}s)';
}
