import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/road_edge.dart';
import '../models/road_graph.dart';

/// ============================================================================
/// RoutingEngine - 災害対応型ルーティングエンジン (Directives Compliant)
/// ============================================================================
/// 
/// 【ABSOLUTE DIRECTIVES IMPLEMENTATION】
/// 1. NAV: Waypoint-based navigation (Produces List<LatLng>).
/// 2. LOGIC (Japan): Road width priority (Avoid narrow/blocked roads).
/// 3. LOGIC (Thailand): Avoid Electric Shock Risk (Flood + Power Infra).
/// 
/// This engine calculates the safest path based on the specific regional mode.
class RoutingEngine {
  final RoadGraph graph;
  final String mode; // 'japan' or 'thailand'
  
  // Data sources for risk calculation
  final List<List<math.Point<double>>>? hazardPolygons; // Japan: Debris/Fire/Tsunami
  final List<Map<String, dynamic>>? hazardPoints; // Thailand: Specific danger spots
  final DateTime? earthquakeTime; // For time-decay logic (Japan)

  RoutingEngine({
    required this.graph,
    required this.mode,
    this.hazardPolygons,
    this.hazardPoints,
    this.earthquakeTime,
  });

  /// ==========================================================================
  /// Public API: Find Safest Path (Waypoint Generation)
  /// ==========================================================================
  /// Returns a list of LatLng constituting the safest route (Waypoints).
  List<LatLng> findSafestRouteWaypoints(LatLng start, LatLng goal) {
    final startNodeId = _findNearestNodeId(start);
    final goalNodeId = _findNearestNodeId(goal);

    if (startNodeId == null || goalNodeId == null) {
      if (kDebugMode) print('❌ RoutingEngine: Start or Goal node not found.');
      return [];
    }

    final nodeIds = _findSafestPathDijkstra(startNodeId, goalNodeId);
    
    // Convert Node IDs to LatLng List (Waypoint-based Navigation)
    return nodeIds
        .map((id) => graph.nodes[id]?.position)
        .whereType<LatLng>()
        .toList();
  }

  /// Legacy API: Returns Node IDs
  List<String> findSafestPath(String startNodeId, String goalNodeId) {
    return _findSafestPathDijkstra(startNodeId, goalNodeId);
  }

  /// ==========================================================================
  /// Core Algorithm: Dijkstra with Safety Weights
  /// ==========================================================================
  List<String> _findSafestPathDijkstra(String startNodeId, String goalNodeId) {
    final distances = <String, double>{};
    final previous = <String, String?>{};
    final queue = _PriorityQueue<_QueueItem>();

    // Initialize
    distances[startNodeId] = 0.0;
    queue.add(_QueueItem(startNodeId, 0.0));

    final Set<String> visited = {};

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      final u = current.nodeId;

      if (u == goalNodeId) break; // Reached goal
      if (visited.contains(u)) continue;
      visited.add(u);

      if (current.cost > (distances[u] ?? double.infinity)) continue;

      final edges = graph.getEdgesFromNode(u);
      for (final edge in edges) {
        final v = graph.getOtherNodeId(edge.id, u);
        if (v == null) continue;

        // Calculate Weight based on Regional Logic
        final weight = _calculateEdgeWeight(edge);
        
        // If infinity, the edge is impassable (High Risk)
        if (weight == double.infinity) continue;

        final newDist = (distances[u] ?? double.infinity) + weight;
        if (newDist < (distances[v] ?? double.infinity)) {
          distances[v] = newDist;
          previous[v] = u;
          queue.add(_QueueItem(v, newDist));
        }
      }
    }

    // Reconstruct Path
    if (!previous.containsKey(goalNodeId) && startNodeId != goalNodeId) {
      return []; // No path found
    }

