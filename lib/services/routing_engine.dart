import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../models/road_edge.dart';
import '../models/road_graph.dart';
import '../models/road_node.dart';

/// ============================================================================
/// RoutingEngine - 災害対応型ルーティングエンジン
/// ============================================================================
/// 
/// 【LOGIC Directive Implementation】
/// 1. Japan Mode: Road Width Priority.
///    - 広い道路（Primary, Secondary）を優先し、倒壊リスクのある狭い路地を避ける。
/// 2. Thailand Mode: Avoid Electric Shock Risk.
///    - 感電リスク（isHighRisk）のあるノードを絶対回避。
///    - 浸水深度（floodDepth）に基づきコストを調整。
/// 
/// 【NAV Directive Implementation】
/// - グラフ探索により最適なウェイポイント（Node ID List）を生成。
class RoutingEngine {
  /// 道路グラフデータ
  final RoadGraph graph;
  
  /// 動作モード ('japan' or 'thailand')
  final String mode;
  
  /// ハザードポリゴン（日本：土砂災害・浸水想定区域など）
  final List<List<math.Point<double>>>? hazardPolygons;
  
  /// ハザードポイント（タイ：局所的な危険箇所）
  final List<Map<String, dynamic>>? hazardPoints;
  
  /// 危険エリア回避を強制するか
  final bool avoidDangerZones;

  /// 洪水データ（タイモード用）
  final Map<String, Map<String, dynamic>>? floodData;
  
  /// 電力設備データ（タイモード用）
  final List<Map<String, dynamic>>? powerInfrastructure;

  /// 地震発生時刻（日本モード用）
  final DateTime? earthquakeTime;

  // --- コンストラクタ ---
  RoutingEngine({
    required this.graph,
    required this.mode,
    this.hazardPolygons,
    this.hazardPoints,
    this.avoidDangerZones = true,
    this.floodData,
    this.powerInfrastructure,
    this.earthquakeTime,
  });

  /// ==========================================================================
  /// 最短経路探索 (Dijkstra Algorithm)
  /// ==========================================================================
  List<String> findSafestPath(String startNodeId, String goalNodeId) {
    if (!graph.nodes.containsKey(startNodeId) || !graph.nodes.containsKey(goalNodeId)) {
      if (kDebugMode) print('❌ RoutingEngine: Start or Goal node not found in graph.');
      return [];
    }

    // 初期化
    final distances = <String, double>{};
    final previous = <String, String?>{};
    final queue = _PriorityQueue<_QueueItem>();
    
    distances[startNodeId] = 0.0;
    queue.add(_QueueItem(startNodeId, 0.0));

    final Set<String> visited = {};

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      final u = current.nodeId;

      // ゴール到達
      if (u == goalNodeId) {
        return _reconstructPath(previous, goalNodeId);
      }

      // 既に確定済みの場合はスキップ
      if (visited.contains(u)) continue;
      visited.add(u);

      // 隣接ノードの探索
      final edges = graph.getEdgesFromNode(u);
      for (final edge in edges) {
        final v = graph.getOtherNodeId(edge.id, u);
        if (v == null) continue;
        if (visited.contains(v)) continue;

        // エッジの重み（コスト）計算 - ここにCore Logicが入る
        final weight = calculateEdgeWeight(edge);
        
        // 通行不可 (Infinity) の場合はスキップ
        if (weight == double.infinity) continue;

        final alt = (distances[u] ?? double.infinity) + weight;
        
        if (alt < (distances[v] ?? double.infinity)) {
          distances[v] = alt;
          previous[v] = u;
          queue.add(_QueueItem(v, alt));
        }
      }
    }

