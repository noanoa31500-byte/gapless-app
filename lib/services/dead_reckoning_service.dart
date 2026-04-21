import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:latlong2/latlong.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'magnetic_declination_config.dart';

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
// 【ステップ検出 (徒歩モード)】
//
//   加速度計の生ノルム |a| のピーク検出（立ち上がりエッジ）を使う。
//   ノルム ≥ 11.5 m/s² かつ 350ms 以上の間隔 → 1歩とみなす。
//   1歩ごとに strideLength × cos(heading) / dLat, sin(heading) / dLng を積算。
//
// 【速度積分 (自転車・車両モード)】
//
//   GPS消失直前の速度をそのまま引き継ぎ、200ms ごとに
//   speed × dt × heading で位置を進める。速度は 0.2%/tick で緩やかに減衰。
//   速度が 0.5 m/s 以下になったら積分を停止する。
//
// ============================================================================

/// 移動モードの分類。GPS 速度から activate() 直前に決定する。
enum MovementMode { walk, bicycle, vehicle }

class DeadReckoningService extends ChangeNotifier {
  // ── 設定定数 ────────────────────────────────────────────────────────────
  static const double defaultStrideLengthM = 0.75;
  static const double _stepThreshold = 11.5; // m/s² (raw accel magnitude)
  /// ステップ判定の上限ガード — 自由落下/衝撃/落下事故等の異常値を除外
  /// 通常歩行は 12〜18 m/s² 程度。50 を超える加速度は端末の物理衝撃とみなす。
  static const double _stepUpperBound = 50.0;
  static const double _stepCooldownMs = 350.0; // 最小ステップ間隔
  /// センサー停止検出のしきい値（5秒間コールバック無し→停止判定）
  static const Duration _sensorStallThreshold = Duration(seconds: 5);
  static const int _headingBufferSize = 7; // ヘディング移動平均サンプル数
  /// 5分（300秒）を超えると精度低下警告
  static const int _accuracyWarningSecs = 300;

  // ── 移動モード分類しきい値 ────────────────────────────────────────────────
  /// この速度（m/s）以上 = 自転車判定（≈ 10.8 km/h）
  static const double _bicycleThresholdMs = 3.0;

  /// この速度（m/s）以上 = 車両判定（≈ 28.8 km/h）
  static const double _vehicleThresholdMs = 8.0;

  /// 速度積分タイマー間隔（ms）
  static const int _velocityTickMs = 200;

  /// タイマー1回ごとの速度減衰係数（5 Hz × 0.2% = ≈ 1%/s 減衰）
  static const double _speedDecayPerTick = 0.998;

  /// この速度以下は停止とみなして積分しない
  static const double _minIntegrationSpeedMs = 0.5;

  // ── 歩幅学習（GPS稼働中のキャリブレーション）────────────────────────────
  /// SharedPreferences に保存するキー
  static const String _stridePrefKey = 'dr_stride_length';

  /// EMA の学習率（新サンプルの重み）
  static const double _calibEmaAlpha = 0.3;

  /// キャリブレーションに必要な最低GPS精度（m）— GPS誤差による歩幅上振れを抑制
  static const double _calibMaxGpsAccuracyM = 15.0;

  /// キャリブレーションに必要な最低移動距離（m）
  static const double _calibMinDistanceM = 8.0;

  /// キャリブレーションに必要な最低歩数
  static const int _calibMinSteps = 6;

  /// 歩幅として有効な速度範囲（m/s）— 0.3未満=ほぼ停止、2.5超=走り
  static const double _calibMinSpeedMs = 0.3;
  static const double _calibMaxSpeedMs = 1.8; // 時速6.5km — 自転車・車を除外

  // ── 状態 ──────────────────────────────────────────────────────────────
  bool _isActive = false;
  LatLng? _estimatedPosition;
  double _headingDeg = 0.0;
  int _stepCount = 0;
  double _strideLengthM = defaultStrideLengthM;

  /// 磁気偏角（度）。activate() 時に起点座標から設定する
  double _declinationDeg = 0.0;

