import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

// ============================================================================
// FallbackModeController — 地図範囲外時の帰還支援モード制御
// ============================================================================
//
// 【動作フロー】
//
//   現在地更新
//    │
//    ├─ 既知範囲内？ ──Yes──► 通常ナビ継続
//    │
//    └─ No
//         │
//         ├─ 初めて範囲外？ → 最後に既知だった地点を保存
//         └─ FallbackMode.returnHome に移行
//              → returnBearingDeg: 保存済み地点への方位
//              → returnDistanceM: 保存済み地点までの距離
//
// 【帰還支援モードの UI】
//   コンパス中央に returnBearingDeg 方向の大矢印を表示し続ける。
//   （ReturnHomeCompassWidget が利用）
//
// 【バックトラック開始】
//   GpsLogger.backtrackRoute() から取得したルートを
//   currentBacktrackWaypoints に設定してバックトラックナビを開始する。
//
// ============================================================================

enum FallbackMode {
  /// 通常ナビ中（地図範囲内）
  normal,

  /// 帰還支援中（範囲外）
  returnHome,

  /// バックトラック案内中
  backtrack,
}

/// 帰還支援モードの状態スナップショット
class FallbackState {
  final FallbackMode mode;

  /// 最後に既知だった地点
  final LatLng? lastKnownPosition;

  /// 現在地 → lastKnownPosition への方位 [0, 360)
  final double returnBearingDeg;

  /// 現在地 → lastKnownPosition までの距離（メートル）
  final double returnDistanceM;

  /// バックトラック中のウェイポイント列（逆順）
  final List<LatLng> backtrackWaypoints;

  /// バックトラックの現在ウェイポイントインデックス
  final int backtrackIndex;

  const FallbackState({
    required this.mode,
    this.lastKnownPosition,
    this.returnBearingDeg = 0,
    this.returnDistanceM = 0,
    this.backtrackWaypoints = const [],
    this.backtrackIndex = 0,
  });

  bool get isReturnHome => mode == FallbackMode.returnHome;
  bool get isBacktrack => mode == FallbackMode.backtrack;
}

class FallbackModeController extends ChangeNotifier {
  // ── マップ境界 ───────────────────────────────────────────────────────────
  /// 既知地図データの境界ボックス（南西・北東）
  double _boundsMinLat = -90;
  double _boundsMaxLat = 90;
  double _boundsMinLng = -180;
  double _boundsMaxLng = 180;

  // ── 状態 ──────────────────────────────────────────────────
  FallbackState _state = const FallbackState(mode: FallbackMode.normal);
  LatLng? _lastKnownPosition;

  FallbackState get state => _state;
  FallbackMode get mode => _state.mode;
  bool get isInFallback =>
      _state.mode != FallbackMode.normal;

  // ---------------------------------------------------------------------------
  // 設定
  // ---------------------------------------------------------------------------

  /// 地図データの境界ボックスを設定する
  ///
  /// gplbParserで読み込んだ道路データのMinLat/MaxLatなどを渡す。
  void setBounds({
    required double minLat,
    required double maxLat,
    required double minLng,
    required double maxLng,
  }) {
    _boundsMinLat = minLat;
    _boundsMaxLat = maxLat;
    _boundsMinLng = minLng;
    _boundsMaxLng = maxLng;
    debugPrint(
        'FallbackModeController: bounds set '
        '[$minLat,$minLng] - [$maxLat,$maxLng]');
  }

  /// RoadFeatureリストから境界を自動算出してセットする
  void setBoundsFromLatLngs(Iterable<LatLng> points) {
    double minLat = 90, maxLat = -90;
    double minLng = 180, maxLng = -180;

    for (final p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }

    // 少し余裕を持たせる（500m相当）
    const pad = 0.005;
    setBounds(
      minLat: minLat - pad,
      maxLat: maxLat + pad,
      minLng: minLng - pad,
      maxLng: maxLng + pad,
    );
  }

  // ---------------------------------------------------------------------------
  // 現在地更新（ナビゲーションループから毎回呼ぶ）
  // ---------------------------------------------------------------------------

