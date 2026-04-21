import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../data/map_repository.dart';
import '../providers/region_mode_provider.dart';
import '../utils/localization.dart';

/// ============================================================================
/// OfflineRiskScanner - 完全オフラインリスク検知エンジン
/// ============================================================================
///
/// 【設計思想】
/// 災害時はインターネット接続が期待できません。
/// 本クラスは、アプリ内にバンドルされたJSONデータのみを使用し、
/// **端末内部の計算だけで**周囲のリスクを検知します。
///
/// 【リスクレーダー = 🌊深水 + 🌀激流の2分類のみ】
/// - 深水ゾーン (deepWater): 水深が閾値以上の方向を警告
/// - 激流ゾーン (rapidFlow): 流速が速い方向を警告
/// ============================================================================

/// リスクの種類
enum RiskType {
  /// 浸水リスク（水深0.5m以上）
  deepWater,

  /// 激流リスク（流速が速い）
  rapidFlow,
}

/// ============================================================================
/// RiskZone - 危険ゾーン（方位角範囲）
/// ============================================================================
class RiskZone {
  final RiskType type;
  final double startBearing;
  final double endBearing;
  final double severity;
  final double nearestDistance;
  final String details;
  final Map<String, String> warnings;

  RiskZone({
    required this.type,
    required this.startBearing,
    required this.endBearing,
    required this.severity,
    required this.nearestDistance,
    required this.details,
    required this.warnings,
  });

  bool containsBearing(double bearing) {
    double b = bearing % 360;
    if (b < 0) b += 360;
    double start = startBearing % 360;
    if (start < 0) start += 360;
    double end = endBearing % 360;
    if (end < 0) end += 360;
    if (start > end) {
      return b >= start || b <= end;
    }
    return b >= start && b <= end;
  }

  String get warningJa => warnings['ja'] ?? '危険な方向です';
  String get warningEn => warnings['en'] ?? 'Danger ahead';
  String get warningTh => warnings['th'] ?? 'อันตราย';

  String get warningLocalized =>
      warnings[GapLessL10n.lang] ?? warnings['en'] ?? warnings['ja'] ?? 'Danger ahead';

  @override
  String toString() => 'RiskZone($type: ${startBearing.toStringAsFixed(0)}°-${endBearing.toStringAsFixed(0)}°, severity: ${(severity * 100).toStringAsFixed(0)}%)';
}

/// ============================================================================
/// RiskScanResult - スキャン結果
/// ============================================================================
class RiskScanResult {
  final List<RiskZone> riskZones;
  final double safestBearing;
  final double safeBearingStart;
  final double safeBearingEnd;
  final double scanRadius;
  final LatLng location;
  final DateTime timestamp;
  final double overallRisk;

  RiskScanResult({
    required this.riskZones,
    required this.safestBearing,
    required this.safeBearingStart,
    required this.safeBearingEnd,
    required this.scanRadius,
    required this.location,
    required this.timestamp,
    required this.overallRisk,
  });

  List<RiskZone> get deepWaterZones =>
      riskZones.where((z) => z.type == RiskType.deepWater).toList();

  List<RiskZone> get rapidFlowZones =>
      riskZones.where((z) => z.type == RiskType.rapidFlow).toList();

  List<RiskZone> getRisksAtBearing(double bearing) {
    return riskZones.where((z) => z.containsBearing(bearing)).toList();
  }

  bool isSafeBearing(double bearing) {
    return getRisksAtBearing(bearing).isEmpty;
  }
}

/// ============================================================================
/// 浸水予測データ（キャッシュ用）
/// ============================================================================
class _FloodPoint {
  final LatLng location;
  final double predDepth;
  final String predSpeed;
  final int riskScore;
  final String displayType;

  _FloodPoint({
    required this.location,
    required this.predDepth,
    required this.predSpeed,
    required this.riskScore,
    required this.displayType,
  });
}

/// ============================================================================
/// OfflineRiskScanner - メインクラス
/// ============================================================================
class OfflineRiskScanner {
  final List<_FloodPoint> _floodPoints = [];
  final Map<String, List<_FloodPoint>> _floodPointGrid = {};

  bool _isLoaded = false;
  bool _isLoading = false;
  String? _loadError;

  static const double defaultScanRadius = 100.0;
  static const double deepWaterThreshold = 0.5;
  static const double gridSize = 0.01;

