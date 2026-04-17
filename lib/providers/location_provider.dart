import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/dead_reckoning_service.dart';

class LocationProvider extends ChangeNotifier {
  LatLng? _currentLocation;
  String _currentLocationName = '';
  bool _isTracking = false;
  bool _isLoadingLocation = false;
  bool _isWaitingForFreshGPS = false;
  StreamSubscription<Position>? _positionStream;

  // デッドレコニング
  final _deadReckoning = DeadReckoningService();
  Timer? _gpsTimeoutTimer;
  VoidCallback? _drListener; // stop/start サイクルで重複しないよう参照を保持
  static const Duration _gpsTimeoutThreshold = Duration(seconds: 3);

  // 歩幅キャリブレーション用（GPS 連続更新間の距離・時刻を保持）
  LatLng? _lastCalibPosition;
  DateTime? _lastCalibTime;

  // Getters
  LatLng? get currentLocation => _currentLocation;
  bool get isUsingLastKnownLocation => _currentLocation != null && _currentLocationName == 'Last Known Location';
  String get currentLocationName => _currentLocationName;
  bool get isTracking => _isTracking;
  bool get isLoadingLocation => _isLoadingLocation;
  bool get isWaitingForFreshGPS => _isWaitingForFreshGPS;
  LocationPermission? get lastPermissionStatus => _lastPermissionStatus;
  bool get isDeadReckoning => _deadReckoning.isActive;
  int get deadReckoningStepCount => _deadReckoning.stepCount;
  int get deadReckoningElapsedSeconds => _deadReckoning.elapsedSeconds;
  double get deadReckoningErrorMeters => _deadReckoning.estimatedErrorMeters;
  bool get isDeadReckoningAccuracyLow => _deadReckoning.isAccuracyLow;
  double get learnedStrideLengthM => _deadReckoning.learnedStrideLengthM;
  bool get hasLearnedStride => _deadReckoning.hasLearnedStride;
  DeadReckoningService get deadReckoningService => _deadReckoning;

  // Internal State
  LocationPermission? _lastPermissionStatus;

/// アプリ起動時の初期化処理（権限リクエストと現在地取得）
  Future<void> initLocation() async {
    // 保存済み学習歩幅を読み込む
    await _deadReckoning.init();
    try {
      // 権限チェックとリクエスト
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      _lastPermissionStatus = permission;
      notifyListeners();
      
      // 許可されていれば読み込み開始（キャッシュ優先）
      if (permission != LocationPermission.denied && 
          permission != LocationPermission.deniedForever) {
        await loadLastKnownLocation();
      }
    } catch (e) {
      debugPrint('Error in initLocation: $e');
    }
  }

  /// 起動時に最新のGPSを粘り強く待つ (最大 timeout 秒)
  Future<bool> waitForFreshGPS({int timeoutSeconds = 10}) async {
    _isWaitingForFreshGPS = true;
    notifyListeners();
    
    try {
      // 位置情報サービスが有効かチェック
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _isWaitingForFreshGPS = false;
        notifyListeners();
        return false;
      }

      // 位置情報の権限チェック
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        _isWaitingForFreshGPS = false;
        notifyListeners();
        return false;
      }

