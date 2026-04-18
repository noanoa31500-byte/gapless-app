import 'package:flutter/foundation.dart';
import '../models/peer_road_report.dart';

// ============================================================================
// RoadReportScorer — 時空間スコアリング
// ============================================================================
//
// 【役割】
//   BLEで受信した PeerRoadReport を蓄積し、
//   ① 期限切れレポートの自動除外
//   ② 同一セグメントに 3 件以上の「通行可」報告 → 安全ルート優先フラグを立てる
//   ③ 各セグメントの表示用不透明度（時間減衰）を提供する
//
// 【スコアリング関数】
//
//   passableScore(segmentId) =
//     Σ [ report.passable && !report.isExpired
//           ? weight(report.ageSeconds) : 0 ]
//
//   weight(age):
//     0 〜 30 min    : 1.0  (新鮮 — 赤/緑マーカー)
//    30 〜 120 min   : 0.5  (やや古い — オレンジマーカー)
//   120 〜 360 min   : 0.1  (古い — 黄マーカー、多数報告があれば表示継続)
//     360 min 以上   : 0 (除外)
//
//   isConfirmedSafe(segmentId) = passableScore(segmentId) ≥ 3.0
//
// ============================================================================

/// 1セグメントの集計結果
class SegmentScore {
  /// セグメントID
  final String segmentId;

  /// 有効な「通行可」報告の合計ウェイト
  final double passableWeight;

  /// 有効な「通行不可」報告の合計ウェイト
  final double impassableWeight;

  /// 代表レポートの表示用不透明度（最新レポートの値）
  final double displayOpacity;

  /// 最新レポートの経過秒数（マーカー鮮度色分けに使用）
  final int latestAgeSeconds;

  /// 安全確認済み（通行可ウェイト ≥ 3.0）
  bool get isConfirmedSafe => passableWeight >= 3.0;

  /// 危険確認済み（通行不可ウェイト ≥ 3.0）
  bool get isConfirmedDangerous => impassableWeight >= 3.0;

  const SegmentScore({
    required this.segmentId,
    required this.passableWeight,
    required this.impassableWeight,
    required this.displayOpacity,
    this.latestAgeSeconds = 0,
  });

  @override
  String toString() =>
      'SegmentScore($segmentId pass=${passableWeight.toStringAsFixed(1)} '
      'impass=${impassableWeight.toStringAsFixed(1)} '
      'safe=$isConfirmedSafe)';
}

class RoadReportScorer extends ChangeNotifier {
  // レポートストア: segmentId → List<PeerRoadReport>
  final Map<String, List<PeerRoadReport>> _store = {};

  // スコアキャッシュ（purgeAfterScoring で無効化）
  Map<String, SegmentScore>? _scoreCache;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// レポートを追加する
  ///
  /// 同一 id のレポートは重複追加しない（BLE重複受信対策）
  void addReport(PeerRoadReport report) {
    final existing = _store.putIfAbsent(report.segmentId, () => []);

    // 重複チェック
    if (existing.any((r) => r.id == report.id)) return;

    existing.add(report);
    _scoreCache = null; // キャッシュ無効化
    _purgeExpired(report.segmentId);
    notifyListeners();
  }

  /// 複数レポートを一括追加（BLE受信バッチ）
  void addReports(Iterable<PeerRoadReport> reports) {
    bool changed = false;
    for (final r in reports) {
      final existing = _store.putIfAbsent(r.segmentId, () => []);
      if (existing.any((e) => e.id == r.id)) continue;
      existing.add(r);
      changed = true;
    }
    if (changed) {
      _scoreCache = null;
      _purgeAllExpired();
      notifyListeners();
    }
  }

  /// 全セグメントのスコアを返す
  Map<String, SegmentScore> get scores {
    _scoreCache ??= _computeScores();
    return _scoreCache!;
  }

  /// 指定セグメントのスコアを返す（存在しない場合は null）
  SegmentScore? scoreFor(String segmentId) => scores[segmentId];

