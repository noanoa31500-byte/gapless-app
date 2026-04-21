import 'package:latlong2/latlong.dart';
import '../models/road_feature.dart';
import '../models/user_profile.dart';
import 'safety_route_engine.dart';

export 'safety_route_engine.dart' show RouteResult;

/// Isolate に渡すルート計算パラメータ
class RouteComputeParams {
  final List<RoadFeature> features;
  final double startLat;
  final double startLng;
  final double goalLat;
  final double goalLng;
  final bool requiresFlatRoute;
  final bool isElderly;
  final double walkSpeedMps;

  /// 絶対回避するハザードポリゴン (洪水浸水域・倒壊予測ゾーン等)。
  /// 各ポリゴンは [[lat, lng], ...] 形式の List<List<double>>。
  final List<List<List<double>>> hazardPolygons;

  const RouteComputeParams({
    required this.features,
    required this.startLat,
    required this.startLng,
    required this.goalLat,
    required this.goalLng,
    this.requiresFlatRoute = false,
    this.isElderly = false,
    this.walkSpeedMps = 1.2,
    this.hazardPolygons = const [],
  });
}

/// compute() に渡すトップレベル関数 — SafetyRouteEngine の A* を実行する
RouteResult computeRouteInIsolate(RouteComputeParams p) {
  final engine = SafetyRouteEngine();
  final profile = UserProfile(
    requiresFlatRoute: p.requiresFlatRoute,
    isElderly: p.isElderly,
    walkSpeedMps: p.walkSpeedMps,
  );
  engine.hazardPolygons = p.hazardPolygons
      .map((poly) => poly.map((pt) => LatLng(pt[0], pt[1])).toList())
      .toList();
  engine.buildGraph(p.features, profile: profile);
  return engine.findRoute(
    LatLng(p.startLat, p.startLng),
    LatLng(p.goalLat, p.goalLng),
    profile: profile,
  );
}
