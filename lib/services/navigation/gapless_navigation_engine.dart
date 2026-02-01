import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'; // For HapticFeedback
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

// Components
import 'compass_logic.dart';
import 'route_manager.dart';
import 'feedback_controller.dart';
import '../routing_engine.dart';
import '../../models/road_graph.dart';
import '../../models/shelter.dart';

/// ============================================================================
/// GapLessNavigationEngine - ナビゲーションの中核エンジン
/// ============================================================================
class GapLessNavigationEngine extends ChangeNotifier {
  // Singleton Pattern (Optional, but useful for Engine)
  static final GapLessNavigationEngine _instance = GapLessNavigationEngine._internal();
  factory GapLessNavigationEngine() => _instance;
  GapLessNavigationEngine._internal();

  // Sub-Systems
  final CompassLogic _compassLogic = CompassLogic();
  final RouteManager _routeManager = RouteManager();
  final FeedbackController _feedbackController = FeedbackController();

  // State
  bool _isNavigating = false;
  LatLng? _currentLocation;
  
  // Streams/Subscriptions
  StreamSubscription<double>? _compassSub;
  StreamSubscription<Position>? _positionSub;

  // Getters
  CompassLogic get compass => _compassLogic;
  RouteManager get route => _routeManager;
  FeedbackController get feedback => _feedbackController;
  bool get isNavigating => _isNavigating;
  LatLng? get currentLocation => _currentLocation;
  
  // Public State Access
  double get currentHeading => _compassLogic.heading;
  double get currentTrueHeading => _compassLogic.trueHeading;
  bool get hasSensorData => _compassLogic.hasSensorData;
  
  /// 初期化 (App Start)
  Future<void> init() async {
    if (kDebugMode) print('🚀 GapLessNavigationEngine: 初期化開始...');
    
    // コンパスを最優先で開始（非同期で待たない）
    final compassStart = _compassLogic.start();
    
    // Listen to Compass Updates
    _compassSub?.cancel();
    _compassSub = _compassLogic.headingStream.listen((heading) {
      _onCompassUpdate(heading);
    });

    // その他の初期化を並列で実行
    await Future.wait([
      compassStart,
      _feedbackController.init(),
    ]);
    
    if (kDebugMode) print('🚀 GapLessNavigationEngine: 通信不要コンポーネントの準備完了');
    
    // Listen to Position Updates (High Accuracy for Nav)
    // これも非同期で開始し、位置が取れるまで待機しない
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high, 
      distanceFilter: 5
    );
    
    _positionSub?.cancel();
    _positionSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        final loc = LatLng(pos.latitude, pos.longitude);
        _currentLocation = loc;
        _onLocationUpdate(loc);
      },
      onError: (e) {
        if (kDebugMode) print('❌ GapLessNavigationEngine: 位置情報ストリームエラー: $e');
      }
    );
  }

  /// エンジン設定 (Graph/RoutingEngine注入)
  void configure(RoutingEngine engine, RoadGraph graph) {
    _routeManager.setEngine(engine, graph);
  }

  /// ナビゲーション開始
  /// @param route 計算済みのルート (List<LatLng>)
  /// @param target 目的地情報
  Future<void> startNavigation(List<LatLng> route, Shelter target) async {
    _routeManager.startNavigation(route, target);
    _isNavigating = true;
    _feedbackController.speak("ナビゲーションを開始します。目的地は、${target.name}です。");
    HapticFeedback.mediumImpact(); // System Haptic
    notifyListeners();
  }

  /// ナビゲーション停止
  void stopNavigation() {
    _routeManager.stopNavigation();
    _isNavigating = false;
    _feedbackController.speak("ナビゲーションを終了します。");
    notifyListeners();
  }

  /// コンパス更新時の処理
  void _onCompassUpdate(double heading) {
    // ウェイポイント吸着 (Magnetic Adsorption)
    if (_isNavigating && _routeManager.hasActiveRoute) {
      // 次のターゲットへの方位を計算
      if (_currentLocation != null) {
        final result = _routeManager.updateProgress(_currentLocation!);
        if (result.nextWaypoint != null) {
          // Calculate bearing for logical purposes if needed, 
          // or pass to magnetic adsorption logic.
          // Currently handled by existing logic or CompassLogic internally.
        }
      }
    }
    notifyListeners();
  }

  /// 位置情報更新時の処理
  void _onLocationUpdate(LatLng loc) {
    // 1. Compass Region Update
    _compassLogic.updateRegion(loc);
    
    // 2. Navigation Progress
    if (_isNavigating) {
      final result = _routeManager.updateProgress(loc);
      
      if (result.arrived) {
        _handleArrival();
      } else if (result.offRoute) {
        _handleOffRoute();
      } else if (result.waypointUpdated) {
        _handleWaypointUpdate(result.nextWaypoint!);
      } else {
        // On Route Check for Feedback
        // Check if facing correct direction
        _checkDirectionFeedback(loc, result.nextWaypoint);
      }
    }
    
    // 3. Offline Cache Update (Background)
    //_routeManager.updateOfflineCache(loc, candidates); // Requires candidates list
  }
  
  void _handleArrival() {
    _feedbackController.speak("目的地に到着しました。お疲れ様でした。");
    _feedbackController.vibrateArrrival();
    stopNavigation();
  }
  
  void _handleOffRoute() {
    _feedbackController.speak("ルートから外れています。再検索します。");
    _feedbackController.vibrateWarning();
    // Trigger Reroute Logic Here
    // _routeManager.recalculate...
  }
  
  void _handleWaypointUpdate(LatLng next) {
    // 次のポイントへ。音声案内など詳細化可能
    // "次は右方向です" 等
    _feedbackController.vibrateOnRoute();
  }
  
  void _checkDirectionFeedback(LatLng loc, LatLng? target) {
    if (target == null) return;
    
    final bearing = Geolocator.bearingBetween(
      loc.latitude, loc.longitude, 
      target.latitude, target.longitude
    );
    
    final currentHead = _compassLogic.trueHeading;
    double diff = (bearing - currentHead).abs();
    if (diff > 180) diff = 360 - diff;
    
    bool isSafe = diff < 30; // 30度以内ならSafe
    // Update Visual
    _feedbackController.updateVisualState(isSafe: isSafe, isOffRoute: false, isNearHazard: false);
    
    if (isSafe && diff < 10) {
      // 非常に正確な方向 -> Light Haptic (Debounced needed widely)
      // _feedbackController.vibrateOnRoute(); 
    }
  }

  /// リソース解放 (センサー停止)
  /// Singletonのため、ChangeNotifier.dispose()は呼ばない。
  void disposeResources() {
    _compassSub?.cancel();
    _positionSub?.cancel();
    _compassLogic.stop(); 
    // Do NOT call super.dispose();
  }
}
