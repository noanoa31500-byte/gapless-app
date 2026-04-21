import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import 'pinned_http_client.dart';

// ============================================================================
// JmaAlertService — 気象庁オープンデータ (緊急地震速報・津波警報) 取得
// ============================================================================
//
// 【使用フィード】
//   https://www.data.jma.go.jp/developer/xml/feed/eqvol_l.xml
//   Atom XML形式。過去2日分のエントリを取得し、タイトルに
//   「緊急地震速報」または「津波」を含むものだけを保持する。
//
// 【更新間隔】
//   フォアグラウンド時: 60秒ごと自動更新
//   手動更新: refresh() を呼ぶ
//
// 【堅牢性】
//   - パーサーは package:xml を使用（手書きRegExpは ReDoS / 切断XMLで例外発生のリスク）
//   - パース失敗時は最後の有効キャッシュを保持
//   - 取得成功時に SharedPreferences へ JSON 永続化（オフライン起動時も警報表示）
//   - 6h TTL: キャッシュは 6 時間以内のものだけ「有効」と判定
//
// ============================================================================

enum JmaAlertType { earthquake, tsunami, other }

class JmaAlert {
  final String title;
  final DateTime updatedAt;
  final JmaAlertType type;
  final String linkUrl;

  const JmaAlert({
    required this.title,
    required this.updatedAt,
    required this.type,
    required this.linkUrl,
  });

  bool get isEarthquake => type == JmaAlertType.earthquake;
  bool get isTsunami => type == JmaAlertType.tsunami;

  /// 発報から6時間以内なら「有効」とみなす（システム時計逆行ガード付き）
  bool get isActive {
    var ageMs =
        DateTime.now().millisecondsSinceEpoch - updatedAt.millisecondsSinceEpoch;
    if (ageMs < 0) ageMs = 0; // 時計逆行クランプ
    return ageMs < const Duration(hours: 6).inMilliseconds;
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
        'type': type.name,
        'linkUrl': linkUrl,
      };

  static JmaAlert? fromJson(Map<String, dynamic> j) {
    try {
      final typeStr = j['type'] as String? ?? 'other';
      final type = JmaAlertType.values.firstWhere(
        (t) => t.name == typeStr,
        orElse: () => JmaAlertType.other,
      );
      return JmaAlert(
        title: j['title'] as String? ?? '',
        updatedAt:
            DateTime.tryParse(j['updatedAt'] as String? ?? '') ?? DateTime.now(),
        type: type,
        linkUrl: j['linkUrl'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }
}

/// JMAパース失敗時の構造化エラー
class JmaParseException implements Exception {
  final String message;
  final Object? cause;
  JmaParseException(this.message, [this.cause]);
  @override
  String toString() => 'JmaParseException: $message${cause != null ? " ($cause)" : ""}';
}

class JmaAlertService extends ChangeNotifier {
  static final JmaAlertService instance = JmaAlertService._();
  JmaAlertService._();

  static const _feedUrl =
      'https://www.data.jma.go.jp/developer/xml/feed/eqvol_l.xml';
  static const _refreshInterval = Duration(seconds: 60);

  // SharedPreferences キー
  static const _kCachedAlertsKey = 'jma_cached_alerts';
  static const _kCachedFetchAtKey = 'jma_cached_fetch_at';
  // キャッシュ有効期間（6時間 TTL）
  static const _cacheTtl = Duration(hours: 6);

  List<JmaAlert> _alerts = [];
  bool _isLoading = false;
  String? _lastError;
  DateTime? _lastFetchAt;
  bool _restoredFromCache = false;

  List<JmaAlert> get alerts => List.unmodifiable(_alerts);
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;
  DateTime? get lastFetchAt => _lastFetchAt;
  bool get isFromCache => _restoredFromCache;

  /// アクティブな警報があるか（バッジ表示用）
  bool get hasActiveAlert => _alerts.any((a) => a.isActive);

  Timer? _timer;

  // 気象庁配信ホスト用に TLS ピン済みクライアントを使用する。
  // pin 値は本番投入前に投入。User-Agent も明示してブロック回避。
  final http.Client _httpClient = createPinnedClient();
  static const Map<String, String> _httpHeaders = {
    'User-Agent': 'GapLess/5.0.0 (disaster-prevention; contact: gapless@example.org)',
    'Accept': 'application/atom+xml, application/xml, text/xml',
  };

  // ---------------------------------------------------------------------------
  // ライフサイクル
  // ---------------------------------------------------------------------------

  void startPolling() {
    // 起動時: まず永続化キャッシュを読み出して即座に UI へ反映
    unawaited(_loadFromPersistentCache());
    refresh();
    _timer?.cancel();
    _timer = Timer.periodic(_refreshInterval, (_) => refresh());
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 永続化キャッシュ
  // ---------------------------------------------------------------------------

  Future<void> _loadFromPersistentCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCachedAlertsKey);
      final fetchAtMs = prefs.getInt(_kCachedFetchAtKey) ?? 0;
      if (raw == null || raw.isEmpty) return;

      // 6h TTL チェック（時計逆行クランプ）
      var ageMs = DateTime.now().millisecondsSinceEpoch - fetchAtMs;
      if (ageMs < 0) ageMs = 0;
      if (ageMs > _cacheTtl.inMilliseconds) {
        debugPrint('JmaAlertService: キャッシュ TTL 切れ ($ageMs ms)');
        return;
      }

      final list = (jsonDecode(raw) as List)
          .map((e) => JmaAlert.fromJson(e as Map<String, dynamic>))
          .whereType<JmaAlert>()
          .toList();
      if (list.isEmpty) return;

      // ライブ取得が未実行なら、キャッシュをそのまま採用
      if (_alerts.isEmpty) {
        _alerts = list;
        _lastFetchAt = DateTime.fromMillisecondsSinceEpoch(fetchAtMs);
        _restoredFromCache = true;
        notifyListeners();
        debugPrint('JmaAlertService: 永続化キャッシュから ${list.length} 件復元');
      }
    } catch (e) {
      debugPrint('JmaAlertService: キャッシュ復元失敗 $e');
    }
  }

  Future<void> _saveToPersistentCache(List<JmaAlert> alerts) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(alerts.map((a) => a.toJson()).toList());
      await prefs.setString(_kCachedAlertsKey, raw);
      await prefs.setInt(
          _kCachedFetchAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('JmaAlertService: キャッシュ保存失敗 $e');
    }
  }

