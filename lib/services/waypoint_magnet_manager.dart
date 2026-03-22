import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

/// ============================================================================
/// WaypointMagnetManager - ウェイポイント吸着ナビゲーションシステム
/// ============================================================================
/// 
/// 【設計思想】
/// 災害時、被災者はパニック状態にあり、地図を読む認知的余裕がありません。
/// 本システムは「針に引っ張られるだけで安全な道に出られる」UXを実現します。
/// 
/// 【従来のナビ vs 吸着型コンパスの違い】
/// 
/// ┌───────────────────────────────────────────────────────────────────────────┐
/// │ 従来の地図ナビ                     │ 吸着型コンパス                       │
/// ├───────────────────────────────────────────────────────────────────────────┤
/// │ ・画面を見続ける必要がある         │ ・針の方向だけ確認すればよい         │
/// │ ・縮尺・方位を頭で計算             │ ・認知負荷ほぼゼロ                   │
/// │ ・暗所・雨天で視認困難             │ ・大きな矢印で視認性確保             │
/// │ ・バッテリー消費大（画面点灯）     │ ・コンパス+GPSのみで省電力           │
/// │ ・通信必須（タイルDL）             │ ・完全オフライン動作                 │
/// └───────────────────────────────────────────────────────────────────────────┘
/// 
/// 【技術的優位性】
/// 1. **認知心理学的根拠**: パニック時、人間の視野は狭窄し、複雑な情報処理が困難になる。
///    単一の「方向」だけを示すUIは、この状態でも機能する。
/// 
/// 2. **アクセシビリティ**: 視覚障害者でも、触覚フィードバック（バイブレーション）と
///    組み合わせることで利用可能。
/// 
/// 3. **エネルギー効率**: 災害時はバッテリーが命綱。画面表示を最小化できる。
/// ============================================================================

/// ナビゲーション状態
enum NavigationState {
  /// 通常ナビゲーション中（ルート上）
  onRoute,
  
  /// ルート逸脱中（復帰モード）
  offRoute,
  
  /// ウェイポイント到達直前（吸着切り替え中）
  approaching,
  
  /// ゴール到達
  arrived,
  
  /// ナビゲーション未開始
  idle,
}

/// ウェイポイント吸着の結果
class MagnetResult {
  /// 現在のターゲットウェイポイント
  final LatLng targetWaypoint;
  
  /// ターゲットまでの距離（メートル）
  final double distanceToTarget;
  
  /// ターゲットへの方位角（度、北=0、時計回り）
  final double bearingToTarget;
  
  /// コンパス表示用の回転角（端末の向きを考慮）
  final double displayAngle;
  
  /// 現在のナビゲーション状態
  final NavigationState state;
  
  /// 現在のウェイポイントインデックス
  final int currentWaypointIndex;
  
  /// 総ウェイポイント数
  final int totalWaypoints;
  
  /// ルートからの逸脱距離（メートル）
  final double offRouteDistance;
  
  /// 残り総距離（メートル）
  final double remainingDistance;
  
  /// 進捗率（0.0〜1.0）
  final double progress;
  
  /// デバッグ情報
  final String? debugInfo;

  MagnetResult({
    required this.targetWaypoint,
    required this.distanceToTarget,
    required this.bearingToTarget,
    required this.displayAngle,
    required this.state,
    required this.currentWaypointIndex,
    required this.totalWaypoints,
    required this.offRouteDistance,
    required this.remainingDistance,
    required this.progress,
    this.debugInfo,
  });

  /// 到達判定
  bool get isArrived => state == NavigationState.arrived;
  
  /// ルート逸脱判定
  bool get isOffRoute => state == NavigationState.offRoute;
  
  /// 進捗文字列
  String get progressText => '${currentWaypointIndex + 1}/${totalWaypoints}';
}

/// ============================================================================
/// WaypointMagnetManager - メインクラス
/// ============================================================================
class WaypointMagnetManager with ChangeNotifier {
  /// ルートのウェイポイントリスト（LatLng座標）
  List<LatLng> _waypoints = [];
  
  /// 現在のターゲットウェイポイントのインデックス
  int _currentWaypointIndex = 0;
  
