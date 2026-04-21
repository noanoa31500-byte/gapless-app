import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path_provider/path_provider.dart';
import 'power_manager.dart';

// ============================================================================
// GpsLogger — 全GPSログの時系列保存 & バックトラック機能
// ============================================================================
//
// 【ログ形式】CSV（1行 = 1点）:
//   UNIXタイムスタンプ(秒),緯度,経度,精度(m),速度(m/s)
//   例: 1741000000,35.68950,139.75000,5.0,0.80
//
// 【省電力モードとの連携】
//   PowerManager.gpsIntervalSec が変わるとログ取得間隔も追随する。
//
// 【バックトラック】
//   backtrackRoute() が呼ばれると記録済み軌跡を逆順にした
//   List<LatLng> を返す。これを SafetyRouteEngine や RouteBearingView に渡す。
//
// ============================================================================

/// 1つのGPSログエントリ
class GpsLogEntry {
  final int timestamp; // UNIXタイムスタンプ（秒）
  final double lat;
  final double lng;
  final double accuracyM;
  final double speedMps;

  const GpsLogEntry({
    required this.timestamp,
    required this.lat,
    required this.lng,
    required this.accuracyM,
    required this.speedMps,
  });

  String toCsvLine() =>
      '$timestamp,${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)},'
      '${accuracyM.toStringAsFixed(1)},${speedMps.toStringAsFixed(2)}';

  factory GpsLogEntry.fromCsvLine(String line) {
    final parts = line.split(',');
    return GpsLogEntry(
      timestamp: int.parse(parts[0]),
      lat: double.parse(parts[1]),
      lng: double.parse(parts[2]),
      accuracyM: double.parse(parts[3]),
      speedMps: double.parse(parts[4]),
    );
  }

  LatLng get latLng => LatLng(lat, lng);
}

class GpsLogger extends ChangeNotifier {
  static final GpsLogger instance = GpsLogger._();
  GpsLogger._();

  // ── 状態 ──────────────────────────────────────────────────
  bool _isLogging = false;
  int _loggedCount = 0;
  bool _disposed = false;

  bool get isLogging => _isLogging;
  int get loggedCount => _loggedCount;

  // ── 内部 ──────────────────────────────────────────────────
  StreamSubscription<Position>? _positionSub;
  IOSink? _logSink;
  File? _logFile;
  DateTime? _sessionStart;

  // インメモリバッファ（バックトラック & 範囲外判定に使用）
  final List<GpsLogEntry> _buffer = [];

  // 直近 N 点のみインメモリに保持（メモリ節約）
  static const int _maxBufferSize = 1000;

  /// インメモリバッファの最新エントリ（null = ロギング前）
  GpsLogEntry? get latestEntry => _buffer.isNotEmpty ? _buffer.last : null;

  /// インメモリバッファ全体の読み取り専用ビュー（行動分析用）
  List<GpsLogEntry> get recentEntries => List.unmodifiable(_buffer);

  // ---------------------------------------------------------------------------
  // ライフサイクル
  // ---------------------------------------------------------------------------

  /// GPS ロギングを開始する
  ///
  /// [powerManager] が提供する間隔を動的に追随する
  Future<void> startLogging() async {
    if (_isLogging) return;
    _isLogging = true;
    _sessionStart = DateTime.now();

    // ログファイルを開く（追記モード）
    _logFile = await _openLogFile();
    _logSink = _logFile!.openWrite(mode: FileMode.append);

    // セパレータを書いて新セッション開始を明示
    _logSink!.writeln('# session_start ${_sessionStart!.toIso8601String()}');

    _startStream();
    debugPrint('GpsLogger: ロギング開始 → ${_logFile!.path}');
    notifyListeners();
  }

  /// GPS ロギングを停止する
  Future<void> stopLogging() async {
    if (!_isLogging) return;
    _isLogging = false;
    _positionSub?.cancel();
    _positionSub = null;
    await _logSink?.flush();
    await _logSink?.close();
    _logSink = null;
    debugPrint('GpsLogger: ロギング停止 (total=$_loggedCount)');
    if (!_disposed) notifyListeners();
  }

