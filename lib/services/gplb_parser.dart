import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/road_feature.dart';
import '../models/poi_feature.dart';

// ============================================================================
// GplbParser  — GapLess Path Library Binary (.gplb) パーサー
// ============================================================================
//
// 【フォーマット仕様】
//
// ┌─────────────────────────────────────────────────────────────────────┐
// │ FILE HEADER                                                          │
// │  Magic      : 4 bytes  "GPLB"  (0x47 0x50 0x4C 0x42)               │
// │  Version    : 1 byte   UInt8  (現在: 0x01)                          │
// │  SectionCnt : 1 byte   UInt8  (セクション数)                         │
// ├─────────────────────────────────────────────────────────────────────┤
// │ SECTION HEADER (セクションごとに繰り返し)                              │
// │  SectionType: 1 byte   UInt8                                        │
// │               0x01 = Roads, 0x02 = POIs                             │
// │  RecordCnt  : 4 bytes  UInt32 BigEndian                             │
// ├─────────────────────────────────────────────────────────────────────┤
// │ ROAD RECORD (SectionType=0x01 の場合)                                │
// │  TypeId     : 1 byte   UInt8  (RoadType enum id)                   │
// │  Flags      : 1 byte   UInt8  (bit0=isOneWay)                       │
// │  NameLen    : 1 byte   UInt8  (0 = 名前なし)                         │
// │  Name       : NameLen bytes  UTF-8                                  │
// │  PointCnt   : 2 bytes  UInt16 BigEndian                             │
// │  [PointCnt 回繰り返し]                                               │
// │    Lat      : 4 bytes  Float32 BigEndian                            │
// │    Lng      : 4 bytes  Float32 BigEndian                            │
// ├─────────────────────────────────────────────────────────────────────┤
// │ POI RECORD (SectionType=0x02 の場合)                                 │
// │  TypeId     : 1 byte   UInt8  (PoiType enum id)                    │
// │  NameLen    : 1 byte   UInt8                                        │
// │  Name       : NameLen bytes  UTF-8                                  │
// │  AddrLen    : 1 byte   UInt8  (0 = 住所なし)                         │
// │  Address    : AddrLen bytes  UTF-8                                  │
// │  Capacity   : 2 bytes  UInt16 BigEndian (0 = 不明)                   │
// │  Lat        : 4 bytes  Float32 BigEndian                            │
// │  Lng        : 4 bytes  Float32 BigEndian                            │
// └─────────────────────────────────────────────────────────────────────┘
//
// ============================================================================

/// パース結果コンテナ
class GplbData {
  final List<RoadFeature> roads;
  final List<PoiFeature> pois;
  final int version;

  const GplbData({
    required this.roads,
    required this.pois,
    required this.version,
  });

  bool get isEmpty => roads.isEmpty && pois.isEmpty;

  @override
  String toString() =>
      'GplbData(v$version, roads=${roads.length}, pois=${pois.length})';
}

/// gplbバイナリファイルのパーサー
class GplbParser {
  static const _magic = [0x47, 0x50, 0x4C, 0x42]; // "GPLB"
  static const _sectionRoads = 0x01;
  static const _sectionPois = 0x02;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// バイト列を解析して GplbData を返す
  ///
  /// Isolate で呼び出しても安全なよう、すべてのログを debugPrint に限定します。
  static GplbData parse(Uint8List bytes) {
    final reader = _ByteReader(bytes);

    // マジックバイト検証
    _checkMagic(reader);

    final version = reader.readUint8();
    final sectionCount = reader.readUint8();

    final roads = <RoadFeature>[];
    final pois = <PoiFeature>[];

    for (int s = 0; s < sectionCount; s++) {
      if (reader.isEof) break;

      final sectionType = reader.readUint8();
      final recordCount = reader.readUint32();

      switch (sectionType) {
        case _sectionRoads:
          roads.addAll(_parseRoads(reader, recordCount));
        case _sectionPois:
          pois.addAll(_parsePois(reader, recordCount));
        default:
          // 未知セクション: スキップできないためパース失敗として扱う
          debugPrint(
              'GplbParser: Unknown section type 0x${sectionType.toRadixString(16)} — skipping remaining data');
          s = sectionCount; // ループを終了
      }
    }

    final result = GplbData(version: version, roads: roads, pois: pois);
    debugPrint('GplbParser: $result');
    return result;
  }

