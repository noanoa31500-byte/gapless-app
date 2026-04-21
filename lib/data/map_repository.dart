// ============================================================
// map_repository.dart
// GitHubからマップデータを取得・保存・オフライン管理する
//
// 動作: 起動時に GPS を取得し index.json から現在地に最も近い
// タイルを選択して DL する。DL したファイルは
//   (a) 既存の consumer 互換のため flat 名（current_roads.gplb 等）で保存
//   (b) {documents}/maps/{areaId}/ 配下にも保存（タイルキャッシュ）
// の両方に書き込む。
// ============================================================

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:path_provider/path_provider.dart';
import '../services/connectivity_service.dart';
import '../utils/localization.dart';
import 'area_data.dart';
import 'map_cache_manager.dart';
import 'map_download_service.dart';
import 'map_tile_index.dart';

// ────────────────────────────────────────
// 既存 consumer (ShelterRepository 等) が読むフラット名
// 動的に選んだタイルのファイルをこの名前にマッピングして保存する
// ────────────────────────────────────────

/// 旧フラット名 → index.json の fileKey
const Map<String, String> _aliasMap = {
  'current_roads.gplb':  'roads',
  'current_poi.gplb':    'poi_shelter', // shelter を代表 POI として配置
  'current_hazard.gplh': 'hazard',
};

/// 現在地 GPS を取得。
/// 1) 直近キャッシュ (getLastKnownPosition) を即試す
/// 2) ダメなら getCurrentPosition を最大 12 秒で待つ
/// 3) それでも失敗したら null を返す（呼び出し側で扱う）
Future<({double lat, double lng})?> _currentPosition() async {
  try {
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      final req = await Geolocator.requestPermission();
      if (req == LocationPermission.denied ||
          req == LocationPermission.deniedForever) {
        return null;
      }
    } else if (perm == LocationPermission.deniedForever) {
      return null;
    }

    final last = await Geolocator.getLastKnownPosition();
    if (last != null) return (lat: last.latitude, lng: last.longitude);

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.low,
      timeLimit: const Duration(seconds: 12),
    );
    return (lat: pos.latitude, lng: pos.longitude);
  } catch (_) {
    return null;
  }
}

/// alias 名のローカルファイル一覧（旧 consumer 互換）
List<String> get _aliasFileNames => _aliasMap.keys.toList();

// ────────────────────────────────────────
// ダウンロード進捗の通知
// ────────────────────────────────────────
class DownloadProgress {
  final int current;      // 現在何件目か
  final int total;        // 全件数
  final String fileName;  // 現在処理中のファイル名
  final bool isDone;      // 全完了したか
  final String? error;    // エラーメッセージ（失敗時のみ）

  const DownloadProgress({
    required this.current,
    required this.total,
    required this.fileName,
    this.isDone = false,
    this.error,
  });
}

// ────────────────────────────────────────
// リポジトリ本体
// ────────────────────────────────────────
class MapRepository {
  static MapRepository? _instance;
  MapRepository._();
  static MapRepository get instance => _instance ??= MapRepository._();

  Directory? _docsDir;

  // 保存ディレクトリを取得（初回のみ初期化）
  Future<Directory> get _dir async {
    _docsDir ??= await getApplicationDocumentsDirectory();
    return _docsDir!;
  }

  // ────────────────────────────────────
  // ローカルファイルのパスを返す
  // ────────────────────────────────────
  Future<String> localPath(String fileName) async {
    final dir = await _dir;
    return '${dir.path}/$fileName';
  }

  // ────────────────────────────────────
  // ファイルが端末に保存済みか確認
  // ────────────────────────────────────
  Future<bool> isDownloaded(String fileName) async {
    final path = await localPath(fileName);
    return File(path).exists();
  }

  // ────────────────────────────────────
  // 全ファイルが揃っているか確認
  // オフライン判定に使う
  // ────────────────────────────────────
  Future<bool> isAllDataReady() async {
    for (final name in _aliasFileNames) {
      if (!await isDownloaded(name)) return false;
    }
    return true;
  }

  // ────────────────────────────────────
  // ネット接続があるか確認
  // ────────────────────────────────────
  Future<bool> hasConnection() async {
    return ConnectivityService.isConnected();
  }

