import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:latlong2/latlong.dart';
import '../magnetic_declination_config.dart';

/// ============================================================================
/// CompassLogic - iOSネイティブ専用センサー処理
/// ============================================================================
///
/// 【iOS最適化方針】
/// - Web用 getIOSWebCompassStream() / kIsWeb 分岐を完全削除
/// - flutter_compass が CoreMotion/CMMotionManager を使ってネイティブに動作
/// - iOSでは CLPermissions は flutter_compass プラグインが自動要求
/// - カルマンフィルタで磁気ノイズを平滑化し真北方位を提供
///
/// 【依存関係】
/// flutter_compass → iOS CoreMotion (CMMotionManager)
///                        → CLDeviceOrientationPortrait etc.
/// ============================================================================
class CompassLogic {
  // センサー状態
  double _heading = 0.0;
  double _trueHeading = 0.0;

  // カルマンフィルタ状態変数
  double _kalmanHeading = 0.0;
  double _kalmanP = 1.0;
  static const double _processNoise = 0.01;      // プロセスノイズ (動き予測誤差)
  static const double _measurementNoise = 0.5;   // 測定ノイズ (センサー誤差)

  GeoRegion _currentRegion = GeoRegion.jpOsaki;
  final CompassCalibrator _calibrator = CompassCalibrator();
  bool _isStarted = false;
  bool _hasReceivedData = false;

  // ヘッディングストリーム（GapLessNavigationEngineが購読）
  StreamSubscription<CompassEvent>? _subscription;
  final StreamController<double> _headingController = StreamController<double>.broadcast();
  Stream<double> get headingStream => _headingController.stream;

  // 公開ゲッター
  double get heading => _heading;
  double get trueHeading => _trueHeading;
  GeoRegion get currentRegion => _currentRegion;
  bool get hasSensorData => _hasReceivedData;

  // ─── 起動 ────────────────────────────────────────────────
  /// flutter_compass が CoreMotion を通じて磁力計データを取得する
  /// iOSでは Info.plist の NSMotionUsageDescription が必要（flutter_compassが自動要求）
  Future<void> start() async {
    if (_isStarted) return;
    _isStarted = true;
    _subscription?.cancel();

    if (kDebugMode) debugPrint('🧭 CompassLogic: iOS CoreMotion センサー開始...');

    // flutter_compass がネイティブの CMMotionManager を購読
    // パーミッションダイアログはiOSが自動的に表示する
    _subscription = FlutterCompass.events?.listen(
      (CompassEvent event) {
        // headingAccuracy が低い場合はスキップ（磁気干渉回避）
        if (event.headingForCameraMode != null) {
          _processSensorData(event.headingForCameraMode!);
        } else if (event.heading != null) {
          _processSensorData(event.heading!);
        }
      },
      onError: (Object error) {
        debugPrint('⚠️ CompassLogic センサーエラー: $error');
      },
    );

    if (kDebugMode) debugPrint('🧭 CompassLogic: CoreMotion購読完了');
  }

  // ─── 強制再起動 ──────────────────────────────────────────
  /// iOSでは権限変更後に再起動不要（flutter_compassが自動的に対処）
  /// ただし互換のために残す
  Future<void> restart() async {
    if (kDebugMode) debugPrint('🧭 CompassLogic: 再起動...');
    _isStarted = false;
    _subscription?.cancel();
    _subscription = null;
    _hasReceivedData = false;
    await start();
  }

  // ─── 停止 ────────────────────────────────────────────────
  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _isStarted = false;
    if (!_headingController.isClosed) _headingController.close();
    if (kDebugMode) debugPrint('🧭 CompassLogic: 停止');
  }

  // ─── 地域更新 ─────────────────────────────────────────────
  /// 現在地から磁気偏角補正パラメータを更新
  void updateRegion(LatLng location) {
    _calibrator.setRegionFromCoordinates(location.latitude, location.longitude);
    _currentRegion = _calibrator.currentRegion;
    if (kDebugMode) {
      debugPrint('🧭 CompassLogic: 地域更新 → ${_currentRegion.nameJa}');
    }
  }

  void updateRegionWithRegion(GeoRegion region) {
    _calibrator.setRegion(region);
    _currentRegion = _calibrator.currentRegion;
  }

  // ─── センサーデータ処理（内部）────────────────────────────
  /// カルマンフィルタ → 偏角補正 → 正規化 → ストリームに流す
  void _processSensorData(double rawHeading) {
    _hasReceivedData = true;
    _updateKalmanFilter(rawHeading);
    _heading = _kalmanHeading;
    _trueHeading = _calibrator.calibrate(_heading);
    _heading = (_heading + 360) % 360;
    _trueHeading = (_trueHeading + 360) % 360;
    _headingController.add(_trueHeading);
  }

  // ─── カルマンフィルタ ────────────────────────────────────
  void _updateKalmanFilter(double measurement) {
    final prediction = _kalmanHeading;
    double innovation = measurement - prediction;
    if (innovation > 180) innovation -= 360;
    if (innovation < -180) innovation += 360;
    final variance = _kalmanP + _processNoise;
    final gain = variance / (variance + _measurementNoise);
    _kalmanHeading = (prediction + gain * innovation + 360) % 360;
    _kalmanP = (1 - gain) * variance;
  }

  // ─── ウェイポイント吸着 ──────────────────────────────────
  double applyMagneticAdsorption(double targetBearing, {double threshold = 5.0}) {
    double diff = (targetBearing - _trueHeading).abs();
    if (diff > 180) diff = 360 - diff;
    return diff <= threshold ? targetBearing : _trueHeading;
  }
}