  bool get isLoaded => _isLoaded;
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;
  int get floodPointCount => _floodPoints.length;

  /// region: 現在の地域 (RegionRegistry.byId or detectFromGPS)。
  Future<void> loadData({Region? region}) async {
    if (_isLoaded || _isLoading) return;
    _isLoading = true;
    _loadError = null;
    try {
      await _loadFloodPredictionData(region ?? RegionRegistry.japan);
      _isLoaded = true;
      if (kDebugMode) {
        debugPrint('🌊 OfflineRiskScanner: データロード完了');
        debugPrint('   - 浸水予測ポイント: ${_floodPoints.length}');
      }
    } catch (e) {
      _loadError = e.toString();
      if (kDebugMode) {
        debugPrint('❌ OfflineRiskScanner: データロードエラー: $e');
      }
    } finally {
      _isLoading = false;
    }
  }

  Future<void> _loadFloodPredictionData(Region region) async {
    final hazardFile = '${region.gplbAssetPath}_hazard.gplh';
    try {
      final jsonString = await MapRepository.instance.readString(hazardFile);
      final data = json.decode(jsonString) as Map<String, dynamic>;

      if (data['type'] == 'point_hazard') {
        final points = data['points'] as List<dynamic>? ?? [];
        for (final p in points) {
          final point = p as Map<String, dynamic>;
          final t = (point['type'] as String? ?? '').toLowerCase();
          final rs = (point['risk_score'] as num?)?.toInt() ?? 0;
          if (!t.contains('flood') && rs == 0) continue;
          final lat = (point['lat'] as num).toDouble();
          final lng = (point['lng'] as num? ?? point['lon'] as num? ?? 0).toDouble();
          final floodPoint = _FloodPoint(
            location: LatLng(lat, lng),
            predDepth: (point['pred_depth'] as num?)?.toDouble() ?? 0.0,
            predSpeed: point['pred_speed'] as String? ?? 'None',
            riskScore: rs,
            displayType: point['display_type'] as String? ?? t,
          );
          _floodPoints.add(floodPoint);
          _addFloodPointToGrid(floodPoint);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 浸水予測データのロードをスキップ: $e');
      }
    }
  }

  void _addFloodPointToGrid(_FloodPoint point) {
    final key = _getGridKey(point.location);
    _floodPointGrid.putIfAbsent(key, () => []).add(point);
  }

  String _getGridKey(LatLng location) {
    final lat = (location.latitude / gridSize).floor() * gridSize;
    final lon = (location.longitude / gridSize).floor() * gridSize;
    return '${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}';
  }

  List<String> _getNearbyGridKeys(LatLng location) {
    final baseLat = (location.latitude / gridSize).floor() * gridSize;
    final baseLon = (location.longitude / gridSize).floor() * gridSize;
    final keys = <String>[];
    for (int i = -1; i <= 1; i++) {
      for (int j = -1; j <= 1; j++) {
        final lat = baseLat + i * gridSize;
        final lon = baseLon + j * gridSize;
        keys.add('${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}');
      }
    }
    return keys;
  }

  RiskScanResult scanRisks(LatLng location, {double radius = defaultScanRadius}) {
    if (!_isLoaded) {
      return RiskScanResult(
        riskZones: [],
        safestBearing: 0,
        safeBearingStart: 0,
        safeBearingEnd: 360,
        scanRadius: radius,
        location: location,
        timestamp: DateTime.now(),
        overallRisk: 0,
      );
    }

    final riskZones = <RiskZone>[];
    riskZones.addAll(_scanDeepWaterRisks(location, radius));
    final safeZone = _findSafestBearing(riskZones);
    final overallRisk = _calculateOverallRisk(riskZones);

    return RiskScanResult(
      riskZones: riskZones,
      safestBearing: safeZone['bearing']!,
      safeBearingStart: safeZone['start']!,
      safeBearingEnd: safeZone['end']!,
      scanRadius: radius,
      location: location,
      timestamp: DateTime.now(),
      overallRisk: overallRisk,
    );
  }

  List<RiskZone> _scanDeepWaterRisks(LatLng location, double radius) {
    final zones = <RiskZone>[];
    final nearbyKeys = _getNearbyGridKeys(location);
    final bearingDepthMap = <int, _FloodPoint>{};
    final bearingRapidFlowMap = <int, _FloodPoint>{};

    for (final key in nearbyKeys) {
      final points = _floodPointGrid[key];
      if (points == null) continue;

      for (final point in points) {
        final distance = _haversineDistance(location, point.location);
        if (distance > radius) continue;

        final bearing = _calculateBearing(location, point.location);
        final bearingBucket = (bearing / 10).round() * 10;

        if (point.predDepth >= deepWaterThreshold) {
          if (!bearingDepthMap.containsKey(bearingBucket) ||
              point.predDepth > bearingDepthMap[bearingBucket]!.predDepth) {
            bearingDepthMap[bearingBucket] = point;
          }
        }

        if (_isRapidFlow(point.predSpeed) && point.predDepth >= 0.3) {
          if (!bearingRapidFlowMap.containsKey(bearingBucket) ||
              _getFlowSpeedPriority(point.predSpeed) >
                  _getFlowSpeedPriority(bearingRapidFlowMap[bearingBucket]!.predSpeed)) {
            bearingRapidFlowMap[bearingBucket] = point;
          }
        }
      }
    }

    zones.addAll(_groupBearingsIntoZones(location, bearingDepthMap, RiskType.deepWater));
    zones.addAll(_groupBearingsIntoZones(location, bearingRapidFlowMap, RiskType.rapidFlow));
    return zones;
  }

  bool _isRapidFlow(String predSpeed) {
    final lower = predSpeed.toLowerCase();
    return lower == 'fast' || lower == 'moderate' || lower == 'rapid';
  }

  int _getFlowSpeedPriority(String predSpeed) {
    switch (predSpeed.toLowerCase()) {
      case 'fast':
      case 'rapid':
        return 3;
      case 'moderate':
        return 2;
      case 'slow':
        return 1;
      default:
        return 0;
    }
  }

  List<RiskZone> _groupBearingsIntoZones(
    LatLng location,
    Map<int, _FloodPoint> bearingMap,
    RiskType type,
  ) {
    final zones = <RiskZone>[];
    if (bearingMap.isEmpty) return zones;

    final sortedBearings = bearingMap.keys.toList()..sort();

    int startBearing = sortedBearings.first;
    int prevBearing = startBearing;
    double maxValue = bearingMap[startBearing]!.predDepth;
    String maxSpeed = bearingMap[startBearing]!.predSpeed;
    double minDistance = _haversineDistance(location, bearingMap[startBearing]!.location);

    for (int i = 1; i <= sortedBearings.length; i++) {
      final isLast = i == sortedBearings.length;
      final currentBearing = isLast ? -999 : sortedBearings[i];

      if (isLast || (currentBearing - prevBearing > 20)) {
        zones.add(_createZoneForType(
          type: type,
          startBearing: (startBearing - 5.0 + 360) % 360,
          endBearing: (prevBearing + 5.0) % 360,
          maxDepth: maxValue,
          maxSpeed: maxSpeed,
          minDistance: minDistance,
        ));

        if (!isLast) {
          startBearing = currentBearing;
          maxValue = bearingMap[currentBearing]!.predDepth;
          maxSpeed = bearingMap[currentBearing]!.predSpeed;
          minDistance = _haversineDistance(location, bearingMap[currentBearing]!.location);
        }
      } else {
        final point = bearingMap[currentBearing]!;
        if (point.predDepth > maxValue) {
          maxValue = point.predDepth;
        }
        if (_getFlowSpeedPriority(point.predSpeed) > _getFlowSpeedPriority(maxSpeed)) {
          maxSpeed = point.predSpeed;
        }
        final dist = _haversineDistance(location, point.location);
        if (dist < minDistance) {
          minDistance = dist;
        }
      }

      prevBearing = currentBearing;
    }

    return zones;
  }

  RiskZone _createZoneForType({
    required RiskType type,
    required double startBearing,
    required double endBearing,
    required double maxDepth,
    required String maxSpeed,
    required double minDistance,
  }) {
    switch (type) {
      case RiskType.deepWater:
        return RiskZone(
          type: type,
          startBearing: startBearing,
          endBearing: endBearing,
          severity: math.min(1.0, maxDepth / 2.0),
          nearestDistance: minDistance,
          details: '水深${maxDepth.toStringAsFixed(1)}m',
          warnings: {
            'ja': '🌊 浸水危険！水深${maxDepth.toStringAsFixed(1)}m',
            'en': '🌊 Flood risk! Depth ${maxDepth.toStringAsFixed(1)}m',
            'th': '🌊 อันตรายน้ำท่วม! ลึก ${maxDepth.toStringAsFixed(1)} ม.',
          },
        );
      case RiskType.rapidFlow:
        final speedText = _getSpeedText(maxSpeed);
        return RiskZone(
          type: type,
          startBearing: startBearing,
          endBearing: endBearing,
          severity: math.min(1.0, _getFlowSpeedPriority(maxSpeed) / 3.0),
          nearestDistance: minDistance,
          details: '激流($speedText)',
          warnings: {
            'ja': '🌀 激流危険！流速が速い（$speedText）',
            'en': '🌀 Rapid flow! Speed: $speedText',
            'th': '🌀 น้ำไหลเชี่ยว! ความเร็ว: $speedText',
          },
        );
    }
  }

  String _getSpeedText(String predSpeed) {
    switch (predSpeed.toLowerCase()) {
      case 'fast':
      case 'rapid':
        return '高速';
      case 'moderate':
        return '中速';
      case 'slow':
        return '低速';
      default:
        return predSpeed;
    }
  }

  Map<String, double> _findSafestBearing(List<RiskZone> zones) {
    if (zones.isEmpty) {
      return {'bearing': 0.0, 'start': 0.0, 'end': 360.0};
    }

    double maxSafeStart = 0;
    double maxSafeEnd = 0;
    double maxSafeWidth = 0;

    for (int start = 0; start < 360; start += 10) {
      int safeWidth = 0;
      for (int offset = 0; offset < 360; offset += 10) {
        final bearing = (start + offset) % 360;
        final isSafe = zones.every((z) => !z.containsBearing(bearing.toDouble()));
        if (isSafe) {
          safeWidth += 10;
        } else {
          break;
        }
      }

      if (safeWidth > maxSafeWidth) {
        maxSafeWidth = safeWidth.toDouble();
        maxSafeStart = start.toDouble();
        maxSafeEnd = (start + safeWidth) % 360;
      }
    }

    final safestBearing = (maxSafeStart + maxSafeWidth / 2) % 360;
    return {
      'bearing': safestBearing,
      'start': maxSafeStart,
      'end': maxSafeEnd,
    };
  }

  double _calculateOverallRisk(List<RiskZone> zones) {
    if (zones.isEmpty) return 0.0;
    double totalCoverage = 0;
    double weightedSeverity = 0;
    for (final zone in zones) {
      double width = zone.endBearing - zone.startBearing;
      if (width < 0) width += 360;
      totalCoverage += width;
      weightedSeverity += width * zone.severity;
    }
    final coverageRatio = math.min(1.0, totalCoverage / 360);
    final avgSeverity = weightedSeverity / math.max(1, totalCoverage);
    return coverageRatio * 0.5 + avgSeverity * 0.5;
  }

  double _calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLon = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    final bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360;
  }

