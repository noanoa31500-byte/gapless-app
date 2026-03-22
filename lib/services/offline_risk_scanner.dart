import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../data/map_repository.dart';

/// ============================================================================
/// OfflineRiskScanner - 完全オフラインリスク検知エンジン
/// ============================================================================
/// 
/// 【設計思想】
/// 災害時はインターネット接続が期待できません。
/// 本クラスは、アプリ内にバンドルされたJSONデータのみを使用し、
/// **端末内部の計算だけで**周囲のリスクを検知します。
/// 
/// 【なぜこの機能が洪水時に有効なのか】
/// 1. **泥水で視界が悪い**: 濁った水の中では、電線や深い水域が見えません。
///    本機能は「見えない危険」を予測データから可視化します。
/// 
/// 2. **感電死は「見えない死」**: 水没した電柱・電線からの漏電は目視不可能。
///    電力設備の位置データから危険方向を事前に警告します。
/// 
/// 3. **激流は突然来る**: 浸水シミュレーションデータを使い、
///    水深が急に深くなる方向を避けるルートを提案します。
/// 
/// 【技術的特徴】
/// - 空間インデックス（グリッドベース）による高速検索
/// - メモリ効率の良いデータ構造
/// - 起動時の一括ロードでランタイム負荷を最小化
/// ============================================================================

/// リスクの種類
enum RiskType {
  /// 感電リスク（電力設備）
  electrocution,
  
  /// 浸水リスク（水深0.5m以上）
  deepWater,
  
  /// 激流リスク（流速が速い）
  rapidFlow,
}

/// ============================================================================
/// RiskZone - 危険ゾーン（方位角範囲）
/// ============================================================================
class RiskZone {
  /// リスクの種類
  final RiskType type;
  
  /// 開始方位角（0-360度）
  final double startBearing;
  
  /// 終了方位角（0-360度）
  final double endBearing;
  
  /// 危険度（0.0-1.0）
  final double severity;
  
  /// 最も近い危険物までの距離（メートル）
  final double nearestDistance;
  
  /// 詳細情報（電圧、水深など）
  final String details;
  
  /// 警告メッセージ
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

  /// この方位角が危険ゾーン内か判定
  bool containsBearing(double bearing) {
    // 正規化
    double b = bearing % 360;
    if (b < 0) b += 360;
    
    double start = startBearing % 360;
    if (start < 0) start += 360;
    
    double end = endBearing % 360;
    if (end < 0) end += 360;
    
    // 境界をまたぐ場合（例: 350度〜10度）
    if (start > end) {
      return b >= start || b <= end;
    }
    
    return b >= start && b <= end;
  }

  /// 日本語の警告メッセージ
  String get warningJa => warnings['ja'] ?? '危険な方向です';
  
  /// 英語の警告メッセージ
  String get warningEn => warnings['en'] ?? 'Danger ahead';
  
  /// タイ語の警告メッセージ
  String get warningTh => warnings['th'] ?? 'อันตราย';

  @override
  String toString() => 'RiskZone($type: ${startBearing.toStringAsFixed(0)}°-${endBearing.toStringAsFixed(0)}°, severity: ${(severity * 100).toStringAsFixed(0)}%)';
}

/// ============================================================================
/// RiskScanResult - スキャン結果
/// ============================================================================
class RiskScanResult {
  /// 検出された危険ゾーンのリスト
  final List<RiskZone> riskZones;
  
  /// 最も安全な方位角（リスクが最小）
  final double safestBearing;
  
  /// 安全な方位角の範囲
  final double safeBearingStart;
  final double safeBearingEnd;
  
  /// スキャン半径（メートル）
  final double scanRadius;
  
  /// 現在地
  final LatLng location;
  
  /// スキャン時刻
  final DateTime timestamp;
  
  /// 全体リスクスコア（0.0-1.0）
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

  /// 感電リスクゾーンのみ
  List<RiskZone> get electrocutionZones =>
      riskZones.where((z) => z.type == RiskType.electrocution).toList();

  /// 浸水リスクゾーンのみ
  List<RiskZone> get deepWaterZones =>
      riskZones.where((z) => z.type == RiskType.deepWater).toList();

  /// 指定方位角のリスクを取得
  List<RiskZone> getRisksAtBearing(double bearing) {
    return riskZones.where((z) => z.containsBearing(bearing)).toList();
  }

  /// 指定方位角が安全か判定
  bool isSafeBearing(double bearing) {
    return getRisksAtBearing(bearing).isEmpty;
  }
}

