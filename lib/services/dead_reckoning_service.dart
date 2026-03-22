import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';

// ============================================================================
// DeadReckoningService — GPS消失時の推定位置計算
// ============================================================================
//
// 【動作フロー】
//
//   LocationProvider.startLocationTracking() が GPS イベントを受け取るたびに
//   _resetGpsTimeoutTimer() を呼ぶ。3秒間 GPS が沈黙したら activate() が呼ばれ、
//   加速度計＋コンパスによる位置推定を開始する。
//
//   GPS が復活したら LocationProvider が deactivate(gpsPos) を呼び、
//   推定位置と GPS 位置を 80/20 で融合してから DR をリセットする。
//
// 【ステップ検出】
//
//   加速度計の生ノルム |a| のピーク検出（立ち上がりエッジ）を使う。
//   ノルム ≥ 11.5 m/s² かつ 350ms 以上の間隔 → 1歩とみなす。
//   1歩ごとに strideLength × cos(heading) / dLat, sin(heading) / dLng を積算。
//
// ============================================================================

class DeadReckoningService extends ChangeNotifier {
  // ── 設定定数 ────────────────────────────────────────────────────────────
  static const double defaultStrideLengthM = 0.75;
  static const double _stepThreshold = 11.5;    // m/s² (raw accel magnitude)
  static const double _stepCooldownMs = 350.0;  // 最小ステップ間隔

  // ── 状態 ──────────────────────────────────────────────────────────────
  bool _isActive = false;
  LatLng? _estimatedPosition;
  double _headingDeg = 0.0;
  int _stepCount = 0;
  double _strideLengthM = defaultStrideLengthM;

  bool get isActive => _isActive;
  LatLng? get estimatedPosition => _estimatedPosition;
  int get stepCount => _stepCount;

  // ── センサー購読 ────────────────────────────────────────────────────────
  StreamSubscription<AccelerometerEvent>? _accelSub;
  StreamSubscription<CompassEvent>? _compassSub;

  // ── ステップ検出内部状態 ────────────────────────────────────────────────
  double _lastMagnitude = 0.0;
  DateTime _lastStepTime = DateTime.fromMillisecondsSinceEpoch(0);

  // ---------------------------------------------------------------------------
  // ライフサイクル
  // ---------------------------------------------------------------------------

  /// GPS 消失時に呼ぶ。[lastKnownPosition] を起点に推定を開始する。
  void activate(LatLng lastKnownPosition) {
    if (_isActive) return;
    _isActive = true;
    _estimatedPosition = lastKnownPosition;
    _stepCount = 0;
    _startSensors();
    notifyListeners();
    debugPrint('DeadReckoning: 開始 (起点: $lastKnownPosition)');
  }

  /// GPS 復活時に呼ぶ。推定位置と GPS 位置を融合して返す。
  LatLng deactivate(LatLng recoveredGpsPosition) {
    final fused = _fuseWithGps(recoveredGpsPosition);
    _isActive = false;
    _estimatedPosition = null;
    _stepCount = 0;
    _stopSensors();
    notifyListeners();
    debugPrint('DeadReckoning: 終了 (融合位置: $fused)');
    return fused;
  }

  /// 歩幅を上書きする（設定画面から呼ぶ想定）
  void setStrideLengthM(double meters) {
    _strideLengthM = meters.clamp(0.3, 2.0);
  }

  @override
  void dispose() {
    _stopSensors();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // センサー購読
  // ---------------------------------------------------------------------------

  void _startSensors() {
    // 加速度計（重力込みの生値）
    _accelSub = accelerometerEventStream().listen(
      _onAccelerometer,
      onError: (Object e) {
        debugPrint('DeadReckoning 加速度計エラー: $e');
      },
      cancelOnError: false,
    );

    // コンパス（FlutterCompass は broadcast stream なので重複購読 OK）
    _compassSub = FlutterCompass.events?.listen(
      _onCompass,
      onError: (Object e) {
        debugPrint('DeadReckoning コンパスエラー: $e');
      },
      cancelOnError: false,
    );
  }

  void _stopSensors() {
    _accelSub?.cancel();
    _accelSub = null;
    _compassSub?.cancel();
    _compassSub = null;
  }

  // ---------------------------------------------------------------------------
  // センサーハンドラ
  // ---------------------------------------------------------------------------

  void _onAccelerometer(AccelerometerEvent event) {
    final magnitude = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );

    // 立ち上がりエッジ検出：前サンプルが閾値以下 → 現サンプルが閾値以上
    final isRisingEdge =
        magnitude >= _stepThreshold && _lastMagnitude < _stepThreshold;

    if (isRisingEdge) {
      final now = DateTime.now();
      final msSinceLast =
          now.difference(_lastStepTime).inMilliseconds.toDouble();
      if (msSinceLast >= _stepCooldownMs) {
        _registerStep();
        _lastStepTime = now;
      }
    }

    _lastMagnitude = magnitude;
  }

  void _onCompass(CompassEvent event) {
    final heading = event.heading ?? event.headingForCameraMode;
    if (heading != null) {
      _headingDeg = (heading + 360) % 360;
    }
  }

  // ---------------------------------------------------------------------------
  // 位置積算
  // ---------------------------------------------------------------------------

  void _registerStep() {
    if (_estimatedPosition == null) return;
    _stepCount++;

    final headingRad = _headingDeg * math.pi / 180.0;
    final lat = _estimatedPosition!.latitude;
    final lng = _estimatedPosition!.longitude;

    // 等距離近似（1km 以内なら十分な精度）
    final dLat = (_strideLengthM * math.cos(headingRad)) / 111320.0;
    final dLng = (_strideLengthM * math.sin(headingRad)) /
        (111320.0 * math.cos(lat * math.pi / 180.0));

    _estimatedPosition = LatLng(lat + dLat, lng + dLng);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // GPS 融合
  // ---------------------------------------------------------------------------

  /// GPS 復活時の加重平均融合（GPS 80%、DR 20%）
  LatLng _fuseWithGps(LatLng gpsPosition) {
    final dr = _estimatedPosition;
    if (dr == null) return gpsPosition;

    const double gpsW = 0.8;
    const double drW = 0.2;
    return LatLng(
      gpsPosition.latitude * gpsW + dr.latitude * drW,
      gpsPosition.longitude * gpsW + dr.longitude * drW,
    );
  }
}
