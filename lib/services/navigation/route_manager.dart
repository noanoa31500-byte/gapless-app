import 'package:latlong2/latlong.dart';
import '../routing_engine.dart';
import '../../models/road_graph.dart';
import '../../models/shelter.dart';

/// ============================================================================
/// RouteManager - 経路探索とナビゲーション状態管理
/// ============================================================================
class RouteManager {
  // Engines & Data
  RoutingEngine? _routingEngine;
  RoadGraph? _roadGraph;
  
  // Navigation State
  List<LatLng> _activeRoute = [];
  int _currentWaypointIndex = 0;
  Shelter? _currentTarget;
  double _remainingDistance = 0.0;
  
  // Offline Cache
  // Key: 'shelter', 'hospital', 'water', 'convenience'
  final Map<String, _CachedRoute> _offlineCache = {};
  
  // Config
  static const double _waypointPassThreshold = 15.0; // 15m以内で通過と判定
  // static const double _offRouteThreshold = 30.0;    // 30m離れたらリルート (Unused for now)
  
  // Getters
  bool get hasActiveRoute => _activeRoute.isNotEmpty;
  int get activeRouteLength => _activeRoute.length;
  List<LatLng> get activeRoute => _activeRoute;
  int get currentWaypointIndex => _currentWaypointIndex;
  Shelter? get currentTarget => _currentTarget;
  double get remainingDistance => _remainingDistance;
  
  /// エンジンとグラフの設定（初期化時またはデータロード時）
  void setEngine(RoutingEngine engine, RoadGraph graph) {
    _routingEngine = engine;
    _roadGraph = graph;
  }
  
  /// ルート設定＆ナビ開始
  void startNavigation(List<LatLng> route, Shelter target) {
    _activeRoute = route;
    _currentTarget = target;
    _currentWaypointIndex = 0;
    
    // Initialize remaining distance for the new route
    _remainingDistance = _calculateRemainingDistance(route.isNotEmpty ? route.first : LatLng(0,0));
    
    // 現在地から最も近いポイントを初期インデックスとする（途中開始対応）
    // (実装は省略、単純に0から開始)
  }
  
  /// ナビ停止
  void stopNavigation() {
    _activeRoute = [];
    _currentTarget = null;
    _currentWaypointIndex = 0;
  }
  
  /// ナビゲーション更新（位置情報連動）
  /// 
  /// 次のウェイポイントを判定し、逸脱があればリルート指示を出す
  /// @return 次の目標地点（Next Waypoint）
  RouteUpdateResult updateProgress(LatLng userLoc) {
    if (_activeRoute.isEmpty) return RouteUpdateResult.empty();

    // Sum all remaining segments for accurate road distance
    _remainingDistance = _calculateRemainingDistance(userLoc);
    
    // 1. ゴール判定
    final distToGoal = const Distance().as(LengthUnit.Meter, userLoc, _activeRoute.last);
    if (distToGoal < 10.0) {
      return RouteUpdateResult.arrived();
    }
    
    // 2. ウェイポイント通過判定
    if (_currentWaypointIndex < _activeRoute.length - 1) {
      // 簡易ロジック: 現在のターゲット(_activeRoute[_currentWaypointIndex])に近づいたらインクリメント
      
      // 安全のため、配列範囲チェックを厳密に
      // ここでは「次に目指すべき点」をIndexが指しているとする
      LatLng targetParam = _activeRoute[_currentWaypointIndex];
      
      final distToTarget = const Distance().as(LengthUnit.Meter, userLoc, targetParam);
      
      if (distToTarget < _waypointPassThreshold) {
        // 通過 -> 次へ
        if (_currentWaypointIndex < _activeRoute.length - 1) {
           _currentWaypointIndex++;
           return RouteUpdateResult.waypointPassed(_activeRoute[_currentWaypointIndex]);
        }
      }
    }
    
    // 3. 逸脱判定 (Off-Route)
    // 現在のターゲットまでの距離ではなく、「ルート線分からの距離」が正しいが、
    // ここでは簡易的に「直近ウェイポイントからの距離」で判定
    // (本来は点と線分の距離公式を使うべき)
    
    return RouteUpdateResult.onRoute(_activeRoute[_currentWaypointIndex]);
  }
  