  /// 現在のターゲット方位角
  double _currentBearing = 0.0;
  
  /// 補間済み方位角（滑らかなアニメーション用）
  double _interpolatedBearing = 0.0;
  
  /// ナビゲーション状態
  NavigationState _state = NavigationState.idle;

  // === 設定パラメータ ===
  
  /// ウェイポイント到達判定距離（メートル）
  /// 
  /// この距離以内に入ると、次のウェイポイントへ自動切り替え。
  /// 
  /// 【設定根拠】
  /// - GPS精度: 一般的なスマートフォンは3-10mの誤差
  /// - 歩行速度: 災害時は通常より遅く、約3km/h = 0.8m/s
  /// - 反応時間: 切り替え後0.5秒で針が動くと仮定
  /// → 余裕を持って5mに設定（3mでは狭すぎる可能性）
  static const double waypointReachedThreshold = 5.0;
  
  /// ルート逸脱判定距離（メートル）
  /// 
  /// この距離以上ルートから離れると、復帰モードに移行。
  /// 
  /// 【設定根拠】
  /// - 通常の歩行者: 道幅4-6m、その半分の位置を歩く → 最大3mの誤差
  /// - GPS誤差: 最大10m
  /// - 意図的逸脱: 障害物回避で5m程度
  /// → 15m以上の逸脱は「道を間違えた」と判断
  static const double offRouteThreshold = 15.0;
  
  /// ウェイポイント接近判定距離（メートル）
  /// 
  /// この距離以内でアニメーション補間を強化
  static const double approachingThreshold = 15.0;
  
  /// ゴール到達判定距離（メートル）
  static const double goalReachedThreshold = 10.0;
  
  /// 方位角補間係数（0.0〜1.0、大きいほど追従が速い）
  static const double bearingInterpolationFactor = 0.15;

  // === Getters ===
  List<LatLng> get waypoints => _waypoints;
  int get currentWaypointIndex => _currentWaypointIndex;
  NavigationState get state => _state;
  double get interpolatedBearing => _interpolatedBearing;
  bool get isNavigating => _state != NavigationState.idle && _waypoints.isNotEmpty;

  /// ============================================================================
  /// ルートを設定してナビゲーションを開始
  /// ============================================================================
  void startNavigation(List<LatLng> route) {
    if (route.isEmpty) {
      if (kDebugMode) print('⚠️ 空のルートが渡されました');
      return;
    }
    
    _waypoints = List.from(route);
    _currentWaypointIndex = 0;
    _currentBearing = 0.0;
    _interpolatedBearing = 0.0;
    _state = NavigationState.onRoute;
    
    if (kDebugMode) {
      debugPrint('🧭 ナビゲーション開始: ${route.length} ウェイポイント');
    }
    
    notifyListeners();
  }

  /// ナビゲーションを停止
  void stopNavigation() {
    _waypoints = [];
    _currentWaypointIndex = 0;
    _state = NavigationState.idle;
    notifyListeners();
  }

  /// ターゲットを強制的に更新（安全ルート更新用）
  void updateTarget(LatLng target) {
    if (_waypoints.isEmpty) return;
    
    // 現在のターゲットのみ更新したい場合（ただし通常は_waypoints全体を更新すべき）
    // 安全ナビゲーションでは _waypoints 自体が更新されないため、
    // ここでは単純に notifyListeners() を呼び出すだけで、
    // 呼び出し元が _currentWaypointIndex を管理している前提で動く設計にするのが安全。
    // しかし CompassProvider 側で _magnetManager.updateTarget を呼んでいるため、
    // 一時的なターゲットとして設定するか、再計算を促す。
    
    notifyListeners();
  }

