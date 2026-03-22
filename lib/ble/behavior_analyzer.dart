import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../services/device_id_service.dart';
import '../services/gps_logger.dart';
import 'ble_packet.dart';
import 'ble_repository.dart';
import 'ble_service.dart';

// ============================================================================
// BehaviorAnalyzer — GPSログから通行不可を自動検知
// ============================================================================
//
// 【判定条件】
//   A. 停滞判定: 50m圏内に3分以上留まった後、進入せず離れた
//   B. 引き返し判定: 前進後100m以内で元の位置に戻った
//   C. 迂回判定: 直線距離に対して2倍以上の迂回を2分以上かけた
//
// 【自動判定の信頼度】
//   手動報告より低いため、payload に {"confidence": 0.6} を付与する
//
// 【省電力連携】
//   setSavingMode(true) → 判定間隔を10秒から60秒に延長
//
// ============================================================================

class BehaviorAnalyzer {
  static final BehaviorAnalyzer instance = BehaviorAnalyzer._();
  BehaviorAnalyzer._();

  static const Duration _normalInterval  = Duration(seconds: 10);
  static const Duration _savingInterval  = Duration(seconds: 60);
  static const Duration _stagnationTime  = Duration(minutes: 3);
  static const Duration _detourTime      = Duration(minutes: 2);
  static const double   _stagnationRadiusM = 50.0; // 停滞判定半径
  static const double   _turnbackThreshM   = 100.0; // 引き返し判定最大前進距離
  static const double   _detourRatioThresh = 2.0;   // 迂回比率閾値
  static const double   _confidence        = 0.6;

  Timer? _timer;
  bool _isSavingMode = false;

  // 前回の判定済み地点（重複レポート防止）
  final List<LatLng> _reportedLocations = [];

  // ---------------------------------------------------------------------------
  // ライフサイクル
  // ---------------------------------------------------------------------------

  void start() {
    _timer?.cancel();
    _scheduleNext();
    debugPrint('BehaviorAnalyzer: 開始');
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    debugPrint('BehaviorAnalyzer: 停止');
  }

  void setSavingMode(bool saving) {
    _isSavingMode = saving;
    final wasRunning = _timer != null;
    _timer?.cancel();
    _timer = null;
    if (wasRunning) _scheduleNext();
  }

  void _scheduleNext() {
    final interval = _isSavingMode ? _savingInterval : _normalInterval;
    _timer = Timer(interval, () {
      _analyze();
      _scheduleNext();
    });
  }

  // ---------------------------------------------------------------------------
  // 分析メイン
  // ---------------------------------------------------------------------------

  Future<void> _analyze() async {
    final entries = GpsLogger.instance.recentEntries;
    if (entries.length < 5) return;

    await _checkStagnation(entries);
    await _checkTurnback(entries);
    await _checkDetour(entries);
  }

  // ---------------------------------------------------------------------------
  // 条件A: 停滞判定
  // ---------------------------------------------------------------------------
  // ある地点の50m圏内に3分以上留まり、その後圏外に出た場合
  // → 留まっていた地点を通行不可と報告

  Future<void> _checkStagnation(List<GpsLogEntry> entries) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // 最後のエントリから3分以上前のエントリを探す
    final recent = entries.last;
    final stagnationCutoff = recent.timestamp - _stagnationTime.inSeconds;

    // 3分前の時点のエントリを探す
    GpsLogEntry? oldEntry;
    for (final e in entries) {
      if (e.timestamp <= stagnationCutoff) {
        oldEntry = e;
        break;
      }
    }
    if (oldEntry == null) return;

    // 停滞期間中のエントリが全て50m圏内にあるか確認
    final center = LatLng(oldEntry.lat, oldEntry.lng);
    final stagnationEntries = entries
        .where((e) =>
            e.timestamp >= stagnationCutoff &&
            e.timestamp <= recent.timestamp)
        .toList();

    final allWithinRadius = stagnationEntries.every(
      (e) => _distM(center.latitude, center.longitude, e.lat, e.lng) <= _stagnationRadiusM,
    );

    if (!allWithinRadius) return;

    // 停滞後に50m以上離れたか確認（圏外に出た）
    final afterEntries = entries
        .where((e) => e.timestamp > recent.timestamp)
        .toList();
    if (afterEntries.isEmpty) return;

    final departed = afterEntries.any(
      (e) => _distM(center.latitude, center.longitude, e.lat, e.lng) > _stagnationRadiusM * 1.5,
    );
    if (!departed) return;

