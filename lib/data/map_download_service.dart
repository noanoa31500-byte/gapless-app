// ============================================================
// map_download_service.dart
// GitHub からのダウンロード・gzip 解凍・リトライ
// ============================================================

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'map_tile_index.dart';

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
            await http.get(Uri.parse(_indexUrl)).timeout(_timeout);
        if (response.statusCode == 200) {
          final json = jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true))
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
  // ────────────────────────────────────
  Future<Uint8List?> downloadFile(List<String> candidateUrls) async {
    for (final url in candidateUrls) {
      final data = await _tryDownload(url);
      if (data != null) return data;
    }
    return null;
  }

  Future<Uint8List?> _tryDownload(String url) async {
    for (int attempt = 0; attempt < _retryCount; attempt++) {
      try {
        final response =
            await http.get(Uri.parse(url)).timeout(_timeout);
        if (response.statusCode == 200) {
          // gzip か否かは Content-Encoding または URL の拡張子で判断
          final bytes = response.bodyBytes;
          if (url.endsWith('.gz')) {
            return Uint8List.fromList(GZipCodec().decode(bytes));
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
      final data = await downloadFile(urls);
      if (data != null) {
        result[key] = data;
      }
    }
    return result;
  }
}
