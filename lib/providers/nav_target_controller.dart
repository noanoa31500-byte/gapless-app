import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shelter.dart';
import '../services/ble_road_report_service.dart';

/// ============================================================================
/// NavTargetController — 現在のナビ目的地と到着判定の状態管理
/// ============================================================================
/// 旧 ShelterProvider から「nav target / startNavigation / persistence /
/// 到着判定 / 外部ルート受信」を分離。
class NavTargetController extends ChangeNotifier {
  static const _kNavTargetKey = 'nav_target_json';

  Shelter? _navTarget;
  bool _isNavigating = false;
  bool _isSafeInShelter = false;
  List<LatLng>? _externalRoute;

  /// A*で計算したナビ経路 (洪水・倒壊回避済み)
  List<LatLng> _computedRoute = const [];

  /// 経路総距離（m）。0 なら未計算 / 直線フォールバック使用。
  double _routeDistanceM = 0;

  /// 経路計算中フラグ
  bool _isComputingRoute = false;

  Shelter? get navTarget => _navTarget;
  bool get isNavigating => _isNavigating;
  bool get isSafeInShelter => _isSafeInShelter;
  List<LatLng> get computedRoute => _computedRoute;
  double get routeDistanceM => _routeDistanceM;
  bool get isComputingRoute => _isComputingRoute;

  /// ルート計算結果を反映する（呼び出し側の Provider が compute 後に渡す）
  void setComputedRoute(List<LatLng> waypoints, double distanceM) {
    _computedRoute = waypoints;
    _routeDistanceM = distanceM;
    _isComputingRoute = false;
    notifyListeners();
  }

  void setComputingRoute(bool v) {
    _isComputingRoute = v;
    notifyListeners();
  }

  void clearComputedRoute() {
    _computedRoute = const [];
    _routeDistanceM = 0;
    _isComputingRoute = false;
  }

  /// 安全ルート（main.dart Isolate 経由で受信した最新の経路）
  List<LatLng> getSafestRouteAsLatLng() => _externalRoute ?? const [];

  Future<void> startNavigation(Shelter shelter, {LatLng? currentLocation}) async {
    _navTarget = shelter;
    _isNavigating = true;
    notifyListeners();
    unawaited(_persistNavTarget(shelter));
  }

  void endNavigation() {
    _navTarget = null;
    _isNavigating = false;
    clearComputedRoute();
    unawaited(_clearPersistedNavTarget());
    notifyListeners();
  }

  /// main.dart Isolate からの計算結果を取り込む
  void updateSafeRoute(List<List<double>> points) {
    if (points.isEmpty) return;
    _externalRoute = points.map((p) => LatLng(p[0], p[1])).toList();
    notifyListeners();
  }

  /// 到着判定 (30m以内)
  bool checkArrival(LatLng currentPos) {
    if (!_isNavigating || _navTarget == null) return false;
    final d = Geolocator.distanceBetween(
      currentPos.latitude,
      currentPos.longitude,
      _navTarget!.lat,
      _navTarget!.lng,
    );
    if (d <= 30.0) {
      setSafeInShelter(true);
      return true;
    }
    return false;
  }

  void setSafeInShelter(bool value) {
    _isSafeInShelter = value;
    if (value) {
      if (_navTarget != null) {
        BleRoadReportService.instance.enqueueShelterStatus(_navTarget!);
      }
      _isNavigating = false;
      unawaited(_clearPersistedNavTarget());
    }
    notifyListeners();
  }

  /// SharedPreferencesから前回の目的地を復元
  /// [knownShelters] が与えられた場合、IDで照合し最新オブジェクトを優先
  Future<void> restoreNavTarget({List<Shelter> knownShelters = const []}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kNavTargetKey);
    if (raw == null) return;
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final restored = Shelter.fromJson(decoded);
      // IDで完全照合、失敗時は座標で50m以内の最近傍を使用（IDプレフィックス変更に対応）
      Shelter? match = knownShelters.where((s) => s.id == restored.id).firstOrNull;
      if (match == null && knownShelters.isNotEmpty) {
        Shelter? nearest;
        double minDist = 50.0; // 50m以内
        for (final s in knownShelters) {
          final d = Geolocator.distanceBetween(
            restored.lat, restored.lng, s.lat, s.lng);
          if (d < minDist) { minDist = d; nearest = s; }
        }
        match = nearest;
      }
      _navTarget = match ?? restored;
      _isNavigating = true;
      notifyListeners();
      if (kDebugMode) debugPrint('🔄 NavTargetController restored: ${_navTarget!.name}');
    } catch (e) {
      if (kDebugMode) debugPrint('NavTarget restore failed: $e');
      await prefs.remove(_kNavTargetKey);
    }
  }

  Future<void> _persistNavTarget(Shelter shelter) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNavTargetKey, jsonEncode(shelter.toJson()));
  }

  Future<void> _clearPersistedNavTarget() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kNavTargetKey);
  }
}
