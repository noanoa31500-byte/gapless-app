import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 巨大なデータファイルをパフォーマンスを落とさずに読み込むためのローダークラス
class FastDataLoader {
  // メモリキャッシュ: パス -> パース済みデータ
  static final Map<String, dynamic> _cache = {};

  /// GeoJSONファイルを非同期で読み込み、パースして返します。
  /// [assetPath] アセットのパス (例: 'assets/data/roads_jp.geojson')
  /// 
  /// 特徴:
  /// 1. キャッシュヒット時は即座にデータを返します。
  /// 2. `compute` を使用してJSONパースを別Isolate(スレッド)で実行するため、UIスレッドをブロックしません。
  static Future<Map<String, dynamic>> loadGeoJson(String assetPath) async {
    // 1. キャッシュチェック (O(1))
    if (_cache.containsKey(assetPath)) {
      debugPrint('⚡ FastDataLoader: Cache hit for $assetPath');
      return _cache[assetPath];
    }

    try {
      debugPrint('⏳ FastDataLoader: Loading $assetPath from disk...');
      final Stopwatch stopwatch = Stopwatch()..start();

      // 2. 文字列として読み込み (非同期I/O)
      final String jsonString = await rootBundle.loadString(assetPath);
      
      // 3. Isolateでパース実行 (ここが重い処理)
      // UIスレッドをフリーズさせないための重要なステップ
      debugPrint('🔄 FastDataLoader: Parsing JSON in background isolate...');
      final dynamic data = await compute(_parseJsonInBackground, jsonString);

      // 4. 結果をキャッシュして返す
      _cache[assetPath] = data;
      
      stopwatch.stop();
      debugPrint('✅ FastDataLoader: Loaded $assetPath in ${stopwatch.elapsedMilliseconds}ms');
      
      return data as Map<String, dynamic>;
    } catch (e) {
      debugPrint('❌ FastDataLoader Error loading $assetPath: $e');
      rethrow;
    }
  }

  /// バックグラウンドIsolateで実行されるJsonデコード関数
  /// トップレベル関数またはstaticメソッドである必要があります
  static dynamic _parseJsonInBackground(String jsonString) {
    return jsonDecode(jsonString);
  }

  /// 特定のファイルのキャッシュを削除
  static void clearCacheFor(String assetPath) {
    _cache.remove(assetPath);
  }

  /// 全てのキャッシュを削除（メモリ警告時などに使用）
  static void clearAllCache() {
    _cache.clear();
    debugPrint('🗑️ FastDataLoader: Cache cleared');
  }

  /// 【応用】ストリーミング的な処理の提案
  /// 巨大すぎる(50MB超)ファイルの場合、JSONを分割して保存し、
  /// 必要なチャンクだけを読み込む設計が推奨されます。
  /// 
  /// 例: loadChunkedData('roads', chunkId: 1)
}
