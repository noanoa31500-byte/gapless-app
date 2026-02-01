import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import '../models/road_node.dart';
import '../models/road_edge.dart';
import '../models/road_graph.dart';

/// タイ専用：感電リスク回避型ルーティングエンジン
/// 
/// 防災エンジニアとしての哲学:
/// Googleマップは「道路が存在すること」を教えてくれます。
/// しかし、洪水時の「見えない死（感電）」は考慮されません。
/// 
/// このエンジンは、「遠回りでも命を守る」ことを最優先とします。
/// 被災者が「なぜこの道を通れないのか」と疑問に思っても、
/// それが命を救うための判断です。
class ThaiSafestRoutingEngine {
  /// 空間インデックス付きグラフ構築（compute用）
  /// 
  /// なぜこの処理順序がスマホに適しているか:
  /// 1. 一度の読み込みで全ての事前計算を完了
  /// 2. ルート計算時は単純な判定のみ（高速）
  /// 3. メモリ効率: フラグだけを保持（座標データは不要）
  static Future<RoadGraph> buildSafetyIndexedGraph({
    required String roadsGeoJsonPath,
    required String floodDataPath,
    required String powerDataPath,
  }) async {
    try {
      // データを並列読み込み
      final results = await Future.wait([
        rootBundle.loadString(roadsGeoJsonPath),
        rootBundle.loadString(floodDataPath),
        rootBundle.loadString(powerDataPath),
      ]);

      final params = _GraphBuildParams(
        roadsJson: results[0],
        floodJson: results[1],
        powerJson: results[2],
      );

      // compute()でバックグラウンド処理
      return await compute(_buildGraphWithSafetyIndex, params);
    } catch (e) {
      if (kDebugMode) print('❌ グラフ構築エラー: $e');
      return RoadGraph();
    }
  }

  /// Isolateで実行されるグラフ構築処理
  /// 
  /// 処理フロー:
  /// 1. 電力設備の位置を抽出
  /// 2. 浸水データの位置を抽出
  /// 3. 道路ネットワークを構築しながら、各ノードに対して:
  ///    - 最寄りの浸水データから水深を取得
  ///    - 最寄りの電力設備までの距離を計算
  ///    - 感電リスクフラグを設定
  static RoadGraph _buildGraphWithSafetyIndex(_GraphBuildParams params) {
    final graph = RoadGraph();

    try {
      // === Step 1: 電力設備の位置を抽出 ===
      final powerLocations = _extractPowerLocations(params.powerJson);
      if (kDebugMode) print('🔌 電力設備: ${powerLocations.length}箇所');

      // === Step 2: 浸水データをマップ化（高速検索用）===
      final floodData = _buildFloodDataMap(params.floodJson);
      if (kDebugMode) print('🌊 浸水データ: ${floodData.length}地点');

      // === Step 3: 道路ネットワークを構築 ===
      final geoJson = jsonDecode(params.roadsJson) as Map<String, dynamic>;
      final features = geoJson['features'] as List<dynamic>?;

      if (features == null) return graph;

      int nodeCounter = 0;
      int edgeCounter = 0;
      final nodeMap = <String, String>{}; // 座標 -> ノードID

      for (var feature in features) {
        try {
          final geometry = feature['geometry'] as Map<String, dynamic>?;
          final properties = feature['properties'] as Map<String, dynamic>?;

          if (geometry == null) continue;

          final geoType = geometry['type'] as String?;
          final coordinates = geometry['coordinates'];

          if (geoType == 'LineString') {
            _processLineString(
              coordinates,
              properties,
              graph,
              nodeMap,
              nodeCounter,
              edgeCounter,
              powerLocations,
              floodData,
            );
            nodeCounter += 100;
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
                powerLocations,
                floodData,
              );
              nodeCounter += 100;
              edgeCounter++;
            }
          }
        } catch (e) {
          continue;
        }
      }

