import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

// Models
import '../models/shelter.dart';

// Services
import '../services/navigation/gapless_navigation_engine.dart';
import '../services/waypoint_magnet_manager.dart'; // For MagnetResult/NavigationState enums
import '../services/magnetic_declination_config.dart';
// import '../services/smart_compass_japan.dart'; // For ClockNavigationResult if needed, or remove if unused

/// ============================================================================
/// CompassProvider - コンパス機能管理（GapLessNavigationEngine Wrapper）
/// ============================================================================
class CompassProvider with ChangeNotifier {
  // Core Engine
  final GapLessNavigationEngine _engine = GapLessNavigationEngine();
  
  // Legacy/Compatibility Getters
  GapLessNavigationEngine get engine => _engine;

  // === State Forwarding ===
  double? get heading => _engine.compass.heading;
  double? get trueHeading => _engine.compass.trueHeading;
  double get headingDegrees => heading ?? 0.0;
  double get trueHeadingDegrees => trueHeading ?? 0.0;
  
  bool get isCalibrating => _engine.compass.heading == 0.0; // Simplified check
  bool get isNavigating => _engine.isNavigating;
  bool get isNavigatingRoute => _engine.route.hasActiveRoute;
  bool get isSafeNavigating => _engine.route.hasActiveRoute;
  
  GeoRegion get currentGeoRegion => _engine.compass.currentRegion;
  double get currentDeclination => _engine.compass.currentRegion.declination;
  bool get hapticEnabled => true; // Managed by Engine/FeedbackController
  bool get hasSensorData => _engine.hasSensorData;

  // === MagnetResult Compatibility ===
  // Engine uses RouteManager, but UI expects MagnetResult. 
  // We construct a MagnetResult on the fly or mapping from RouteManager state.
  MagnetResult? get magnetResult {
    if (!_engine.route.hasActiveRoute) return null;
    
    final target = _engine.route.currentTarget?.position ?? _engine.route.activeRoute.lastOrNull;
    if (target == null) return null;

    // Note: accessing private _currentLocation via public getter needed in Engine
    // For now, let's assume Engine exposes currentLocation.
    // If not, we might explicitly track it or ask Engine to expose it.
    
    // Check RouteManager state
    // Ideally RouteManager should expose a "currentStatus" object synonymous to MagnetResult
    
    final userLoc = _engine.currentLocation ?? LatLng(0, 0);
    final bearing = calculateBearing(userLoc.latitude, userLoc.longitude, target.latitude, target.longitude);

    return MagnetResult(
      targetWaypoint: target,
      distanceToTarget: _engine.route.remainingDistance,
      bearingToTarget: bearing,
      displayAngle: (bearing - (_engine.compass.heading)) * (pi / 180),
      state: _engine.route.hasActiveRoute ? NavigationState.onRoute : NavigationState.idle,
      currentWaypointIndex: _engine.route.currentWaypointIndex,
      totalWaypoints: _engine.route.activeRouteLength,
      offRouteDistance: 0,
      remainingDistance: _engine.route.remainingDistance,
      progress: 0,
    );
  }
  
  // Quick fix: RouteManager doesn't expose all these yet.
  // Ideally, RouteManager should have "updateProgress" return a rich status object.
  // For this refactor, I will add `lastMagnetResult` to RouteManager or Engine.
  
  // TEMPORARY: Adapter to keep UI working without rewriting UI logic
  // The UI calls `getDisplayAngle`.
  
  MagnetResult? get lastMagnetResult => magnetResult; // Alias
  NavigationState get navigationState => _engine.route.hasActiveRoute ? NavigationState.onRoute : NavigationState.idle;
  double get remainingDistance => _engine.route.remainingDistance;

  LatLng? get nextSafeWaypoint => _engine.route.currentTarget?.position;

  // === Lifecycle ===
  
  Future<void> startListening() async {
    await _engine.init();
    _engine.addListener(_onEngineUpdate);
  }

  void stopListening() {
    _engine.removeListener(_onEngineUpdate);
    _engine.disposeResources();
  }