    final path = <String>[];
    String? curr = goalNodeId;
    while (curr != null) {
      path.insert(0, curr);
      curr = previous[curr];
    }
    return path;
  }

  /// ==========================================================================
  /// Logic Directive Implementation
  /// ==========================================================================
  double _calculateEdgeWeight(RoadEdge edge) {
    if (mode == 'thailand') {
      return _calculateThailandWeight(edge);
    } else {
      return _calculateJapanWeight(edge);
    }
  }

  /// --------------------------------------------------------------------------
  /// LOGIC: Japan = Road Width Priority
  /// --------------------------------------------------------------------------
  /// 地震時はブロック塀倒壊や建物崩壊により、狭い道路が閉塞するリスクが高い。
  /// 広い道路（Primary/Secondary）を優先し、狭い道路（Residential/Service）を避ける。
  double _calculateJapanWeight(RoadEdge edge) {
    // 1. Hazard Polygon Check (Absolute Avoidance)
    if (_isEdgeInHazardPolygon(edge)) {
      return double.infinity;
    }

    // 2. Road Width Logic (OSM Highway Types)
    double widthMultiplier = 1.0;
    final type = edge.highwayType?.toLowerCase() ?? 'unknown';

    switch (type) {
      // Wide Roads (Safe from collapse blockage)
      case 'motorway':
      case 'trunk':
      case 'primary':
      case 'secondary':
        widthMultiplier = 1.0; // Base cost
        break;
      
      // Medium Roads
      case 'tertiary':
        widthMultiplier = 1.2;
        break;

      // Narrow Roads (High Risk of Blockage)
      case 'residential':
      case 'living_street':
      case 'unclassified':
        widthMultiplier = 2.0; // Avoid if possible
        break;

      // Very Narrow / Hazardous
      case 'service':
      case 'track':
      case 'path':
      case 'footway':
      case 'steps':
        widthMultiplier = 5.0; // Strong avoidance
        break;
        
      default:
        widthMultiplier = 3.0; // Unknown is risky
    }

    // Time Decay Factor (Immediately after quake vs later)
    double timeDecay = 1.0;
    if (earthquakeTime != null) {
      final hoursSinceEarthquake = 
          DateTime.now().difference(earthquakeTime!).inHours;

      if (hoursSinceEarthquake < 6) {
        timeDecay = 1.5;
      } else if (hoursSinceEarthquake < 24) {
        timeDecay = 1.2;
      } else if (hoursSinceEarthquake < 72) {
        timeDecay = 1.0;
      } else {
        timeDecay = 0.8;
      }
    }
    
    return edge.distance * widthMultiplier * timeDecay;
  }

  /// --------------------------------------------------------------------------
  /// LOGIC: Thailand = Avoid Electric Shock Risk
  /// --------------------------------------------------------------------------
  /// 洪水時は「見えない死（感電）」が最大のリスク。
  /// 電力設備に近く、かつ浸水している場所は「絶対回避（Infinity）」。
  double _calculateThailandWeight(RoadEdge edge) {
    final nodeFrom = graph.nodes[edge.fromNodeId];
    final nodeTo = graph.nodes[edge.toNodeId];

    if (nodeFrom == null || nodeTo == null) return edge.distance * 2.0;

    // 1. Hazard Polygon Check (Absolute Avoidance)
    if (_isEdgeInHazardPolygon(edge)) {
      return double.infinity;
    }

    // 2. Hazard Points Check (Thailand-specific danger spots)
    if (_isEdgeNearHazardPoint(edge)) {
      return double.infinity;
    }

    // 3. Electric Shock Risk Assessment
    // Data from Graph Building Phase (Pre-calculated for performance)
    // Flood depth in meters
    final depthFrom = nodeFrom.floodDepth ?? 0.0;
    final depthTo = nodeTo.floodDepth ?? 0.0;
    final maxDepth = math.max(depthFrom, depthTo);

    // Distance to nearest power infrastructure (meters)
    final powerDistFrom = nodeFrom.distanceToPowerInfra ?? 9999.0;
    final powerDistTo = nodeTo.distanceToPowerInfra ?? 9999.0;
    final minPowerDist = math.min(powerDistFrom, powerDistTo);

    // Check if nodes are marked as high risk
    final isHighRiskFrom = nodeFrom.isHighRisk;
    final isHighRiskTo = nodeTo.isHighRisk;

    // Electric Shock Risk (The "Kill Zone")
    // Rule 1: Either node marked as high risk = DANGER
    if (isHighRiskFrom || isHighRiskTo) {
      if (kDebugMode) print('⚡ ROUTING: High Risk Node at edge ${edge.id}');
      return double.infinity;
    }

    // Rule 2: Water > 30cm AND Power < 30m = DANGER
    if (maxDepth > 0.3 && minPowerDist < 30.0) {
      if (kDebugMode) print('⚡ ROUTING: Avoiding Electric Risk at edge ${edge.id}');
      return double.infinity; // Absolutely impassable
    }

    // 4. High Water Risk (Non-electric)
    // Walking in >80cm water is dangerous (currents, hidden holes)
    if (maxDepth > 0.8) {
      return double.infinity;
    }

    // 5. Weight Penalties (Soft Avoidance)
    double penaltyMultiplier = 1.0;

    // Shallow water penalty (slow walking)
    if (maxDepth > 0.1) {
      penaltyMultiplier += (maxDepth * 5.0); // 0.5m depth adds +2.5x cost
    }

    // Power proximity penalty (even without confirmed deep water, stay away)
    if (minPowerDist < 50.0) {
      penaltyMultiplier += 2.0; // Prefer roads far from power lines
    }

    return edge.distance * penaltyMultiplier;
  }

  /// ==========================================================================
  /// Helper Methods
  /// ==========================================================================
  
  String? _findNearestNodeId(LatLng point) {
    if (graph.nodes.isEmpty) return null;
    
    double minDistance = double.infinity;
    String? nearestId;
    const distanceCalc = Distance();

    // Optimization: Simple linear scan (Sufficient for <10k nodes, otherwise use QuadTree)
    for (final entry in graph.nodes.entries) {
      final nodePos = entry.value.position;
      // Fast Manhattan distance check first
      if ((nodePos.latitude - point.latitude).abs() > 0.05 || 
          (nodePos.longitude - point.longitude).abs() > 0.05) continue;

      final dist = distanceCalc.as(LengthUnit.Meter, point, nodePos);
      if (dist < minDistance) {
        minDistance = dist;
        nearestId = entry.key;
      }
    }
    
    // Threshold: Don't snap if too far (e.g., > 1km)
    if (minDistance > 1000) return null;
    
    return nearestId;
  }

  bool _isEdgeInHazardPolygon(RoadEdge edge) {
    if (hazardPolygons == null || hazardPolygons!.isEmpty) return false;

    // Check midpoint of edge
    final midLat = edge.centerPoint.latitude;
    final midLng = edge.centerPoint.longitude;
    final p = math.Point(midLat, midLng);

    for (final poly in hazardPolygons!) {
      if (_isPointInPolygon(p, poly)) return true;
    }
    return false;
  }

  bool _isEdgeNearHazardPoint(RoadEdge edge) {
    if (hazardPoints == null || hazardPoints!.isEmpty) return false;

    const double threshold = 0.0005; // ~50m
    
    final midLat = edge.centerPoint.latitude;
    final midLng = edge.centerPoint.longitude;

    for (final point in hazardPoints!) {
      final pLat = point['lat'] as double;
      final pLng = point['lng'] as double;

      final dLat = (midLat - pLat).abs();
      final dLng = (midLng - pLng).abs();

      if (dLat < threshold && dLng < threshold) {
        return true;
      }
    }
    return false;
  }

  bool _isPointInPolygon(math.Point<double> p, List<math.Point<double>> polygon) {
    bool inside = false;
    int j = polygon.length - 1;
    for (int i = 0; i < polygon.length; i++) {
      if (((polygon[i].x > p.x) != (polygon[j].x > p.x)) &&
          (p.y < (polygon[j].y - polygon[i].y) * (p.x - polygon[i].x) /
              (polygon[j].x - polygon[i].x) + polygon[i].y)) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }
  
  /// Helper method specifically for calculating single edge weight externally if needed
  double calculateEdgeWeight(RoadEdge edge) {
    return _calculateEdgeWeight(edge);
  }
}

