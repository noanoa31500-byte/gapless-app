import 'dart:typed_data';
import 'package:latlong2/latlong.dart';

/// GPLH v3 バイナリパーサー
///
/// フォーマット (scripts/compress.py と一致):
///   マジック:     'GPLH' (4)
///   バージョン:   uint8 (=3)
///   ポリゴン数:   uint32 LE
///   各ポリゴン:
///     hazType:    uint8 (1=洪水)
///     riskLevel:  uint8 (1=high, 2=med, 3=low)
///     pointCount: uint16 LE
///     先頭lat:    int32 LE (×1e6)
///     先頭lng:    int32 LE (×1e6)
///     以降:       int16 LE dlat, int16 LE dlng × (pointCount-1)
class HazardPolygon {
  final int hazType;
  final int riskLevel;
  final List<LatLng> points;
  const HazardPolygon({
    required this.hazType,
    required this.riskLevel,
    required this.points,
  });
}

class HazardParser {
  /// バイナリ → ポリゴンリスト
  static List<HazardPolygon> parse(Uint8List bytes) {
    if (bytes.length < 9) {
      throw const FormatException('GPLH data too short');
    }
    if (bytes[0] != 0x47 ||
        bytes[1] != 0x50 ||
        bytes[2] != 0x4C ||
        bytes[3] != 0x48) {
      throw const FormatException('GPLH magic mismatch');
    }
    final bd = ByteData.sublistView(bytes);
    final version = bytes[4];
    if (version != 3) {
      throw FormatException('Unsupported GPLH version: $version');
    }
    final polygonCount = bd.getUint32(5, Endian.little);
    int off = 9;
    final out = <HazardPolygon>[];

    for (int i = 0; i < polygonCount; i++) {
      if (off + 12 > bytes.length) break;
      final hazType = bytes[off];
      final riskLevel = bytes[off + 1];
      final pointCount = bd.getUint16(off + 2, Endian.little);
      int firstLat = bd.getInt32(off + 4, Endian.little);
      int firstLng = bd.getInt32(off + 8, Endian.little);
      off += 12;

      final pts = <LatLng>[LatLng(firstLat / 1e6, firstLng / 1e6)];
      int curLat = firstLat;
      int curLng = firstLng;

      final deltasBytes = (pointCount - 1) * 4;
      if (off + deltasBytes > bytes.length) break;
      for (int k = 0; k < pointCount - 1; k++) {
        final dlat = bd.getInt16(off, Endian.little);
        final dlng = bd.getInt16(off + 2, Endian.little);
        off += 4;
        curLat += dlat;
        curLng += dlng;
        pts.add(LatLng(curLat / 1e6, curLng / 1e6));
      }
      out.add(HazardPolygon(
        hazType: hazType,
        riskLevel: riskLevel,
        points: pts,
      ));
    }
    return out;
  }
}
