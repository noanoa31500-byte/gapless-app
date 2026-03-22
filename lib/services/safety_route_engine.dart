import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/road_feature.dart';
import '../models/user_profile.dart';

// ============================================================================
// SafetyRouteEngine — gplbデータを使った安全優先A*経路計算エンジン
// ============================================================================
//
// 【コストモデル】
//
//   edge_cost = distance_m × width_factor × profile_factor
//
//   width_factor:
//     道幅がある場合   → max(1.0, 6.0 / widthMeters)
//                        幅6m以上 = factor 1.0（ペナルティなし）
//                        幅3m     = factor 2.0（2倍コスト）
//     道幅がない場合   → RoadType 推定値（下表）
//
//     RoadType         推定幅(m)  factor(6÷w)
//     motorway         20.0       1.00
//     primary          12.0       1.00
//     secondary         8.0       1.00
//     residential       5.0       1.20
//     path              2.0       3.00
//     unknown           4.0       1.50
//
//   profile_factor (UserProfile):
//     requiresFlatRoute=true の場合
//       path → × 50.0   （段差含む小道を実質回避）
//     isElderly=true の場合
//       path        → × 3.0   （小道を避ける）
//       residential → × 1.5   （生活道路もやや避ける）
//       primary/secondary → × 0.8  （広い道を積極的に選ぶ）
//
// ============================================================================

/// グラフノード（道路交差点）
class _Node {
  final String id;
  final LatLng pos;
  final List<_Edge> edges = [];

  _Node(this.id, this.pos);
}

/// グラフエッジ（道路セグメント）
class _Edge {
  final _Node to;
  final double cost;
  final List<LatLng> geometry;

  _Edge(this.to, this.cost, this.geometry);
}

/// A* 優先キュー用アイテム
class _PqItem implements Comparable<_PqItem> {
  final String nodeId;
  final double f; // g + h
  _PqItem(this.nodeId, this.f);

  @override
  int compareTo(_PqItem other) => f.compareTo(other.f);
}

/// 経路計算結果
class RouteResult {
  /// 経路を構成するウェイポイント列
  final List<LatLng> waypoints;

  /// 総距離（メートル）
  final double totalDistanceM;

  /// 推定所要時間（秒）
  final double estimatedTimeSec;

  const RouteResult({
    required this.waypoints,
    required this.totalDistanceM,
    required this.estimatedTimeSec,
  });

  bool get found => waypoints.isNotEmpty;

  static const RouteResult notFound = RouteResult(
    waypoints: [],
    totalDistanceM: 0,
    estimatedTimeSec: 0,
  );
}

/// 安全優先A*経路計算エンジン
class SafetyRouteEngine {
  // ノードマップ: id → _Node
  final Map<String, _Node> _nodes = {};

  // 空間インデックス: "lat5,lng5" → nodeId のバケット
  // （小数点以下5桁 ≈ 1.1m 精度でスナップ）
  final Map<String, String> _snapIndex = {};

  static const int _snapPrecision = 5; // 小数点以下5桁

  /// RoadFeatureリストからグラフを構築する
  ///
  /// [features] gplbパーサーが返したRoadFeatureのリスト
  /// [profile]  ユーザープロファイル（コスト係数に影響）
  void buildGraph(List<RoadFeature> features, {UserProfile profile = UserProfile.standard}) {
    _nodes.clear();
    _snapIndex.clear();

    for (final feature in features) {
      if (feature.geometry.length < 2) continue;

      // ポリラインを順に辿り、隣接点同士をエッジとして登録
      for (int i = 0; i < feature.geometry.length - 1; i++) {
        final fromPos = feature.geometry[i];
        final toPos = feature.geometry[i + 1];

        final fromNode = _getOrCreateNode(fromPos);
        final toNode = _getOrCreateNode(toPos);

        final segmentGeom = [fromPos, toPos];
        final dist = _distanceM(fromPos, toPos);
        final cost = dist * _widthFactor(feature) * _profileFactor(feature, profile);

        fromNode.edges.add(_Edge(toNode, cost, segmentGeom));
        if (!feature.isOneWay) {
          toNode.edges.add(_Edge(fromNode, cost, List.from(segmentGeom.reversed)));
        }
      }
    }

    debugPrint(
        'SafetyRouteEngine: graph built — nodes=${_nodes.length}, features=${features.length}');
  }

