import 'dart:convert';
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

/// 未対応の GPLB バージョンを検出した場合の例外
class GplbUnsupportedVersionException implements Exception {
  final int version;
  final int maxSupported;
  GplbUnsupportedVersionException(this.version, this.maxSupported);
  @override
  String toString() =>
      'GplbUnsupportedVersionException(version=$version, max=$maxSupported)';
}

/// v2 以降のファイルで CRC32 footer が一致しない場合の例外。
/// 通信途中での破損または改ざんを検出します。
class GplbCrcMismatchException implements Exception {
  final int expected;
  final int actual;
  GplbCrcMismatchException(this.expected, this.actual);
  @override
  String toString() =>
      'GplbCrcMismatchException(expected=0x${expected.toRadixString(16)}, '
      'actual=0x${actual.toRadixString(16)})';
}

/// gplbバイナリファイルのパーサー
class GplbParser {
  static const _magic = [0x47, 0x50, 0x4C, 0x42]; // "GPLB"
  static const _sectionRoads = 0x01;
  static const _sectionPois = 0x02;

  /// 当パーサが解釈できる最大スキーマバージョン。
  /// これより大きい version のファイルは安全に reject し、再ダウンロードを促す。
  ///
  /// v1: CRC なし（既存ファイル）
  /// v2: 末尾 4 バイトに CRC32 (IEEE 802.3, big-endian) を付与。検証で改ざん/転送破損を検出。
  static const int kMaxSupportedVersion = 2;

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
    if (version > kMaxSupportedVersion) {
      throw GplbUnsupportedVersionException(version, kMaxSupportedVersion);
    }

    // v2+: 末尾 4 バイトの CRC32 を検証してから本体パース。
    // 不一致 → 通信破損 or 改ざんとして拒否。
    Uint8List bodyBytes = bytes;
    if (version >= 2) {
      if (bytes.length < 10) {
        throw const FormatException('GPLB v2: too short to contain CRC footer');
      }
      final expectedCrc = (bytes[bytes.length - 4] << 24) |
          (bytes[bytes.length - 3] << 16) |
          (bytes[bytes.length - 2] << 8) |
          bytes[bytes.length - 1];
      bodyBytes = Uint8List.sublistView(bytes, 0, bytes.length - 4);
      final actualCrc = _crc32(bodyBytes);
      if (actualCrc != expectedCrc) {
        throw GplbCrcMismatchException(expectedCrc, actualCrc);
      }
    }
    // 以降は CRC を除いた範囲をパースする (sectionCount 取得済みオフセットを再計算)。
    final body = _ByteReader(bodyBytes)
      ..skip(5); // magic(4) + version(1) は既に検証済み
    final sectionCount = body.readUint8();
    return _parseSections(body, sectionCount, version);
  }

  static GplbData _parseSections(_ByteReader body, int sectionCount,
      int version) {

    final roads = <RoadFeature>[];
    final pois = <PoiFeature>[];

    for (int s = 0; s < sectionCount; s++) {
      if (body.isEof) break;

      final sectionType = body.readUint8();
      final recordCount = body.readUint32();

      switch (sectionType) {
        case _sectionRoads:
          roads.addAll(_parseRoads(body, recordCount));
        case _sectionPois:
          pois.addAll(_parsePois(body, recordCount));
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

  @visibleForTesting
  static int debugCrc32(Uint8List bytes) => _crc32(bytes);

  // CRC32 IEEE 802.3 (reversed polynomial 0xEDB88320) — matches zlib/PNG.
  static int _crc32(Uint8List bytes) {
    var crc = 0xFFFFFFFF;
    for (final b in bytes) {
      var x = (crc ^ b) & 0xFF;
      for (int i = 0; i < 8; i++) {
        x = (x & 1) != 0 ? (0xEDB88320 ^ (x >> 1)) : (x >> 1);
      }
      crc = ((crc >> 8) ^ x) & 0xFFFFFFFF;
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

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

  void skip(int n) {
    _check(n);
    _offset += n;
  }

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
    final bytes = Uint8List.view(_data.buffer, _offset + _data.offsetInBytes, length);
    _offset += length;
    return utf8.decode(bytes, allowMalformed: true);
  }

  void _check(int needed) {
    if (_offset + needed > _data.lengthInBytes) {
      throw RangeError(
          'GplbParser: Unexpected EOF at offset $_offset '
          '(needed $needed, remaining $remaining)');
    }
  }
}