  /// 現在地を受け取り、範囲外チェックとモード更新を行う
  ///
  /// [current] 最新の現在地
  void updatePosition(LatLng current) {
    final inBounds = _isInBounds(current);

    switch (_state.mode) {
      case FallbackMode.normal:
        if (inBounds) {
          _lastKnownPosition = current;
        } else {
          // 初めて範囲外 → 帰還支援モードへ
          _enterReturnHome(current);
        }

      case FallbackMode.returnHome:
        if (inBounds) {
          // 範囲内に戻った → 通常モードへ復帰
          _exitFallback(current);
        } else {
          // 方位・距離を更新
          _updateReturnVector(current);
        }

      case FallbackMode.backtrack:
        // バックトラック中は範囲判定をスキップ（ユーザーが意図的に操作中）
        _advanceBacktrack(current);
    }
  }

  // ---------------------------------------------------------------------------
  // バックトラック
  // ---------------------------------------------------------------------------

  /// バックトラックを開始する
  ///
  /// [waypoints] GpsLogger.backtrackRoute() の戻り値（逆順ウェイポイント列）
  void startBacktrack(List<LatLng> waypoints) {
    if (waypoints.isEmpty) return;
    _state = FallbackState(
      mode: FallbackMode.backtrack,
      lastKnownPosition: _lastKnownPosition,
      backtrackWaypoints: waypoints,
      backtrackIndex: 0,
    );
    notifyListeners();
    debugPrint('FallbackModeController: バックトラック開始 (${waypoints.length}点)');
  }

  /// バックトラックを停止して通常モードに戻る
  void stopBacktrack() {
    _state = const FallbackState(mode: FallbackMode.normal);
    notifyListeners();
  }

  /// バックトラック中の現在ターゲットウェイポイント
  LatLng? get backtrackCurrentTarget {
    final wp = _state.backtrackWaypoints;
    final idx = _state.backtrackIndex;
    if (wp.isEmpty || idx >= wp.length) return null;
    return wp[idx];
  }

  // ---------------------------------------------------------------------------
  // 内部ロジック
  // ---------------------------------------------------------------------------

  bool _isInBounds(LatLng pos) =>
      pos.latitude >= _boundsMinLat &&
      pos.latitude <= _boundsMaxLat &&
      pos.longitude >= _boundsMinLng &&
      pos.longitude <= _boundsMaxLng;

  void _enterReturnHome(LatLng current) {
    final last = _lastKnownPosition;
    if (last == null) {
      // 一度も既知地点がなければ何もしない
      return;
    }
    _state = FallbackState(
      mode: FallbackMode.returnHome,
      lastKnownPosition: last,
      returnBearingDeg: _bearing(current, last),
      returnDistanceM: _distanceM(current, last),
    );
    notifyListeners();
    debugPrint(
        'FallbackModeController: 範囲外検知 → 帰還支援モード '
        '(方位: ${_state.returnBearingDeg.toStringAsFixed(0)}°, '
        '距離: ${_state.returnDistanceM.toStringAsFixed(0)}m)');
  }

  void _updateReturnVector(LatLng current) {
    final last = _state.lastKnownPosition;
    if (last == null) return;
    _state = FallbackState(
      mode: FallbackMode.returnHome,
      lastKnownPosition: last,
      returnBearingDeg: _bearing(current, last),
      returnDistanceM: _distanceM(current, last),
    );
    notifyListeners();
  }

  void _exitFallback(LatLng current) {
    _lastKnownPosition = current;
    _state = const FallbackState(mode: FallbackMode.normal);
    notifyListeners();
    debugPrint('FallbackModeController: 範囲内復帰 → 通常モード');
  }

  void _advanceBacktrack(LatLng current) {
    final target = backtrackCurrentTarget;
    if (target == null) {
      stopBacktrack();
      return;
    }
    // 15m 以内に近づいたら次のウェイポイントへ
    if (_distanceM(current, target) <= 15.0) {
      final nextIndex = _state.backtrackIndex + 1;
      if (nextIndex >= _state.backtrackWaypoints.length) {
        stopBacktrack();
        debugPrint('FallbackModeController: バックトラック完了');
      } else {
        _state = FallbackState(
          mode: FallbackMode.backtrack,
          lastKnownPosition: _state.lastKnownPosition,
          backtrackWaypoints: _state.backtrackWaypoints,
          backtrackIndex: nextIndex,
        );
        notifyListeners();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 幾何計算
  // ---------------------------------------------------------------------------

  double _bearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLng = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  double _distanceM(LatLng a, LatLng b) {
    const dist = Distance();
    return dist(a, b);
  }
}
