import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// GeoJSONファイルを効率的に読み込むためのサービスクラス
/// 
/// 大きなGeoJSONファイル（10MB以上）を別スレッドでパースすることで、
/// UIのフリーズを防ぎます。
class GeoJsonLoader {
  /// 日本の道路データを読み込む
  /// 
  /// ⚠️ 非推奨: 道路データはBinaryRoadLoaderを使用してください
  /// バイナリファイル: assets/data/roads_jp.bin
  @Deprecated('Use BinaryRoadLoader.load() or BinaryGraphLoader.loadGraph() instead')
  Future<Map<String, dynamic>> loadRoadDataJapan() async {
    throw UnsupportedError(
      '道路データはバイナリ形式に移行しました。'
      'BinaryRoadLoader.load("assets/data/roads_jp.bin") を使用してください。'
    );
  }

  /// タイの道路データを読み込む
  /// 
  /// ⚠️ 非推奨: 道路データはBinaryRoadLoaderを使用してください
  /// バイナリファイル: assets/data/roads_th.bin
  @Deprecated('Use BinaryRoadLoader.load() or BinaryGraphLoader.loadGraph() instead')
  Future<Map<String, dynamic>> loadRoadDataThailand() async {
    throw UnsupportedError(
      '道路データはバイナリ形式に移行しました。'
      'BinaryRoadLoader.load("assets/data/roads_th.bin") を使用してください。'
    );
  }

  /// タイの病院データを読み込む
  Future<Map<String, dynamic>> loadHospitalDataThailand() async {
    return await _loadGeoJson('assets/data/hospital_th.geojson');
  }

  /// タイの店舗データを読み込む
  Future<Map<String, dynamic>> loadStoreDataThailand() async {
    return await _loadGeoJson('assets/data/store_th.geojson');
  }

  /// タイのシェルターデータを読み込む
  Future<Map<String, dynamic>> loadShelterDataThailand() async {
    return await _loadGeoJson('assets/data/shelter_th.geojson');
  }

  /// 指定されたパスのGeoJSONファイルを読み込む（汎用メソッド）
  /// 
  /// [path] - assetsフォルダからの相対パス
  /// 
  /// 使用例:
  /// ```dart
  /// final loader = GeoJsonLoader();
  /// final data = await loader.loadGeoJson('assets/data/custom.geojson');
  /// ```
  Future<Map<String, dynamic>> loadGeoJson(String path) async {
    return await _loadGeoJson(path);
  }

  /// 道路データを読み込んでPolylineデータに変換（最適化版）
  /// 
  /// GeoJSONの読み込みとPolylineデータへの変換を全てバックグラウンドで実行します。
  /// 返り値: List<List<Map<String, double>>> - 各PolylineのLatLng座標リスト
  /// 
  /// 使用例:
  /// ```dart
  /// final polylineData = await loader.loadAndBuildRoadData('assets/data/roads_th.geojson');
  /// // polylineData[i] = [{'lat': 14.0, 'lng': 100.0}, {'lat': 14.1, 'lng': 100.1}, ...]
  /// ```
  Future<List<Map<String, dynamic>>> loadAndBuildRoadPolylines(String path) async {
    try {
      // 1. ファイルを文字列として読み込む
      final String jsonString = await rootBundle.loadString(path);

      // 2. 別スレッドでJSON解析とPolylineデータ抽出を実行
      return await compute(_parseAndBuildPolylines, jsonString);
    } catch (e) {
      debugPrint('❌ 道路データ変換エラー [$path]: $e');
      return [];
    }
  }