/// ============================================================================
/// Internal Utilities
/// ============================================================================

class _QueueItem implements Comparable<_QueueItem> {
  final String nodeId;
  final double cost;

  _QueueItem(this.nodeId, this.cost);

  @override
  int compareTo(_QueueItem other) => cost.compareTo(other.cost);
}

class _PriorityQueue<T extends Comparable<T>> {
  final List<T> _heap = [];

  void add(T item) {
    _heap.add(item);
    _bubbleUp(_heap.length - 1);
  }

  T removeFirst() {
    if (_heap.isEmpty) throw StateError('Queue is empty');
    final first = _heap.first;
    final last = _heap.removeLast();
    if (_heap.isNotEmpty) {
      _heap[0] = last;
      _bubbleDown(0);
    }
    return first;
  }

  bool get isNotEmpty => _heap.isNotEmpty;

  void _bubbleUp(int index) {
    while (index > 0) {
      final parentIndex = (index - 1) ~/ 2;
      if (_heap[index].compareTo(_heap[parentIndex]) >= 0) break;
      _swap(index, parentIndex);
      index = parentIndex;
    }
  }

  void _bubbleDown(int index) {
    while (true) {
      final leftChild = 2 * index + 1;
      final rightChild = 2 * index + 2;
      var smallest = index;

      if (leftChild < _heap.length &&
          _heap[leftChild].compareTo(_heap[smallest]) < 0) {
        smallest = leftChild;
      }
      if (rightChild < _heap.length &&
          _heap[rightChild].compareTo(_heap[smallest]) < 0) {
        smallest = rightChild;
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