  double _haversineDistance(LatLng p1, LatLng p2) {
    const R = 6371000.0;
    final lat1 = p1.latitude * math.pi / 180;
    final lat2 = p2.latitude * math.pi / 180;
    final dLat = (p2.latitude - p1.latitude) * math.pi / 180;
    final dLon = (p2.longitude - p1.longitude) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  void printDebugInfo(RiskScanResult result) {
    if (!kDebugMode) return;
    debugPrint('''
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🌊🌀 OfflineRiskScanner Results
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📍 Location: (${result.location.latitude.toStringAsFixed(5)}, ${result.location.longitude.toStringAsFixed(5)})
📡 Scan Radius: ${result.scanRadius}m
⚠️ Overall Risk: ${(result.overallRisk * 100).toStringAsFixed(0)}%
✅ Safest Bearing: ${result.safestBearing.toStringAsFixed(0)}° (${result.safeBearingStart.toStringAsFixed(0)}°-${result.safeBearingEnd.toStringAsFixed(0)}°)

🌊 Deep Water Zones: ${result.deepWaterZones.length}
${result.deepWaterZones.map((z) => '   ${z.startBearing.toStringAsFixed(0)}°-${z.endBearing.toStringAsFixed(0)}° (${z.details})').join('\n')}

🌀 Rapid Flow Zones: ${result.rapidFlowZones.length}
${result.rapidFlowZones.map((z) => '   ${z.startBearing.toStringAsFixed(0)}°-${z.endBearing.toStringAsFixed(0)}° (${z.details})').join('\n')}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''');
  }
}