/// ============================================================================
/// 電力設備データ（キャッシュ用）
/// ============================================================================
class _PowerLineSegment {
  final LatLng start;
  final LatLng end;
  final int voltage;
  final String name;

  _PowerLineSegment({
    required this.start,
    required this.end,
    required this.voltage,
    required this.name,
  });
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
  // === キャッシュデータ ===
  List<_PowerLineSegment> _powerLines = [];
  List<_FloodPoint> _floodPoints = [];
  
  // === 空間インデックス（グリッドベース） ===
  // キー: "lat_lon" (小数点2桁で丸め)
  Map<String, List<_PowerLineSegment>> _powerLineGrid = {};
  Map<String, List<_FloodPoint>> _floodPointGrid = {};
  
  // === 状態 ===
  bool _isLoaded = false;
  bool _isLoading = false;
  String? _loadError;

  // === 設定 ===
  /// デフォルトのスキャン半径（メートル）
  static const double defaultScanRadius = 100.0;
  
  /// 感電リスクの警告距離（メートル）
  static const double electrocutionWarningDistance = 50.0;
  
  /// 深水の閾値（メートル）
  static const double deepWaterThreshold = 0.5;
  
  /// グリッドサイズ（度）- 約1km
  static const double gridSize = 0.01;

  // === Getters ===
  bool get isLoaded => _isLoaded;
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;
  int get powerLineCount => _powerLines.length;
  int get floodPointCount => _floodPoints.length;

