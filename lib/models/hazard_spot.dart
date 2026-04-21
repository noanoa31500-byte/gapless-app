import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================================
/// HazardSpot - 第二の指示: データ構造
/// ============================================================================
///
/// 構成要素:
///   lat, lng    : タップされた場所の緯度・経度
///   deviceId    : 端末固有のUUID（個人情報なし）
///   timestamp   : 記録時刻（UTC）
///   status      : 情報の状態 (unconfirmed / confirmed / resolved)
///   reportCount : 異なるデバイスからの同一地点報告の合算数
///
/// BLE転送: toCompactJson() / fromCompactJson() で47バイト前後に圧縮
/// ============================================================================
class HazardSpot {
  final String id; // 一意識別子
  final double lat;
  final double lng;
  final String deviceId; // 投稿端末のUUID
  final DateTime timestamp;
  final String status;
  final int reportCount; // 複数デバイスからの報告合算数

  HazardSpot({
    required this.id,
    required this.lat,
    required this.lng,
    required this.deviceId,
    required this.timestamp,
    this.status = 'unconfirmed',
    this.reportCount = 1,
  });

  // ─── 完全JSON（永続化用）────────────────────────────────────
  Map<String, dynamic> toJson() => {
        'id': id,
        'lat': lat,
        'lng': lng,
        'device_id': deviceId,
        'timestamp': timestamp.millisecondsSinceEpoch,
        'status': status,
        'report_count': reportCount,
      };

  factory HazardSpot.fromJson(Map<String, dynamic> json) => HazardSpot(
        id: json['id'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        deviceId: json['device_id'] as String,
        timestamp: DateTime.fromMillisecondsSinceEpoch(json['timestamp'] as int,
            isUtc: true),
        status: json['status'] as String? ?? 'unconfirmed',
        reportCount: json['report_count'] as int? ?? 1,
      );

  // ─── 圧縮JSON（BLE転送用: パケットサイズを最小化）───────────
  // 例: {"i":"abc12345","a":38.25943,"o":140.88,"d":"uuid8ch","t":1741000,"s":0,"r":1}
  // ※ 座標は小数点5桁(約1m精度)、タイムスタンプはUnixtime秒
  String toCompactJson() => jsonEncode({
        'i': id.length > 8 ? id.substring(0, 8) : id, // ID先頭8文字
        'a': double.parse(lat.toStringAsFixed(5)),
        'o': double.parse(lng.toStringAsFixed(5)),
        'd': deviceId.length > 8 ? deviceId.substring(0, 8) : deviceId,
        't': (timestamp.millisecondsSinceEpoch / 1000).round(),
        's': status == 'unconfirmed'
            ? 0
            : status == 'confirmed'
                ? 1
                : 2,
        'r': reportCount,
      });

  factory HazardSpot.fromCompactJson(Map<String, dynamic> json) {
    final statusInt = json['s'] as int? ?? 0;
    return HazardSpot(
      id: json['i'] as String,
      lat: (json['a'] as num).toDouble(),
      lng: (json['o'] as num).toDouble(),
      deviceId: json['d'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
          ((json['t'] as num) * 1000).toInt(),
          isUtc: true),
      status: statusInt == 0
          ? 'unconfirmed'
          : statusInt == 1
              ? 'confirmed'
              : 'resolved',
      reportCount: json['r'] as int? ?? 1,
    );
  }

  /// マージ: 同一IDで別デバイスの報告 → reportCountを加算して最新タイムスタンプで更新
  HazardSpot mergeWith(HazardSpot other) => HazardSpot(
        id: id,
        lat: lat,
        lng: lng,
        deviceId: deviceId,
        timestamp:
            other.timestamp.isAfter(timestamp) ? other.timestamp : timestamp,
        status: status,
        reportCount: reportCount + (other.deviceId != deviceId ? 1 : 0),
      );

  @override
  String toString() =>
      'HazardSpot($id: lat=$lat, lng=$lng, reports=$reportCount, status=$status)';
}

/// ============================================================================
/// HazardSpotRepository - 第二の指示: 永続化の仕組み
/// ============================================================================
///
/// SharedPreferences(iOSのNSUserDefaults相当)を使い
/// HazardSpotのリストをJSONとして端末内部に永続保存する。
/// アプリの再起動後も失われることなく読み出せる。
/// ============================================================================
class HazardSpotRepository extends ChangeNotifier {
  static final HazardSpotRepository instance = HazardSpotRepository._();
  HazardSpotRepository._();

