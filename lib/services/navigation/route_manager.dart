import 'package:latlong2/latlong.dart';
import '../../models/shelter.dart';

/// RouteManager — 計算済みウェイポイント列の追従管理
///
/// ルート計算は SafetyRouteEngine (route_compute_service.dart) が担う。
/// このクラスは受け取ったウェイポイント列を追従するだけで、
/// 自前でグラフ探索を行わない。
class RouteManager {
  List<LatLng> _activeRoute = [];
  int _currentWaypointIndex = 0;
  Shelter? _currentTarget;
  double _remainingDistance = 0.0;

  static const double _waypointPassThreshold = 15.0;

  bool get hasActiveRoute => _activeRoute.isNotEmpty;
  int get activeRouteLength => _activeRoute.length;
  List<LatLng> get activeRoute => _activeRoute;
  int get currentWaypointIndex => _currentWaypointIndex;
  Shelter? get currentTarget => _currentTarget;
  double get remainingDistance => _remainingDistance;

  void startNavigation(List<LatLng> route, Shelter target) {
    _activeRoute = route;
    _currentTarget = target;
    _currentWaypointIndex = 0;
    _remainingDistance =
        _calcRemaining(route.isNotEmpty ? route.first : LatLng(0, 0));
  }

  void stopNavigation() {
    _activeRoute = [];
    _currentTarget = null;
    _currentWaypointIndex = 0;
  }

  RouteUpdateResult updateProgress(LatLng userLoc) {
    if (_activeRoute.isEmpty) return RouteUpdateResult.empty();

    _remainingDistance = _calcRemaining(userLoc);

    final distToGoal =
        const Distance().as(LengthUnit.Meter, userLoc, _activeRoute.last);
    if (distToGoal < 10.0) return RouteUpdateResult.arrived();

    if (_currentWaypointIndex < _activeRoute.length - 1) {
      final distToTarget = const Distance()
          .as(LengthUnit.Meter, userLoc, _activeRoute[_currentWaypointIndex]);
      if (distToTarget < _waypointPassThreshold) {
        _currentWaypointIndex++;
        return RouteUpdateResult.waypointPassed(
            _activeRoute[_currentWaypointIndex]);
      }
    }

    return RouteUpdateResult.onRoute(_activeRoute[_currentWaypointIndex]);
  }

  double _calcRemaining(LatLng currentLoc) {
    if (_activeRoute.isEmpty || _currentWaypointIndex >= _activeRoute.length)
      return 0.0;
    double total = 0.0;
    const d = Distance();
    total +=
        d.as(LengthUnit.Meter, currentLoc, _activeRoute[_currentWaypointIndex]);
    for (int i = _currentWaypointIndex; i < _activeRoute.length - 1; i++) {
      total += d.as(LengthUnit.Meter, _activeRoute[i], _activeRoute[i + 1]);
    }
    return total;
  }
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
    this.nextWaypoint,
  });

  factory RouteUpdateResult.empty() => RouteUpdateResult();
  factory RouteUpdateResult.arrived() => RouteUpdateResult(arrived: true);
  factory RouteUpdateResult.waypointPassed(LatLng next) =>
      RouteUpdateResult(waypointUpdated: true, nextWaypoint: next);
  factory RouteUpdateResult.onRoute(LatLng next) =>
      RouteUpdateResult(nextWaypoint: next);
}