  // ---------------------------------------------------------------------------
  // フェッチ & パース
  // ---------------------------------------------------------------------------

  Future<void> refresh() async {
    if (_isLoading) return;
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      final response = await _httpClient
          .get(Uri.parse(_feedUrl), headers: _httpHeaders)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        try {
          final parsed = _parseAtomFeed(response.body);
          _alerts = parsed;
          _lastFetchAt = DateTime.now();
          _lastError = null;
          _restoredFromCache = false;
          unawaited(_saveToPersistentCache(parsed));
        } on JmaParseException catch (e) {
          // パース失敗時は最後の有効キャッシュ (_alerts) を保持し、エラーだけ報告
          _lastError = 'parse: ${e.message}';
          debugPrint('JmaAlertService: パース失敗 → 既存キャッシュ維持 ($e)');
        }
      } else {
        _lastError = 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      _lastError = e.toString();
      debugPrint('JmaAlertService: 取得失敗 $e');
      // ネットワーク失敗時にキャッシュが無ければ復元を試みる
      if (_alerts.isEmpty) {
        await _loadFromPersistentCache();
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Atom XML パーサー（package:xml）
  // ---------------------------------------------------------------------------

  List<JmaAlert> _parseAtomFeed(String xml) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(xml);
    } catch (e) {
      throw JmaParseException('XML parse error', e);
    }

    final results = <JmaAlert>[];

    for (final entry in doc.findAllElements('entry')) {
      final title = entry.getElement('title')?.innerText.trim() ?? '';
      final updatedStr = entry.getElement('updated')?.innerText.trim() ?? '';

      // <link href="..."/> または <link rel="alternate" href="..."/>
      String linkUrl = '';
      for (final link in entry.findElements('link')) {
        final href = link.getAttribute('href');
        if (href != null && href.isNotEmpty) {
          linkUrl = href;
          break;
        }
      }

      // 緊急地震速報・津波のみ抽出
      final isEq = title.contains('緊急地震速報');
      final isTsu = title.contains('津波');
      if (!isEq && !isTsu) continue;

      final updatedAt = DateTime.tryParse(updatedStr) ?? DateTime.now();

      results.add(JmaAlert(
        title: title,
        updatedAt: updatedAt,
        type: isEq ? JmaAlertType.earthquake : JmaAlertType.tsunami,
        linkUrl: linkUrl,
      ));
    }

    // 新しい順にソート
    results.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return results;
  }
}