  /// Isolate 経由でパースする（UI スレッドをブロックしない）
  static Future<GplbData> parseAsync(Uint8List bytes) {
    return compute(_parseInIsolate, bytes);
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  static GplbData _parseInIsolate(Uint8List bytes) => parse(bytes);

  static void _checkMagic(_ByteReader r) {
    for (int i = 0; i < _magic.length; i++) {
      final b = r.readUint8();
      if (b != _magic[i]) {
        throw FormatException(
            'GplbParser: Invalid magic byte at $i: '
            'expected 0x${_magic[i].toRadixString(16)}, got 0x${b.toRadixString(16)}');
      }
    }
  }

  static List<RoadFeature> _parseRoads(_ByteReader r, int count) {
    final roads = <RoadFeature>[];

    for (int i = 0; i < count; i++) {
      if (r.isEof) break;

      final typeId = r.readUint8();
      final flags = r.readUint8();
      final isOneWay = (flags & 0x01) != 0;

      final nameLen = r.readUint8();
      final name = nameLen > 0 ? r.readUtf8(nameLen) : null;

      final pointCount = r.readUint16();
      if (pointCount == 0) continue;

      final geometry = <LatLng>[];
      for (int p = 0; p < pointCount; p++) {
        final lat = r.readFloat32();
        final lng = r.readFloat32();
        geometry.add(LatLng(lat, lng));
      }

      roads.add(RoadFeature(
        type: RoadType.fromId(typeId),
        name: name,
        geometry: geometry,
        isOneWay: isOneWay,
      ));
    }

    return roads;
  }

  static List<PoiFeature> _parsePois(_ByteReader r, int count) {
    final pois = <PoiFeature>[];

    for (int i = 0; i < count; i++) {
      if (r.isEof) break;

      final typeId = r.readUint8();

      final nameLen = r.readUint8();
      final name = nameLen > 0 ? r.readUtf8(nameLen) : '（名称不明）';

      final addrLen = r.readUint8();
      if (addrLen > 0) r.readUtf8(addrLen); // read and discard address bytes

      final capacity = r.readUint16(); // 0 = 不明
      final lat = r.readFloat32();
      final lng = r.readFloat32();

      pois.add(PoiFeature(
        type: PoiType.fromId(typeId),
        lat: lat,
        lng: lng,
        capacity: capacity,
        flags: 0,
        name: name,
      ));
    }

    return pois;
  }
}

// ============================================================================
// _ByteReader — オフセット管理を隠蔽した内部ユーティリティ
// ============================================================================
class _ByteReader {
  final ByteData _data;
  int _offset = 0;

  _ByteReader(Uint8List bytes) : _data = bytes.buffer.asByteData();

  bool get isEof => _offset >= _data.lengthInBytes;

  int get remaining => _data.lengthInBytes - _offset;

  int readUint8() {
    _check(1);
    return _data.getUint8(_offset++);
  }

  int readUint16() {
    _check(2);
    final v = _data.getUint16(_offset, Endian.big);
    _offset += 2;
    return v;
  }

  int readUint32() {
    _check(4);
    final v = _data.getUint32(_offset, Endian.big);
    _offset += 4;
    return v;
  }

  double readFloat32() {
    _check(4);
    final v = _data.getFloat32(_offset, Endian.big);
    _offset += 4;
    return v;
  }

  String readUtf8(int length) {
    _check(length);
    final bytes = Uint8List.view(_data.buffer, _offset, length);
    _offset += length;
    return String.fromCharCodes(bytes);
  }

  void _check(int needed) {
    if (_offset + needed > _data.lengthInBytes) {
      throw RangeError(
          'GplbParser: Unexpected EOF at offset $_offset '
          '(needed $needed, remaining $remaining)');
    }
  }
}