  /// DR 開始時刻
  DateTime? _activatedAt;

  /// ヘディング循環バッファ（角度平均用）
  final List<double> _headingBuffer = [];

  /// 最初のコンパスサンプルが届いたら true。それまでステップ登録を保留する
  bool _compassReady = false;

  /// GPS キャリブレーションで歩幅が一度でも更新されたら true（float比較回避）
  bool _strideHasBeenLearned = false;

  // ── 移動モード状態 ─────────────────────────────────────────────────────
  /// GPS稼働中に推定した移動モード
  MovementMode _movementMode = MovementMode.walk;

  /// GPS消失直前の速度（m/s）
  double _lastGpsSpeedMs = 0.0;

  /// 速度積分中の現在推定速度（m/s）— タイマーごとに減衰
  double _currentSpeedMs = 0.0;

  /// 速度積分による総移動距離（m）— 誤差モデルに使用
  double _integratedDistanceM = 0.0;

  /// 自転車・車両モード用の速度積分タイマー
  Timer? _velocityTimer;

  // ── キャリブレーション状態 ─────────────────────────────────────────────
  /// GPS 稼働中のキャリブレーション歩数カウンター
  int _calibStepCount = 0;

  /// キャリブレーション用加速度計サブスクリプション（DR とは独立）
  StreamSubscription<AccelerometerEvent>? _calibAccelSub;

  /// キャリブレーション用ステップ検出の直前ノルム
  double _lastCalibMagnitude = 0.0;

  /// キャリブレーション用直前ステップ時刻
  DateTime _lastCalibStepTime = DateTime.fromMillisecondsSinceEpoch(0);

  // ── センサー停止検出 ─────────────────────────────────────────────────────
  /// 加速度センサーから最後にコールバックが届いた時刻
  DateTime? _lastAccelEventAt;

  /// センサー停止状態フラグ（UI へ通知）
  bool _sensorStalled = false;

  /// 停止検出用 watchdog タイマー
  Timer? _sensorWatchdog;

  /// センサー停止状態（5秒間コールバック無し）— UI 表示用
  bool get isSensorStalled => _sensorStalled;

  bool get isActive => _isActive;
  LatLng? get estimatedPosition => _estimatedPosition;
  int get stepCount => _stepCount;
  MovementMode get movementMode => _movementMode;
  double get currentSpeedMs => _currentSpeedMs;

  /// DR 開始からの経過秒数（システム時計逆行ガード付き）
  int get elapsedSeconds {
    if (_activatedAt == null) return 0;
    final secs = DateTime.now().difference(_activatedAt!).inSeconds;
    return secs < 0 ? 0 : secs; // 時計逆行クランプ
  }

  /// 推定誤差半径（メートル）— モードごとに異なるモデルを使用
  double get estimatedErrorMeters {
    switch (_movementMode) {
      case MovementMode.walk:
        if (_stepCount == 0) return 0;
        final n = _stepCount.toDouble();
        final randomComponent = _strideLengthM * 0.12 * math.sqrt(n);
        final systematicComponent = _strideLengthM * 0.04 * n;
        return (5.0 + randomComponent + systematicComponent).clamp(5.0, 9999.0);
      case MovementMode.bicycle:
        // 100m到達 ≈ 3分45秒（15km/h 走行時）
        return (10.0 + elapsedSeconds * 0.4 + _integratedDistanceM * 0.04)
            .clamp(10.0, 9999.0);
      case MovementMode.vehicle:
        // 100m到達 ≈ 1分25秒（40km/h 走行時）
        return (15.0 + elapsedSeconds * 1.0 + _integratedDistanceM * 0.06)
            .clamp(15.0, 9999.0);
    }
  }

  /// 5分以上経過または推定誤差 100m 超で精度低下とみなす
  bool get isAccuracyLow =>
      elapsedSeconds >= _accuracyWarningSecs || estimatedErrorMeters >= 100;

  /// 現在の学習済み歩幅（m）
  double get learnedStrideLengthM => _strideLengthM;

