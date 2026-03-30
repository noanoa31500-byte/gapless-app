import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:vibration/vibration.dart';

/// ルート追従型スマートコンパスコントローラー
/// 
/// 防災エンジニアとしての視点:
/// 災害時、ユーザーはパニック状態で地図を正確に読めないことがあります。
/// このコンパスは「見るだけで進むべき方向が分かる」シンプルさを実現します。
class SmartCompassController {
  /// 現在追従中のルート（ノード座標のリスト）
  List<LatLng>? _route;
  
  /// 現在地
  LatLng? _currentLocation;
  
  /// デバイスの向き（度数、北が0度）
  double _deviceHeading = 0.0;
  
  /// 次のウェイポイント（目標地点）
  LatLng? _nextWaypoint;
  
  /// 次のウェイポイントまでの距離（メートル）
  double? _distanceToNext;
  
  /// 目的地までの総距離（メートル）
  double? _distanceToGoal;
  
  /// オフコース状態か
  bool _isOffCourse = false;
  
  /// オフコース判定距離（メートル）
  final double offCourseThreshold;
  
  /// バイブレーション機能を有効にするか
  final bool enableVibration;
  
  /// コンパス状態の変更を通知するStream
  final _stateController = StreamController<CompassState>.broadcast();
  Stream<CompassState> get stateStream => _stateController.stream;

  SmartCompassController({
    this.offCourseThreshold = 20.0,
    this.enableVibration = true,
  });

  /// ルートを設定
  void setRoute(List<LatLng> route) {
    _route = route;
    _updateNextWaypoint();
    _broadcastState();
  }

  /// 現在地を更新
  void updateLocation(LatLng location) {
    _currentLocation = location;
    _updateNextWaypoint();
    _checkOffCourse();
    _calculateDistances();
    _broadcastState();
  }

  /// デバイスの向きを更新
  void updateHeading(double heading) {
    _deviceHeading = heading;
    _broadcastState();
  }

  /// 次のウェイポイントを更新
  /// 
  /// ロジック:
  /// 1. ルート上で現在地に最も近い点を見つける
  /// 2. その点より先の最初の「重要な地点」を次のウェイポイントとする
  void _updateNextWaypoint() {
    if (_route == null || _route!.isEmpty || _currentLocation == null) {
      _nextWaypoint = null;
      return;
    }

    const distance = Distance();
    
    // 1. 現在地に最も近いルート上の点を見つける
    int nearestIndex = 0;
    double minDist = double.infinity;
    
    for (int i = 0; i < _route!.length; i++) {
      final dist = distance.as(
        LengthUnit.Meter,
        _currentLocation!,
        _route![i],
      );
      
      if (dist < minDist) {
        minDist = dist;
        nearestIndex = i;
      }
    }
    
    // 2. 次の重要な地点を決定
    // 戦略: 現在地点から一定距離（10m以上）先、または次の曲がり角
    _nextWaypoint = _findNextSignificantPoint(nearestIndex);
  }

  /// 次の重要な地点を見つける
  /// 
  /// 重要な地点の定義:
  /// - 現在地から10m以上離れている
  /// - 進行方向が大きく変わる曲がり角（30度以上の角度変化）
  LatLng? _findNextSignificantPoint(int currentIndex) {
    if (_route == null || currentIndex >= _route!.length - 1) {
      return _route?.last; // ルートの終点
    }
    
    const distance = Distance();
    const minDistance = 10.0; // 最小距離（メートル）
    const angleThreshold = 30.0; // 角度変化の閾値（度）
    
    // まず、現在地から10m以上離れた点を探す
    for (int i = currentIndex + 1; i < _route!.length; i++) {
      final dist = distance.as(
        LengthUnit.Meter,
        _route![currentIndex],
        _route![i],
      );
      
      if (dist >= minDistance) {
        // さらに先に大きな曲がり角があるかチェック
        for (int j = i + 1; j < _route!.length && j < i + 5; j++) {
          final angle = _calculateAngleChange(
            _route![i - 1],
            _route![i],
            _route![j],
          );
          
          if (angle.abs() >= angleThreshold) {
            return _route![i]; // 曲がり角の手前
          }
        }
        
        return _route![i]; // 通常の次のポイント
      }
    }
    
    return _route!.last; // デフォルトで終点
  }

  /// 3点間の角度変化を計算（度数）
  double _calculateAngleChange(LatLng p1, LatLng p2, LatLng p3) {
    final bearing1 = Geolocator.bearingBetween(
      p1.latitude,
      p1.longitude,
      p2.latitude,
      p2.longitude,
    );
    
    final bearing2 = Geolocator.bearingBetween(
      p2.latitude,
      p2.longitude,
      p3.latitude,
      p3.longitude,
    );
    
    double diff = bearing2 - bearing1;
    
    // -180～180の範囲に正規化
    while (diff > 180) diff -= 360;
    while (diff < -180) diff += 360;
    
    return diff;
  }

