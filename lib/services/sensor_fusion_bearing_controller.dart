import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

// ============================================================================
// SensorFusionBearingController — GPS／コンパス ハイブリッド方位制御
// ============================================================================
//
// 【フュージョンロジック】
//
//   GPS速度 < 0.3 m/s (停止)  → コンパス方位を採用
//   GPS速度 ≥ 0.3 m/s (移動)  → GPS移動ベクトル方位を採用
//
//   両者の差 ≥ 30°             → divergenceWarning ストリームに通知
//
// 【磁気精度監視】
//
//   CompassEvent.accuracy (iOS CoreMotion) は許容誤差 [°]。
//   accuracy > 45° → SensorAccuracyLevel.low とみなす
//   low 継続 3 秒  → calibrationNeeded ストリームに通知
//   ※ 案内を一時停止し「八の字補正」オーバーレイを表示する契機として使う
//
// ============================================================================

/// 磁気センサー精度レベル
enum SensorAccuracyLevel {
  high, // accuracy ≤ 15°
  medium, // accuracy ≤ 45°
  low, // accuracy > 45°
}

/// センサーフュージョン後の方位状態
class BearingState {
  /// フュージョン後の確定方位 [0, 360)
  final double bearing;

  /// 採用したソース
  final BearingSource source;

  /// コンパス生値（磁気偏角補正済み）
  final double compassBearing;

  /// GPS移動ベクトルから計算した方位（移動中のみ有効）
  final double? gpsBearing;

  /// 現在の磁気センサー精度
  final SensorAccuracyLevel accuracy;

  /// GPS速度 [m/s]
  final double speedMps;

  const BearingState({
    required this.bearing,
    required this.source,
    required this.compassBearing,
    required this.accuracy,
    required this.speedMps,
    this.gpsBearing,
  });
}

/// 採用した方位ソース
enum BearingSource { compass, gps }

/// GPS－コンパス間の乖離警告
class DivergenceWarning {
  /// コンパス方位
  final double compassBearing;

  /// GPS方位
  final double gpsBearing;

  /// 乖離角度 [0, 180]
  final double divergenceDeg;

  const DivergenceWarning({
    required this.compassBearing,
    required this.gpsBearing,
    required this.divergenceDeg,
  });
}

class SensorFusionBearingController {
  // ── 閾値定数 ──────────────────────────────────────────────────────────────
  static const double _stopSpeedThreshold = 0.3; // m/s
  static const double _divergenceThreshold = 30.0; // °
  static const Duration _lowAccuracyTimeout = Duration(seconds: 3);

  // ── センサー購読 ───────────────────────────────────────────────────────────
  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<Position>? _gpsSub;

  // ── 内部状態 ──────────────────────────────────────────────────────────────
  double _compassBearing = 0.0;
  double _compassAccuracyDeg = 0.0; // iOS accuracy field (lower = better)
  double _gpsBearing = 0.0;
  double _speedMps = 0.0;
  Position? _prevPosition;
  DateTime? _lowAccuracyStart;

  // ── 出力ストリーム ────────────────────────────────────────────────────────
  final _bearingCtrl = StreamController<BearingState>.broadcast();
  final _divergenceCtrl = StreamController<DivergenceWarning>.broadcast();
  final _calibrationCtrl = StreamController<bool>.broadcast();

  /// フュージョン後の方位ストリーム
  Stream<BearingState> get bearingStream => _bearingCtrl.stream;

  /// GPS－コンパス乖離 ≥ 30° のとき発火
  Stream<DivergenceWarning> get divergenceWarningStream =>
      _divergenceCtrl.stream;

  /// true = 八の字補正が必要、false = 補正完了
  Stream<bool> get calibrationNeededStream => _calibrationCtrl.stream;

  // ---------------------------------------------------------------------------
  // ライフサイクル
  // ---------------------------------------------------------------------------

  /// センサー購読を開始する
  void start() {
    _startCompass();
    _startGps();
    debugPrint('SensorFusionBearingController: 開始');
  }