  // ────────────────────────────────────
  // 起動時のメイン処理
  // 1. GPS 取得（失敗時は東京駅）
  // 2. index.json 取得
  // 3. 現在地に最も近いタイルを 1 件選んで全ファイルを DL
  // 4. _aliasMap で旧名にマッピングして保存（既存 consumer 互換）
  //    + {documents}/maps/{areaId}/ にも保存（新タイルキャッシュ）
  // ────────────────────────────────────
  Future<void> ensureAllData({
    void Function(DownloadProgress)? progressCallback,
  }) async {
    // 既に揃っていればスキップ
    if (await isAllDataReady()) return;

    if (!await hasConnection()) {
      progressCallback?.call(DownloadProgress(
        current: 0,
        total: _aliasMap.length,
        fileName: '',
        error: GapLessL10n.t('map_no_connection'),
      ));
      return;
    }

    final service = MapDownloadService();
    final cache = MapCacheManager();

    // index.json
    progressCallback?.call(const DownloadProgress(
      current: 0, total: 3, fileName: 'index.json',
    ));
    final index = await service.fetchIndex();
    if (index == null) {
      progressCallback?.call(DownloadProgress(
        current: 0, total: _aliasMap.length, fileName: 'index.json',
        error: GapLessL10n.t('map_download_failed').replaceAll('@filename', 'index.json'),
      ));
      return;
    }
    await cache.saveIndex(index);

    // GPS 取得 → 最寄りタイル選定
    final pos = await _currentPosition();
    if (pos == null) {
      progressCallback?.call(const DownloadProgress(
        current: 0, total: 3, fileName: '',
        error: '位置情報が取得できませんでした。設定で位置情報の許可を確認してください。',
      ));
      return;
    }
    final candidates = index.tilesNear(pos.lat, pos.lng, radiusKm: 50);
    final TileEntry tile;
    if (candidates.isNotEmpty) {
      candidates.sort((a, b) => a
          .distanceFromPoint(pos.lat, pos.lng)
          .compareTo(b.distanceFromPoint(pos.lat, pos.lng)));
      tile = candidates.first;
    } else {
      // 50km 圏内にタイルが無い場合、index 全体から最近傍
      final all = [...index.tiles]..sort((a, b) => a
          .distanceFromPoint(pos.lat, pos.lng)
          .compareTo(b.distanceFromPoint(pos.lat, pos.lng)));
      if (all.isEmpty) {
        progressCallback?.call(const DownloadProgress(
          current: 0, total: 0, fileName: '',
          error: 'index.json にタイルが存在しません',
        ));
        return;
      }
      tile = all.first;
    }

    // タイル丸 DL（解凍済み）
    progressCallback?.call(DownloadProgress(
      current: 1, total: 3, fileName: '${tile.id} (DL中)',
    ));
    final downloaded = await service.downloadTile(tile);
    if (downloaded.isEmpty) {
      progressCallback?.call(DownloadProgress(
        current: 1, total: 3, fileName: tile.id,
        error: GapLessL10n.t('map_download_failed').replaceAll('@filename', tile.id),
      ));
      return;
    }

    // タイルキャッシュに保存
    for (final entry in downloaded.entries) {
      await cache.saveMapData(tile.id, entry.key, entry.value);
    }

    // 旧 consumer 互換: alias 名で保存
    // POI は category 別 (poi_shelter / poi_hospital / poi_store / poi_water) を
    // すべて単一 current_poi.gplb にマージ
    final mergedPoi = _mergePoiBinaries([
      downloaded['poi_shelter'],
      downloaded['poi_hospital'],
      downloaded['poi_store'],
      downloaded['poi_water'],
      downloaded['poi'],
    ].whereType<Uint8List>().toList());

    final aliasData = <String, Uint8List?>{
      'current_roads.gplb':  downloaded['roads'],
      'current_poi.gplb':    mergedPoi,
      'current_hazard.gplh': downloaded['hazard'],
    };

    int progress = 1;
    for (final entry in aliasData.entries) {
      progress++;
      progressCallback?.call(DownloadProgress(
        current: progress, total: 3, fileName: entry.key,
      ));
      final data = entry.value;
      if (data == null) continue;
      final path = await localPath(entry.key);
      await File(path).writeAsBytes(data);
    }

    // 遠方タイルキャッシュ削除
    try {
      await cache.evictDistantCache(pos.lat, pos.lng, index);
    } catch (_) {}

    progressCallback?.call(DownloadProgress(
      current: 3, total: 3, fileName: tile.id, isDone: true,
    ));
  }

