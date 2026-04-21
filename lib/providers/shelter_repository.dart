import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import '../models/shelter.dart';
import '../models/road_feature.dart';
import '../data/poi_catalog.dart';
import '../data/map_repository.dart';
import '../data/road_parser.dart';
import '../data/hazard_parser.dart';

/// ============================================================================
/// ShelterRepository — 避難所/POI/道路/ハザードのデータアクセス層
/// ============================================================================
/// 旧 ShelterProvider から「データ読み込み」関連を切り出した責務分離クラス。
///
/// このクラスは ChangeNotifier ではない。状態通知が必要な側
/// (ShelterProvider ファサード) が結果を受けて notifyListeners() を呼ぶ。
class ShelterRepository {
  // 民間施設などを除外するためのブラックリスト
  static const List<String> blackListKeywords = [
    'そろばん', '珠算', '塾',
    '英会話', '公文', 'スイミング', 'ピアノ', 'バレエ', 'ダンス',
    '自動車', 'driving', 'kumon', 'ballet', 'dance', 'piano', 'swimming',
  ];

  /// region → アセットファイル名プレフィックス
  static String _assetPrefix(String region) => 'current';

  /// 指定地域の POI gplb を読み込み Shelter リストとして返す
  Future<List<Shelter>> loadPoiForRegion(String region) async {
    final fileName = '${_assetPrefix(region)}_poi.gplb';
    try {
      final bytes = await MapRepository.instance.readBytes(fileName);
      final grouped = GplbPoiParser.parseAndGroup(bytes);
      final shelters = grouped[PoiCategory.shelter] ?? [];
      final hospitals = grouped[PoiCategory.hospital] ?? [];
      final convStores = grouped[PoiCategory.convenience] ?? [];
      final supplies = grouped[PoiCategory.supply] ?? [];
      final landmarks = grouped[PoiCategory.landmark] ?? [];

      final out = <Shelter>[];
      for (final feature in [
        ...shelters,
        ...hospitals,
        ...convStores,
        ...supplies,
        ...landmarks,
      ]) {
        final String type;
        if (feature.isShelter) {
          type = 'shelter';
        } else if (feature.isHospital) {
          type = 'hospital';
        } else if (feature.isConvenience) {
          type = 'convenience';
        } else if (feature.isSupply) {
          type = 'water';
        } else {
          type = 'landmark';
        }

        final idPrefix = 'gplb_${_assetPrefix(region)}_';
        out.add(Shelter(
          id: '$idPrefix${feature.type.id}_${feature.lat.toStringAsFixed(5)}_${feature.lng.toStringAsFixed(5)}',
          name: feature.name,
          lat: feature.lat,
          lng: feature.lng,
          type: type,
          verified: true,
          region: region,
          isFloodShelter: feature.handlesFlood,
        ));
      }
      if (kDebugMode) {
        debugPrint(
            '📦 ShelterRepository: loaded ${out.length} POIs from $fileName');
      }
      return out;
    } catch (e) {
      debugPrint('❌ ShelterRepository POI load error ($fileName): $e');
      return [];
    }
  }

  /// ブランド/ノイズ名を除去するフィルタ
  List<Shelter> filterNoise(List<Shelter> input) {
    return input.where((s) {
      final name = s.name;
      if (name.isEmpty ||
          name.toLowerCase() == 'unknown' ||
          name == 'Unknown Spot' ||
          name == 'Unnamed' ||
          name == '不明' ||
          name == '（名称不明）') return false;
      for (final kw in blackListKeywords) {
        if (name.contains(kw)) return false;
      }
      return true;
    }).toList();
  }

  /// 指定地域の道路ポリラインを読み込む
  Future<List<List<LatLng>>> loadRoadPolylines(String region) async {
    final features = await loadRoadFeatures(region);
    return features.map((f) => f.geometry).toList();
  }

  /// 指定地域の道路 RoadFeature を読み込む（A* 用）
  Future<List<RoadFeature>> loadRoadFeatures(String region) async {
    final file = '${_assetPrefix(region)}_roads.gplb';
    try {
      final bytes = await MapRepository.instance.readBytes(file);
      return RoadParser.parse(bytes);
    } catch (e) {
      debugPrint('❌ ShelterRepository road load error ($file): $e');
      return [];
    }
  }

  /// 指定地域のハザードポリゴンを読み込む。
  /// 新形式 (GPLH v3 バイナリ) を優先し、旧 JSON フォーマットにもフォールバック。
  Future<List<List<LatLng>>> loadHazardPolygons(String region) async {
    final file = '${_assetPrefix(region)}_hazard.gplh';
    try {
      final bytes = await MapRepository.instance.readBytes(file);
      // GPLH バイナリマジック判定
      if (bytes.length >= 4 &&
          bytes[0] == 0x47 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4C &&
          bytes[3] == 0x48) {
        final polys = HazardParser.parse(bytes);
        return polys.map((p) => p.points).toList();
      }
      // 旧 JSON フォールバック
      final jsonStr = String.fromCharCodes(bytes);
      final data = json.decode(jsonStr) as Map<String, dynamic>;
      final polygonsData = (data['polygons'] as List<dynamic>?) ?? [];
      return polygonsData.map((polygon) {
        final coords = polygon is Map<String, dynamic> &&
                polygon.containsKey('coordinates')
            ? polygon['coordinates'] as List<dynamic>
            : polygon as List<dynamic>;
        return coords.map((c) {
          final pt = c as List<dynamic>;
          return LatLng(
              (pt[1] as num).toDouble(), (pt[0] as num).toDouble());
        }).toList();
      }).toList();
    } catch (e) {
      debugPrint('❌ ShelterRepository hazard load error ($file): $e');
      return [];
    }
  }
}