  /// A* 経路探索
  ///
  /// [start] 出発地の座標
  /// [goal]  目的地の座標
  /// [profile] ユーザープロファイル
  RouteResult findRoute(
    LatLng start,
    LatLng goal, {
    UserProfile profile = UserProfile.standard,
  }) {
    if (_nodes.isEmpty) return RouteResult.notFound;

    final startNode = _nearestNode(start);
    final goalNode = _nearestNode(goal);

    if (startNode == null || goalNode == null) return RouteResult.notFound;
    if (startNode.id == goalNode.id) {
      return RouteResult(
        waypoints: [start, goal],
        totalDistanceM: _distanceM(start, goal),
        estimatedTimeSec: _distanceM(start, goal) / profile.walkSpeedMps,
      );
    }

    // A* 本体
    final gScore = <String, double>{startNode.id: 0.0};
    final cameFrom = <String, String?>{startNode.id: null};
    final cameEdge = <String, _Edge?>{};

    final openSet = _MinHeap<_PqItem>((a, b) => a.f.compareTo(b.f));
    openSet.push(_PqItem(startNode.id, _heuristic(startNode.pos, goalNode.pos)));

    final closed = <String>{};

    while (openSet.isNotEmpty) {
      final current = openSet.pop();
      final u = current.nodeId;

      if (u == goalNode.id) break;
      if (closed.contains(u)) continue;
      closed.add(u);

      final node = _nodes[u]!;
      for (final edge in node.edges) {
        final v = edge.to.id;
        if (closed.contains(v)) continue;

        final tentative = (gScore[u] ?? double.infinity) + edge.cost;
        if (tentative < (gScore[v] ?? double.infinity)) {
          gScore[v] = tentative;
          cameFrom[v] = u;
          cameEdge[v] = edge;
          final f = tentative + _heuristic(edge.to.pos, goalNode.pos);
          openSet.push(_PqItem(v, f));
        }
      }
    }

    if (!cameFrom.containsKey(goalNode.id)) return RouteResult.notFound;

    // パス再構築
    final waypoints = <LatLng>[];
    String? curr = goalNode.id;

    while (curr != null && cameFrom[curr] != null) {
      final edge = cameEdge[curr];
      if (edge != null) waypoints.insertAll(0, edge.geometry);
      curr = cameFrom[curr];
    }

    // 始点・終点を追加
    if (waypoints.isEmpty || waypoints.first != start) waypoints.insert(0, start);
    if (waypoints.isEmpty || waypoints.last != goal) waypoints.add(goal);

    // 総距離をウェイポイントから再計算
    double realDist = 0;
    for (int i = 0; i < waypoints.length - 1; i++) {
      realDist += _distanceM(waypoints[i], waypoints[i + 1]);
    }

    return RouteResult(
      waypoints: waypoints,
      totalDistanceM: realDist,
      estimatedTimeSec: realDist / profile.walkSpeedMps,
    );
  }

  // ---------------------------------------------------------------------------
  // コスト計算ヘルパー
  // ---------------------------------------------------------------------------

  /// 道幅ファクター
  /// 幅が広いほど factor が小さく（コストが低く）なる
  double _widthFactor(RoadFeature f) {
    final w = f.widthMeters ?? _estimatedWidth(f.type);
    // 6m 以上は factor = 1.0、それ以下は反比例
    return math.max(1.0, 6.0 / w);
  }

  /// RoadTypeから道幅を推定（メートル）
  double _estimatedWidth(RoadType type) {
    switch (type) {
      case RoadType.motorway:
        return 20.0;
      case RoadType.primary:
        return 12.0;
      case RoadType.secondary:
        return 8.0;
      case RoadType.residential:
        return 5.0;
      case RoadType.path:
        return 2.0;
      case RoadType.unknown:
        return 4.0;
    }
  }