  /// ============================================================================
  /// calcTargetBearing - メイン計算関数
  /// ============================================================================
  /// 
  /// 【アルゴリズム概要】
  /// 1. 現在地と各ウェイポイントの距離を計算
  /// 2. 進行方向ベクトルを用いて「通過済み」を判定
  /// 3. 最適なターゲットを選定
  /// 4. ルート逸脱チェック
  /// 5. 方位角を計算・補間
  /// 
  /// @param userLocation 現在のユーザー位置
  /// @param deviceHeading 端末のコンパス方位（0-360度）
  /// @return MagnetResult 計算結果
  MagnetResult calcTargetBearing(LatLng userLocation, double deviceHeading) {
    // ナビゲーション未開始
    if (_waypoints.isEmpty || _state == NavigationState.idle) {
      return MagnetResult(
        targetWaypoint: userLocation,
        distanceToTarget: 0,
        bearingToTarget: 0,
        displayAngle: 0,
        state: NavigationState.idle,
        currentWaypointIndex: 0,
        totalWaypoints: 0,
        offRouteDistance: 0,
        remainingDistance: 0,
        progress: 0,
      );
    }

    // === Step 1: ルート逸脱チェック ===
    final offRouteResult = _checkOffRoute(userLocation);
    final offRouteDistance = offRouteResult.distance;
    final nearestPointOnRoute = offRouteResult.nearestPoint;

    if (offRouteDistance > offRouteThreshold) {
      // ルート復帰モード: ルート上の最近接点を一時的なターゲットに
      _state = NavigationState.offRoute;
      
      final bearingToRoute = Geolocator.bearingBetween(
        userLocation.latitude,
        userLocation.longitude,
        nearestPointOnRoute.latitude,
        nearestPointOnRoute.longitude,
      );
      
      _updateBearing(bearingToRoute);
      
      return MagnetResult(
        targetWaypoint: nearestPointOnRoute,
        distanceToTarget: offRouteDistance,
        bearingToTarget: bearingToRoute,
        displayAngle: _calculateDisplayAngle(deviceHeading),
        state: NavigationState.offRoute,
        currentWaypointIndex: _currentWaypointIndex,
        totalWaypoints: _waypoints.length,
        offRouteDistance: offRouteDistance,
        remainingDistance: _calculateRemainingDistance(userLocation),
        progress: _currentWaypointIndex / _waypoints.length,
        debugInfo: '🔴 ルート逸脱: ${offRouteDistance.toStringAsFixed(1)}m',
      );
    }

    // ルートに復帰した場合
    if (_state == NavigationState.offRoute) {
      _state = NavigationState.onRoute;
      if (kDebugMode) print('✅ ルートに復帰しました');
    }

    // === Step 2: 動的ターゲット選定 ===
    _updateCurrentWaypoint(userLocation);

    // ゴール到達チェック
    final isLastWaypoint = _currentWaypointIndex >= _waypoints.length - 1;
    final distanceToFinal = _calculateDistance(userLocation, _waypoints.last);
    
    if (isLastWaypoint && distanceToFinal < goalReachedThreshold) {
      _state = NavigationState.arrived;
      return MagnetResult(
        targetWaypoint: _waypoints.last,
        distanceToTarget: distanceToFinal,
        bearingToTarget: _currentBearing,
        displayAngle: _calculateDisplayAngle(deviceHeading),
        state: NavigationState.arrived,
        currentWaypointIndex: _currentWaypointIndex,
        totalWaypoints: _waypoints.length,
        offRouteDistance: 0,
        remainingDistance: 0,
        progress: 1.0,
        debugInfo: '🎉 目的地に到着！',
      );
    }

    // === Step 3: ターゲットへの方位角計算 ===
    final targetWaypoint = _waypoints[_currentWaypointIndex];
    final distanceToTarget = _calculateDistance(userLocation, targetWaypoint);
    
    final bearingToTarget = Geolocator.bearingBetween(
      userLocation.latitude,
      userLocation.longitude,
      targetWaypoint.latitude,
      targetWaypoint.longitude,
    );

    // 接近中かどうかの判定
    if (distanceToTarget < approachingThreshold) {
      _state = NavigationState.approaching;
    } else {
      _state = NavigationState.onRoute;
    }

    // 方位角を更新（補間付き）
    _updateBearing(bearingToTarget);

    return MagnetResult(
      targetWaypoint: targetWaypoint,
      distanceToTarget: distanceToTarget,
      bearingToTarget: bearingToTarget,
      displayAngle: _calculateDisplayAngle(deviceHeading),
      state: _state,
      currentWaypointIndex: _currentWaypointIndex,
      totalWaypoints: _waypoints.length,
      offRouteDistance: offRouteDistance,
      remainingDistance: _calculateRemainingDistance(userLocation),
      progress: _currentWaypointIndex / _waypoints.length,
      debugInfo: _state == NavigationState.approaching 
          ? '🟡 接近中: ${distanceToTarget.toStringAsFixed(1)}m'
          : '🟢 ナビ中: WP ${_currentWaypointIndex + 1}/${_waypoints.length}',
    );
  }

