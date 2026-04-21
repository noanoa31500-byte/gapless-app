// ============================================================
// map_download_service.dart
// GitHub からのダウンロード・gzip 解凍・リトライ
// ============================================================

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../services/pinned_http_client.dart';
import 'map_cache_manager.dart';
import 'map_tile_index.dart';

final http.Client _pinnedClient = createPinnedClient();

class MapDownloadService {
  static const _indexUrl =
      'https://raw.githubusercontent.com/noanoa31500-byte/maps/main/index.json';

  static const _timeout = Duration(seconds: 30);
  static const _retryCount = 3;
  static const _retryDelay = Duration(seconds: 1);

  // ダウンロード優先順位
  static const _fileKeyOrder = [
    'roads',
    'poi_hospital',
    'poi_shelter',
    'hazard',
    'poi_store',
    'poi_water',
  ];

  // ────────────────────────────────────
  // index.json を取得してパース（3回リトライ）
  // ────────────────────────────────────
  Future<TileIndex?> fetchIndex() async {
    for (int attempt = 0; attempt < _retryCount; attempt++) {
      try {
        final response =
            await _pinnedClient.get(Uri.parse(_indexUrl)).timeout(_timeout);
        if (response.statusCode == 200) {
          final json =
              jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true))
                  as Map<String, dynamic>;
          return TileIndex.fromJson(json);
        }
      } catch (_) {
        // fall through to retry
      }
      if (attempt < _retryCount - 1) {
        await Future.delayed(_retryDelay);
      }
    }
    return null;
  }

  // ────────────────────────────────────
  // candidateUrls を先頭から試してダウンロード・gzip 解凍
  // 全 URL 失敗時は null を返す
  // [areaId] [fileKey] が指定されると、gzip 解凍失敗時に
  // 該当キャッシュファイルを削除して起動毎の再DLループを防ぐ
  // ────────────────────────────────────
  Future<Uint8List?> downloadFile(
    List<String> candidateUrls, {
    String? areaId,
    String? fileKey,
  }) async {
    for (final url in candidateUrls) {
      final data = await _tryDownload(url, areaId: areaId, fileKey: fileKey);
      if (data != null) return data;
    }
    return null;
  }

  Future<Uint8List?> _tryDownload(
    String url, {
    String? areaId,
    String? fileKey,
  }) async {
    for (int attempt = 0; attempt < _retryCount; attempt++) {
      try {
        final response =
            await _pinnedClient.get(Uri.parse(url)).timeout(_timeout);
        if (response.statusCode == 200) {
          // gzip か否かは Content-Encoding または URL の拡張子で判断
          final bytes = response.bodyBytes;
          if (url.endsWith('.gz')) {
            try {
              return Uint8List.fromList(GZipCodec().decode(bytes));
            } catch (gzipErr) {
              // GZip 破損: 部分DL済みキャッシュも削除して再DLループを断ち切る
              // ignore: avoid_print
              print('⚠️ MapDownloadService: GZip decode failed for $url — '
                  'purging cache file ($gzipErr)');
              if (areaId != null && fileKey != null) {
                try {
                  await MapCacheManager().deleteCacheFile(areaId, fileKey);
                } catch (_) {/* best effort */}
              }
              // この URL は壊れていると判断して諦める（次の候補 URL を試す）
              return null;
            }
          }
          return bytes;
        }
        // 404 等はこの URL を諦めて次の URL へ
        if (response.statusCode == 404) return null;
      } catch (_) {
        // タイムアウト・ネットワークエラーはリトライ
      }
      if (attempt < _retryCount - 1) {
        await Future.delayed(_retryDelay);
      }
    }
    return null;
  }

  // ────────────────────────────────────
  // TileEntry の全ファイルをダウンロードして返す
  // key: "roads", "poi_hospital", "hazard" など
  // ────────────────────────────────────
  Future<Map<String, Uint8List>> downloadTile(TileEntry entry) async {
    final result = <String, Uint8List>{};

    // 優先順位リストにないキーも末尾に追加する
    final orderedKeys = [
      ..._fileKeyOrder.where(entry.files.containsKey),
      ...entry.files.keys.where((k) => !_fileKeyOrder.contains(k)),
    ];

    for (final key in orderedKeys) {
      final urls = entry.candidateUrls(key);
      if (urls.isEmpty) continue;
      final data = await downloadFile(urls, areaId: entry.id, fileKey: key);
      if (data != null) {
        result[key] = data;
      }
    }
    return result;
  }
}