  /// ユーザープロファイルによるペナルティ係数
  double _profileFactor(RoadFeature f, UserProfile profile) {
    double factor = 1.0;

    if (profile.requiresFlatRoute) {
      // 小道・不明道路は段差が含まれる可能性が高いため強くペナルティ
      if (f.type == RoadType.path || f.type == RoadType.unknown) {
        factor *= 50.0;
      }
    }

    if (profile.isElderly) {
      switch (f.type) {
        case RoadType.primary:
        case RoadType.secondary:
          factor *= 0.8; // 幹線道路を積極的に選ぶ
        case RoadType.residential:
          factor *= 1.5;
        case RoadType.path:
          factor *= 3.0;
        default:
          break;
      }
    }

    return factor;
  }

  // ---------------------------------------------------------------------------
  // グラフ構築ヘルパー
  // ---------------------------------------------------------------------------

  _Node _getOrCreateNode(LatLng pos) {
    final key = _snapKey(pos);
    final existingId = _snapIndex[key];
    if (existingId != null) return _nodes[existingId]!;

    final id = 'n${_nodes.length}';
    final node = _Node(id, pos);
    _nodes[id] = node;
    _snapIndex[key] = id;
    return node;
  }

  _Node? _nearestNode(LatLng pos) {
    if (_nodes.isEmpty) return null;

    // まずスナップキーで完全一致検索
    final exact = _snapIndex[_snapKey(pos)];
    if (exact != null) return _nodes[exact];

    // なければ全ノードから最近傍を線形探索（起点・終点のみなので許容）
    _Node? best;
    double bestDist = double.infinity;
    for (final node in _nodes.values) {
      final d = _distanceM(pos, node.pos);
      if (d < bestDist) {
        bestDist = d;
        best = node;
      }
    }
    return best;
  }

  String _snapKey(LatLng pos) {
    final lat = pos.latitude.toStringAsFixed(_snapPrecision);
    final lng = pos.longitude.toStringAsFixed(_snapPrecision);
    return '$lat,$lng';
  }

  // ---------------------------------------------------------------------------
  // 幾何計算
  // ---------------------------------------------------------------------------

  double _distanceM(LatLng a, LatLng b) {
    const dist = Distance();
    return dist(a, b);
  }

  /// A* のヒューリスティック：直線距離
  double _heuristic(LatLng a, LatLng b) => _distanceM(a, b);
}

// ============================================================================
// _MinHeap — 汎用バイナリ最小ヒープ（外部パッケージ不要）
// ============================================================================
class _MinHeap<T> {
  final int Function(T a, T b) _compare;
  final List<T> _data = [];

  _MinHeap(this._compare);

  bool get isNotEmpty => _data.isNotEmpty;

  void push(T item) {
    _data.add(item);
    _bubbleUp(_data.length - 1);
  }

  T pop() {
    final top = _data[0];
    final last = _data.removeLast();
    if (_data.isNotEmpty) {
      _data[0] = last;
      _siftDown(0);
    }
    return top;
  }

  void _bubbleUp(int i) {
    while (i > 0) {
      final parent = (i - 1) ~/ 2;
      if (_compare(_data[i], _data[parent]) < 0) {
        final tmp = _data[i];
        _data[i] = _data[parent];
        _data[parent] = tmp;
        i = parent;
      } else {
        break;
      }
    }
  }

  void _siftDown(int i) {
    final n = _data.length;
    while (true) {
      int smallest = i;
      final l = 2 * i + 1;
      final r = 2 * i + 2;
      if (l < n && _compare(_data[l], _data[smallest]) < 0) smallest = l;
      if (r < n && _compare(_data[r], _data[smallest]) < 0) smallest = r;
      if (smallest == i) break;
      final tmp = _data[i];
      _data[i] = _data[smallest];
      _data[smallest] = tmp;
      i = smallest;
    }
  }
}
