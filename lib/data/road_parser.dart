// ============================================================
// road_parser.dart
// バイナリ gplb 道路データのパーサー（version 1 / version 3）
// と交差点隣接グラフのビルダー
// ============================================================

import 'dart:typed_data';
import 'package:latlong2/latlong.dart';
import '../models/road_feature.dart';

// ────────────────────────────────────────
// 道路セグメント（グラフのエッジ）
// ────────────────────────────────────────
class RoadSegment {
  final List<LatLng> points;
  final RoadType type;
  final double? widthMeters;

  const RoadSegment({
    required this.points,
    required this.type,
    this.widthMeters,
  });

  LatLng get start => points.isNotEmpty ? points.first : const LatLng(0, 0);
  LatLng get end => points.isNotEmpty ? points.last : const LatLng(0, 0);

  double get lengthMeters {
    double total = 0;
    const dist = Distance();
    for (int i = 0; i < points.length - 1; i++) {
      total += dist(points[i], points[i + 1]);
    }
    return total;
  }
}

// ────────────────────────────────────────
// グラフキー: "lat,lng" (小数点6桁)
// ────────────────────────────────────────
String _nodeKey(LatLng p) =>
    '${p.latitude.toStringAsFixed(6)},${p.longitude.toStringAsFixed(6)}';

// ────────────────────────────────────────
// 隣接グラフ
// ────────────────────────────────────────
class RoadGraph {
  /// ノード(交差点) → 隣接セグメント一覧
  final Map<String, List<RoadSegment>> adjacency;

  const RoadGraph(this.adjacency);

  /// RoadFeature リストからグラフを構築する
  static RoadGraph build(List<RoadFeature> features) {
    final adj = <String, List<RoadSegment>>{};

    void add(String key, RoadSegment seg) {
      adj.putIfAbsent(key, () => []).add(seg);
    }

    for (final f in features) {
      if (f.geometry.length < 2) continue;
      final seg = RoadSegment(
        points: f.geometry,
        type: f.type,
        widthMeters: f.widthMeters,
      );
      final startKey = _nodeKey(f.geometry.first);
      final endKey = _nodeKey(f.geometry.last);
      add(startKey, seg);
      if (!f.isOneWay) {
        // 双方向: 逆向きセグメントも追加
        final reversed = RoadSegment(
          points: f.geometry.reversed.toList(),
          type: f.type,
          widthMeters: f.widthMeters,
        );
        add(endKey, reversed);
      }
    }

    return RoadGraph(adj);
  }

  List<RoadSegment> neighborsOf(LatLng node) =>
      adjacency[_nodeKey(node)] ?? const [];
}

// ────────────────────────────────────────
// バイナリパーサー
// ────────────────────────────────────────

// GPLB マジックバイト: 'G','P','L','B' (0x47 0x50 0x4C 0x42)
const _kMagic = [0x47, 0x50, 0x4C, 0x42];

class RoadParser {
  /// バイト列から RoadFeature リストを返す
  /// version 1: 各頂点を Int32LE (lat*1e6, lng*1e6) で格納
  /// version 3: 先頭頂点のみ Int32LE、以降は Int16LE デルタ
  static List<RoadFeature> parse(Uint8List bytes) {
    final buf = ByteData.sublistView(bytes);
    int offset = 0;

    // 最小長チェック（magic 4 + version 1 = 5 bytes）
    if (bytes.length < 5) {
      throw FormatException('GPLB data too short');
    }

    // マジックチェック
    for (int i = 0; i < 4; i++) {
      if (bytes[offset + i] != _kMagic[i]) {
        throw FormatException('GPLB magic mismatch');
      }
    }
    offset += 4;

    final version = buf.getUint8(offset);
    offset += 1;

    if (version == 1) {
      return _parseV1(buf, offset, bytes.length);
    } else if (version == 3) {
      return _parseV3(buf, offset, bytes.length);
    } else {
      throw FormatException('Unsupported GPLB road version: $version');
    }
  }

  // ──── version 1: フル Int32 座標 ────────────────────────────────────────

  static List<RoadFeature> _parseV1(ByteData buf, int offset, int end) {
    final features = <RoadFeature>[];

    while (offset + 6 <= end) {
      final typeId = buf.getUint8(offset);
      offset += 1;
      final flags = buf.getUint8(offset);
      offset += 1;
      final pointCount = buf.getUint16(offset, Endian.little);
      offset += 2;

      if (pointCount == 0) continue;
      final needed = pointCount * 8; // each point: lat Int32 + lng Int32
      if (offset + needed > end) break;

      final geometry = <LatLng>[];
      for (int i = 0; i < pointCount; i++) {
        final latE6 = buf.getInt32(offset, Endian.little);
        offset += 4;
        final lngE6 = buf.getInt32(offset, Endian.little);
        offset += 4;
        geometry.add(LatLng(latE6 / 1e6, lngE6 / 1e6));
      }

      features.add(RoadFeature(
        type: RoadType.fromId(typeId),
        geometry: geometry,
        isOneWay: (flags & 0x01) != 0,
      ));
    }

    return features;
  }

  // ──── version 3: デルタ Int16 座標 ──────────────────────────────────────

  static List<RoadFeature> _parseV3(ByteData buf, int offset, int end) {
    final features = <RoadFeature>[];

    while (offset + 6 <= end) {
      final typeId = buf.getUint8(offset);
      offset += 1;
      final flags = buf.getUint8(offset);
      offset += 1;
      final pointCount = buf.getUint16(offset, Endian.little);
      offset += 2;

      if (pointCount == 0) continue;
      // first point: 2 x Int32 = 8 bytes; subsequent: 2 x Int16 = 4 bytes each
      final needed = 8 + (pointCount - 1) * 4;
      if (offset + needed > end) break;

      // 先頭頂点（フル座標）
      final lat0 = buf.getInt32(offset, Endian.little);
      offset += 4;
      final lng0 = buf.getInt32(offset, Endian.little);
      offset += 4;

      final geometry = <LatLng>[LatLng(lat0 / 1e6, lng0 / 1e6)];
      int curLat = lat0;
      int curLng = lng0;

      for (int i = 1; i < pointCount; i++) {
        final dLat = buf.getInt16(offset, Endian.little);
        offset += 2;
        final dLng = buf.getInt16(offset, Endian.little);
        offset += 2;
        curLat += dLat;
        curLng += dLng;
        geometry.add(LatLng(curLat / 1e6, curLng / 1e6));
      }

      features.add(RoadFeature(
        type: RoadType.fromId(typeId),
        geometry: geometry,
        isOneWay: (flags & 0x01) != 0,
      ));
    }

    return features;
  }
}