  static const String _key = 'gapless_hazard_spots_v2';

  /// メモリ上のスポット一覧（地図表示・BLE同期の参照元）
  List<HazardSpot> _spots = [];
  List<HazardSpot> get spots => List.unmodifiable(_spots);

  /// 未確認のみ
  List<HazardSpot> get unconfirmedSpots =>
      _spots.where((s) => s.status == 'unconfirmed').toList();

  // ─── 起動時読み込み（第四の指示）────────────────────────────
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawList = prefs.getStringList(_key) ?? [];
      _spots = rawList
          .map((s) {
            try {
              return HazardSpot.fromJson(jsonDecode(s) as Map<String, dynamic>);
            } catch (_) {
              return null;
            }
          })
          .whereType<HazardSpot>()
          .toList();

      debugPrint('📦 HazardSpotRepository: ${_spots.length}件 読み込み完了');
      notifyListeners();
    } catch (e) {
      debugPrint('⚠️ HazardSpotRepository.load: $e');
    }
  }

  // ─── 新規追加 ─────────────────────────────────────────────
  Future<void> add(HazardSpot spot) async {
    _spots = [..._spots, spot];
    notifyListeners();
    await _persist();
  }

  // ─── 第四の指示: BLE受信データのマージ処理 ──────────────────
  /// receivedSpots: 相手端末から受信したHazardSpotのリスト
  ///
  /// ルール:
  ///   - 自端末にない id → 新規追加
  ///   - 同じ id が既存 → 異なるdeviceIdなら reportCount を合算
  ///   - 同じ id・同じdeviceId → 新しいタイムスタンプで上書き
  ///
  /// 戻り値: 実際に変更があったかどうか
  Future<bool> mergeReceived(List<HazardSpot> receivedSpots) async {
    bool changed = false;
    final Map<String, HazardSpot> existing = {for (var s in _spots) s.id: s};

    for (final received in receivedSpots) {
      if (existing.containsKey(received.id)) {
        final merged = existing[received.id]!.mergeWith(received);
        // reportCountが変化した、またはタイムスタンプが新しい場合のみ更新
        if (merged.reportCount != existing[received.id]!.reportCount ||
            merged.timestamp != existing[received.id]!.timestamp) {
          existing[received.id] = merged;
          changed = true;
        }
      } else {
        // 自端末に存在しない新規スポット → 追加
        existing[received.id] = received;
        changed = true;
      }
    }

    if (changed) {
      _spots = existing.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      notifyListeners(); // ← 地図画面に即時反映
      await _persist();
      debugPrint('🔄 HazardSpotRepository: マージ完了 (total=${_spots.length})');
    }
    return changed;
  }

  // ─── 永続化 ───────────────────────────────────────────────
  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _spots.map((s) => jsonEncode(s.toJson())).toList();
      // 最大500件まで保持（古いものは削除）
      if (jsonList.length > 500) jsonList.removeRange(0, jsonList.length - 500);
      await prefs.setStringList(_key, jsonList);
    } catch (e) {
      debugPrint('⚠️ HazardSpotRepository._persist: $e');
    }
  }

  /// sendable形式: 自端末の全スポットをBLE送信用にシリアライズ
  List<String> toSendableJsonList() =>
      _spots.map((s) => s.toCompactJson()).toList();
}
