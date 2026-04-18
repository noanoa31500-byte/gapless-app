import '../data/map_cache_manager.dart';
import '../data/map_repository.dart';
import '../data/road_parser.dart';
import '../models/road_feature.dart';

/// 道路フィーチャのシングルトンキャッシュ。
/// main.dart と NavigationScreen が同じファイルを二重ロードしないよう共有する。
class RoadFeaturesCache {
  static final RoadFeaturesCache instance = RoadFeaturesCache._();
  RoadFeaturesCache._();

  final Map<String, List<RoadFeature>> _cache = {};

  /// [filename] の道路フィーチャを返す。キャッシュ済みならディスクI/Oなし。
  Future<List<RoadFeature>> get(String filename) async {
    if (_cache.containsKey(filename)) return _cache[filename]!;
    final bytes = await MapRepository.instance.readBytes(filename);
    final features = RoadParser.parse(bytes);
    _cache[filename] = features;
    return features;
  }

  /// ベースファイル + MapAutoLoaderがダウンロードした近傍タイルをマージして返す。
  /// タイルが未キャッシュの場合はベースのみ。
  Future<List<RoadFeature>> getMergedWithTiles(
      String baseFile, double lat, double lng) async {
    final base = await get(baseFile);
    final tiles = await _loadNearbyTileFeatures(lat, lng);
    return tiles.isEmpty ? base : [...base, ...tiles];
  }

  Future<List<RoadFeature>> _loadNearbyTileFeatures(
      double lat, double lng) async {
    final cache = MapCacheManager();
    final index = await cache.loadIndex();
    if (index == null) return [];

    const radiusKm = 5.0;
    final nearby = index.tilesNear(lat, lng, radiusKm: radiusKm);
    final result = <RoadFeature>[];

    for (final tile in nearby) {
      if (_cache.containsKey(tile.id)) {
        result.addAll(_cache[tile.id]!);
        continue;
      }
      final bytes = await cache.loadMapData(tile.id, 'roads');
      if (bytes == null) continue;
      try {
        final features = RoadParser.parse(bytes);
        _cache[tile.id] = features;
        result.addAll(features);
      } catch (_) {}
    }
    return result;
  }

  /// キャッシュをクリア（地域切替など）
  void invalidate() => _cache.clear();

  /// タイルキャッシュのみクリア（ベースファイルキャッシュは保持）
  void invalidateTiles() {
    _cache.removeWhere((key, _) => !key.endsWith('.gplb'));
  }
}