  /// オフコース（ルート逸脱）を判定
  void _checkOffCourse() {
    if (_route == null || _route!.isEmpty || _currentLocation == null) {
      _isOffCourse = false;
      return;
    }
    
    const distance = Distance();
    
    // ルート上の最寄り点までの距離を計算
    double minDist = double.infinity;
    for (var point in _route!) {
      final dist = distance.as(LengthUnit.Meter, _currentLocation!, point);
      if (dist < minDist) {
        minDist = dist;
      }
    }
    
    // 閾値を超えたらオフコース
    final wasOffCourse = _isOffCourse;
    _isOffCourse = minDist > offCourseThreshold;
    
    // オフコース状態に変化した場合、バイブレーション警告
    if (_isOffCourse && !wasOffCourse && enableVibration) {
      _triggerOffCourseVibration();
    }
  }

  /// オフコース時のバイブレーション警告
  Future<void> _triggerOffCourseVibration() async {
    try {
      // デバイスがバイブレーション機能を持つか確認
      final hasVibrator = await Vibration.hasVibrator();
      
      if (hasVibrator) {
        // パターン: 短い振動3回（警告）
        await Vibration.vibrate(
          pattern: [0, 200, 100, 200, 100, 200],
          intensities: [0, 128, 0, 128, 0, 128],
        );
        
        if (kDebugMode) {
          debugPrint('⚠️ オフコース警告: バイブレーション実行');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ バイブレーションエラー: $e');
      }
    }
  }

  /// 距離を計算
  void _calculateDistances() {
    if (_currentLocation == null || _nextWaypoint == null) {
      _distanceToNext = null;
      _distanceToGoal = null;
      return;
    }
    
    const distance = Distance();
    
    // 次のウェイポイントまでの距離
    _distanceToNext = distance.as(
      LengthUnit.Meter,
      _currentLocation!,
      _nextWaypoint!,
    );
    
    // 目的地までの距離（ルートの終点まで）
    if (_route != null && _route!.isNotEmpty) {
      _distanceToGoal = distance.as(
        LengthUnit.Meter,
        _currentLocation!,
        _route!.last,
      );
    }
  }

  /// 進むべき方位を計算（度数、北が0度）
  double? getTargetBearing() {
    if (_currentLocation == null || _nextWaypoint == null) {
      return null;
    }
    
    final bearing = Geolocator.bearingBetween(
      _currentLocation!.latitude,
      _currentLocation!.longitude,
      _nextWaypoint!.latitude,
      _nextWaypoint!.longitude,
    );
    
    // -180～180を0～360に変換
    return (bearing + 360) % 360;
  }

  /// コンパスの針の回転角度を計算（度数）
  /// 
  /// 返り値: デバイスの向きに対する相対角度
  /// 0度 = 正面、90度 = 右、-90度 = 左
  double? getCompassRotation() {
    final targetBearing = getTargetBearing();
    if (targetBearing == null) return null;
    
    // デバイスの向きとターゲット方位の差分
    double diff = targetBearing - _deviceHeading;
    
    // -180～180の範囲に正規化
    while (diff > 180) diff -= 360;
    while (diff < -180) diff += 360;
    
    return diff;
  }

  /// 状態を通知
  void _broadcastState() {
    if (_stateController.isClosed) return;
    _stateController.add(CompassState(
      currentLocation: _currentLocation,
      nextWaypoint: _nextWaypoint,
      targetBearing: getTargetBearing(),
      compassRotation: getCompassRotation(),
      distanceToNext: _distanceToNext,
      distanceToGoal: _distanceToGoal,
      isOffCourse: _isOffCourse,
      deviceHeading: _deviceHeading,
    ));
  }

  /// リソースを解放
  void dispose() {
    _stateController.close();
  }
}

/// コンパスの状態
class CompassState {
  final LatLng? currentLocation;
  final LatLng? nextWaypoint;
  final double? targetBearing;
  final double? compassRotation;
  final double? distanceToNext;
  final double? distanceToGoal;
  final bool isOffCourse;
  final double deviceHeading;

  CompassState({
    this.currentLocation,
    this.nextWaypoint,
    this.targetBearing,
    this.compassRotation,
    this.distanceToNext,
    this.distanceToGoal,
    required this.isOffCourse,
    required this.deviceHeading,
  });
}
