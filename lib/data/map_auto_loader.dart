// ============================================================
// map_auto_loader.dart
// 起動時ロード・10分タイマー・シングルトン
// ============================================================

import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'map_tile_index.dart';
import 'map_download_service.dart';
import 'map_cache_manager.dart';

// ────────────────────────────────────────
// イベント型
// ────────────────────────────────────────
enum MapLoadEventType { started, tileLoaded, allLoaded, error }

class MapLoadEvent {
  final MapLoadEventType type;
  final String? areaId;
  final String? message;
  const MapLoadEvent(this.type, {this.areaId, this.message});
}

// ────────────────────────────────────────
// MapAutoLoader
// ────────────────────────────────────────
class MapAutoLoader {
  static const _updateInterval = Duration(minutes: 10);
  static const _radiusKm = 3.0;

  // 東京デフォルト座標
  static const _defaultLat = 35.6762;
  static const _defaultLng = 139.6503;

  static final MapAutoLoader instance = MapAutoLoader._();
  MapAutoLoader._();

  Timer? _timer;
  final _controller = StreamController<MapLoadEvent>.broadcast();
  bool _running = false;

  Stream<MapLoadEvent> get onEvent => _controller.stream;

  // ────────────────────────────────────
  // 起動: ローカルキャッシュ即利用 + バックグラウンド更新
  // ────────────────────────────────────
  Future<void> start() async {
    if (_running) return;
    _running = true;

    _controller.add(const MapLoadEvent(MapLoadEventType.started));

    // 初回ロード（バックグラウンドで実行）
    unawaited(_loadNearbyTiles());

    // 10 分ごとに更新
    _timer = Timer.periodic(_updateInterval, (_) {
      unawaited(_loadNearbyTiles());
    });
  }

  // ────────────────────────────────────
  // 停止
  // ────────────────────────────────────
  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }

  // ────────────────────────────────────
  // メイン処理
  // ────────────────────────────────────
  Future<void> _loadNearbyTiles() async {
    final cache = MapCacheManager();
    final service = MapDownloadService();

    // 1. 現在地取得
    final (lat, lng) = await _getCurrentLocation();

    // 2. index.json をローカルから読む（なければ GitHub から取得）
    TileIndex? index = await cache.loadIndex();
    if (index == null) {
      index = await service.fetchIndex();
      if (index == null) {
        _controller.add(const MapLoadEvent(
          MapLoadEventType.error,
          message: 'index.json の取得に失敗しました',
        ));
        return;
      }
      await cache.saveIndex(index);
    } else {
      // バックグラウンドで index を更新
      unawaited(_refreshIndex(cache, service));
    }

    // 3. 近隣タイルを特定
    final nearTiles = index.tilesNear(lat, lng, radiusKm: _radiusKm);

    // 4. 各タイルをダウンロード（roads がキャッシュ済みならスキップ）
    for (final tile in nearTiles) {
      final roadsCached = await cache.isCached(tile.id, 'roads');
      if (roadsCached) continue;

      final files = await service.downloadTile(tile);
      for (final entry in files.entries) {
        await cache.saveMapData(tile.id, entry.key, entry.value);
      }

      _controller.add(MapLoadEvent(
        MapLoadEventType.tileLoaded,
        areaId: tile.id,
      ));
    }

    // 5. 遠方キャッシュを削除
    await cache.evictDistantCache(lat, lng, index);

    _controller.add(const MapLoadEvent(MapLoadEventType.allLoaded));
  }

  Future<void> _refreshIndex(
      MapCacheManager cache, MapDownloadService service) async {
    final index = await service.fetchIndex();
    if (index != null) await cache.saveIndex(index);
  }

  // ────────────────────────────────────
  // 現在地取得（失敗時は SharedPreferences → デフォルト東京）
  // ────────────────────────────────────
  Future<(double lat, double lng)> _getCurrentLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return _fallbackLocation();
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.reduced,
      ).timeout(const Duration(seconds: 5));
      // 成功したら SharedPreferences に保存
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('last_lat', pos.latitude);
      await prefs.setDouble('last_lng', pos.longitude);
      return (pos.latitude, pos.longitude);
    } catch (_) {
      return _fallbackLocation();
    }
  }

  Future<(double, double)> _fallbackLocation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lat = prefs.getDouble('last_lat');
      final lng = prefs.getDouble('last_lng');
      if (lat != null && lng != null) return (lat, lng);
    } catch (_) {}
    return (_defaultLat, _defaultLng);
  }
}

