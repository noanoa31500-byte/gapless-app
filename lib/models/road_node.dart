import 'package:latlong2/latlong.dart';

/// 道路グラフのノード（交差点）
/// 
/// 防災エンジニアとしての視点:
/// 各ノードは避難経路の「意思決定ポイント」を表します。
/// ここで「どの道を選ぶか」が生死を分けることがあります。
class RoadNode {
  /// ノードの一意識別子（通常はOSMのnode_id）
  final String id;
  
  /// ノードの位置座標
  final LatLng position;
  
  /// このノードから伸びるエッジのリスト
  final List<String> edgeIds;
  
  /// リスクフラグ（事前計算用）
  /// 日本モード: 狭い路地エリアか
  /// タイモード: 冠水エリアか、電力設備近くか
  bool isHighRisk;
  
  /// 水深データ（タイモードのみ）
  double? floodDepth;
  
  /// 電力設備までの最短距離（タイモードのみ、事前計算）
  double? distanceToPowerInfra;

  RoadNode({
    required this.id,
    required this.position,
    List<String>? edgeIds,
    this.isHighRisk = false,
    this.floodDepth,
    this.distanceToPowerInfra,
  }) : edgeIds = edgeIds ?? [];

  /// ノードをJSON形式に変換
  Map<String, dynamic> toJson() => {
    'id': id,
    'lat': position.latitude,
    'lng': position.longitude,
    'edgeIds': edgeIds,
    'isHighRisk': isHighRisk,
    'floodDepth': floodDepth,
    'distanceToPowerInfra': distanceToPowerInfra,
  };

  /// JSONからノードを作成
  factory RoadNode.fromJson(Map<String, dynamic> json) => RoadNode(
    id: json['id'] as String,
    position: LatLng(
      json['lat'] as double,
      json['lng'] as double,
    ),
    edgeIds: (json['edgeIds'] as List?)?.cast<String>(),
    isHighRisk: json['isHighRisk'] as bool? ?? false,
    floodDepth: json['floodDepth'] as double?,
    distanceToPowerInfra: json['distanceToPowerInfra'] as double?,
  );
}