  /// GPS キャリブレーションで一度でも学習されていれば true
  bool get hasLearnedStride => _strideHasBeenLearned;

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
    _headingBuffer.clear();
    _compassReady = false; // コンパスサンプルが届くまでステップ登録を保留
    _activatedAt = DateTime.now();
    // GPS モード中のキャリブレーションを停止（DR とセンサー競合を防ぐ）
    stopCalibration();
    // 起点座標から磁気偏角を取得（真北基準に補正するため）
    _declinationDeg = MagneticDeclinationConfig.getDeclination(
      lastKnownPosition.latitude,
      lastKnownPosition.longitude,
    );
    // 速度積分の初期値をリセット
    _currentSpeedMs = _lastGpsSpeedMs;
    _integratedDistanceM = 0.0;
    _startSensors();
    // 自転車・車両モードは速度積分タイマーも起動
    if (_movementMode != MovementMode.walk) _startVelocityIntegrator();
    notifyListeners();
    debugPrint(
      'DeadReckoning: 開始 (起点: $lastKnownPosition, モード: $_movementMode, '
      '速度: ${_currentSpeedMs.toStringAsFixed(1)}m/s, 偏角: ${_declinationDeg.toStringAsFixed(1)}°)',
    );
  }

  /// GPS 復活時に呼ぶ。推定位置と GPS 位置を融合して返す。
  LatLng deactivate(LatLng recoveredGpsPosition) {
    final fused = _fuseWithGps(recoveredGpsPosition);
    _isActive = false;
    _estimatedPosition = null;
    _stepCount = 0;
    _activatedAt = null;
    _headingBuffer.clear();
    _stopVelocityIntegrator();
    _integratedDistanceM = 0.0;
    _currentSpeedMs = 0.0;
    _stopSensors();
    notifyListeners();
    debugPrint('DeadReckoning: 終了 (融合位置: $fused)');
    return fused;
  }

  /// GPS稼働中に移動モードと速度を記録する（DR起動前のみ有効）
  void setMovementContext(double speedMs) {
    if (_isActive) return;
    _lastGpsSpeedMs = speedMs.clamp(0.0, 100.0);
    if (speedMs >= _vehicleThresholdMs) {
      _movementMode = MovementMode.vehicle;
    } else if (speedMs >= _bicycleThresholdMs) {
      _movementMode = MovementMode.bicycle;
    } else {
      _movementMode = MovementMode.walk;
    }
  }

  /// 歩幅を上書きする（設定画面から呼ぶ想定）
  void setStrideLengthM(double meters) {
    _strideLengthM = meters.clamp(0.3, 2.0);
  }

  // ---------------------------------------------------------------------------
  // 歩幅学習（GPS稼働中キャリブレーション）
  // ---------------------------------------------------------------------------

  /// 保存済みの学習歩幅を読み込む。LocationProvider.initLocation() から呼ぶ。
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_stridePrefKey);
    if (saved != null) {
      _strideLengthM = saved.clamp(0.3, 1.5);
      _strideHasBeenLearned = true;
      debugPrint(
        'DeadReckoning: 保存済み歩幅を読み込み: '
        '${_strideLengthM.toStringAsFixed(3)} m',
      );
    }
  }

  /// GPS 稼働中の歩数カウントを開始する。DR 開始時は自動停止される。
  void startCalibration() {
    if (_calibAccelSub != null) return; // すでに稼働中
    _calibStepCount = 0;
    _lastCalibMagnitude = 0.0;
    _lastCalibStepTime = DateTime.fromMillisecondsSinceEpoch(0);
    _calibAccelSub = accelerometerEventStream().listen(
      _onCalibAccelerometer,
      onError: (Object e) => debugPrint('DeadReckoning キャリブ加速度計エラー: $e'),
      cancelOnError: false,
    );
    debugPrint('DeadReckoning: 歩幅学習モード開始');
  }

  /// GPS 稼働中の歩数カウントを停止する。
  void stopCalibration() {
    _calibAccelSub?.cancel();
    _calibAccelSub = null;
    debugPrint('DeadReckoning: 歩幅学習モード停止');
  }

  /// 現在のキャリブレーション歩数を取得してカウンターをリセットする。
  /// LocationProvider の GPS コールバックから呼ぶ。
  int takeCalibStepSnapshot() {
    final count = _calibStepCount;
    _calibStepCount = 0;
    return count;
  }

  /// GPS 移動距離と歩数から実際の歩幅を学習する（EMA 更新）。
  ///
  /// 品質チェック:
  ///   - GPS 精度 < 20 m
  ///   - 移動距離 >= 8 m
  ///   - 歩数 >= 6
  ///   - 速度 0.3〜2.5 m/s（停止・走りを除外）
  Future<void> updateStrideFromGps({
    required double distanceM,
    required int steps,
    required double elapsedSecs,
    required double gpsAccuracyM,
  }) async {
    // ── 品質ゲート ────────────────────────────────────────────────────────
    if (gpsAccuracyM > _calibMaxGpsAccuracyM) return;
    if (distanceM < _calibMinDistanceM) return;
    if (steps < _calibMinSteps) return;
    if (elapsedSecs <= 0) return;

    final speedMs = distanceM / elapsedSecs;
    if (speedMs < _calibMinSpeedMs || speedMs > _calibMaxSpeedMs) return;

    final measured = distanceM / steps;
    if (measured < 0.3 || measured > 1.5) return; // 物理的に異常な値を除外

    // ── EMA 更新 ──────────────────────────────────────────────────────────
    final prev = _strideLengthM;
    _strideLengthM =
        (_calibEmaAlpha * measured + (1 - _calibEmaAlpha) * _strideLengthM)
            .clamp(0.3, 1.5);
    _strideHasBeenLearned = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_stridePrefKey, _strideLengthM);

    debugPrint(
      'DeadReckoning: 歩幅学習 '
      'dist=${distanceM.toStringAsFixed(1)}m '
      'steps=$steps '
      'measured=${measured.toStringAsFixed(3)}m '
      '${prev.toStringAsFixed(3)} → ${_strideLengthM.toStringAsFixed(3)}m',
    );
    notifyListeners();
  }

  /// キャリブレーション専用のステップ検出（DR モードとは独立）
  void _onCalibAccelerometer(AccelerometerEvent event) {
    final mag = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );
    // 上限ガード — 衝撃/落下を歩数として誤計上しない
    if (mag > _stepUpperBound) {
      _lastCalibMagnitude = mag;
      return;
    }
    if (mag >= _stepThreshold && _lastCalibMagnitude < _stepThreshold) {
      final now = DateTime.now();
      final ms = now.difference(_lastCalibStepTime).inMilliseconds.toDouble();
      if (ms >= _stepCooldownMs) {
        _calibStepCount++;
        _lastCalibStepTime = now;
      }
    }
    _lastCalibMagnitude = mag;
  }

  @override
  void dispose() {
    stopCalibration();
    _stopVelocityIntegrator();
    _stopSensors();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 速度積分（自転車・車両モード）
  // ---------------------------------------------------------------------------

  void _startVelocityIntegrator() {
    _velocityTimer?.cancel();
    _velocityTimer = Timer.periodic(
      const Duration(milliseconds: _velocityTickMs),
      (_) => _integrateVelocityTick(),
    );
  }

  void _stopVelocityIntegrator() {
    _velocityTimer?.cancel();
    _velocityTimer = null;
  }

  void _integrateVelocityTick() {
    if (_estimatedPosition == null || !_compassReady) return;

    _currentSpeedMs *= _speedDecayPerTick;
    if (_currentSpeedMs < _minIntegrationSpeedMs) return;

    const dtSecs = _velocityTickMs / 1000.0;
    final distM = _currentSpeedMs * dtSecs;
    _integratedDistanceM += distM;

    final trueHeadingDeg = (_smoothedHeading() - _declinationDeg + 360) % 360;
    final headingRad = trueHeadingDeg * math.pi / 180.0;

    final lat = _estimatedPosition!.latitude;
    final lng = _estimatedPosition!.longitude;
    final dLat = (distM * math.cos(headingRad)) / 111320.0;
    final dLng = (distM * math.sin(headingRad)) /
        (111320.0 * math.cos(lat * math.pi / 180.0));

    _estimatedPosition = LatLng(lat + dLat, lng + dLng);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // センサー購読
  // ---------------------------------------------------------------------------

  void _startSensors() {
    // 加速度計（重力込みの生値）
    _lastAccelEventAt = DateTime.now();
    _sensorStalled = false;
    _accelSub = accelerometerEventStream().listen(
      _onAccelerometer,
      onError: (Object e) {
        debugPrint('DeadReckoning 加速度計エラー: $e');
      },
      cancelOnError: false,
    );

    // センサー停止検出 watchdog（1秒ごとに最終受信時刻をチェック）
    _sensorWatchdog?.cancel();
    _sensorWatchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      final last = _lastAccelEventAt;
      if (last == null) return;
      final age = DateTime.now().difference(last);
      if (age >= _sensorStallThreshold && !_sensorStalled) {
        _sensorStalled = true;
        debugPrint('⚠️ DeadReckoning: センサー停止検出 (${age.inSeconds}s 無応答)');
        notifyListeners();
      }
    });

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
    _sensorWatchdog?.cancel();
    _sensorWatchdog = null;
    _lastAccelEventAt = null;
    if (_sensorStalled) {
      _sensorStalled = false;
      // notify は呼ばない（dispose 系経路でも安全）
    }
  }

  // ---------------------------------------------------------------------------
  // センサーハンドラ
  // ---------------------------------------------------------------------------

  void _onAccelerometer(AccelerometerEvent event) {
    // センサー稼働確認（停止検出用）
    _lastAccelEventAt = DateTime.now();
    if (_sensorStalled) {
      _sensorStalled = false;
      notifyListeners();
    }

    final magnitude = math.sqrt(
      event.x * event.x + event.y * event.y + event.z * event.z,
    );

    // 上限ガード — 自由落下/衝撃などの異常値はステップとして登録しない
    // ただし _lastMagnitude は更新する（次サンプルとの比較が破綻するのを防ぐ）
    if (magnitude > _stepUpperBound) {
      _lastMagnitude = magnitude;
      return;
    }

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
      // 循環バッファに追加（最大 _headingBufferSize サンプル）
      if (_headingBuffer.length >= _headingBufferSize) {
        _headingBuffer.removeAt(0);
      }
      _headingBuffer.add(_headingDeg);
      // 初回サンプル到着 → ステップ登録を解禁
      if (!_compassReady) _compassReady = true;
    }
  }

  /// ヘディングの移動平均を sin/cos 平均で計算する。
  /// 単純算術平均は 359°→1° をまたぐ場合に誤差が出るため円周平均を使う。
  double _smoothedHeading() {
    if (_headingBuffer.isEmpty) return _headingDeg;
    double sinSum = 0, cosSum = 0;
    for (final h in _headingBuffer) {
      final rad = h * math.pi / 180.0;
      sinSum += math.sin(rad);
      cosSum += math.cos(rad);
    }
    final avg = math.atan2(sinSum, cosSum) * 180.0 / math.pi;
    return (avg + 360) % 360;
  }

  // ---------------------------------------------------------------------------
  // 位置積算
  // ---------------------------------------------------------------------------

  void _registerStep() {
    if (_estimatedPosition == null) return;
    // コンパスの最初のサンプルが届く前は方位不明 → カウントだけして位置は動かさない
    if (!_compassReady) {
      _stepCount++;
      return;
    }
    _stepCount++;

    // ① 移動平均ヘディング（ノイズ低減）
    // ② 磁気偏角を加算して真北基準に補正（例: 日本では +7〜9° して磁北→真北）
    final trueHeadingDeg = (_smoothedHeading() - _declinationDeg + 360) % 360;
    final headingRad = trueHeadingDeg * math.pi / 180.0;

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