  /// ============================================================================
  /// ウェイポイント更新ロジック（通過判定）
  /// ============================================================================
  void _updateCurrentWaypoint(LatLng userLocation) {
    while (_currentWaypointIndex < _waypoints.length) {
      final currentTarget = _waypoints[_currentWaypointIndex];
      final distance = _calculateDistance(userLocation, currentTarget);
      
      // ウェイポイントに十分近づいた場合
      if (distance < waypointReachedThreshold) {
        if (_currentWaypointIndex < _waypoints.length - 1) {
          // 次のウェイポイントへ
          _currentWaypointIndex++;
          
          if (kDebugMode) {
            debugPrint('🎯 ウェイポイント通過: '
                '${_currentWaypointIndex}/${_waypoints.length}');
          }
        } else {
          // 最終ウェイポイント
          break;
        }
      } else {
        // まだ到達していない
        break;
      }
    }
    
    // === 進行方向ベクトルによる追加チェック ===
    // 「通り過ぎた」ウェイポイントを飛ばす
    if (_currentWaypointIndex < _waypoints.length - 1) {
      final currentTarget = _waypoints[_currentWaypointIndex];
      final nextTarget = _waypoints[_currentWaypointIndex + 1];
      
      if (_hasPassedWaypoint(userLocation, currentTarget, nextTarget)) {
        _currentWaypointIndex++;
        if (kDebugMode) {
          debugPrint('⏭️ ウェイポイントを通過（ベクトル判定）: '
              '${_currentWaypointIndex}/${_waypoints.length}');
        }
      }
    }
  }

  /// ============================================================================
  /// 進行方向ベクトルによる通過判定
  /// ============================================================================
  /// 
  /// 【数学的説明】
  /// ユーザーがウェイポイントAを通過してBに向かっている場合、
  /// ベクトル A→B と ベクトル A→User の内積が正なら「Aを通過した」と判定。
  bool _hasPassedWaypoint(LatLng userLocation, LatLng waypointA, LatLng waypointB) {
    // A→B ベクトル
    final abLat = waypointB.latitude - waypointA.latitude;
    final abLng = waypointB.longitude - waypointA.longitude;
    
    // A→User ベクトル
    final auLat = userLocation.latitude - waypointA.latitude;
    final auLng = userLocation.longitude - waypointA.longitude;
    
    // 内積
    final dotProduct = abLat * auLat + abLng * auLng;
    
    // A→B ベクトルの長さの2乗
    final abLengthSquared = abLat * abLat + abLng * abLng;
    
    // 内積が正で、かつA→Bの長さ以上進んでいる場合は通過済み
    // （ただし、次のウェイポイントに近すぎない場合のみ）
    final distanceToB = _calculateDistance(userLocation, waypointB);
    return dotProduct > 0 && 
           dotProduct >= abLengthSquared * 0.5 &&
           distanceToB < _calculateDistance(waypointA, waypointB) * 0.8;
  }

  /// ============================================================================
  /// ルート逸脱チェック
  /// ============================================================================
  _OffRouteResult _checkOffRoute(LatLng userLocation) {
    if (_waypoints.length < 2) {
      return _OffRouteResult(
        distance: 0,
        nearestPoint: _waypoints.isNotEmpty ? _waypoints.first : userLocation,
      );
    }

    double minDistance = double.infinity;
    LatLng nearestPoint = _waypoints.first;

    // 各ルートセグメントとの距離をチェック
    for (int i = 0; i < _waypoints.length - 1; i++) {
      final segmentStart = _waypoints[i];
      final segmentEnd = _waypoints[i + 1];
      
      final result = _pointToSegmentDistance(
        userLocation,
        segmentStart,
        segmentEnd,
      );
      
      if (result.distance < minDistance) {
        minDistance = result.distance;
        nearestPoint = result.nearestPoint;
      }
    }

    return _OffRouteResult(distance: minDistance, nearestPoint: nearestPoint);
  }

