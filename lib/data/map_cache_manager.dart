// ============================================================
// map_cache_manager.dart
// ローカルストレージへの保存・読み込み・キャッシュ削除
// ============================================================

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'map_tile_index.dart';

class MapCacheManager {
  // ────────────────────────────────────
  // ベースディレクトリ: {documents}/maps/
  // ────────────────────────────────────
  Future<Directory> _mapsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/maps');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ────────────────────────────────────
  // マップデータ保存・読み込み
  // パス: {documents}/maps/{areaId}/{fileKey}.bin
  // ────────────────────────────────────
  Future<File> _dataFile(String areaId, String fileKey) async {
    final base = await _mapsDir();
    final dir = Directory('${base.path}/$areaId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/$fileKey.bin');
  }

  Future<void> saveMapData(
      String areaId, String fileKey, Uint8List data) async {
    final file = await _dataFile(areaId, fileKey);
    await file.writeAsBytes(data);
  }

  Future<Uint8List?> loadMapData(String areaId, String fileKey) async {
    final file = await _dataFile(areaId, fileKey);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  Future<bool> isCached(String areaId, String fileKey) async {
    final file = await _dataFile(areaId, fileKey);
    return file.exists();
  }

  /// 単一キャッシュファイルを削除する。
  /// gzip 解凍失敗（破損ダウンロード）後の cleanup に使う。
  /// ファイルが無くてもエラーにしない。
  Future<void> deleteCacheFile(String areaId, String fileKey) async {
    try {
      final file = await _dataFile(areaId, fileKey);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // best effort — 削除失敗は致命的ではない
    }
  }

  // ────────────────────────────────────
  // index.json キャッシュ
  // パス: {documents}/maps/index.json
  // ────────────────────────────────────
  Future<File> _indexFile() async {
    final base = await _mapsDir();
    return File('${base.path}/index.json');
  }

  Future<void> saveIndex(TileIndex index) async {
    final file = await _indexFile();
    await file.writeAsString(jsonEncode(index.toJson()));
  }

  Future<TileIndex?> loadIndex() async {
    final file = await _indexFile();
    if (!await file.exists()) return null;
    final content = await file.readAsString();
    final json = jsonDecode(content) as Map<String, dynamic>;
    return TileIndex.fromJson(json);
  }

  // ────────────────────────────────────
  // 50km 以上離れたエリアのキャッシュを削除
  // ────────────────────────────────────
  Future<void> evictDistantCache(
    double currentLat,
    double currentLng,
    TileIndex index,
  ) async {
    const evictThresholdKm = 50.0;

    for (final tile in index.tiles) {
      final centerLat = (tile.latMin + tile.latMax) / 2;
      final centerLng = (tile.lngMin + tile.lngMax) / 2;
      final dist = haversineKm(currentLat, currentLng, centerLat, centerLng);

      if (dist > evictThresholdKm) {
        final base = await _mapsDir();
        final dir = Directory('${base.path}/${tile.id}');
        if (await dir.exists()) await dir.delete(recursive: true);
      }
    }
  }
}
