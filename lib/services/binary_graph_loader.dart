
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../models/road_node.dart';
import '../models/road_edge.dart';
import '../models/road_graph.dart';

/// ============================================================================
/// BinaryGraphLoader - バイナリ形式からグラフ構造を構築
/// ============================================================================
/// 
/// 【設計思想】
/// 災害時はネットワーク断絶を想定し、ローカルデータのみで動作する必要があります。
/// バイナリ形式はGeoJSONより高速に読み込めるため、アプリ起動時間を短縮し、
/// ユーザーを早く安全な状態に導くことができます。
///
/// 【現行バイナリフォーマット（roads_jp.bin / roads_th.bin）】
/// ポリライン形式（BinaryRoadLoaderと同じ）:
/// [Roads Loop]
///   - Point Count (2byte UInt16 BigEndian)
///   - Type ID (1byte UInt8)
///   - [Points Loop]
///     - Lat (4byte Float32 BigEndian)
///     - Lng (4byte Float32 BigEndian)
///
/// このローダーはポリラインデータからグラフ構造を再構築します。
/// ============================================================================
class BinaryGraphLoader {
  /// バイナリファイルからRoadGraphを構築（Isolate対応）
  /// 
  /// @param assetPath アセットファイルのパス
  /// @param mode 'japan' または 'thailand'（将来の拡張用）
  /// @return 構築されたRoadGraph
  static Future<RoadGraph> loadGraph(String assetPath, {String mode = 'japan'}) async {
    try {
      // 1. バイナリファイルを読み込む
      final ByteData data = await rootBundle.load(assetPath);
      
      // 2. Isolateでグラフ構築（UIスレッドをブロックしない）
      final params = _GraphBuildParams(
        bytes: data.buffer.asUint8List(),
        mode: mode,
      );
      
      return await compute(_buildGraphInIsolate, params);
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ BinaryGraphLoader Error: $e');
      }
      // 空のグラフを返す（フォールバックはGraphBuilderで対応）
      return RoadGraph();
    }
  }
  
  /// Isolate内でグラフを構築
  static RoadGraph _buildGraphInIsolate(_GraphBuildParams params) {
    final graph = RoadGraph();
    final nodeMap = <String, String>{}; // 座標キー -> ノードID
    int nodeCounter = 0;
    int edgeCounter = 0;
    
    try {
      final data = ByteData.view(Uint8List.fromList(params.bytes).buffer);
      int offset = 0;
      final int length = data.lengthInBytes;
      
      // ポリラインをパースしながらグラフを構築
      while (offset < length) {
        // 安全策: 残りバイト数がヘッダー分(3byte)未満なら終了
        if (offset + 3 > length) break;
        
        // 点の数を取得 (2byte BigEndian)
        final int pointCount = data.getUint16(offset, Endian.big);
        offset += 2;
        
        // 道路タイプIDを取得 (1byte)
        final int typeId = data.getUint8(offset);
        offset += 1;
        
        // 座標データを読み込む
        if (offset + (pointCount * 8) > length) {
          if (kDebugMode) print('⚠️ BinaryGraphLoader: Unexpected EOF');
          break;
        }
        
        final List<LatLng> points = [];
        final List<String> nodeIds = [];
        
        for (int i = 0; i < pointCount; i++) {
          final double lat = data.getFloat32(offset, Endian.big);
          offset += 4;
          
          final double lng = data.getFloat32(offset, Endian.big);
          offset += 4;
          
          final point = LatLng(lat, lng);
          points.add(point);
          
          // ノードを作成またはマップから取得
          final nodeKey = '${lat.toStringAsFixed(5)}_${lng.toStringAsFixed(5)}';
          String nodeId;
          
          if (nodeMap.containsKey(nodeKey)) {
            nodeId = nodeMap[nodeKey]!;
          } else {
            nodeId = 'n$nodeCounter';
            nodeCounter++;
            nodeMap[nodeKey] = nodeId;
            
            // ノードを追加
            final node = RoadNode(
              id: nodeId,
              position: point,
            );
            graph.addNode(node);
          }
          
          nodeIds.add(nodeId);
        }
        
        // 連続するノード間にエッジを作成
        for (int i = 0; i < nodeIds.length - 1; i++) {
          final fromId = nodeIds[i];
          final toId = nodeIds[i + 1];
          
          // 距離を計算
          const distance = Distance();
          final dist = distance.as(LengthUnit.Meter, points[i], points[i + 1]);
          
          // 道路タイプを判定
          final highwayType = _getHighwayTypeFromId(typeId);
          
          // エッジを追加
          final edge = RoadEdge(
            id: 'e$edgeCounter',
            fromNodeId: fromId,
            toNodeId: toId,
            distance: dist,
            geometry: [points[i], points[i + 1]],
            highwayType: highwayType,
          );
          
          graph.addEdge(edge);
          edgeCounter++;
        }
      }
      
      if (kDebugMode) {
        debugPrint('✅ BinaryGraphLoader: 構築完了 - ${graph.nodes.length}ノード, ${graph.edges.length}エッジ');
      }
      
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ BinaryGraphLoader Isolate Error: $e');
      }
    }
    
    return graph;
  }
  
  /// タイプIDから道路タイプ文字列を取得
  /// 
  /// BinaryRoadLoaderの変換時に使用したマッピングに合わせる
  static String _getHighwayTypeFromId(int typeId) {
    switch (typeId) {
      case 1: return 'primary';      // 主要道路
      case 2: return 'secondary';    // 二次道路
      case 3: return 'tertiary';     // 三次道路
      case 4: return 'residential';  // 住宅街道路
      case 5: return 'service';      // サービス道路
      case 6: return 'footway';      // 歩道
      case 7: return 'path';         // 小道
      default: return 'unclassified'; // 分類なし
    }
  }
  
  /// 座標からの最近接ノードを検索
  /// 
  /// @param graph 検索対象のグラフ
  /// @param position 検索位置
  /// @param maxDistance 最大検索距離（メートル）
  /// @return 最近接ノードのID（見つからなければnull）
  static String? findNearestNode(RoadGraph graph, LatLng position, {double maxDistance = 500}) {
    String? nearestId;
    double minDist = maxDistance;
    
    const distance = Distance();
    
    for (final node in graph.nodes.values) {
      final dist = distance.as(LengthUnit.Meter, position, node.position);
      if (dist < minDist) {
        minDist = dist;
        nearestId = node.id;
      }
    }
    
    return nearestId;
  }
}

/// Isolateに渡すパラメータ
class _GraphBuildParams {
  final List<int> bytes;
  final String mode;
  
  _GraphBuildParams({
    required this.bytes,
    required this.mode,
  });
}
