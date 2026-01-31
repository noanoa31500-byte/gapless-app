import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/road_edge.dart';
import '../models/road_graph.dart';
import 'safest_route_engine.dart';

/// ============================================================================
/// RoutingEngine - 災害対応型ルーティングエンジン（統合版）
/// ============================================================================
/// 
/// 命を守る最大安全ルート探索システム
class RoutingEngine {
  /// 道路グラフ
  final RoadGraph graph;
  
  /// 洪水データ（タイモード用）
  final Map<String, Map<String, dynamic>>? floodData;
  
  /// 電力設備データ（タイモード用）
  final List<Map<String, dynamic>>? powerInfrastructure;
  
  /// 動作モード: 'japan' (地震) または 'thailand' (洪水)
  final String mode;

  /// 地震発生時刻（日本モード用）
  final DateTime? earthquakeTime;

  /// ハザードポリゴン（日本モード用: 浸水域・土砂災害など、タイモードも可）
  final List<List<math.Point<double>>>? hazardPolygons;

  /// 危険地点（タイモード用: 半径判定）
  /// List of {lat, lng, radius}
  final List<Map<String, dynamic>>? hazardPoints;

  /// 危険エリア回避フラグ
  final bool avoidDangerZones;

  RoutingEngine({
    required this.graph,
    required this.mode,
    this.floodData,
    this.powerInfrastructure,
    this.earthquakeTime,
    this.hazardPolygons,
    this.hazardPoints,
    this.avoidDangerZones = true,
  });

  /// ============================================================================
  /// calculateEdgeWeight - エッジの生存コストを計算
  /// ============================================================================
  double calculateEdgeWeight(RoadEdge edge) {
    // 基本重み = 実距離
    double weight = edge.distance;
    
    if (mode == 'japan') {
      // === 日本モード: 地震時の道路評価（強化版） ===
      return _calculateJapanModeWeight(edge, weight);
    } else if (mode == 'thailand') {
      // === タイモード: 洪水時の道路評価 ===
      return _calculateThailandModeWeight(edge, weight);
    }
    
    return weight;
  }

  /// ============================================================================
  /// 日本モード（地震）の重み計算 - SurvivalRiskFactor統合版
  /// ============================================================================
  double _calculateJapanModeWeight(RoadEdge edge, double baseWeight) {
    // === Step A: ハザードポリゴンによる通行不可判定 ===
    if (hazardPolygons != null && hazardPolygons!.isNotEmpty) {
      final fromNode = graph.nodes[edge.fromNodeId];
      final toNode = graph.nodes[edge.toNodeId];
      
      if (fromNode != null && toNode != null) {
        // ノード自体がハザード内かチェック
        bool fromInDanger = _isPointInPolygons(fromNode.position.latitude, fromNode.position.longitude);
        bool toInDanger = _isPointInPolygons(toNode.position.latitude, toNode.position.longitude);
        
        // エッジの中間点もチェック
        double midLat = (fromNode.position.latitude + toNode.position.latitude) / 2;
        double midLng = (fromNode.position.longitude + toNode.position.longitude) / 2;
        bool midInDanger = _isPointInPolygons(midLat, midLng);

        if (fromInDanger || toInDanger || midInDanger) {
          if (kDebugMode) {
            print('🚨 [JP] ハザード区域を検出: ${edge.name ?? "unnamed"} (回避強制)');
          }
          return double.infinity; // ハザード内は通行不可
        }
      }
    }

    // === Step B: 道路種別によるリスク評価 ===
    final riskFactor = SurvivalRiskFactor.getFactorForHighwayType(
      edge.highwayType,
    );

    if (riskFactor == double.infinity) {
      return double.infinity;
    }

    // 時間減衰係数
    final timeDecay = _calculateTimeDecayFactor();

    // 最終コスト
    final cost = baseWeight * riskFactor * timeDecay;
    return cost;
  }

  /// 点がハザードポリゴンのいずれかに入っているか
  bool _isPointInPolygons(double lat, double lng) {
    if (hazardPolygons == null) return false;
    
    final p = math.Point(lat, lng);
    for (final polygon in hazardPolygons!) {
      if (_isPointInPolygon(p, polygon)) return true;
    }
    return false;
  }