  // ────────────────────────────────────
  // ローカルファイルを読み込む
  // ────────────────────────────────────
  Future<Uint8List> readBytes(String fileName) async {
    final path = await localPath(fileName);
    final file = File(path);
    if (!await file.exists()) {
      throw Exception('$fileName がまだダウンロードされていません');
    }
    return file.readAsBytes();
  }

  /// 複数の POI gplb バイナリを 1 つにマージする。
  /// フォーマット: GPLB(4) + version(1) + count uint32 LE(4) + records...
  /// レコード長は固定 13 + nameLen バイト。
  static Uint8List? _mergePoiBinaries(List<Uint8List> parts) {
    if (parts.isEmpty) return null;
    if (parts.length == 1) return parts.first;

    int totalCount = 0;
    int version = 2;
    final bodies = <Uint8List>[];
    for (final p in parts) {
      if (p.length < 9) continue;
      if (p[0] != 0x47 || p[1] != 0x50 || p[2] != 0x4C || p[3] != 0x42) continue;
      version = p[4];
      final cnt = ByteData.sublistView(p).getUint32(5, Endian.little);
      totalCount += cnt;
      bodies.add(Uint8List.sublistView(p, 9));
    }
    if (bodies.isEmpty) return null;

    final bodyLen = bodies.fold<int>(0, (s, b) => s + b.length);
    final out = Uint8List(9 + bodyLen);
    out[0] = 0x47; out[1] = 0x50; out[2] = 0x4C; out[3] = 0x42;
    out[4] = version;
    ByteData.sublistView(out).setUint32(5, totalCount, Endian.little);
    int off = 9;
    for (final b in bodies) {
      out.setRange(off, off + b.length, b);
      off += b.length;
    }
    return out;
  }

  Future<String> readString(String fileName) async {
    final bytes = await readBytes(fileName);
    return utf8.decode(bytes, allowMalformed: true);
  }

  // ────────────────────────────────────
  // データを強制的に再取得したい場合
  // ローカルファイルを削除してから再ダウンロード
  // ────────────────────────────────────
  Future<void> clearAndRefresh({
    void Function(DownloadProgress)? progressCallback,
  }) async {
    final dir = await _dir;
    for (final name in _aliasFileNames) {
      final file = File('${dir.path}/$name');
      if (await file.exists()) await file.delete();
    }
    // タイルキャッシュも消す
    final mapsDir = Directory('${dir.path}/maps');
    if (await mapsDir.exists()) {
      try { await mapsDir.delete(recursive: true); } catch (_) {}
    }
    await ensureAllData(progressCallback: progressCallback);
  }

  // ────────────────────────────────────
  // タイルベースキャッシュからエリアデータを読み込む
  // キャッシュ済みなら即返し、なければダウンロードして保存する
  // 戻り値: fileKey → 解凍済みバイト列（roads, poi_*, hazard）
  // ────────────────────────────────────
  Future<AreaData?> loadAreaData(String areaId) async {
    final cache = MapCacheManager();

    // キャッシュから roads を確認
    final roads = await cache.loadMapData(areaId, 'roads');
    if (roads != null) {
      return _parseAreaData(areaId, roads, cache);
    }

    // キャッシュなし → index.json を取得してダウンロード
    final index = await cache.loadIndex();
    if (index == null) return null;

    final matches = index.tiles.where((t) => t.id == areaId);
    if (matches.isEmpty) return null;
    final tile = matches.first;

    final service = MapDownloadService();
    final files = await service.downloadTile(tile);
    if (files.isEmpty || !files.containsKey('roads')) return null;

    for (final entry in files.entries) {
      await cache.saveMapData(areaId, entry.key, entry.value);
    }
    final roadsData = files['roads']!;
    return _parseAreaData(areaId, roadsData, cache);
  }

  Future<AreaData> _parseAreaData(
    String areaId,
    Uint8List roads,
    MapCacheManager cache,
  ) =>
      AreaData.load(areaId, roads, cache);
}