    // 経路が見つからない場合
    if (kDebugMode) print('⚠️ RoutingEngine: No path found between $startNodeId and $goalNodeId');
    return [];
  }

  List<String> _reconstructPath(Map<String, String?> previous, String current) {
    final path = <String>[current];
    while (previous.containsKey(current) && previous[current] != null) {
      current = previous[current]!;
      path.add(current);
    }
    return path.reversed.toList();
  }

  /// ==========================================================================
  /// コスト計算ロジック (Directives Implementation)
  /// ==========================================================================
  double calculateEdgeWeight(RoadEdge edge) {
    // 基本コストは距離 (メートル)
    double cost = edge.distance;

    if (mode == 'japan') {
      cost = _calculateJapanWeight(edge, cost);
    } else if (mode == 'thailand') {
      cost = _calculateThailandWeight(edge, cost);
    }

    return cost;
  }

  /// --------------------------------------------------------------------------
  /// LOGIC: Japan = Road Width Priority
  /// --------------------------------------------------------------------------
  double _calculateJapanWeight(RoadEdge edge, double baseCost) {
    // 1. ハザードポリゴン回避 (絶対的回避)
    if (avoidDangerZones && _isEdgeInHazardPolygon(edge)) {
      return double.infinity; 
    }

    // 2. 道路幅員・タイプによる重み付け
    // 広い道 (low multiplier) を優先し、狭い道 (high multiplier) を避ける
    double multiplier = 1.0;
    final type = edge.highwayType?.toLowerCase() ?? 'unclassified';

    switch (type) {
      case 'motorway':
      case 'trunk':
      case 'primary':
        // 最優先（幅員大、倒壊閉塞リスク低）
        multiplier = 1.0; 
        break;
      case 'secondary':
        multiplier = 1.1;
        break;
      case 'tertiary':
        multiplier = 1.2;
        break;
      case 'residential':
      case 'living_street':
        // 住宅街（ブロック塀倒壊リスクあり）-> 距離の1.5倍換算
        multiplier = 1.5; 
        break;
      case 'service':
      case 'footway':
      case 'path':
      case 'track':
      case 'unclassified':
      default:
        // 路地・細道（非常に危険）-> 距離の5倍換算
        multiplier = 5.0; 
        break;
    }

    return baseCost * multiplier;
  }

  /// --------------------------------------------------------------------------
  /// LOGIC: Thailand = Avoid Electric Shock Risk
  /// --------------------------------------------------------------------------
  double _calculateThailandWeight(RoadEdge edge, double baseCost) {
    final fromNode = graph.nodes[edge.fromNodeId];
    final toNode = graph.nodes[edge.toNodeId];

    if (fromNode == null || toNode == null) return baseCost;

    // 0. ハザードエリア回避（強制）
    if (avoidDangerZones) {
      // ポリゴン判定
      if (_isEdgeInHazardPolygon(edge)) {
        return double.infinity;
      }
      
      // ハザードポイント判定
      if (hazardPoints != null && hazardPoints!.isNotEmpty) {
        if (_isNearHazardPoint(fromNode.position.latitude, fromNode.position.longitude) ||
            _isNearHazardPoint(toNode.position.latitude, toNode.position.longitude)) {
          return double.infinity;
        }
      }
    }

    // 1. 感電リスク回避 (最優先)
    // ノードが電力設備に近い(isHighRisk)場合は、即座に通行不可とする
    if (fromNode.isHighRisk || toNode.isHighRisk) {
      // 感電死リスクエリア = 絶対通行禁止
      return double.infinity;
    }

    // 2. 浸水深度による重み付け
    // 両端点の平均水深を取得 (nullなら0m)
    final depth1 = fromNode.floodDepth ?? 0.0;
    final depth2 = toNode.floodDepth ?? 0.0;
    final avgDepth = (depth1 + depth2) / 2.0;

    double multiplier = 1.0;

    if (avgDepth >= 1.0) {
      // 1m以上: ボート推奨レベル -> 実質通行不可に近いペナルティ
      multiplier = 20.0;
    } else if (avgDepth >= 0.5) {
      // 50cm以上: 車両通行不能、歩行危険 -> 大幅ペナルティ
      multiplier = 10.0;
    } else if (avgDepth >= 0.3) {
      // 30cm以上: 歩行困難 -> ペナルティ
      multiplier = 3.0;
    } else if (avgDepth > 0.0) {
      // 多少の浸水
      multiplier = 1.2;
    }

    // 3. 電力インフラへの距離 (念押し)
    // isHighRiskフラグだけでなく、距離データがあればさらに回避
    final distToPower1 = fromNode.distanceToPowerInfra ?? double.infinity;
    final distToPower2 = toNode.distanceToPowerInfra ?? double.infinity;
    final minDistToPower = math.min(distToPower1, distToPower2);

    if (minDistToPower < 30.0) {
      // 30m以内は念のため避ける (係数を上げる)
      multiplier *= 2.0;
    }

    return baseCost * multiplier;
  }

  // --- Helper Methods ---

  /// エッジ（またはその端点）がハザードポリゴンに含まれるか
  bool _isEdgeInHazardPolygon(RoadEdge edge) {
    if (hazardPolygons == null || hazardPolygons!.isEmpty) return false;

    // 簡易判定: 端点または中間点がポリゴン内ならNG
    final from = graph.nodes[edge.fromNodeId];
    final to = graph.nodes[edge.toNodeId];
    if (from == null || to == null) return false;

    final fromPos = from.position;
    final toPos = to.position;

    // 端点チェック
    if (_isPointInPolygons(fromPos.latitude, fromPos.longitude) || 
        _isPointInPolygons(toPos.latitude, toPos.longitude)) return true;

    // 中間点チェック
    final midLat = (fromPos.latitude + toPos.latitude) / 2;
    final midLng = (fromPos.longitude + toPos.longitude) / 2;
    if (_isPointInPolygons(midLat, midLng)) return true;

    return false;
  }

  bool _isPointInPolygons(double lat, double lng) {
    if (hazardPolygons == null) return false;
    final point = math.Point(lat, lng);
    
    for (final poly in hazardPolygons!) {
      if (_containsPoint(poly, point)) return true;
    }
    return false;
  }

  /// Ray-casting algorithm for polygon containment
  bool _containsPoint(List<math.Point<double>> polygon, math.Point<double> p) {
    int i, j = polygon.length - 1;
    bool oddNodes = false;

    for (i = 0; i < polygon.length; i++) {
      if ((polygon[i].y < p.y && polygon[j].y >= p.y || 
           polygon[j].y < p.y && polygon[i].y >= p.y) &&
          (polygon[i].x <= p.x || polygon[j].x <= p.x)) {
        if (polygon[i].x + (p.y - polygon[i].y) / 
            (polygon[j].y - polygon[i].y) * (polygon[j].x - polygon[i].x) < p.x) {
          oddNodes = !oddNodes;
        }
      }
      j = i;
    }
    return oddNodes;
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

// --- Priority Queue Implementation ---

class _QueueItem implements Comparable<_QueueItem> {
  final String nodeId;
  final double cost;

  _QueueItem(this.nodeId, this.cost);

  @override
  int compareTo(_QueueItem other) => cost.compareTo(other.cost);
}

class _PriorityQueue<T extends Comparable<T>> {
  final List<T> _heap = [];

  void add(T value) {
    _heap.add(value);
    _siftUp(_heap.length - 1);
  }

  T removeFirst() {
    if (_heap.isEmpty) throw StateError('No elements in queue');
    final result = _heap.first;
    final last = _heap.removeLast();
    if (_heap.isNotEmpty) {
      _heap[0] = last;
      _siftDown(0);
    }
    return result;
  }

  bool get isNotEmpty => _heap.isNotEmpty;

  void _siftUp(int index) {
    while (index > 0) {
      final parent = (index - 1) ~/ 2;
      if (_heap[index].compareTo(_heap[parent]) >= 0) break;
      _swap(index, parent);
      index = parent;
    }
  }

  void _siftDown(int index) {
    final length = _heap.length;
    while (true) {
      final left = 2 * index + 1;
      final right = 2 * index + 2;
      var smallest = index;

      if (left < length && _heap[left].compareTo(_heap[smallest]) < 0) {
        smallest = left;
      }
      if (right < length && _heap[right].compareTo(_heap[smallest]) < 0) {
        smallest = right;
      }
      if (smallest == index) break;
      _swap(index, smallest);
      index = smallest;
    }
  }

  void _swap(int i, int j) {
    final temp = _heap[i];
    _heap[i] = _heap[j];
    _heap[j] = temp;
  }
}