  /// 指定した点がポリゴン内にあるか判定 (Ray-casting Algorithm)
  bool _isPointInPolygon(math.Point<double> p, List<math.Point<double>> polygon) {
    if (polygon.length < 3) return false;
    
    bool inside = false;
    int j = polygon.length - 1;
    
    for (int i = 0; i < polygon.length; i++) {
      if (((polygon[i].x > p.x) != (polygon[j].x > p.x)) &&
          (p.y < (polygon[j].y - polygon[i].y) * (p.x - polygon[i].x) / (polygon[j].x - polygon[i].x) + polygon[i].y)) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  /// 時間減衰係数を計算
  double _calculateTimeDecayFactor() {
    if (earthquakeTime == null) {
      return 1.0;
    }

    final hoursSinceEarthquake = 
        DateTime.now().difference(earthquakeTime!).inHours;

    if (hoursSinceEarthquake < 6) {
      return 1.5;
    } else if (hoursSinceEarthquake < 24) {
      return 1.2;
    } else if (hoursSinceEarthquake < 72) {
      return 1.0;
    } else {
      return 0.8;
    }
  }

  /// タイモード（洪水）の重み計算（強化版）
  double _calculateThailandModeWeight(RoadEdge edge, double baseWeight) {
    // === Step 1: エッジの端点ノードを取得 ===
    final fromNode = graph.nodes[edge.fromNodeId];
    final toNode = graph.nodes[edge.toNodeId];

    if (fromNode == null || toNode == null) {
      return baseWeight * 2.0; // ノード情報がない場合は回避
    }

    // === Step 0: 強制危険エリア回避 (Danger Zone Avoidance) ===
    if (avoidDangerZones) {
      // ポリゴン判定 (Thailand Hazard Polygons)
      if (hazardPolygons != null && hazardPolygons!.isNotEmpty) {
          bool fromIn = _isPointInPolygons(fromNode.position.latitude, fromNode.position.longitude);
          bool toIn = _isPointInPolygons(toNode.position.latitude, toNode.position.longitude);
          // Check midpoint as well
          double midLat = (fromNode.position.latitude + toNode.position.latitude) / 2;
          double midLng = (fromNode.position.longitude + toNode.position.longitude) / 2;
          bool midIn = _isPointInPolygons(midLat, midLng);

          if (fromIn || toIn || midIn) {
             if (kDebugMode) print('⛔ [TH] 危険ポリゴン内 (通行禁止): ${edge.id}');
             return double.infinity;
          }
      }

      // ポイント判定 (Thailand Hazard Points - e.g. Leakage spots)
      if (hazardPoints != null && hazardPoints!.isNotEmpty) {
          // Check if edge is near any hazard point
          if (_isNearHazardPoint(fromNode.position.latitude, fromNode.position.longitude) ||
              _isNearHazardPoint(toNode.position.latitude, toNode.position.longitude)) {
              if (kDebugMode) print('⛔ [TH] 危険地点接近 (通行禁止): ${edge.id}');
              return double.infinity;
          }
      }
    }

    // === Step 2: 感電デッドゾーン判定（最優先）===
    // どちらかのノードが感電リスクありなら、そのエッジは通行不能
    if (fromNode.isHighRisk || toNode.isHighRisk) {
      if (kDebugMode) {
        print('⚡ 感電デッドゾーン検出: ${edge.name ?? edge.id}');
      }
      return double.infinity; // 絶対に通行させない
    }

    // === Step 3: 水深に応じたコスト計算 ===
    final avgDepth = ((fromNode.floodDepth ?? 0.0) + (toNode.floodDepth ?? 0.0)) / 2.0;

    if (avgDepth > 0) {
      if (avgDepth >= 1.5) {
        return baseWeight * 5.0;
      } else if (avgDepth >= 1.0) {
        return baseWeight * 4.0;
      } else if (avgDepth >= 0.5) {
        return baseWeight * 3.0;
      } else if (avgDepth >= 0.3) {
        return baseWeight * 2.0;
      } else {
        return baseWeight * 1.5;
      }
    }

    // === Step 4: 電力設備が近い（冠水なし）===
    final minPowerDist = math.min(
      fromNode.distanceToPowerInfra ?? double.infinity,
      toNode.distanceToPowerInfra ?? double.infinity,
    );

    if (minPowerDist <= 50.0) {
      return baseWeight * 1.2;
    }

    return baseWeight;
  }

  /// Dijkstraアルゴリズムで最大安全ルートを探索
  List<String> findSafestPath(String startNodeId, String goalNodeId) {
    if (!graph.nodes.containsKey(startNodeId) || 
        !graph.nodes.containsKey(goalNodeId)) {
      return [];
    }
    
    final distances = <String, double>{};
    final previous = <String, String?>{};
    final queue = PriorityQueue<_QueueItem>();
    
    for (var nodeId in graph.nodes.keys) {
      distances[nodeId] = double.infinity;
      previous[nodeId] = null;
    }
    distances[startNodeId] = 0.0;
    queue.add(_QueueItem(startNodeId, 0.0));
    
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      final currentNodeId = current.nodeId;
      
      if (current.cost > distances[currentNodeId]!) {
        continue;
      }
      
      if (currentNodeId == goalNodeId) {
        break;
      }
      
      final edges = graph.getEdgesFromNode(currentNodeId);
      for (var edge in edges) {
        final neighborId = graph.getOtherNodeId(edge.id, currentNodeId);
        if (neighborId == null) continue;
        
        final edgeWeight = calculateEdgeWeight(edge);
        
        if (edgeWeight == double.infinity) continue;
        
        final newCost = distances[currentNodeId]! + edgeWeight;
        
        if (newCost < distances[neighborId]!) {
          distances[neighborId] = newCost;
          previous[neighborId] = currentNodeId;
          queue.add(_QueueItem(neighborId, newCost));
        }
      }
    }
    
    if (distances[goalNodeId] == double.infinity) {
      return [];
    }
    
    final path = <String>[];
    String? current = goalNodeId;
    while (current != null) {
      path.insert(0, current);
      current = previous[current];
    }
    
    return path;
  }

  /// 指定座標が危険地点（Hazard Points）の近くにあるか判定
  bool _isNearHazardPoint(double lat, double lng) {
    if (hazardPoints == null) return false;
    const double threshold = 0.0005; // ~50m
    
    for (final point in hazardPoints!) {
      final pLat = point['lat'] as double;
      final pLng = point['lng'] as double;

      final dLat = (lat - pLat).abs();
      final dLng = (lng - pLng).abs();

      if (dLat < threshold && dLng < threshold) {
        return true;
      }
    }
    return false;
  }
}

/// Dijkstra用の優先度付きキューアイテム
class _QueueItem implements Comparable<_QueueItem> {
  final String nodeId;
  final double cost;

  _QueueItem(this.nodeId, this.cost);

  @override
  int compareTo(_QueueItem other) => cost.compareTo(other.cost);
}

/// 簡易優先度付きキュー
class PriorityQueue<T extends Comparable<T>> {
  final List<T> _items = [];

  void add(T item) {
    _items.add(item);
    _items.sort();
  }

  T removeFirst() => _items.removeAt(0);

  bool get isNotEmpty => _items.isNotEmpty;
  bool get isEmpty => _items.isEmpty;
}
