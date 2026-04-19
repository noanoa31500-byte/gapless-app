import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/risk_visualization_service.dart';

/// ============================================================================
/// HazardService — ハザードゾーン判定 + リスクスキャン状態
/// ============================================================================
/// 旧 ShelterProvider から「ハザード判定 / 浸水円リスト保持」を分離。
class HazardService extends ChangeNotifier {
  List<List<LatLng>> _hazardPolygons = [];
  List<Map<String, dynamic>> _hazardPoints = [];
  List<FloodCircleData> _floodRiskCircles = [];

  List<List<LatLng>> get hazardPolygons => _hazardPolygons;
  List<Map<String, dynamic>> get hazardPoints => _hazardPoints;
  List<FloodCircleData> get floodRiskCircles => _floodRiskCircles;

  void setHazardPolygons(List<List<LatLng>> polys) {
    _hazardPolygons = polys;
    notifyListeners();
  }

  void setHazardPoints(List<Map<String, dynamic>> pts) {
    _hazardPoints = pts;
    notifyListeners();
  }

  void setFloodRiskCircles(List<FloodCircleData> circles) {
    _floodRiskCircles = circles;
    notifyListeners();
  }

  /// 指定座標がハザードポリゴンに含まれるか
  bool isPointInHazardZone(LatLng point) {
    for (final polygon in _hazardPolygons) {
      if (_isPointInPolygon(point, polygon)) return true;
    }
    return false;
  }

  /// 指定座標が浸水リスク円もしくは hazard point から半径 [radiusM] 以内か
  bool isNearFloodRisk(LatLng point, {double radiusM = 50.0}) {
    for (final circle in _floodRiskCircles) {
      final dist = Geolocator.distanceBetween(
        point.latitude, point.longitude,
        circle.position.latitude, circle.position.longitude,
      );
      if (dist <= radiusM) return true;
    }
    for (final p in _hazardPoints) {
      final t = (p['type'] as String? ?? '').toLowerCase();
      if (!t.contains('flood')) continue;
      final lat = (p['lat'] as num?)?.toDouble() ?? 0;
      final lng = (p['lng'] as num?)?.toDouble() ?? 0;
      if (lat == 0 && lng == 0) continue;
      final dist =
          Geolocator.distanceBetween(point.latitude, point.longitude, lat, lng);
      if (dist <= radiusM) return true;
    }
    return false;
  }

  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    bool inside = false;
    int j = polygon.length - 1;
    for (int i = 0; i < polygon.length; i++) {
      if (((polygon[i].latitude > point.latitude) !=
              (polygon[j].latitude > point.latitude)) &&
          (point.longitude <
              (polygon[j].longitude - polygon[i].longitude) *
                      (point.latitude - polygon[i].latitude) /
                      (polygon[j].latitude - polygon[i].latitude) +
                  polygon[i].longitude)) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }
}