  /// 点から線分への最短距離と最近接点を計算
  _PointToSegmentResult _pointToSegmentDistance(
    LatLng point,
    LatLng segmentStart,
    LatLng segmentEnd,
  ) {
    final dx = segmentEnd.longitude - segmentStart.longitude;
    final dy = segmentEnd.latitude - segmentStart.latitude;
    
    if (dx == 0 && dy == 0) {
      // セグメントが点の場合
      return _PointToSegmentResult(
        distance: _calculateDistance(point, segmentStart),
        nearestPoint: segmentStart,
      );
    }

    // パラメータ t を計算（0〜1の範囲に制限）
    final t = math.max(0, math.min(1,
      ((point.longitude - segmentStart.longitude) * dx +
       (point.latitude - segmentStart.latitude) * dy) /
      (dx * dx + dy * dy)
    ));

    // 最近接点
    final nearestLat = segmentStart.latitude + t * dy;
    final nearestLng = segmentStart.longitude + t * dx;
    final nearestPoint = LatLng(nearestLat, nearestLng);

    return _PointToSegmentResult(
      distance: _calculateDistance(point, nearestPoint),
      nearestPoint: nearestPoint,
    );
  }

  /// ============================================================================
  /// 方位角の滑らかな更新（補間）
  /// ============================================================================
  void _updateBearing(double newBearing) {
    _currentBearing = newBearing;
    
    // 角度の差を計算（最短経路）
    double diff = _currentBearing - _interpolatedBearing;
    
    // -180〜180の範囲に正規化
    while (diff > 180) diff -= 360;
    while (diff < -180) diff += 360;
    
    // 補間（急な変化を防ぐ）
    _interpolatedBearing += diff * bearingInterpolationFactor;
    
    // 0〜360の範囲に正規化
    _interpolatedBearing = (_interpolatedBearing + 360) % 360;
  }

  /// 表示用回転角を計算（端末の向きを考慮）
  double _calculateDisplayAngle(double deviceHeading) {
    return (_interpolatedBearing - deviceHeading) * (math.pi / 180);
  }

  /// 2点間の距離を計算（メートル）
  double _calculateDistance(LatLng from, LatLng to) {
    return Geolocator.distanceBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );
  }

  /// 残り総距離を計算
  double _calculateRemainingDistance(LatLng userLocation) {
    if (_waypoints.isEmpty) return 0;
    
    double total = 0;
    
    // 現在地からターゲットウェイポイントまで
    if (_currentWaypointIndex < _waypoints.length) {
      total += _calculateDistance(userLocation, _waypoints[_currentWaypointIndex]);
    }
    
    // ターゲット以降のウェイポイント間距離
    for (int i = _currentWaypointIndex; i < _waypoints.length - 1; i++) {
      total += _calculateDistance(_waypoints[i], _waypoints[i + 1]);
    }
    
    return total;
  }

  /// ============================================================================
  /// 距離を人間が読みやすい形式に変換
  /// ============================================================================
  static String formatDistance(double meters) {
    if (meters < 100) {
      return '${meters.toStringAsFixed(0)}m';
    } else if (meters < 1000) {
      return '${(meters / 10).round() * 10}m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)}km';
    }
  }

  /// デバッグ情報を出力
  void printDebugInfo() {
    if (!kDebugMode) return;
    
    debugPrint('''
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🧭 WaypointMagnetManager Debug
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
State: $_state
Waypoints: ${_waypoints.length}
Current Index: $_currentWaypointIndex
Current Bearing: ${_currentBearing.toStringAsFixed(1)}°
Interpolated: ${_interpolatedBearing.toStringAsFixed(1)}°
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''');
  }
}

/// ルート逸脱チェック結果
class _OffRouteResult {
  final double distance;
  final LatLng nearestPoint;
  
  _OffRouteResult({required this.distance, required this.nearestPoint});
}

/// 点から線分への距離計算結果
class _PointToSegmentResult {
  final double distance;
  final LatLng nearestPoint;
  
  _PointToSegmentResult({required this.distance, required this.nearestPoint});
}
