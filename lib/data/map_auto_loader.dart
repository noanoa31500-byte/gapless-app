// ============================================================
// map_auto_loader.dart
// 起動時ロード・10分タイマー・シングルトン
// GPS消失時はDeadReckoningServiceにフォールバック
// ============================================================

import 'dart:async';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'map_tile_index.dart';
import 'map_download_service.dart';
import 'map_cache_manager.dart';
import '../services/dead_reckoning_service.dart';
import '../services/secure_pii_storage.dart';
import '../providers/region_mode_provider.dart';

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

  /// デフォルト座標は Region レジストリ から取得（地域汎用化）
  /// 旧 35.6762/139.6503 (東京) のハードコードを排除
  static double get _defaultLat => RegionRegistry.japan.defaultCenter.latitude;
  static double get _defaultLng => RegionRegistry.japan.defaultCenter.longitude;

  static final MapAutoLoader instance = MapAutoLoader._();
  MapAutoLoader._();

  Timer? _timer;
  final _controller = StreamController<MapLoadEvent>.broadcast();
  bool _running = false;
  DeadReckoningService? _deadReckoning;

  Stream<MapLoadEvent> get onEvent => _controller.stream;

  /// DeadReckoningService をバインドする（main.dart の initState で呼ぶ）
  void bindDeadReckoning(DeadReckoningService dr) {
    _deadReckoning = dr;
  }

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

    // 4. 各タイルをダウンロードしてローカルストレージを常に最新で上書き更新
    //    （キャッシュ済みでも必ず再取得し、古いデータを置き換える）
    for (final tile in nearTiles) {
      final files = await service.downloadTile(tile);
      if (files.isEmpty || !files.containsKey('roads')) continue;

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
  // 現在地取得
  // 優先順: GPS → DeadReckoning → SharedPreferences → 東京デフォルト
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

      // GPS成功: DRが起動中なら位置を融合して停止
      final dr = _deadReckoning;
      if (dr != null && dr.isActive) {
        final fused = dr.deactivate(LatLng(pos.latitude, pos.longitude));
        await SecurePiiStorage.setLastLatLng(fused.latitude, fused.longitude);
        return (fused.latitude, fused.longitude);
      }

      await SecurePiiStorage.setLastLatLng(pos.latitude, pos.longitude);
      return (pos.latitude, pos.longitude);
    } catch (_) {
      return _fallbackLocation();
    }
  }

  // GPS失敗時のフォールバック
  // 優先順: DeadReckoning推定位置 → SharedPreferences → 東京デフォルト
  Future<(double, double)> _fallbackLocation() async {
    // 1. DeadReckoningが起動中なら推定位置を使用
    final dr = _deadReckoning;
    if (dr != null && dr.isActive) {
      final drPos = dr.estimatedPosition;
      if (drPos != null) {
        return (drPos.latitude, drPos.longitude);
      }
    }

    // 2. SecurePiiStorageから前回位置を復元し、DRを起動
    try {
      final lat = await SecurePiiStorage.getLastLat();
      final lng = await SecurePiiStorage.getLastLng();
      if (lat != null && lng != null) {
        if (dr != null && !dr.isActive) {
          dr.activate(LatLng(lat, lng));
        }
        return (lat, lng);
      }
    } catch (_) {}

    // 3. 地域レジストリのデフォルト座標（前回位置不明 → DR起動しない。地図表示の初期値のみに使う）
    return (_defaultLat, _defaultLng);
  }
}