  /// ============================================================================
  /// loadData - データを非同期でロード
  /// ============================================================================
  Future<void> loadData() async {
    if (_isLoaded || _isLoading) return;
    
    _isLoading = true;
    _loadError = null;
    
    try {
      // 並列でデータをロード
      await Future.wait([
        _loadPowerRiskData(),
        _loadFloodPredictionData(),
      ]);
      
      _isLoaded = true;
      
      if (kDebugMode) {
        debugPrint('⚡ OfflineRiskScanner: データロード完了');
        debugPrint('   - 送電線セグメント: ${_powerLines.length}');
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

  /// 電力リスクデータをロード (thailand_hazard.gplh から power タイプを抽出)
  Future<void> _loadPowerRiskData() async {
    try {
      final jsonString = await MapRepository.instance.readString('thailand_hazard.gplh');
      final data = json.decode(jsonString) as Map<String, dynamic>;

      if (data['type'] == 'point_hazard') {
        final points = data['points'] as List<dynamic>? ?? [];
        for (final p in points) {
          final point = p as Map<String, dynamic>;
          final t = (point['type'] as String? ?? '').toLowerCase();
          if (!t.contains('power') && !t.contains('tower') && !t.contains('electric')) continue;
          final lat = (point['lat'] as num).toDouble();
          final lng = (point['lng'] as num).toDouble();
          // 点を微小セグメントとして扱う
          final segment = _PowerLineSegment(
            start: LatLng(lat, lng),
            end: LatLng(lat + 0.00001, lng + 0.00001),
            voltage: (point['voltage'] as num?)?.toInt() ?? 0,
            name: point['name'] as String? ?? 'power',
          );
          _powerLines.add(segment);
          _addToGrid(segment);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ 電力リスクデータのロードをスキップ: $e');
      }
    }
  }

  /// 浸水予測データをロード (thailand_hazard.gplh から flood タイプを抽出)
  Future<void> _loadFloodPredictionData() async {
    try {
      final jsonString = await MapRepository.instance.readString('thailand_hazard.gplh');
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

  /// グリッドに送電線セグメントを追加
  void _addToGrid(_PowerLineSegment segment) {
    // 始点と終点の両方のグリッドに追加
    final startKey = _getGridKey(segment.start);
    final endKey = _getGridKey(segment.end);
    
    _powerLineGrid.putIfAbsent(startKey, () => []).add(segment);
    if (startKey != endKey) {
      _powerLineGrid.putIfAbsent(endKey, () => []).add(segment);
    }
  }

  /// グリッドに浸水ポイントを追加
  void _addFloodPointToGrid(_FloodPoint point) {
    final key = _getGridKey(point.location);
    _floodPointGrid.putIfAbsent(key, () => []).add(point);
  }

  /// グリッドキーを取得
  String _getGridKey(LatLng location) {
    final lat = (location.latitude / gridSize).floor() * gridSize;
    final lon = (location.longitude / gridSize).floor() * gridSize;
    return '${lat.toStringAsFixed(2)}_${lon.toStringAsFixed(2)}';
  }

  /// 周囲のグリッドキーを取得
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

  /// ============================================================================
  /// scanRisks - リスクスキャン実行
  /// ============================================================================
  /// 
  /// @param location 現在地
  /// @param radius スキャン半径（メートル）
  /// @return RiskScanResult スキャン結果
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
    
    // 感電リスクをスキャン
    riskZones.addAll(_scanElectrocutionRisks(location, radius));
    
    // 浸水リスクをスキャン
    riskZones.addAll(_scanDeepWaterRisks(location, radius));
    
    // 安全な方位を計算
    final safeZone = _findSafestBearing(riskZones);
    
    // 全体リスクスコアを計算
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

  /// 感電リスクをスキャン
  List<RiskZone> _scanElectrocutionRisks(LatLng location, double radius) {
    final zones = <RiskZone>[];
    final nearbyKeys = _getNearbyGridKeys(location);
    final checkedSegments = <_PowerLineSegment>{};
    
    for (final key in nearbyKeys) {
      final segments = _powerLineGrid[key];
      if (segments == null) continue;
      
      for (final segment in segments) {
        if (checkedSegments.contains(segment)) continue;
        checkedSegments.add(segment);
        
        // 線分と点の最短距離を計算
        final distance = _distanceToLineSegment(location, segment.start, segment.end);
        
        if (distance <= radius) {
          // 線分の中点への方位角を計算
          final midpoint = LatLng(
            (segment.start.latitude + segment.end.latitude) / 2,
            (segment.start.longitude + segment.end.longitude) / 2,
          );
          final bearing = _calculateBearing(location, midpoint);
          
          // 距離に基づく危険度
          final severity = 1.0 - (distance / radius);
          
          // 危険角度範囲（距離が近いほど広い）
          final angularWidth = 30.0 * (1.0 + severity * 0.5);
          
          zones.add(RiskZone(
            type: RiskType.electrocution,
            startBearing: (bearing - angularWidth / 2 + 360) % 360,
            endBearing: (bearing + angularWidth / 2) % 360,
            severity: severity,
            nearestDistance: distance,
            details: '${segment.voltage / 1000}kV送電線',
            warnings: {
              'ja': '⚡ 感電危険！送電線あり（${distance.toStringAsFixed(0)}m）',
              'en': '⚡ Electrocution risk! Power line (${distance.toStringAsFixed(0)}m)',
              'th': '⚡ อันตราย! สายไฟฟ้า (${distance.toStringAsFixed(0)}m)',
            },
          ));
        }
      }
    }
    
    return zones;
  }

  /// 浸水リスクをスキャン
  List<RiskZone> _scanDeepWaterRisks(LatLng location, double radius) {
    final zones = <RiskZone>[];
    final nearbyKeys = _getNearbyGridKeys(location);
    final bearingDepthMap = <int, _FloodPoint>{};
    final bearingRapidFlowMap = <int, _FloodPoint>{}; // 激流用マップ
    
    for (final key in nearbyKeys) {
      final points = _floodPointGrid[key];
      if (points == null) continue;
      
      for (final point in points) {
        final distance = _haversineDistance(location, point.location);
        if (distance > radius) continue;
        
        final bearing = _calculateBearing(location, point.location);
        final bearingBucket = (bearing / 10).round() * 10;
        
        // 深水リスク（0.5m以上）
        if (point.predDepth >= deepWaterThreshold) {
          if (!bearingDepthMap.containsKey(bearingBucket) ||
              point.predDepth > bearingDepthMap[bearingBucket]!.predDepth) {
            bearingDepthMap[bearingBucket] = point;
          }
        }
        
        // 激流リスク（流速が Fast または Moderate かつ水深がある）
        if (_isRapidFlow(point.predSpeed) && point.predDepth >= 0.3) {
          if (!bearingRapidFlowMap.containsKey(bearingBucket) ||
              _getFlowSpeedPriority(point.predSpeed) > 
              _getFlowSpeedPriority(bearingRapidFlowMap[bearingBucket]!.predSpeed)) {
            bearingRapidFlowMap[bearingBucket] = point;
          }
        }
      }
    }
    
    // 深水ゾーンを追加
    zones.addAll(_groupBearingsIntoZones(
      location, 
      bearingDepthMap, 
      RiskType.deepWater,
    ));
    
    // 激流ゾーンを追加
    zones.addAll(_groupBearingsIntoZones(
      location, 
      bearingRapidFlowMap, 
      RiskType.rapidFlow,
    ));
    
    return zones;
  }
  
  /// 流速が危険かどうかを判定
  bool _isRapidFlow(String predSpeed) {
    final lower = predSpeed.toLowerCase();
    return lower == 'fast' || lower == 'moderate' || lower == 'rapid';
  }
  
  /// 流速の優先度を取得（高いほど危険）
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
  
  /// 方位バケットをゾーンにグループ化
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
      
      // 連続していない場合、ゾーンを確定
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
        // 連続している場合、最大値を更新
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
  
  /// リスクタイプに応じたゾーンを作成
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
            'ja': '💨 激流危険！流速が速い（$speedText）',
            'en': '💨 Rapid flow! Speed: $speedText',
            'th': '💨 น้ำไหลเชี่ยว! ความเร็ว: $speedText',
          },
        );
      case RiskType.electrocution:
        // このメソッドでは電気リスクは扱わない
        return RiskZone(
          type: type,
          startBearing: startBearing,
          endBearing: endBearing,
          severity: 0.5,
          nearestDistance: minDistance,
          details: '電力設備',
          warnings: {
            'ja': '⚡ 感電危険',
            'en': '⚡ Electric shock risk',
            'th': '⚡ อันตราย ไฟฟ้า',
          },
        );
    }
  }
  
  /// 流速のテキスト表現を取得
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

  /// 最も安全な方位を見つける
  Map<String, double> _findSafestBearing(List<RiskZone> zones) {
    if (zones.isEmpty) {
      return {'bearing': 0.0, 'start': 0.0, 'end': 360.0};
    }
    
    // 360度を10度刻みでスキャン
    double maxSafeStart = 0;
    double maxSafeEnd = 0;
    double maxSafeWidth = 0;
    
    for (int start = 0; start < 360; start += 10) {
      // この開始点から連続して安全な範囲を探す
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

  /// 全体リスクスコアを計算
  double _calculateOverallRisk(List<RiskZone> zones) {
    if (zones.isEmpty) return 0.0;
    
    // 危険ゾーンがカバーする角度の割合と重大度の加重平均
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

  /// 2点間の方位角を計算
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

  /// ハーバーサイン距離（メートル）
  double _haversineDistance(LatLng p1, LatLng p2) {
    const R = 6371000.0; // 地球半径（メートル）
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

  /// 点から線分への最短距離
  double _distanceToLineSegment(LatLng point, LatLng start, LatLng end) {
    final a = _haversineDistance(point, start);
    final b = _haversineDistance(point, end);
    final c = _haversineDistance(start, end);
    
    if (c == 0) return a;
    
    // 点が線分の外側にある場合
    if (a * a >= b * b + c * c) return b;
    if (b * b >= a * a + c * c) return a;
    
    // 点から線分への垂線の距離（ヘロンの公式）
    final s = (a + b + c) / 2;
    final area = math.sqrt(math.max(0, s * (s - a) * (s - b) * (s - c)));
    return 2 * area / c;
  }

  /// デバッグ出力
  void printDebugInfo(RiskScanResult result) {
    if (!kDebugMode) return;
    
    debugPrint('''
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⚡🌊 OfflineRiskScanner Results
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📍 Location: (${result.location.latitude.toStringAsFixed(5)}, ${result.location.longitude.toStringAsFixed(5)})
📡 Scan Radius: ${result.scanRadius}m
⚠️ Overall Risk: ${(result.overallRisk * 100).toStringAsFixed(0)}%
✅ Safest Bearing: ${result.safestBearing.toStringAsFixed(0)}° (${result.safeBearingStart.toStringAsFixed(0)}°-${result.safeBearingEnd.toStringAsFixed(0)}°)

⚡ Electrocution Zones: ${result.electrocutionZones.length}
${result.electrocutionZones.map((z) => '   ${z.startBearing.toStringAsFixed(0)}°-${z.endBearing.toStringAsFixed(0)}° (${z.nearestDistance.toStringAsFixed(0)}m)').join('\n')}

🌊 Deep Water Zones: ${result.deepWaterZones.length}
${result.deepWaterZones.map((z) => '   ${z.startBearing.toStringAsFixed(0)}°-${z.endBearing.toStringAsFixed(0)}° (${z.details})').join('\n')}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''');
  }
}
