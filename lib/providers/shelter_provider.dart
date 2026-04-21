import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../models/shelter.dart';
import '../services/risk_visualization_service.dart';
import '../services/ble_road_report_service.dart';
import '../services/route_compute_service.dart';
import 'region_mode_provider.dart';
import 'shelter_repository.dart';
import 'hazard_service.dart';
import 'nav_target_controller.dart';
import 'disaster_mode_notifier.dart';

/// ============================================================================
/// ShelterProvider — 旧 God Object のファサード
/// ============================================================================
/// このクラスは Wave2 リファクタリング以前は 880 行に膨張していた。
/// 責務は以下のサブクラスに分割済み:
///   - ShelterRepository      : POI/道路/ハザード のデータ読み込み
///   - HazardService          : ハザード判定・浸水円リスト
///   - NavTargetController    : ナビ目的地・到着判定・ルート受信
///   - DisasterModeNotifier   : 災害/緊急モード・言語切替
///
/// 本クラスは既存スクリーン互換のため公開 API を維持しつつ、
/// 上記サブクラスへ委譲する薄いラッパー。
class ShelterProvider with ChangeNotifier {
  // Sub-services (composition)
  final ShelterRepository _repo;
  final HazardService _hazard;
  final NavTargetController _nav;
  final DisasterModeNotifier _mode;

  ShelterProvider({
    ShelterRepository? repository,
    HazardService? hazardService,
    NavTargetController? navController,
    DisasterModeNotifier? modeNotifier,
  })  : _repo = repository ?? ShelterRepository(),
        _hazard = hazardService ?? HazardService(),
        _nav = navController ?? NavTargetController(),
        _mode = modeNotifier ?? DisasterModeNotifier() {
    // 子サービスの変更を親に伝搬（外部の Consumer<ShelterProvider> 互換維持）
    _hazard.addListener(notifyListeners);
    _nav.addListener(notifyListeners);
    _mode.addListener(notifyListeners);
  }

  // Sub-service access (新規コードはこれらを直接使うことを推奨)
  ShelterRepository get repository => _repo;
  HazardService get hazardService => _hazard;
  NavTargetController get navController => _nav;
  DisasterModeNotifier get modeNotifier => _mode;

  // ── State (Region) ────────────────────────────────────────────────
  String _currentRegion = 'jp_tokyo';
  AppRegion _currentAppRegion = AppRegion.japan;
  List<Shelter> _shelters = [];
  List<List<LatLng>> _roadPolylines = [];
  bool _isLoading = false;
  bool _isRoutingLoading = false;

  static final _distance = Distance();

  // ── Getters (互換) ────────────────────────────────────────────────
  String get currentRegion => _currentRegion;
  AppRegion get currentAppRegion => _currentAppRegion;
  List<Shelter> get shelters => _shelters;
  List<List<LatLng>> get hazardPolygons => _hazard.hazardPolygons;
  List<Map<String, dynamic>> get hazardPoints => _hazard.hazardPoints;
  List<List<LatLng>> get roadPolylines => _roadPolylines;
  List<FloodCircleData> get floodRiskCircles => _hazard.floodRiskCircles;
  bool get isLoading => _isLoading;
  bool get isRoutingLoading => _isRoutingLoading;
  bool get isEmergencyMode => _mode.isEmergencyMode;
  bool get isDisasterMode => _mode.isDisasterMode;
  String get currentLanguage => _mode.currentLanguage;
  Shelter? get navTarget => _nav.navTarget;
  bool get isNavigating => _nav.isNavigating;
  bool get isSafeInShelter => _nav.isSafeInShelter;

  /// A* で計算した経路距離 (m)。0 = 未計算。
  double get navRouteDistanceM => _nav.routeDistanceM;
  bool get isComputingRoute => _nav.isComputingRoute;
  List<LatLng> get computedRoute => _nav.computedRoute;

  /// 表示用Shelterリスト (モードに応じてフィルタリング)
  List<Shelter> get displayedShelters {
    if (!isEmergencyMode && !isDisasterMode) return _shelters;
    const officialTypes = [
      'shelter', 'hospital', 'school', 'temple', 'gov', 'community_centre'
    ];
    return _shelters.where((s) => officialTypes.contains(s.type)).toList();
  }

  // ── Region helpers ────────────────────────────────────────────────
  Future<void> setRegionFromCoordinates(double lat, double lng) async {
    if (_currentRegion != 'jp_tokyo') {
      await setRegion('jp_tokyo');
    }
  }

