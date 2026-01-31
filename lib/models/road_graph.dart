import 'road_node.dart';
import 'road_edge.dart';

/// 道路ネットワークのグラフ構造
/// 
/// 防災エンジニアとしての視点:
/// このグラフは「命を繋ぐ道のネットワーク」を表現します。
/// 効率的な探索のため、隣接リスト構造を採用しています。
class RoadGraph {
  /// ノードID -> RoadNode のマップ
  final Map<String, RoadNode> nodes;
  
  /// エッジID -> RoadEdge のマップ
  final Map<String, RoadEdge> edges;
  
  /// ノードID -> そのノードに接続されているエッジIDリスト
  final Map<String, List<String>> adjacencyList;

  RoadGraph({
    Map<String, RoadNode>? nodes,
    Map<String, RoadEdge>? edges,
    Map<String, List<String>>? adjacencyList,
  })  : nodes = nodes ?? {},
        edges = edges ?? {},
        adjacencyList = adjacencyList ?? {};

  /// ノードを追加
  void addNode(RoadNode node) {
    nodes[node.id] = node;
    adjacencyList.putIfAbsent(node.id, () => []);
  }

  /// エッジを追加し、隣接リストを更新
  void addEdge(RoadEdge edge) {
    edges[edge.id] = edge;
    
    // 双方向の隣接リストを更新
    adjacencyList.putIfAbsent(edge.fromNodeId, () => []).add(edge.id);
    
    // 道路は通常双方向なので、逆方向も追加
    // （一方通行の場合はOSMタグで判定して除外する実装も可能）
    adjacencyList.putIfAbsent(edge.toNodeId, () => []).add(edge.id);
  }

  /// 指定ノードから出ている全エッジを取得
  List<RoadEdge> getEdgesFromNode(String nodeId) {
    final edgeIds = adjacencyList[nodeId] ?? [];
    return edgeIds
        .map((id) => edges[id])
        .whereType<RoadEdge>()
        .toList();
  }

  /// エッジの終点ノードを取得（fromNodeIdから見て）
  String? getOtherNodeId(String edgeId, String fromNodeId) {
    final edge = edges[edgeId];
    if (edge == null) return null;
    
    if (edge.fromNodeId == fromNodeId) {
      return edge.toNodeId;
    } else if (edge.toNodeId == fromNodeId) {
      return edge.fromNodeId;
    }
    return null;
  }

  /// グラフの統計情報を取得
  Map<String, int> getStats() => {
    'nodes': nodes.length,
    'edges': edges.length,
  };

  /// グラフをクリア
  void clear() {
    nodes.clear();
    edges.clear();
    adjacencyList.clear();
  }
}
