import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart'; // For kDebugMode
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:vector_math/vector_math.dart' as vector;

/// 洪水・感電リスクを回避するナビゲーションサービス
class SafeNavigationService {
  // シングルトン
  static final SafeNavigationService _instance = SafeNavigationService._internal();
  factory SafeNavigationService() => _instance;
  SafeNavigationService._internal();

  List<LatLng> _floodRiskPoints = [];
  List<List<LatLng>> _powerLinePolylines = [];
  
  // グリッド設定
  // 0.0001度 ≒ 11m (赤道付近)
  // 計算負荷を下げるため、少し粗めのグリッドでリスク判定を行う
  static const double _gridSize = 0.0001; 
  
  // リスクエリアの定義
  static const double _floodRiskRadius = 15.0; // meters
  static const double _powerRiskRadius = 20.0; // meters

  bool _isDataLoaded = false;

  /// データの初期化
  Future<void> initialize() async {
    if (_isDataLoaded) return;
    await _loadFloodData();
    await _loadPowerData();
    _isDataLoaded = true;
    print('✅ SafeNavigationService initialized');
  }

  /// 外部からハザードポリゴンを注入（日本など、GeoJSONから読み込んだポリゴン用）
  void setHazardPolygons(List<List<LatLng>> polygons) {
    // 浸水予測ポイントとして扱うには少し変換が必要だが、
    // ここでは簡易的に「ポリゴン中心」や「頂点」を危険ポイントとして登録するか、
    // あるいは `_hazardPolygons` リストを新設して A* で判定する。
    // 今回は A* の `_isHighRisk` を拡張してポリゴン判定を入れるのが確実。
    _externalHazardPolygons = polygons;
    print('⚠️ SafeNav: Updated ${_externalHazardPolygons.length} external hazard polygons');
  }

  List<List<LatLng>> _externalHazardPolygons = [];

  Future<void> _loadFloodData() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/data/satun_flood_prediction.json');
      final List<dynamic> jsonList = json.decode(jsonString);
      