  /// センサー購読を停止する
  void dispose() {
    _compassSub?.cancel();
    _gpsSub?.cancel();
    _bearingCtrl.close();
    _divergenceCtrl.close();
    _calibrationCtrl.close();
    debugPrint('SensorFusionBearingController: 停止');
  }

  // ---------------------------------------------------------------------------
  // コンパス購読
  // ---------------------------------------------------------------------------

  void _startCompass() {
    _compassSub = FlutterCompass.events?.listen((event) {
      final raw = event.heading ?? event.headingForCameraMode;
      if (raw == null) return;

      _compassBearing = (raw + 360) % 360;
      _compassAccuracyDeg = event.accuracy ?? 0.0;

      _checkAccuracy();
      _fuse();
    });
  }

  void _checkAccuracy() {
    final level = _accuracyLevel(_compassAccuracyDeg);

    if (level == SensorAccuracyLevel.low) {
      _lowAccuracyStart ??= DateTime.now();
      final elapsed = DateTime.now().difference(_lowAccuracyStart!);
      if (elapsed >= _lowAccuracyTimeout) {
        _calibrationCtrl.add(true); // 補正オーバーレイを表示
      }
    } else {
      if (_lowAccuracyStart != null) {
        _lowAccuracyStart = null;
        _calibrationCtrl.add(false); // 補正完了 → オーバーレイ非表示
      }
    }
  }

  // ---------------------------------------------------------------------------
  // GPS購読
  // ---------------------------------------------------------------------------

  void _startGps() {
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 0, // すべての更新を受け取る
    );

    _gpsSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        _speedMps = pos.speed.clamp(0.0, double.infinity);

        // GPS移動ベクトルから方位を計算
        if (_prevPosition != null) {
          _gpsBearing = _bearingBetween(
            LatLng(_prevPosition!.latitude, _prevPosition!.longitude),
            LatLng(pos.latitude, pos.longitude),
          );
        }
        _prevPosition = pos;

        _fuse();
      },
      onError: (Object e) {
        debugPrint('SensorFusionBearingController GPS エラー: $e');
      },
    );
  }

  // ---------------------------------------------------------------------------
  // フュージョンロジック
  // ---------------------------------------------------------------------------

  void _fuse() {
    final bool isMoving = _speedMps >= _stopSpeedThreshold;
    final source = isMoving ? BearingSource.gps : BearingSource.compass;
    final fused = isMoving ? _gpsBearing : _compassBearing;

    // 乖離チェック（移動中のみ意味がある）
    if (isMoving) {
      final diff = _angleDiff(_compassBearing, _gpsBearing);
      if (diff >= _divergenceThreshold) {
        _divergenceCtrl.add(DivergenceWarning(
          compassBearing: _compassBearing,
          gpsBearing: _gpsBearing,
          divergenceDeg: diff,
        ));
      }
    }

    _bearingCtrl.add(BearingState(
      bearing: fused,
      source: source,
      compassBearing: _compassBearing,
      gpsBearing: isMoving ? _gpsBearing : null,
      accuracy: _accuracyLevel(_compassAccuracyDeg),
      speedMps: _speedMps,
    ));
  }

  // ---------------------------------------------------------------------------
  // ユーティリティ
  // ---------------------------------------------------------------------------

  static const double _mediumAccuracyThreshold = 15.0;
  static const double _lowAccuracyThreshold = 45.0;

  static SensorAccuracyLevel _accuracyLevel(double accuracyDeg) {
    if (accuracyDeg <= _mediumAccuracyThreshold)
      return SensorAccuracyLevel.high;
    if (accuracyDeg <= _lowAccuracyThreshold) return SensorAccuracyLevel.medium;
    return SensorAccuracyLevel.low;
  }

  /// 2つの方位の最小角度差 [0, 180]
  static double _angleDiff(double a, double b) {
    double diff = (a - b).abs() % 360;
    if (diff > 180) diff = 360 - diff;
    return diff;
  }

  /// 2点間の方位角 [0, 360)
  static double _bearingBetween(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLng = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }
}
