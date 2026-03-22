import 'package:latlong2/latlong.dart';

/// 道路グラフのエッジ（道路セグメント）
/// 
/// 防災エンジニアとしての視点:
/// エッジは「移動経路」そのものです。ここで適切な重み付けを行うことで、
/// 「最も安全に避難できる経路」を計算できます。
class RoadEdge {
  /// エッジの一意識別子
  final String id;
  
  /// 始点ノードID
  final String fromNodeId;
  
  /// 終点ノードID
  final String toNodeId;
  
  /// 道路の実距離（メートル）
  final double distance;
  
  /// OSM道路タイプ（highway=primary, residential等）
  final String? highwayType;
  
  /// 道路名
  final String? name;
  
  /// 幅員（メートル、利用可能な場合）
  final double? width;
  
  /// 経路座標のリスト（詳細な形状）
  final List<LatLng> geometry;
  
  /// 道路の中心点（リスク計算用）
  late final LatLng centerPoint;
  
  /// 追加プロパティ（OSMタグなど）
  final Map<String, dynamic>? properties;

  RoadEdge({
    required this.id,
    required this.fromNodeId,
    required this.toNodeId,
    required this.distance,
    required this.geometry,
    this.highwayType,
    this.name,
    this.width,
    this.properties,
  }) {
    // 中心点を計算
    if (geometry.isNotEmpty) {
      final midIndex = geometry.length ~/ 2;
      centerPoint = geometry[midIndex];
    } else {
      // フォールバック: ゼロ座標
      centerPoint = LatLng(0, 0);
    }
  }

  /// エッジをJSON形式に変換
  Map<String, dynamic> toJson() => {
    'id': id,
    'fromNodeId': fromNodeId,
    'toNodeId': toNodeId,
    'distance': distance,
    'highwayType': highwayType,
    'name': name,
    'width': width,
    'geometry': geometry.map((p) => {'lat': p.latitude, 'lng': p.longitude}).toList(),
    'properties': properties,
  };

  /// JSONからエッジを作成
  factory RoadEdge.fromJson(Map<String, dynamic> json) => RoadEdge(
    id: json['id'] as String,
    fromNodeId: json['fromNodeId'] as String,
    toNodeId: json['toNodeId'] as String,
    distance: (json['distance'] as num).toDouble(),
    geometry: (json['geometry'] as List)
        .map((p) => LatLng(
              (p['lat'] as num).toDouble(),
              (p['lng'] as num).toDouble(),
            ))
        .toList(),
    highwayType: json['highwayType'] as String?,
    name: json['name'] as String?,
    width: json['width'] != null ? (json['width'] as num).toDouble() : null,
    properties: json['properties'] as Map<String, dynamic>?,
  );
}