  /// 安全確認済みセグメント ID の集合
  Set<String> get confirmedSafeSegments =>
      scores.entries
          .where((e) => e.value.isConfirmedSafe)
          .map((e) => e.key)
          .toSet();

  /// 危険確認済みセグメント ID の集合
  Set<String> get confirmedDangerousSegments =>
      scores.entries
          .where((e) => e.value.isConfirmedDangerous)
          .map((e) => e.key)
          .toSet();

  /// 全セグメントのレポートをクリア
  void clear() {
    _store.clear();
    _scoreCache = null;
    notifyListeners();
  }

  /// 期限切れレポートを全セグメントから削除してリスナーに通知
  void purgeExpired() {
    _purgeAllExpired();
    _scoreCache = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // スコア計算
  // ---------------------------------------------------------------------------

  Map<String, SegmentScore> _computeScores() {
    final result = <String, SegmentScore>{};

    for (final entry in _store.entries) {
      final segId = entry.key;
      final reports = entry.value.where((r) => !r.isExpired).toList();
      if (reports.isEmpty) continue;

      double passableWeight = 0.0;
      double impassableWeight = 0.0;
      double latestOpacity = 0.0;
      int latestAge = 999999;

      for (final r in reports) {
        final w = _reportWeight(r.ageSeconds) * _drReliability(r);
        if (r.passable) {
          passableWeight += w;
        } else {
          impassableWeight += w;
        }
        if (r.displayOpacity > latestOpacity) {
          latestOpacity = r.displayOpacity;
        }
        if (r.ageSeconds < latestAge) {
          latestAge = r.ageSeconds;
        }
      }

      result[segId] = SegmentScore(
        segmentId: segId,
        passableWeight: passableWeight,
        impassableWeight: impassableWeight,
        displayOpacity: latestOpacity,
        latestAgeSeconds: latestAge,
      );
    }

    return result;
  }

  /// 経過時間に基づくレポートのウェイト
  ///   0 〜 30 分   : 1.0  (新鮮)
  ///  30 〜 120 分  : 0.5  (やや古い)
  /// 120 〜 360 分  : 0.1  (古い — 多数報告があれば表示継続)
  static double _reportWeight(int ageSeconds) {
    final minutes = ageSeconds / 60.0;
    if (minutes < 30) return 1.0;
    if (minutes < 120) return 0.5;
    if (minutes < 360) return 0.1;
    return 0.0;
  }

  /// DR誤差に基づく信頼性係数
  ///   GPS正常（DR非稼働）: 1.0
  ///   DR稼働 & 誤差 ≤ 50m: 0.7
  ///   DR稼働 & 誤差 ≤ 100m: 0.4
  ///   DR稼働 & 誤差 > 100m: 0.2
  static double _drReliability(PeerRoadReport r) {
    if (!r.isDrActive) return 1.0;
    if (r.drErrorM <= 50) return 0.7;
    if (r.drErrorM <= 100) return 0.4;
    return 0.2;
  }

  // ---------------------------------------------------------------------------
  // 期限切れ除去
  // ---------------------------------------------------------------------------

  void _purgeExpired(String segmentId) {
    final list = _store[segmentId];
    if (list == null) return;
    list.removeWhere((r) => r.isExpired);
    if (list.isEmpty) _store.remove(segmentId);
  }

  void _purgeAllExpired() {
    final keys = List<String>.from(_store.keys);
    for (final key in keys) {
      _purgeExpired(key);
    }
  }

  // ---------------------------------------------------------------------------
  // デバッグ
  // ---------------------------------------------------------------------------

  @override
  String toString() {
    final s = scores;
    return 'RoadReportScorer: ${_store.length} segments, '
        '${s.values.where((v) => v.isConfirmedSafe).length} safe, '
        '${s.values.where((v) => v.isConfirmedDangerous).length} dangerous';
  }
}