      // 現在位置を取得
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: timeoutSeconds),
      );
      
      _currentLocation = LatLng(position.latitude, position.longitude);
      _currentLocationName = 'GPS Location';

      // 保存
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('last_lat', position.latitude);
      await prefs.setDouble('last_lng', position.longitude);
      await prefs.setString('last_loc_time', DateTime.now().toIso8601String());

      _isWaitingForFreshGPS = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('⚠️ Fresh GPS acquisition failed/timeout: $e');
      _isWaitingForFreshGPS = false;
      notifyListeners();
      return false;
    }
  }

  /// 最後に保存された位置情報を読み込む
  Future<void> loadLastKnownLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble('last_lat');
      final lng = prefs.getDouble('last_lng');

      if (lat != null && lng != null) {
        _currentLocation = LatLng(lat, lng);
        _currentLocationName = 'Last Known Location';
        notifyListeners();
        debugPrint('📍 Last known location loaded: $_currentLocation');
      }
    } catch (e) {
      debugPrint('Error loading last known location: $e');
    }
  }

  // ---------------------------------------------------------------------------

  /// GPS位置情報を取得
  Future<bool> getCurrentGPSLocation() async {
    _isLoadingLocation = true;
    notifyListeners();

    try {
      // 位置情報サービスが有効かチェック
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _isLoadingLocation = false;
        notifyListeners();
        debugPrint('❌ Location services are disabled.');
        return false;
      }

      // 位置情報の権限チェック
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        _lastPermissionStatus = permission;
        if (permission == LocationPermission.denied) {
          _isLoadingLocation = false;
          notifyListeners();
          debugPrint('❌ Location permissions are denied');
          return false;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _lastPermissionStatus = permission;
        _isLoadingLocation = false;
        notifyListeners();
        debugPrint('❌ Location permissions are permanently denied');
        return false;
      }

      // 現在位置を取得
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10), // Add timeout
      );
      
      _lastPermissionStatus = LocationPermission.whileInUse; // Assumed success

      _currentLocation = LatLng(position.latitude, position.longitude);
      
      // 位置情報を永続化 (オフライン起動用)
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('last_lat', position.latitude);
        await prefs.setDouble('last_lng', position.longitude);
        await prefs.setString('last_loc_time', DateTime.now().toIso8601String());
      } catch (e) {
        debugPrint('⚠️ 位置情報の保存に失敗: $e');
      }

      _currentLocationName = 'GPS Location';
      _isLoadingLocation = false;
      notifyListeners();

      debugPrint('📍 GPS Location acquired: $_currentLocation');
      return true;
    } catch (e) {
      _isLoadingLocation = false;
      notifyListeners();
      debugPrint('❌ Error getting GPS location: $e');
      return false;
    }
  }

  /// リアルタイム位置追跡を開始
  Future<void> startLocationTracking() async {
    if (_isTracking) return;

    // 権限チェック
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      debugPrint('❌ Location services are disabled.');
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        debugPrint('❌ Location permissions are denied');
        return;
      }
    }

    // 位置情報の購読開始
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // 10メートル移動ごとに更新
    );

    // DR 推定位置を現在地に反映（重複登録を防ぐため前回分を先に除去）
    if (_drListener != null) {
      _deadReckoning.removeListener(_drListener!);
    }
    _drListener = () {
      if (_deadReckoning.isActive && _deadReckoning.estimatedPosition != null) {
        _currentLocation = _deadReckoning.estimatedPosition;
        notifyListeners();
      }
    };
    _deadReckoning.addListener(_drListener!);

    // GPS 稼働中の歩幅学習を開始
    _lastCalibPosition = null;
    _lastCalibTime = null;
    _deadReckoning.startCalibration();

    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position position) async {
        _resetGpsTimeoutTimer();

        final gpsPos = LatLng(position.latitude, position.longitude);
        final now = position.timestamp;

        if (_deadReckoning.isActive) {
          // DR モードから GPS 復帰 → 融合位置を使う
          _currentLocation = _deadReckoning.deactivate(gpsPos);
          // GPS 復帰後すぐに学習再開（キャリブ基準点をリセット）
          _lastCalibPosition = gpsPos;
          _lastCalibTime = now;
          _deadReckoning.startCalibration();
        } else {
          // GPS 正常稼働中 → 前回位置との差分で歩幅を学習（await で保存完了を保証）
          await _updateStrideCalibration(gpsPos, position.accuracy, now);
          _currentLocation = gpsPos;
        }
        _currentLocationName = 'GPS Tracking';
        notifyListeners();
        debugPrint('📍 GPS Tracking update: $_currentLocation');
      },
    );

    // 最初のタイマーをセット
    _resetGpsTimeoutTimer();

    _isTracking = true;
    notifyListeners();
    debugPrint('✅ GPS tracking started');
  }

  /// GPS 更新ごとに歩幅学習を実行する。
  /// [newPos] 今回の GPS 座標, [accuracy] GPS 水平精度(m), [now] 計測時刻
  Future<void> _updateStrideCalibration(
    LatLng newPos,
    double accuracy,
    DateTime now,
  ) async {
    final last = _lastCalibPosition;
    final lastTime = _lastCalibTime;

    if (last != null && lastTime != null) {
      final distM = Geolocator.distanceBetween(
        last.latitude, last.longitude,
        newPos.latitude, newPos.longitude,
      );
      final elapsedSecs =
          now.difference(lastTime).inMilliseconds / 1000.0;
      final steps = _deadReckoning.takeCalibStepSnapshot();

      await _deadReckoning.updateStrideFromGps(
        distanceM: distM,
        steps: steps,
        elapsedSecs: elapsedSecs,
        gpsAccuracyM: accuracy,
      );
    }

    _lastCalibPosition = newPos;
    _lastCalibTime = now;
  }

  /// リアルタイム位置追跡を停止
  void stopLocationTracking() {
    _positionStream?.cancel();
    _positionStream = null;
    _gpsTimeoutTimer?.cancel();
    _deadReckoning.stopCalibration();
    _lastCalibPosition = null;
    _lastCalibTime = null;
    _isTracking = false;
    notifyListeners();
    debugPrint('⏹️ GPS tracking stopped');
  }

  void _resetGpsTimeoutTimer() {
    _gpsTimeoutTimer?.cancel();
    _gpsTimeoutTimer = Timer(_gpsTimeoutThreshold, () {
      if (_currentLocation != null && !_deadReckoning.isActive) {
        _deadReckoning.activate(_currentLocation!);
        _currentLocationName = 'DR Estimated';
        notifyListeners();
        debugPrint('📍 GPS timeout → DR モード開始');
      }
    });
  }

  /// 現在地を設定
  void setCurrentLocation(LatLng location, {String name = 'Current Location'}) {
    _currentLocation = location;
    _currentLocationName = name;
    notifyListeners();
  }


  /// 現在地をクリア
  void exitDemoMode() {
    _currentLocation = null;
    _currentLocationName = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _gpsTimeoutTimer?.cancel();
    if (_drListener != null) _deadReckoning.removeListener(_drListener!);
    _deadReckoning.dispose();
    stopLocationTracking();
    super.dispose();
  }
}
