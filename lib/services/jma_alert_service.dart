import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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

  /// 発報から6時間以内なら「有効」とみなす
  bool get isActive =>
      DateTime.now().difference(updatedAt).inHours < 6;
}

class JmaAlertService extends ChangeNotifier {
  static final JmaAlertService instance = JmaAlertService._();
  JmaAlertService._();

  static const _feedUrl =
      'https://www.data.jma.go.jp/developer/xml/feed/eqvol_l.xml';
  static const _refreshInterval = Duration(seconds: 60);

  List<JmaAlert> _alerts = [];
  bool _isLoading = false;
  String? _lastError;
  DateTime? _lastFetchAt;

  List<JmaAlert> get alerts => List.unmodifiable(_alerts);
  bool get isLoading => _isLoading;
  String? get lastError => _lastError;
  DateTime? get lastFetchAt => _lastFetchAt;

  /// アクティブな警報があるか（バッジ表示用）
  bool get hasActiveAlert => _alerts.any((a) => a.isActive);

  Timer? _timer;

  // ---------------------------------------------------------------------------
  // ライフサイクル
  // ---------------------------------------------------------------------------

  void startPolling() {
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
  // フェッチ & パース
  // ---------------------------------------------------------------------------

  Future<void> refresh() async {
    if (_isLoading) return;
    _isLoading = true;
    _lastError = null;
    notifyListeners();

    try {
      final response = await http
          .get(Uri.parse(_feedUrl))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        _alerts = _parseAtomFeed(response.body);
        _lastFetchAt = DateTime.now();
        _lastError = null;
      } else {
        _lastError = 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      _lastError = e.toString();
      debugPrint('JmaAlertService: 取得失敗 $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Atom XML パーサー（RegExp ベース）
  // ---------------------------------------------------------------------------

  static final _entryRe = RegExp(r'<entry>([\s\S]*?)</entry>');
  static final _titleRe = RegExp(r'<title[^>]*>([\s\S]*?)</title>');
  static final _updatedRe = RegExp(r'<updated>([\s\S]*?)</updated>');
  static final _linkRe =
      RegExp(r'<link[^>]*href="([^"]*)"[^>]*/?>');

  List<JmaAlert> _parseAtomFeed(String xml) {
    final results = <JmaAlert>[];

    for (final match in _entryRe.allMatches(xml)) {
      final block = match.group(1) ?? '';

      final titleMatch = _titleRe.firstMatch(block);
      final updatedMatch = _updatedRe.firstMatch(block);
      final linkMatch = _linkRe.firstMatch(block);

      final title = titleMatch?.group(1)?.trim() ?? '';
      final updatedStr = updatedMatch?.group(1)?.trim() ?? '';
      final linkUrl = linkMatch?.group(1)?.trim() ?? '';

      // 緊急地震速報・津波のみ抽出
      final isEq = title.contains('緊急地震速報');
      final isTsu = title.contains('津波');
      if (!isEq && !isTsu) continue;

      DateTime? updatedAt;
      try {
        updatedAt = DateTime.parse(updatedStr);
      } catch (_) {
        updatedAt = DateTime.now();
      }

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