  @override
  void dispose() {
    stopListening();
    super.dispose();
  }
  
  void _onEngineUpdate() {
    notifyListeners();
  }

  // === Navigation Methods ===
  
  void startRouteNavigation(List<LatLng> route) {
    // Engine requires Shelter object for target.
    // UI passes List<LatLng>.
    // creating a dummy Shelter or using first point.
    if (route.isEmpty) return;
    
    // We need a specific target. For generic route nav, we can define a Dummy Shelter.
    final lastPt = route.last;
    final target = Shelter(
      id: 'nav_target', 
      name: 'Destination', 
      lat: lastPt.latitude, 
      lng: lastPt.longitude, 
      type: 'user_target', 
      verified: false
    );
    
    _engine.startNavigation(route, target);
  }
  
  void stopRouteNavigation() {
    _engine.stopNavigation();
  }

  // === UI Helpers ===
  
  String getNavigationMessage(String lang) {
     if (!_engine.isNavigating) return _getLocalizedText('waiting_destination', lang);
     // Delegate to Engine or keep local? Engine doesn't have localization logic yet.
     // Keep local map for now.
     return _getLocalizedText('follow_arrow', lang);
  }
  
  double getDisplayAngle({
    required double userLat,
    required double userLng,
    required double targetLat,
    required double targetLng,
  }) {
    // Engine's CompassLogic should provide this or we calculate it here using Engine's trueHeading
    final deviceHeading = _engine.compass.heading; // Use magnetic or true?
    // Using simple calculation
    
    // Check if Engine has "magnetic adsorption" active
    // If Engine is navigating, use adsorbed heading?
    
    final bearing = calculateBearing(userLat, userLng, targetLat, targetLng);
    return (bearing - deviceHeading) * (pi / 180);
  }

  // === Utilities ===
  
  void setGeoRegion(GeoRegion region) {
    _engine.compass.updateRegionWithRegion(region);
    notifyListeners();
  }
  
  void setGeoRegionFromCoordinates(double lat, double lng) {
    _engine.compass.updateRegion(LatLng(lat, lng));
    notifyListeners();
  }
  
  double calculateBearing(double fromLat, double fromLng, double toLat, double toLng) {
    final double lat1 = fromLat * (pi / 180);
    final double lat2 = toLat * (pi / 180);
    final double dLng = (toLng - fromLng) * (pi / 180);
    final double y = sin(dLng) * cos(lat2);
    final double x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng);
    final double bearing = atan2(y, x) * (180 / pi);
    return (bearing + 360) % 360;
  }
  
  // Direction Names from Engine (not implemented there yet, keep here)
  String getDirectionName() => _getDirName(_engine.currentHeading, ['北', '北東', '東', '南東', '南', '南西', '西', '北西']);
  String getDirectionNameEN() => _getDirName(_engine.currentHeading, ['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW']);
  String getDirectionNameTH() => _getDirName(_engine.currentHeading, ['เหนือ', 'ตะวันออกเฉียงเหนือ', 'ตะวันออก', 'ตะวันออกเฉียงใต้', 'ใต้', 'ตะวันตกเฉียงใต้', 'ตะวันตก', 'ตะวันตกเฉียงเหนือ']);

  String _getDirName(double heading, List<String> dirs) {
    if (heading < 0) return '---';
    final idx = ((heading + 22.5) % 360) ~/ 45;
    return dirs[idx];
  }
  
  String _getLocalizedText(String key, String lang) {
     // ... (Same map as before) ...
     const Map<String, Map<String, String>> texts = {
      'waiting_destination': {
        'ja': '目的地を設定してください',
        'en': 'Set a destination',
        'th': 'กรุณาตั้งจุดหมาย',
      },
      'follow_arrow': {
        'ja': '矢印の方向に進んでください',
        'en': 'Follow the arrow',
        'th': 'ตามลูกศร',
      },
     };
     return texts[key]?[lang] ?? texts[key]?['en'] ?? key;
  }
}

// Extensions removed as real getters are now implemented.