  /// PowerManager の間隔変更に追随して位置ストリームを再起動
  void onGpsIntervalChanged(int intervalSec) {
    if (!_isLogging) return;
    _positionSub?.cancel();
    _startStream(intervalSec: intervalSec);
    debugPrint('GpsLogger: GPS間隔 → ${intervalSec}秒');
  }

  @override
  void dispose() {
    _disposed = true;
    _isLogging = false;
    _positionSub?.cancel();
    _positionSub = null;
    _logSink?.flush().then((_) => _logSink?.close());
    _logSink = null;
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // バックトラック
  // ---------------------------------------------------------------------------

  /// 記録済み軌跡を逆順で返す（バックトラック案内用）
  ///
  /// インメモリバッファが不足する場合はログファイルから読み込む
  Future<List<LatLng>> backtrackRoute() async {
    List<GpsLogEntry> entries;

    if (_buffer.isNotEmpty) {
      entries = List.from(_buffer);
    } else {
      entries = await _loadFromFile();
    }

    if (entries.isEmpty) return [];

    // 5m 以上離れた点のみ残す（重複点を間引いてルートをシンプルに）
    final filtered = _decimateByDistance(entries, minDistanceM: 5.0);
    return filtered.reversed.map((e) => e.latLng).toList();
  }

  /// 現在のバックトラックルート（軽量版: バッファから即時）
  List<LatLng> backtrackRouteFromBuffer() {
    if (_buffer.isEmpty) return [];
    final filtered = _decimateByDistance(_buffer, minDistanceM: 5.0);
    return filtered.reversed.map((e) => e.latLng).toList();
  }

  // ---------------------------------------------------------------------------
  // ログファイル管理
  // ---------------------------------------------------------------------------

  Future<File> _openLogFile() async {
    final dir = await getApplicationSupportDirectory();
    final dateStr = DateTime.now().toIso8601String().substring(0, 10);
    return File('${dir.path}/gps_log_$dateStr.csv');
  }

  Future<List<GpsLogEntry>> _loadFromFile() async {
    try {
      final file = await _openLogFile();
      if (!await file.exists()) return [];

      final lines = await file.readAsLines();
      final entries = <GpsLogEntry>[];
      for (final line in lines) {
        if (line.startsWith('#') || line.trim().isEmpty) continue;
        try {
          entries.add(GpsLogEntry.fromCsvLine(line));
        } catch (_) {}
      }
      return entries;
    } catch (e) {
      debugPrint('GpsLogger: ファイル読み込みエラー $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // GPS ストリーム
  // ---------------------------------------------------------------------------

  void _startStream({int? intervalSec}) {
    final interval = intervalSec ?? PowerManager.instance.gpsIntervalSec;

    final settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      timeLimit: Duration(seconds: interval * 2),
    );

    _positionSub = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      _onPosition,
      onError: (Object e) {
        debugPrint('GpsLogger: GPS エラー $e');
      },
    );
  }

  void _onPosition(Position pos) {
    final entry = GpsLogEntry(
      timestamp: pos.timestamp.millisecondsSinceEpoch ~/ 1000,
      lat: pos.latitude,
      lng: pos.longitude,
      accuracyM: pos.accuracy,
      speedMps: pos.speed.clamp(0.0, double.infinity),
    );

    // ファイル書き込み
    _logSink?.writeln(entry.toCsvLine());
    _loggedCount++;

    // インメモリバッファ（一定サイズを超えたら先頭を捨てる）
    _buffer.add(entry);
    if (_buffer.length > _maxBufferSize) {
      _buffer.removeAt(0);
    }

    if (!_disposed) notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // ユーティリティ
  // ---------------------------------------------------------------------------

  List<GpsLogEntry> _decimateByDistance(List<GpsLogEntry> entries,
      {required double minDistanceM}) {
    if (entries.isEmpty) return [];

    const dist = Distance();
    final result = [entries.first];

    for (int i = 1; i < entries.length; i++) {
      final d = dist(result.last.latLng, entries[i].latLng);
      if (d >= minDistanceM) result.add(entries[i]);
    }
    return result;
  }
}
