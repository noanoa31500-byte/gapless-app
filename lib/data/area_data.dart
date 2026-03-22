import 'dart:typed_data';
import 'map_cache_manager.dart';

class AreaData {
  final String areaId;
  final Uint8List roads;
  final Uint8List? poiHospital;
  final Uint8List? poiShelter;
  final Uint8List? poiStore;
  final Uint8List? poiWater;
  final Uint8List? hazard;

  const AreaData({
    required this.areaId,
    required this.roads,
    this.poiHospital,
    this.poiShelter,
    this.poiStore,
    this.poiWater,
    this.hazard,
  });

  static Future<AreaData> load(
    String areaId,
    Uint8List roads,
    MapCacheManager cache,
  ) async {
    return AreaData(
      areaId: areaId,
      roads: roads,
      poiHospital: await cache.loadMapData(areaId, 'poi_hospital'),
      poiShelter: await cache.loadMapData(areaId, 'poi_shelter'),
      poiStore: await cache.loadMapData(areaId, 'poi_store'),
      poiWater: await cache.loadMapData(areaId, 'poi_water'),
      hazard: await cache.loadMapData(areaId, 'hazard'),
    );
  }
}