  Future<void> setRegion(String region) async {
    _nav.endNavigation();
    _currentAppRegion = AppRegion.japan;
    _currentRegion = 'jp_tokyo';
    debugPrint('🌏 Region set to: $_currentRegion');
    notifyListeners();
    await loadShelters();
  }

  Map<String, double> getCenter() {
    return {'lat': 35.6812, 'lng': 139.7671};
  }

  // ── Data loading (delegated to repository) ────────────────────────
  Future<void> loadShelters() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();
    try {
      final loaded = await _repo.loadPoiForRegion(_currentRegion);
      _shelters = _repo.filterNoise(loaded);
      debugPrint('✅ Loaded ${_shelters.length} shelters (filtered)');
      // BLE 受信時のなりすまし検証用に既知シェルター位置を共有
      BleRoadReportService.instance.setKnownShelters(_shelters);
    } catch (e) {
      debugPrint('Error loading shelters: $e');
      _shelters = [];
    } finally {
      _isLoading = false;
      notifyListeners();
      await _nav.restoreNavTarget(knownShelters: _shelters);
    }
  }

  Future<void> loadRoadData() async {
    _roadPolylines = await _repo.loadRoadPolylines(_currentRegion);
    notifyListeners();
  }

  Future<void> loadHazardPolygons() async {
    final polys = await _repo.loadHazardPolygons(_currentRegion);
    _hazard.setHazardPolygons(polys);
  }

  // ── Mode (delegated) ──────────────────────────────────────────────
  void toggleEmergencyMode() => _mode.toggleEmergencyMode();
  void toggleDisasterMode() => _mode.toggleDisasterMode();
  void setDisasterMode(bool v) => _mode.setDisasterMode(v);
  void setLanguage(String l) => _mode.setLanguage(l);

  // ── Hazard (delegated) ────────────────────────────────────────────
  bool isPointInHazardZone(LatLng p) => _hazard.isPointInHazardZone(p);
  bool isNearFloodRisk(LatLng p, {double radiusM = 50.0}) =>
      _hazard.isNearFloodRisk(p, radiusM: radiusM);
  bool isShelterInHazardZone(Shelter s) =>
      _hazard.isPointInHazardZone(LatLng(s.lat, s.lng));

  // ── Navigation (delegated) ────────────────────────────────────────
  Future<void> startNavigation(Shelter shelter,
      {LatLng? currentLocation}) async {
    await _nav.startNavigation(shelter, currentLocation: currentLocation);
    if (currentLocation != null) {
      unawaited(_computeSafeRouteFor(shelter, currentLocation));
    }
  }

  /// 洪水・倒壊予測ハザードを絶対回避する A* 経路を計算してキャッシュ。
  /// roads / hazards はキャッシュが空なら遅延ロード。
  Future<void> _computeSafeRouteFor(Shelter target, LatLng from) async {
    _nav.setComputingRoute(true);
    try {
      final features =
          await _repo.loadRoadFeatures(_currentRegion);
      if (features.isEmpty) {
        _nav.setComputedRoute(const [], 0);
        return;
      }
      // hazard が未ロードならロード
      if (_hazard.hazardPolygons.isEmpty) {
        await loadHazardPolygons();
      }
      final hazardSerialized = _hazard.hazardPolygons
          .map((poly) =>
              poly.map((pt) => [pt.latitude, pt.longitude]).toList())
          .toList();

      final result = await compute(
        computeRouteInIsolate,
        RouteComputeParams(
          features: features,
          startLat: from.latitude,
          startLng: from.longitude,
          goalLat: target.lat,
          goalLng: target.lng,
          hazardPolygons: hazardSerialized,
        ),
      ).timeout(const Duration(seconds: 20));

      _nav.setComputedRoute(result.waypoints, result.totalDistanceM);
    } catch (e) {
      debugPrint('❌ Safe route compute failed: $e');
      _nav.setComputedRoute(const [], 0);
    }
  }
  void endNavigation() => _nav.endNavigation();
  void updateSafeRoute(List<List<double>> pts) => _nav.updateSafeRoute(pts);
  List<LatLng> getSafestRouteAsLatLng() => _nav.getSafestRouteAsLatLng();
  bool checkArrival(LatLng pos) => _nav.checkArrival(pos);
  void setSafeInShelter(bool v) => _nav.setSafeInShelter(v);
  Future<void> restoreNavTarget() =>
      _nav.restoreNavTarget(knownShelters: _shelters);

  // ── Shelter search ────────────────────────────────────────────────
  Shelter? getNearestShelter(
    LatLng userLocation, {
    List<String>? includeTypes,
    bool officialOnly = true,
  }) {
    if (_shelters.isEmpty) return null;
    const excludeTypes = ['convenience', 'fuel', 'water', 'store'];
    Shelter? nearest;
    var minDistance = double.infinity;
    for (final shelter in _shelters) {
      final name = shelter.name.toLowerCase();
      if (name == 'unknown' || name.isEmpty || shelter.name == '不明') continue;
      bool isMatch = true;
      if (includeTypes != null && includeTypes.isNotEmpty) {
        if (!includeTypes.contains(shelter.type)) isMatch = false;
      } else if (officialOnly) {
        if (excludeTypes.contains(shelter.type)) isMatch = false;
      }
      if (!isMatch) continue;
      if (_hazard.isPointInHazardZone(LatLng(shelter.lat, shelter.lng)) &&
          !shelter.isFloodShelter) continue;
      final d = _distance.as(
          LengthUnit.Meter, userLocation, LatLng(shelter.lat, shelter.lng));
      if (d < minDistance) {
        minDistance = d;
        nearest = shelter;
      }
    }
    return nearest;
  }

  List<Shelter> getSafeShelters() =>
      _shelters.where((s) => !isShelterInHazardZone(s)).toList();

  Shelter? getNearestSafeShelter(LatLng currentPos) {
    final safe = getSafeShelters();
    if (safe.isEmpty) return null;
    Shelter? nearest;
    var minD = double.infinity;
    for (final s in safe) {
      final d = Geolocator.distanceBetween(
          currentPos.latitude, currentPos.longitude, s.lat, s.lng);
      if (d < minD) {
        minD = d;
        nearest = s;
      }
    }
    return nearest;
  }

  Shelter? getAbsoluteNearest(LatLng currentPos) {
    if (_shelters.isEmpty) return null;
    Shelter? nearest;
    var minCost = double.infinity;
    for (final s in _shelters) {
      final d = Geolocator.distanceBetween(
          currentPos.latitude, currentPos.longitude, s.lat, s.lng);
      final inHazard =
          _hazard.isPointInHazardZone(LatLng(s.lat, s.lng));
      final cost = inHazard ? d * 3.0 : d;
      if (cost < minCost) {
        minCost = cost;
        nearest = s;
      }
    }
    return nearest;
  }

  // ── Offline chat helpers ──────────────────────────────────────────
  String getBlindDirectionText(LatLng from, LatLng to) {
    final bearing = Geolocator.bearingBetween(
        from.latitude, from.longitude, to.latitude, to.longitude);
    final normalized = (bearing + 360) % 360;
    const directions = ['北', '北東', '東', '南東', '南', '南西', '西', '北西'];
    final index = ((normalized + 22.5) / 45).floor() % 8;
    final cardinal = directions[index];
    int clock = (normalized / 30).round();
    if (clock == 0) clock = 12;
    return '$cardinal ($clock時の方向)';
  }

  String generateOfflineResponse(Shelter target, LatLng currentPos) {
    final dist = _distance.as(
        LengthUnit.Meter, currentPos, LatLng(target.lat, target.lng));
    final dir =
        getBlindDirectionText(currentPos, LatLng(target.lat, target.lng));
    return '''
【誘導開始】
目的地: ${target.name}
距離: あと ${dist}m
進む方向: $dir

⚠️ 足元に注意して、スマホのコンパスまたは太陽の位置を頼りに進んでください。''';
  }

  @override
  void dispose() {
    _hazard.removeListener(notifyListeners);
    _nav.removeListener(notifyListeners);
    _mode.removeListener(notifyListeners);
    super.dispose();
  }
}

/// 地域避難所データモデル（共通）
class RegionalShelter {
  final String nameTh;
  final String nameEn;
  final double lat;
  final double lng;
  final String amenityType;
  final bool isFloodShelter;
  final String address;
  final int capacity;

  RegionalShelter({
    required this.nameTh,
    required this.nameEn,
    required this.lat,
    required this.lng,
    this.amenityType = 'shelter',
    this.isFloodShelter = false,
    this.address = '',
    this.capacity = 0,
  });

  LatLng get position => LatLng(lat, lng);

  String getDisplayName(String lang) {
    if (lang == 'th' || lang == 'ja') {
      return nameTh.isNotEmpty ? nameTh : nameEn;
    }
    return nameEn.isNotEmpty ? nameEn : nameTh;
  }
}

/// キャッシュ用ルートデータ（互換のため残置）
class CachedRouteData {
  final List<String> route;
  final Shelter target;
  final double distance;

  CachedRouteData({
    required this.route,
    required this.target,
    required this.distance,
  });
}
