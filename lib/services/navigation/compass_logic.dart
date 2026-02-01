import 'dart:async';
import 'package:flutter/foundation.dart'; // for kIsWeb
import 'package:flutter_compass/flutter_compass.dart';
import 'package:latlong2/latlong.dart';
import '../magnetic_declination_config.dart';
import '../compass_permission_service.dart'; // Web Support

/// ============================================================================
/// CompassLogic - センサー処理と方位計算の中核ロジック
/// ============================================================================
class CompassLogic {
  // Sensor State
  double _heading = 0.0;
  double _trueHeading = 0.0;
  
  // Kalman Filter State
  double _kalmanHeading = 0.0;
  double _kalmanP = 1.0;
  static const double _processNoise = 0.01;
  static const double _measurementNoise = 0.5;

  GeoRegion _currentRegion = GeoRegion.jpOsaki;
  final CompassCalibrator _calibrator = CompassCalibrator();
  bool _isStarted = false;

  // Stream
  StreamSubscription<dynamic>? _subscription;
  final StreamController<double> _headingController = StreamController<double>.broadcast();
  Stream<double> get headingStream => _headingController.stream;

  // Getters
  double get heading => _heading;
  double get trueHeading => _trueHeading;
  GeoRegion get currentRegion => _currentRegion;
  bool get hasSensorData => _hasReceivedData;

  // Internal State
  bool _hasReceivedData = false;

  /// コンパス初期化・開始
  Future<void> start() async {
    if (_isStarted) return;
    _isStarted = true;
    _subscription?.cancel();
    
    if (kDebugMode) print('🧭 CompassLogic: センサー開始試行...');
    
    if (kIsWeb) {
      // iOS Web Fallback
      _subscription = getIOSWebCompassStream().listen((double? heading) {
        if (heading != null) {
          _processSensorData(heading);
        }
      });
    } else {
      // Native
      _subscription = FlutterCompass.events?.listen((event) {
        final heading = event.heading;
        if (heading != null) {
          _processSensorData(heading);
        }
      });
    }
    
    if (kDebugMode) print('🧭 CompassLogic: ストリーム購読完了');
  }

  /// 停止
  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _isStarted = false;
    if (kDebugMode) print('🧭 CompassLogic: センサー停止');
  }

  /// 現在地に基づく偏角補正設定の更新
  void updateRegion(LatLng location) {
    if (kDebugMode) print('🧭 CompassLogic: 地域更新 (座標) -> ${location.latitude}, ${location.longitude}');
    _calibrator.setRegionFromCoordinates(location.latitude, location.longitude);
    _currentRegion = _calibrator.currentRegion;
  }

  /// 地域を直接指定して更新 (オフライン/フォールバック用)
  void updateRegionWithRegion(GeoRegion region) {
    if (kDebugMode) print('🧭 CompassLogic: 地域更新 (直接) -> ${region.nameJa}');
    _calibrator.setRegion(region);
    _currentRegion = _calibrator.currentRegion;
  }

  /// センサー生データの処理 (カルマンフィルタ + 偏角補正)
  void _processSensorData(double rawHeading) {
    _hasReceivedData = true;

    // 1. Kalman Filter (Low-pass)
    _updateKalmanFilter(rawHeading);
    
    _heading = _kalmanHeading;

    // 2. Declination Correction
    _trueHeading = _calibrator.calibrate(_heading);

    // 3. Normalize
    _heading = (_heading + 360) % 360;
    _trueHeading = (_trueHeading + 360) % 360;

    _headingController.add(_trueHeading);
  }

  /// カルマンフィルタ更新
  void _updateKalmanFilter(double measurement) {
    final prediction = _kalmanHeading;
    double innovation = measurement - prediction;
    
    // 角度の循環（-180~180）処理
    if (innovation > 180) innovation -= 360;
    if (innovation < -180) innovation += 360;

    final variance = _kalmanP + _processNoise;
    final gain = variance / (variance + _measurementNoise);
    
    _kalmanHeading = prediction + gain * innovation;
    _kalmanP = (1 - gain) * variance;
    
    // Normalize
    _kalmanHeading = (_kalmanHeading + 360) % 360;
  }

  /// ウェイポイント吸着ロジック (Magnetic Adsorption)
  /// 
  /// 目標方位との差が閾値以内なら、針を目標にスナップさせる
  /// @param targetBearing 目標方位 (0-360)
  /// @param threshold 吸着範囲 (度)
  /// @return 吸着後の方位
  double applyMagneticAdsorption(double targetBearing, {double threshold = 5.0}) {
    double diff = (targetBearing - _trueHeading).abs();
    if (diff > 180) diff = 360 - diff;

    if (diff <= threshold) {
      // 吸着 (Snap to target)
      return targetBearing;
    }
    return _trueHeading;
  }
}