    await _reportBlocked(
      center,
      now,
      reason: 'stagnation_${_stagnationTime.inMinutes}min',
    );
  }

  // ---------------------------------------------------------------------------
  // 条件B: 引き返し判定
  // ---------------------------------------------------------------------------
  // 前進 → 100m以内で元の地点に戻った場合

  Future<void> _checkTurnback(List<GpsLogEntry> entries) async {
    if (entries.length < 10) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // 直近30エントリを対象
    final recent = entries.length > 30 ? entries.sublist(entries.length - 30) : entries;

    // 最大前進距離を探し、その後戻ったかを確認
    final start = LatLng(recent.first.lat, recent.first.lng);
    double maxDist = 0.0;
    LatLng? farthestPoint;

    for (final e in recent) {
      final d = _distM(start.latitude, start.longitude, e.lat, e.lng);
      if (d > maxDist) {
        maxDist = d;
        farthestPoint = LatLng(e.lat, e.lng);
      }
    }

    if (farthestPoint == null || maxDist > _turnbackThreshM) return;
    if (maxDist < 20) return; // 20m未満は誤検知防止

    // 最後の位置が出発点近く (20m以内) に戻っているか
    final lastPos = LatLng(recent.last.lat, recent.last.lng);
    final returnDist = _distM(start.latitude, start.longitude, lastPos.latitude, lastPos.longitude);
    if (returnDist > 25.0) return;

    // 引き返した先（最遠点）を通行不可として報告
    await _reportBlocked(
      farthestPoint,
      now,
      reason: 'turnback',
    );
  }

  // ---------------------------------------------------------------------------
  // 条件C: 迂回判定
  // ---------------------------------------------------------------------------
  // 直線距離に対して2分以上かけて2倍以上の経路を歩いた場合

  Future<void> _checkDetour(List<GpsLogEntry> entries) async {
    if (entries.length < 10) return;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    // 直近2分 + α のウィンドウ
    final cutoff = now - _detourTime.inSeconds - 30;
    final window = entries.where((e) => e.timestamp >= cutoff).toList();
    if (window.length < 5) return;

    final startE = window.first;
    final endE   = window.last;

    // 直線距離
    final straightDist = _distM(startE.lat, startE.lng, endE.lat, endE.lng);
    if (straightDist < 50) return; // 移動が小さすぎる

    // 実際の経路距離
    double actualDist = 0.0;
    for (int i = 1; i < window.length; i++) {
      actualDist += _distM(
        window[i - 1].lat, window[i - 1].lng,
        window[i].lat,     window[i].lng,
      );
    }

    // 迂回比率
    final ratio = actualDist / straightDist;
    if (ratio < _detourRatioThresh) return;

    // 経路の中間点付近を通行不可として報告（直線上の中間）
    final midLat = (startE.lat + endE.lat) / 2;
    final midLng = (startE.lng + endE.lng) / 2;

    await _reportBlocked(
      LatLng(midLat, midLng),
      now,
      reason: 'detour_ratio${ratio.toStringAsFixed(1)}',
    );
  }

  // ---------------------------------------------------------------------------
  // 自動報告の生成・保存
  // ---------------------------------------------------------------------------

  Future<void> _reportBlocked(LatLng pos, int timestamp, {required String reason}) async {
    // 重複チェック（50m以内に既報告があれば無視）
    for (final reported in _reportedLocations) {
      if (_distM(reported.latitude, reported.longitude, pos.latitude, pos.longitude) < 50) {
        return;
      }
    }

    final deviceId = DeviceIdService.instance.deviceId ?? 'unknown';
    final payload = jsonEncode({'confidence': _confidence, 'reason': reason});

    final packet = BlePacket(
      senderDeviceId: deviceId,
      timestamp:      timestamp,
      lat:            pos.latitude,
      lng:            pos.longitude,
      accuracyMeters: 30.0, // 自動判定の精度は低め
      dataType:       BleDataType.blocked,
      payload:        payload,
    );

    await BleRepository.instance.insert(packet);
    BleService.instance.enqueue(packet);

    _reportedLocations.add(pos);
    // メモリ上限
    if (_reportedLocations.length > 200) _reportedLocations.removeAt(0);

    debugPrint('BehaviorAnalyzer: 自動通行不可報告 pos=$pos reason=$reason');
  }

  // ---------------------------------------------------------------------------
  // ユーティリティ
  // ---------------------------------------------------------------------------

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