      _floodRiskPoints = jsonList
          .where((item) => (item['pred_depth'] as num) > 0.3) // 浸水0.3m以上を危険とみなす
          .map((item) => LatLng(
                (item['lat'] as num).toDouble(),
                (item['lon'] as num).toDouble(),
              ))
          .toList();
      print('🌊 Loaded ${_floodRiskPoints.length} flood risk points');
    } catch (e) {
      print('❌ Error loading flood data: $e');
    }
  }

  Future<void> _loadPowerData() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/data/power_risk_th.geojson');
      final Map<String, dynamic> geoJson = json.decode(jsonString);
      final List<dynamic> features = geoJson['features'];

      for (var feature in features) {
        final geometry = feature['geometry'];
        final type = geometry['type'];
        final coordinates = geometry['coordinates'];

        if (type == 'LineString') {
          List<LatLng> polyline = (coordinates as List).map((point) {
            return LatLng((point[1] as num).toDouble(), (point[0] as num).toDouble());
          }).toList();
          _powerLinePolylines.add(polyline);
        } else if (type == 'Point') {
          // Pointもリスクとして扱うが、単純化のため短い線分として追加するか、別途管理
          // ここでは簡易的に短いLineStringとして扱う
          double lat = (coordinates[1] as num).toDouble();
          double lng = (coordinates[0] as num).toDouble();
          _powerLinePolylines.add([LatLng(lat, lng), LatLng(lat + 0.00001, lng + 0.00001)]);
        }
      }
      print('⚡ Loaded ${_powerLinePolylines.length} power risk lines');
    } catch (e) {
      print('❌ Error loading power data: $e');
    }
  }

  /// 安全ルート検索 (A* Algorithm)
  /// 単純化のため、グリッドベースの探索を行う
  List<LatLng> findSafeRoute(LatLng start, LatLng end) {
    // グリッド化された開始点と終了点
    final GridPoint startGrid = _toGrid(start);
    final GridPoint endGrid = _toGrid(end);

    // オープンリスト（探索対象）とクローズドリスト（探索済み）
    final List<Node> openList = [];
    final Set<String> closedList = {};

    openList.add(Node(startGrid, null, 0, _heuristic(startGrid, endGrid)));

    int iterations = 0;
    const int maxIterations = 3000; // 安全のため探索回数を制限

    while (openList.isNotEmpty) {
      // 最もスコアが良いノードを選択
      openList.sort((a, b) => a.f.compareTo(b.f));
      final Node currentNode = openList.removeAt(0);

      // ゴール到達判定（グリッドレベルでの近似）
      if (_distanceGrid(currentNode.point, endGrid) < 2) {
        return _reconstructPath(currentNode, end);
      }

      final key = currentNode.point.toString();
      if (closedList.contains(key)) continue;
      closedList.add(key);

      iterations++;
      if (iterations > maxIterations) {
        print('⚠️ Pathfinding output limited by max iterations');
        // 最善の策として、現在までのパスを返す（あるいは直線）
        return _reconstructPath(currentNode, end);
      }

      // 8方向へ展開
      for (final neighbor in _getNeighbors(currentNode.point)) {
        if (closedList.contains(neighbor.toString())) continue;

        // リスクチェック (コスト計算)
        if (_isHighRisk(neighbor)) {
          continue; // 危険エリアは通行不可
        }

        final double gScore = currentNode.g + 1; // グリッド間距離を1とする簡易計算
        final double hScore = _heuristic(neighbor, endGrid);
        
        // 既存のノードより良い経路か確認（今回は簡易実装のため省略し、追加する）
        openList.add(Node(neighbor, currentNode, gScore, hScore));
      }
    }

    // 経路が見つからない場合は直線ルート（ただし警告付き）を返す
    print('⚠️ SafeNav: No safe route found after $iterations iterations. Returning direct path.');
    return [start, end];
  }

  /// ルート詳細のデバッグ出力
  void debugPrintRoute(List<LatLng> route) {
    if (!kDebugMode) return;
    print('🧩 --- Safe Route Debug ---');
    print('Total Points: ${route.length}');
    for (int i = 0; i < route.length; i++) {
        print('WP[$i]: ${route[i].latitude}, ${route[i].longitude}');
    }
    print('-------------------------');
  }

  // グリッド座標系への変換
  GridPoint _toGrid(LatLng latLng) {
    return GridPoint(
      (latLng.latitude / _gridSize).round(),
      (latLng.longitude / _gridSize).round(),
    );
  }

  LatLng _fromGrid(GridPoint grid) {
    return LatLng(grid.x * _gridSize, grid.y * _gridSize);
  }

  // 近傍ノード取得 (8方向)
  List<GridPoint> _getNeighbors(GridPoint p) {
    return [
      GridPoint(p.x + 1, p.y),
      GridPoint(p.x - 1, p.y),
      GridPoint(p.x, p.y + 1),
      GridPoint(p.x, p.y - 1),
      GridPoint(p.x + 1, p.y + 1),
      GridPoint(p.x - 1, p.y - 1),
      GridPoint(p.x + 1, p.y - 1),
      GridPoint(p.x - 1, p.y + 1),
    ];
  }

  // ヒューリスティック関数 (マンハッタン距離 or ユークリッド距離)
  double _heuristic(GridPoint a, GridPoint b) {
    return math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
  }
  
  // グリッド間の距離
  double _distanceGrid(GridPoint a, GridPoint b) {
     return math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
  }

  // 経路復元
  List<LatLng> _reconstructPath(Node endNode, LatLng actualGoal) {
    final List<LatLng> path = [];
    path.add(actualGoal);
    
    Node? current = endNode;
    while (current != null) {
      path.add(_fromGrid(current.point));
      current = current.parent;
    }
    
    return path.reversed.toList();
  }

  // 指定グリッドが危険かどうか判定
  bool _isHighRisk(GridPoint p) {
    final center = _fromGrid(p);
    
    // 1. 浸水リスクチェック
    for (final point in _floodRiskPoints) {
      final dist = const Distance().as(LengthUnit.Meter, center, point);
      if (dist < _floodRiskRadius) return true;
    }

    // 2. 感電リスクチェック
    // 線分との距離を見るのは計算コストが高いので、簡易的に周辺のPolylineの頂点チェック
    // 本来は点と線分の距離計算が必要
    for (final polyline in _powerLinePolylines) {
      for (final point in polyline) {
        final dist = const Distance().as(LengthUnit.Meter, center, point);
        if (dist < _powerRiskRadius) return true;
      }
    }

    // 3. 外部ハザードポリゴン (Japan Polygons)
    for (final polygon in _externalHazardPolygons) {
       if (_isPointInPolygon(center, polygon)) return true;
    }

    return false;
  }
  
  /// 点がポリゴン内にあるか判定 (Ray-casting Algorithm)
  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    
    bool inside = false;
    int j = polygon.length - 1;
    
    for (int i = 0; i < polygon.length; i++) {
      if (((polygon[i].latitude > point.latitude) != (polygon[j].latitude > point.latitude)) &&
          (point.longitude < (polygon[j].longitude - polygon[i].longitude) * (point.latitude - polygon[i].latitude) / (polygon[j].latitude - polygon[i].latitude) + polygon[i].longitude)) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }
  
  /// 指定した位置と方位の先にあるリスクをチェック（リアルタイムアラート用）
  /// distance: チェックする距離 (m)
  String? checkHazardAhead(LatLng start, double heading, {double distance = 50.0}) {
    // 進行方向50m先のポイントを計算
    final double radUrl = vector.radians(heading);
    final double dx = math.sin(radUrl) * distance; // East
    final double dy = math.cos(radUrl) * distance; // North
    
    // 簡易的な緯度経度変換 (赤道付近近似)
    const double metersPerDegree = 111320.0;
    final double latDiff = dy / metersPerDegree;
    final double lngDiff = dx / (metersPerDegree * math.cos(vector.radians(start.latitude)));
    
    final LatLng checkPoint = LatLng(start.latitude + latDiff, start.longitude + lngDiff);
    
    // 中間地点もチェック (25m地点)
    final LatLng midPoint = LatLng(
      start.latitude + latDiff * 0.5, 
      start.longitude + lngDiff * 0.5
    );
    
    // 浸水チェック
    if (_isPointRisky(checkPoint, _floodRiskRadius, isFlood: true) || 
        _isPointRisky(midPoint, _floodRiskRadius, isFlood: true)) {
      if (kDebugMode) print('🌊 SafeNav: Flood detected ahead at distance ${distance}m (Heading: $heading)');
      return 'Deep Water Ahead';
    }
    
    // 感電チェック
    if (_isPointRisky(checkPoint, _powerRiskRadius, isFlood: false) || 
        _isPointRisky(midPoint, _powerRiskRadius, isFlood: false)) {
      if (kDebugMode) print('⚡ SafeNav: Voltage risk detected ahead at distance ${distance}m (Heading: $heading)');
      return 'High Voltage Ahead';
    }
    
    return null;
  }
  
  bool _isPointRisky(LatLng p, double radius, {required bool isFlood}) {
    if (isFlood) {
      // 1. 点ベースのリスク (Thailand)
      for (final point in _floodRiskPoints) {
        if (const Distance().as(LengthUnit.Meter, p, point) < radius) return true;
      }
      // 2. 外部ポリゴンベースのリスク (Japan)
      for (final polygon in _externalHazardPolygons) {
        if (_isPointInPolygon(p, polygon)) return true;
      }
    } else {
      for (final polyline in _powerLinePolylines) {
         for (final point in polyline) {
            if (const Distance().as(LengthUnit.Meter, p, point) < radius) return true;
         }
      }
    }
    return false;
  }
}

class GridPoint {
  final int x;
  final int y;
  GridPoint(this.x, this.y);
  
  @override
  String toString() => '$x,$y';
  
  @override
  bool operator ==(Object other) => other is GridPoint && x == other.x && y == other.y;
  
  @override
  int get hashCode => x.hashCode ^ y.hashCode;
}

class Node {
  final GridPoint point;
  final Node? parent;
  final double g; // Cost from start
  final double h; // Heuristic to end
  
  Node(this.point, this.parent, this.g, this.h);
  double get f => g + h;
}