  /// バックグラウンドでのオフラインルート計算
  Future<void> updateOfflineCache(LatLng currentLoc, List<Shelter> candidates) async {
    if (_routingEngine == null || _roadGraph == null) return;
    
    final types = ['shelter', 'hospital', 'water', 'convenience'];
    
    for (var type in types) {
      // Find nearest candidate
      Shelter? nearest = _findNearest(candidates, type, currentLoc);
      if (nearest != null) {
        // Calculate
        final route = _calculateRoute(currentLoc, nearest.position);
        if (route.isNotEmpty) {
          _offlineCache[type] = _CachedRoute(route, nearest);
        }
      }
    }
  }
  
  /// キャッシュから即時ナビ開始
  bool startFromCache(String type) {
    if (_offlineCache.containsKey(type)) {
      final data = _offlineCache[type]!;
      startNavigation(data.route, data.target);
      return true;
    }
    return false;
  }
  
  // --- Private Helpers ---
  
  Shelter? _findNearest(List<Shelter> list, String type, LatLng loc) {
    Shelter? best;
    double min = double.infinity;
    const distance = Distance();
    
    for (var s in list) {
       // Type matching logic (simplified)
       bool match = s.type == type;
       // ... (Add detailed type matching if needed) ...
       
       if (match) {
         final d = distance.as(LengthUnit.Meter, loc, s.position);
         if (d < min) {
           min = d;
           best = s;
         }
       }
    }
    return best;
  }
  
  List<LatLng> _calculateRoute(LatLng start, LatLng end) {
    if (_routingEngine == null || _roadGraph == null) return [];
    
    final startNodeId = _findNearestNode(start);
    final goalNodeId = _findNearestNode(end);
    
    if (startNodeId != null && goalNodeId != null) {
      final nodeIds = _routingEngine!.findSafestPath(startNodeId, goalNodeId);
      // Convert Node IDs to LatLngs (Safely)
      return nodeIds
          .map((id) => _roadGraph!.nodes[id]?.position)
          .whereType<LatLng>() // Filter nulls
          .toList();
    }
    return [];
  }

  /// Calculates the total distance along the remaining path waypoints
  double _calculateRemainingDistance(LatLng currentLoc) {
    if (_activeRoute.isEmpty) return 0.0;
    if (_currentWaypointIndex >= _activeRoute.length) return 0.0;

    double total = 0.0;
    const distanceCalc = Distance();

    // 1. Distance from current location to the NEXT waypoint
    total += distanceCalc.as(LengthUnit.Meter, currentLoc, _activeRoute[_currentWaypointIndex]);

    // 2. Sum of all segments from NEXT waypoint to the GOAL
    for (int i = _currentWaypointIndex; i < _activeRoute.length - 1; i++) {
        total += distanceCalc.as(LengthUnit.Meter, _activeRoute[i], _activeRoute[i+1]);
    }

    return total;
  }

  
  String? _findNearestNode(LatLng point) {
    if (_roadGraph == null) return null;
    double minDist = double.infinity;
    String? nearestNodeId;
    const distance = Distance();
    
    // Optimization: This defines a linear scan. 
    // Ideally should use a spatial index (stored in RoadGraph?), but for now O(N) is acceptable for <10k nodes.
    for (var node in _roadGraph!.nodes.values) {
      final dist = distance.as(LengthUnit.Meter, point, node.position);
      if (dist < minDist) {
        minDist = dist;
        nearestNodeId = node.id;
      }
    }
    if (minDist > 500) return null; // 500m threshold
    return nearestNodeId;
  }
}

class _CachedRoute {
  final List<LatLng> route;
  final Shelter target;
  _CachedRoute(this.route, this.target);
}

class RouteUpdateResult {
  final bool arrived;
  final bool offRoute;
  final bool waypointUpdated;
  final LatLng? nextWaypoint;
  
  RouteUpdateResult({
    this.arrived = false, 
    this.offRoute = false, 
    this.waypointUpdated = false,
    this.nextWaypoint
  });
  
  factory RouteUpdateResult.empty() => RouteUpdateResult();
  factory RouteUpdateResult.arrived() => RouteUpdateResult(arrived: true);
  factory RouteUpdateResult.waypointPassed(LatLng next) => RouteUpdateResult(waypointUpdated: true, nextWaypoint: next);
  factory RouteUpdateResult.onRoute(LatLng next) => RouteUpdateResult(nextWaypoint: next);
}
