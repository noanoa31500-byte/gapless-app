import 'package:latlong2/latlong.dart';

/// 道路フィーチャー
///
/// gplbファイルから読み込んだ道路セグメントを表します。
/// 地図描画・経路探索の両方で使用します。
class RoadFeature {
  /// 道路タイプ（OSMのhighway値に対応）
  final RoadType type;

  /// 道路名（任意）
  final String? name;

  /// ポリライン座標列
  final List<LatLng> geometry;

  /// 幅員メートル（任意）
  final double? widthMeters;

  /// 一方通行フラグ
  final bool isOneWay;

  const RoadFeature({
    required this.type,
    required this.geometry,
    this.name,
    this.widthMeters,
    this.isOneWay = false,
  });

  /// 道路セグメントの中点を返す（マーカー表示用）
  LatLng get midpoint {
    if (geometry.isEmpty) return const LatLng(0, 0);
    final mid = geometry[geometry.length ~/ 2];
    return mid;
  }

  @override
  String toString() =>
      'RoadFeature(type: $type, points: ${geometry.length}, name: $name)';
}

/// 道路タイプ（gplbバイナリの type_id に対応）
///
/// 0x01 primary      主要幹線道路
/// 0x02 secondary    補助幹線道路
/// 0x03 residential  生活道路
/// 0x04 path         歩道・小道
/// 0x05 motorway     高速道路
/// 0xFF unknown      不明
enum RoadType {
  primary(0x01, '主要幹線'),
  secondary(0x02, '補助幹線'),
  residential(0x03, '生活道路'),
  path(0x04, '歩道'),
  motorway(0x05, '高速道路'),
  unknown(0xFF, '不明');

  const RoadType(this.id, this.label);

  /// バイト値
  final int id;

  /// 表示ラベル
  final String label;

  /// バイト値からRoadTypeへ変換
  static RoadType fromId(int id) {
    for (final t in values) {
      if (t.id == id) return t;
    }
    return unknown;
  }
}
