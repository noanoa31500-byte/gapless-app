import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../models/road_node.dart';
import '../models/road_edge.dart';
import '../models/road_graph.dart';

/// GeoJSONから道路グラフを構築するサービス
/// 
/// compute()を使用してバックグラウンドで構築することで、
/// UIスレッドをブロックせずに大規模データを処理します。
class GraphBuilder {
  /// GeoJSONファイルから道路グラフを構築（compute対応）
  /// 
  /// @param geoJsonPath GeoJSONファイルのパス
  /// @param mode 'japan' または 'thailand'
  /// @param floodDataPath 洪水データのパス（タイモードの場合）
  /// @return 構築されたRoadGraph
  static Future<RoadGraph> buildGraphFromGeoJson({
    required String geoJsonPath,
    required String mode,
    String? floodDataPath,
  }) async {
    // 1. GeoJSONを読み込む
    final geoJsonString = await rootBundle.loadString(geoJsonPath);
    
    // 2. 洪水データを読み込む（タイモードの場合）
    String? floodDataString;
    if (mode == 'thailand' && floodDataPath != null) {
      try {
        floodDataString = await rootBundle.loadString(floodDataPath);
      } catch (e) {
        if (kDebugMode) print('⚠️ 洪水データの読み込みに失敗: $e');
      }
    }
    
    // 3. compute()でバックグラウンド処理
    final params = _GraphBuildParams(
      geoJsonString: geoJsonString,
      floodDataString: floodDataString,
      mode: mode,
    );
    
    return await compute(_buildGraphInIsolate, params);
  }

  /// Isolateで実行されるグラフ構築処理
  static RoadGraph _buildGraphInIsolate(_GraphBuildParams params) {
    final graph = RoadGraph();
    
    try {
      // GeoJSONをパース
      final geoJson = jsonDecode(params.geoJsonString) as Map<String, dynamic>;
      final features = geoJson['features'] as List<dynamic>?;
      
      if (features == null) return graph;
      
      // 洪水データをパース（タイモードの場合）
      Map<String, Map<String, dynamic>>? floodData;
      if (params.floodDataString != null) {
        try {
          final floodList = jsonDecode(params.floodDataString!) as List<dynamic>;
          floodData = {};
          for (var item in floodList) {
            final lat = item['lat'];
            final lon = item['lon'];
            if (lat != null && lon != null) {
              final key = '${lat}_${lon}';
              floodData[key] = item as Map<String, dynamic>;
            }
          }
        } catch (e) {
          if (kDebugMode) print('洪水データのパースエラー: $e');
        }
      }
      
      // ノードマップ（座標 -> ノードID）
      final nodeMap = <String, String>{};
      int nodeCounter = 0;
      int edgeCounter = 0;
      
      // 各featureを処理
      for (var feature in features) {
        try {
          final geometry = feature['geometry'] as Map<String, dynamic>?;
          final properties = feature['properties'] as Map<String, dynamic>?;
          
          if (geometry == null) continue;
          
          final geoType = geometry['type'] as String?;
          final coordinates = geometry['coordinates'];
          
          if (geoType != 'LineString' && geoType != 'MultiLineString') {
            continue; // 道路はLineStringまたはMultiLineString
          }
          
          // LineStringの処理
          if (geoType == 'LineString') {
            _processLineString(
              coordinates,
              properties,
              graph,
              nodeMap,
              nodeCounter,
              edgeCounter,
              floodData,
              params.mode,
            );
            nodeCounter += 100; // ノードIDの衝突を避けるため
            edgeCounter++;
          } else if (geoType == 'MultiLineString') {
            final lines = coordinates as List;
            for (var line in lines) {
              _processLineString(
                line,
                properties,
                graph,
                nodeMap,
                nodeCounter,
                edgeCounter,
                floodData,
                params.mode,
              );
              nodeCounter += 100;
              edgeCounter++;
            }
          }
        } catch (e) {
          // エラーがあっても続行
          continue;
        }
      }
      
      if (kDebugMode) {
        debugPrint('✅ グラフ構築完了: ${graph.getStats()}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ グラフ構築エラー: $e');
      }
    }
    
    return graph;
  }

  /// LineStringを処理してノードとエッジを追加
  static void _processLineString(
    dynamic coordinates,
    Map<String, dynamic>? properties,
    RoadGraph graph,
    Map<String, String> nodeMap,
    int nodeCounter,
    int edgeCounter,
    Map<String, Map<String, dynamic>>? floodData,
    String mode,
  ) {
    final coordList = coordinates as List;
    if (coordList.length < 2) return;
    
    final List<LatLng> points = [];
    final List<String> nodeIds = [];
    
    // 座標リストをLatLngに変換し、ノードを作成
    for (var coord in coordList) {
      final c = coord as List;
      if (c.length < 2) continue;
      
      final lng = (c[0] as num).toDouble();
      final lat = (c[1] as num).toDouble();
      final point = LatLng(lat, lng);
      points.add(point);
      
      // ノードのキー（座標を文字列化）
      final nodeKey = '${lat.toStringAsFixed(6)}_${lng.toStringAsFixed(6)}';
      
      String nodeId;
      if (nodeMap.containsKey(nodeKey)) {
        nodeId = nodeMap[nodeKey]!;
      } else {
        nodeId = 'node_${nodeCounter}_${nodeMap.length}';
        nodeMap[nodeKey] = nodeId;
        
        // ノードを追加
        final node = RoadNode(
          id: nodeId,
          position: point,
          floodDepth: mode == 'thailand' ? _getFloodDepthAt(point, floodData) : null,
        );
        graph.addNode(node);
      }
      
      nodeIds.add(nodeId);
    }
    
    // エッジを作成（連続するノード間）
    for (int i = 0; i < nodeIds.length - 1; i++) {
      final fromId = nodeIds[i];
      final toId = nodeIds[i + 1];
      
      // 距離を計算
      const distance = Distance();
      final dist = distance.as(LengthUnit.Meter, points[i], points[i + 1]);
      
      // エッジを追加
      final edge = RoadEdge(
        id: 'edge_${edgeCounter}_$i',
        fromNodeId: fromId,
        toNodeId: toId,
        distance: dist,
        geometry: [points[i], points[i + 1]],
        highwayType: properties?['highway'] as String?,
        name: properties?['name'] as String?,
        properties: properties,
      );
      
      graph.addEdge(edge);
    }
  }

  /// 指定座標の水深を取得
  static double _getFloodDepthAt(
    LatLng point,
    Map<String, Map<String, dynamic>>? floodData,
  ) {
    if (floodData == null) return 0.0;
    
    // 最も近いデータポイントを検索
    double minDist = double.infinity;
    double depth = 0.0;
    
    const distance = Distance();
    
    floodData.forEach((key, data) {
      final lat = data['lat'] as double?;
      final lon = data['lon'] as double?;
      if (lat == null || lon == null) return;
      
      final dist = distance.as(LengthUnit.Meter, point, LatLng(lat, lon));
      if (dist < minDist) {
        minDist = dist;
        depth = (data['pred_depth'] as num?)?.toDouble() ?? 0.0;
      }
    });
    
    // 200m以上離れていたらデータなしとみなす
    if (minDist > 200) return 0.0;
    
    return depth;
  }
}

/// compute()に渡すパラメータ
class _GraphBuildParams {
  final String geoJsonString;
  final String? floodDataString;
  final String mode;

  _GraphBuildParams({
    required this.geoJsonString,
    this.floodDataString,
    required this.mode,
  });
}