  /// 内部用：GeoJSONファイルを読み込んでパースする
  /// 
  /// 1. ファイルを文字列として読み込む
  /// 2. 別スレッド（Isolate）でパース（10MBあるので、computeを使わないと画面が固まります）
  Future<Map<String, dynamic>> _loadGeoJson(String path) async {
    try {
      // 1. ファイルを文字列として読み込む
      final String jsonString = await rootBundle.loadString(path);

      // 2. 別スレッドでパース（10MBあるので、computeを使わないと画面が固まります）
      return await compute(_parseJson, jsonString);
    } catch (e) {
      // エラーハンドリング：ファイルが見つからない、または破損している場合
      debugPrint('❌ GeoJSON読み込みエラー [$path]: $e');
      rethrow; // 呼び出し元でエラーハンドリングできるように再スロー
    }
  }

  /// 静的メソッド：computeで使用するためのJSON解析関数
  /// 
  /// この関数は別スレッド（Isolate）で実行されるため、
  /// トップレベル関数または静的メソッドである必要があります。
  static Map<String, dynamic> _parseJson(String text) {
    return jsonDecode(text) as Map<String, dynamic>;
  }

  /// 静的メソッド：GeoJSONを解析してPolylineデータに変換（Isolateで実行）
  /// 
  /// この関数はcomputeで別スレッド実行されるため、静的メソッドである必要があります。
  /// 返り値: LatLng座標のリストのリスト（各要素がPolyline用のデータ）
  static List<Map<String, dynamic>> _parseAndBuildPolylines(String jsonString) {
    try {
      // 1. JSON解析
      final Map<String, dynamic> geoJson = jsonDecode(jsonString) as Map<String, dynamic>;
      final features = geoJson['features'] as List<dynamic>?;
      
      if (features == null) return [];

      List<Map<String, dynamic>> polylines = [];

      // 2. 各featureを処理
      for (var feature in features) {
        try {
          final geometry = feature['geometry'] as Map<String, dynamic>?;
          if (geometry == null) continue;

          final geoType = geometry['type'] as String?;
          final coordinates = geometry['coordinates'];

          if (coordinates == null || geoType == null) continue;

          // 3. Geometryタイプごとに処理
          if (geoType == 'LineString') {
            final points = _extractLineString(coordinates);
            if (points.isNotEmpty) {
              polylines.add({
                'points': points,
                'type': 'road',
                'strokeWidth': 2.5,
              });
            }
          } else if (geoType == 'MultiLineString') {
            final lines = coordinates as List;
            for (var line in lines) {
              final points = _extractLineString(line);
              if (points.isNotEmpty) {
                polylines.add({
                  'points': points,
                  'type': 'road',
                  'strokeWidth': 2.5,
                });
              }
            }
          } else if (geoType == 'Polygon') {
            final rings = coordinates as List;
            if (rings.isNotEmpty) {
              final points = _extractLineString(rings[0]);
              if (points.isNotEmpty) {
                polylines.add({
                  'points': points,
                  'type': 'building',
                  'strokeWidth': 2.0,
                });
              }
            }
          } else if (geoType == 'MultiPolygon') {
            final polygons = coordinates as List;
            for (var polygon in polygons) {
              final rings = polygon as List;
              if (rings.isNotEmpty) {
                final points = _extractLineString(rings[0]);
                if (points.isNotEmpty) {
                  polylines.add({
                    'points': points,
                    'type': 'building',
                    'strokeWidth': 2.0,
                  });
                }
              }
            }
          }
        } catch (e) {
          // エラーがあっても続行
          continue;
        }
      }

      return polylines;
    } catch (e) {
      return [];
    }
  }

  /// GeoJSON座標配列をLatLng座標マップのリストに変換（Isolate内で使用）
  static List<Map<String, double>> _extractLineString(dynamic coords) {
    try {
      final coordList = coords as List;
      return coordList.map<Map<String, double>?>((point) {
        final p = point as List;
        if (p.length >= 2) {
          return {
            'lat': (p[1] as num).toDouble(),
            'lng': (p[0] as num).toDouble(),
          };
        }
        return null;
      }).whereType<Map<String, double>>().toList();
    } catch (e) {
      return [];
    }
  }
}