      if (kDebugMode) {
        print('✅ グラフ構築完了: ${graph.getStats()}');
      }
    } catch (e) {
      if (kDebugMode) print('グラフ構築エラー: $e');
    }

    return graph;
  }

  /// 電力設備の位置を抽出
  static List<LatLng> _extractPowerLocations(String powerJson) {
    try {
      final data = jsonDecode(powerJson) as Map<String, dynamic>;
      final features = data['features'] as List<dynamic>?;

      if (features == null) return [];

      final List<LatLng> locations = [];

      for (var feature in features) {
        try {
          final geometry = feature['geometry'] as Map<String, dynamic>?;
          if (geometry == null || geometry['type'] != 'Point') continue;

          final coords = geometry['coordinates'] as List;
          if (coords.length < 2) continue;

          final lng = (coords[0] as num).toDouble();
          final lat = (coords[1] as num).toDouble();

          locations.add(LatLng(lat, lng));
        } catch (e) {
          continue;
        }
      }

      return locations;
    } catch (e) {
      return [];
    }
  }

  /// 浸水データをマップ化（高速検索用）
  static Map<String, double> _buildFloodDataMap(String floodJson) {
    try {
      final List<dynamic> data = jsonDecode(floodJson);
      final Map<String, double> floodMap = {};

      for (var item in data) {
        final lat = item['lat'] as double?;
        final lon = item['lon'] as double?;
        final depth = (item['pred_depth'] as num?)?.toDouble() ?? 0.0;

        if (lat != null && lon != null) {
          final key = '${lat.toStringAsFixed(4)}_${lon.toStringAsFixed(4)}';
          floodMap[key] = depth;
        }
      }

      return floodMap;
    } catch (e) {
      return {};
    }
  }

  /// LineStringを処理してノードとエッジを追加（安全性インデックス付き）
  static void _processLineString(
    dynamic coordinates,
    Map<String, dynamic>? properties,
    RoadGraph graph,
    Map<String, String> nodeMap,
    int nodeCounter,
    int edgeCounter,
    List<LatLng> powerLocations,
    Map<String, double> floodData,
  ) {
    final coordList = coordinates as List;
    if (coordList.length < 2) return;

    final List<LatLng> points = [];
    final List<String> nodeIds = [];

    const distance = Distance();

    // 各座標をノードに変換
    for (var coord in coordList) {
      final c = coord as List;
      if (c.length < 2) continue;

      final lng = (c[0] as num).toDouble();
      final lat = (c[1] as num).toDouble();
      final point = LatLng(lat, lng);
      points.add(point);

      final nodeKey = '${lat.toStringAsFixed(6)}_${lng.toStringAsFixed(6)}';

      String nodeId;
      if (nodeMap.containsKey(nodeKey)) {
        nodeId = nodeMap[nodeKey]!;
      } else {
        nodeId = 'node_${nodeCounter}_${nodeMap.length}';
        nodeMap[nodeKey] = nodeId;

        // === 安全性インデックスの計算 ===
        // 1. 水深を取得
        final floodDepth = _getNearestFloodDepth(point, floodData);

        // 2. 最寄りの電力設備までの距離を計算
        double minPowerDist = double.infinity;
        for (var powerLoc in powerLocations) {
          final dist = distance.as(LengthUnit.Meter, point, powerLoc);
          if (dist < minPowerDist) {
            minPowerDist = dist;
          }
        }

        // 3. 感電リスク判定
        // 条件: 水深 >= 0.5m AND 電力設備 <= 20m
        final isElectricShockRisk =
            floodDepth >= 0.5 && minPowerDist <= 20.0;

        // ノードを追加
        final node = RoadNode(
          id: nodeId,
          position: point,
          floodDepth: floodDepth,
          distanceToPowerInfra: minPowerDist,
          isHighRisk: isElectricShockRisk,
        );

        graph.addNode(node);
      }

      nodeIds.add(nodeId);
    }

    // エッジを作成
    for (int i = 0; i < nodeIds.length - 1; i++) {
      final fromId = nodeIds[i];
      final toId = nodeIds[i + 1];

      final dist = distance.as(LengthUnit.Meter, points[i], points[i + 1]);

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

  /// 最寄りの浸水データから水深を取得
  static double _getNearestFloodDepth(
    LatLng point,
    Map<String, double> floodData,
  ) {
    // 簡易的に、最も近いグリッドセルの値を使用
    final key = '${point.latitude.toStringAsFixed(4)}_${point.longitude.toStringAsFixed(4)}';
    return floodData[key] ?? 0.0;
  }
}

/// compute()に渡すパラメータ
class _GraphBuildParams {
  final String roadsJson;
  final String floodJson;
  final String powerJson;

  _GraphBuildParams({
    required this.roadsJson,
    required this.floodJson,
    required this.powerJson,
  });
}
