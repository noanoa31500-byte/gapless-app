// ============================================================
// map_repository.dart
// GitHubからマップデータを取得・保存・オフライン管理する
// ============================================================

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/localization.dart';
import 'area_data.dart';
import 'map_cache_manager.dart';
import 'map_download_service.dart';

// ────────────────────────────────────────
// ダウンロード対象ファイルの定義
// ────────────────────────────────────────
class MapFile {
  final String remoteUrl;   // GitHubのURL（gz圧縮済み or 生）
  final String localName;   // 端末に保存するファイル名
  final bool isGzipped;     // gzip圧縮されているか

  const MapFile({
    required this.remoteUrl,
    required this.localName,
    required this.isGzipped,
  });
}

const _baseUrl = 'https://raw.githubusercontent.com/noanoa31500-byte/maps/main';

const mapFiles = [
  // 東京中心部（gz圧縮あり）
  MapFile(
    remoteUrl: '$_baseUrl/tokyo_center_roads.gplb.gz',
    localName: 'tokyo_center_roads.gplb',
    isGzipped: true,
  ),
  MapFile(
    remoteUrl: '$_baseUrl/tokyo_center_poi.gplb.gz',
    localName: 'tokyo_center_poi.gplb',
    isGzipped: true,
  ),
  MapFile(
    remoteUrl: '$_baseUrl/tokyo_center_hazard.gplh.gz',
    localName: 'tokyo_center_hazard.gplh',
    isGzipped: true,
  ),
  // 大崎（gz圧縮あり）
  MapFile(
    remoteUrl: '$_baseUrl/osaki_poi.gplb.gz',
    localName: 'osaki_poi.gplb',
    isGzipped: true,
  ),
  MapFile(
    remoteUrl: '$_baseUrl/osaki_roads.gplb.gz',
    localName: 'osaki_roads.gplb',
    isGzipped: true,
  ),
  MapFile(
    remoteUrl: '$_baseUrl/osaki_hazard.gplh.gz',
    localName: 'osaki_hazard.gplh',
    isGzipped: true,
  ),
  // タイ（gz圧縮あり）
  MapFile(
    remoteUrl: '$_baseUrl/thailand_poi.gplb.gz',
    localName: 'thailand_poi.gplb',
    isGzipped: true,
  ),
  MapFile(
    remoteUrl: '$_baseUrl/thailand_roads.gplb.gz',
    localName: 'thailand_roads.gplb',
    isGzipped: true,
  ),
  MapFile(
    remoteUrl: '$_baseUrl/thailand_hazard.gplh.gz',
    localName: 'thailand_hazard.gplh',
    isGzipped: true,
  ),
];

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
    for (final f in mapFiles) {
      if (!await isDownloaded(f.localName)) return false;
    }
    return true;
  }

  // ────────────────────────────────────
  // ネット接続があるか確認
  // ────────────────────────────────────
  Future<bool> hasConnection() async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }

  // ────────────────────────────────────
  // 起動時のメイン処理
  // 未取得のファイルだけダウンロードする
  // progressCallback: 進捗をUIに通知するコールバック
  // ────────────────────────────────────
  Future<void> ensureAllData({
    void Function(DownloadProgress)? progressCallback,
  }) async {
    // まず未取得ファイルを洗い出す
    final pending = <MapFile>[];
    for (final f in mapFiles) {
      if (!await isDownloaded(f.localName)) {
        pending.add(f);
      }
    }

    // 全部揃っていればスキップ
    if (pending.isEmpty) return;

    // オフラインかつデータ未取得の場合はエラーを通知
    if (!await hasConnection()) {
      progressCallback?.call(DownloadProgress(
        current: 0,
        total: pending.length,
        fileName: '',
        error: GapLessL10n.t('map_no_connection'),
      ));
      return;
    }

    // 未取得ファイルを順番にダウンロード
    for (int i = 0; i < pending.length; i++) {
      final f = pending[i];
      progressCallback?.call(DownloadProgress(
        current: i + 1,
        total: pending.length,
        fileName: f.localName,
      ));

      try {
        await _downloadFile(f);
      } catch (e) {
        progressCallback?.call(DownloadProgress(
          current: i + 1,
          total: pending.length,
          fileName: f.localName,
          error: GapLessL10n.t('map_download_failed').replaceAll('@filename', f.localName),
        ));
        return; // 1件失敗したら中断
      }
    }

    // 全完了
    progressCallback?.call(DownloadProgress(
      current: pending.length,
      total: pending.length,
      fileName: '',
      isDone: true,
    ));
  }

  // ────────────────────────────────────
  // 1ファイルをダウンロードして保存
  // ────────────────────────────────────
  Future<void> _downloadFile(MapFile mapFile) async {
    final response = await http
        .get(Uri.parse(mapFile.remoteUrl))
        .timeout(const Duration(seconds: 30));

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}');
    }

    // gz圧縮されている場合は展開してから保存
    final Uint8List bytes;
    if (mapFile.isGzipped) {
      bytes = Uint8List.fromList(GZipCodec().decode(response.bodyBytes));
    } else {
      bytes = response.bodyBytes;
    }

    final path = await localPath(mapFile.localName);
    await File(path).writeAsBytes(bytes);
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
    for (final f in mapFiles) {
      final file = File('${dir.path}/${f.localName}');
      if (await file.exists()) await file.delete();
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
