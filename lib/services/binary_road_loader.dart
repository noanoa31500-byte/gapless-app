import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

/// 独自バイナリ形式(.bin)の道路データを高速に読み込むローダー
class BinaryRoadLoader {
  /// バイナリファイルを読み込んで、地図描画用の座標リストのリストを返す
  ///
  /// フォーマット仕様:
  /// [Roads Loop]
  ///   - Point Count (2byte UInt16)
  ///   - Type ID (1byte UInt8)
  ///   - [Points Loop]
  ///     - Lat (4byte Float32)
  ///     - Lng (4byte Float32)
  static Future<List<List<LatLng>>> load(String assetPath) async {
    try {
      // 1. ファイルをバイナリとして読み込む
      final ByteData data = await rootBundle.load(assetPath);

      final List<List<LatLng>> roads = [];
      int offset = 0;
      final int length = data.lengthInBytes;

      // 2. バイトストリームをシーケンシャルに解析
      while (offset < length) {
        // 安全策: 残りバイト数がヘッダー分(3byte)未満なら終了
        if (offset + 3 > length) break;

        // 点の数を取得 (2byte)
        final int pointCount = data.getUint16(offset, Endian.big);
        offset += 2;

        // 道路タイプIDを取得 (1byte) - 今は使わないが読み飛ばす
        offset += 1; // typeId

        // 座標データを読み込む
        final List<LatLng> points = [];

        // 安全策: 座標データ分の容量があるか確認 (1点あたり8byte)
        if (offset + (pointCount * 8) > length) {
          debugPrint('BinaryRoadLoader: Unexpected EOF');
          break;
        }

        for (int i = 0; i < pointCount; i++) {
          // GeoJSON/Python側は [lat, lng] や [lng, lat] の順序に注意
          // 今回のPythonスクリプトは struct.pack('>ff', float(lat), float(lng)) で保存している
          // よって、先にLat(4byte), 次にLng(4byte) が来る

          final double lat = data.getFloat32(offset, Endian.big);
          offset += 4;

          final double lng = data.getFloat32(offset, Endian.big);
          offset += 4;

          points.add(LatLng(lat, lng));
        }

        if (points.isNotEmpty) {
          roads.add(points);
        }
      }

      debugPrint(
          'BinaryRoadLoader: Loaded ${roads.length} roads from $assetPath');
      return roads;
    } catch (e) {
      debugPrint('BinaryRoadLoader Error: $e');
      return [];
    }
  }
}
