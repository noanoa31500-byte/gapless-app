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

  const RouteComputeParams({
    required this.features,
    required this.startLat,
    required this.startLng,
    required this.goalLat,
    required this.goalLng,
    this.requiresFlatRoute = false,
    this.isElderly = false,
    this.walkSpeedMps = 1.2,
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
  engine.buildGraph(p.features, profile: profile);
  return engine.findRoute(
    LatLng(p.startLat, p.startLng),
    LatLng(p.goalLat, p.goalLng),
    profile: profile,
  );
}
