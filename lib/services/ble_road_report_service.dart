import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:latlong2/latlong.dart';
import 'dart:collection';
import 'device_id_service.dart';
import 'power_manager.dart';
import 'road_report_scorer.dart';
import '../ble/ble_packet.dart';
import '../ble/ble_repository.dart';
import '../models/peer_road_report.dart';
import '../models/shelter_status_report.dart';
import '../models/shelter.dart';
import '../models/gps_track_snapshot.dart';
import '../models/sos_report.dart';
import 'gps_logger.dart';

// ============================================================================
// BleRoadReportService — BLEすれ違い通信による道路通行可否データ交換
// ============================================================================
//
// 【GATT 構成】（既存 BleSyncService と同一サービス UUID、別キャラクタリスティック）
//   Service UUID     : 4b474150-4c45-5353-0001-000000000001  (GapLess共通)
//   Char TX Road     : ...0004  セントラルが書き込む（通行可否レポート）
//   Char RX Road     : ...0005  ペリフェラルからNotify
//
// 【省電力モードとの連携】
//   setSavingMode(true) → スキャン間隔を 30 秒 → 3 分に延長
//
// ============================================================================

/// 偽SOSスパム検出のために送信元の最終位置を保持
class _SosOriginRecord {
  final double lat;
  final double lng;
  final int timestamp; // sec
  const _SosOriginRecord(this.lat, this.lng, this.timestamp);
}

class BleRoadReportService extends ChangeNotifier {
  static final BleRoadReportService instance = BleRoadReportService._();
  BleRoadReportService._();

  static final Guid _serviceUuid =
      Guid('4b474150-4c45-5353-0001-000000000001');
  static final Guid _txRoadCharUuid =
      Guid('4b474150-4c45-5353-0001-000000000004');
  static final Guid _rxRoadCharUuid =
      Guid('4b474150-4c45-5353-0001-000000000005');

  static const Duration _normalScanInterval = Duration(seconds: 30);
  static const Duration _savingScanInterval = Duration(minutes: 3);
  Duration _currentScanInterval = _normalScanInterval;

  // ── 状態 ──────────────────────────────────────────────────
  bool _isRunning = false;
  int _receivedCount = 0;

  bool get isRunning => _isRunning;
  int get receivedCount => _receivedCount;

  // ── 内部変数 ───────────────────────────────────────────────
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  Timer? _scanTimer;
  final Set<DeviceIdentifier> _pendingConnect = {};
  final Set<DeviceIdentifier> _connected = {};

  /// 送信待ち道路レポートのキュー
  final List<PeerRoadReport> _queue = [];

  /// 送信待ち避難所ステータスキュー
  final List<ShelterStatusReport> _shelterQueue = [];

  /// 送信待ちSOSキュー
  final List<SosReport> _sosQueue = [];

  /// 受信済みSOSレポート（地図マーカー表示用）
  final List<SosReport> _receivedSos = [];

  /// 受信済みSOSの数（UI側でカウント変化を検知してTTS/ハプティクスをトリガーする）
  int _receivedSosCount = 0;

  List<SosReport> get receivedSosReports => List.unmodifiable(_receivedSos);
  int get receivedSosCount => _receivedSosCount;

  /// 受信した避難所ステータス (shelterId → report)
  final Map<String, ShelterStatusReport> _shelterStatuses = {};

  /// シェルター位置の参照テーブル（ID → 座標）。距離検証で使用。
  /// ShelterProvider#loadShelters 完了時に setKnownShelters() で投入する。
  final Map<String, LatLng> _knownShelterLocations = {};

  /// 「報告者がそのシェルターから半径 [m] 以内にいた」と要求する閾値。
  /// なりすまし「満員」報告をフィルタ。
  static const double _shelterReportMaxDistanceM = 500.0;

  /// テスト専用: 内部状態を初期化する。
  @visibleForTesting
  void debugReset() {
    _receivedSos.clear();
    _receivedSosCount = 0;
    _shelterStatuses.clear();
    _knownShelterLocations.clear();
    _sosCellLastTs.clear();
    _sosOriginByDevice.clear();
  }

  /// テスト専用: SOS 受信処理の入口。
  @visibleForTesting
  void debugIngestSos(Map<String, dynamic> json) => _ingestSos(json);

  /// テスト専用: シェルター受信処理の入口。
  @visibleForTesting
  void debugIngestShelter(Map<String, dynamic> json) => _ingestShelter(json);

  /// シェルター位置を更新（ShelterProvider から呼ぶ）。
  void setKnownShelters(Iterable<Shelter> shelters) {
    _knownShelterLocations
      ..clear()
      ..addEntries(shelters.map((s) => MapEntry(s.id, LatLng(s.lat, s.lng))));
  }

  /// スコアリングエンジン
  final RoadReportScorer scorer = RoadReportScorer();

  /// 受信済み避難所ステータスの読み取り専用ビュー
  Map<String, ShelterStatusReport> get shelterStatuses =>
      Map.unmodifiable(_shelterStatuses);

  static const int _maxRelayHops = 3;
  static const int _maxReceivedSos = 200;
  static const int _maxPeerTracks = 100;
  static const int _maxRelayQueue = 100;
  static const int _maxShelterStatuses = 500;
  final List<PeerRoadReport> _relayQueue = [];

  /// 送信待ちGPS軌跡（交換ごとに直前の軌跡を1件だけ送る）
  GpsTrackSnapshot? _pendingTrack;

  /// 受信したピアの軌跡 (deviceId → snapshot)
  final Map<String, GpsTrackSnapshot> _peerTracks = {};

  /// 受信済みピア軌跡の読み取り専用ビュー
  Map<String, GpsTrackSnapshot> get peerTracks =>
      Map.unmodifiable(_peerTracks);

  /// iOS バックグラウンドタスク延長用チャンネル（Android では未使用）
  static const _bgTaskChannel = MethodChannel('gapless/bg_task');

  /// BLE発信に使う短命ローテーションID（1時間ごとに変わる）
  String _outgoingBleId() => DeviceIdService.instance.ephemeralBleId;

  /// 偽SOSスパム対策用 LRU: deviceId → (lat, lng, timestamp)
  /// 同 deviceId が 1分以内に 10km 超移動した場合は drop。
  final LinkedHashMap<String, _SosOriginRecord> _sosOriginByDevice =
      LinkedHashMap<String, _SosOriginRecord>();
  static const double _maxSosJumpMetersPerMinute = 10000.0;

  /// 100m グリッドキー → 直近 SOS 受信時刻（UNIX秒）
  /// deviceId ローテートでスパムする攻撃をフィルタするため。
  final LinkedHashMap<String, int> _sosCellLastTs = LinkedHashMap<String, int>();
  static const int _maxSosCells = 1024;

  /// 受信PII最小化: lat/lng は小数2桁(≈1km)に丸めてログ出力
  String _redactGeo(double lat, double lng) =>
      '${lat.toStringAsFixed(2)}/${lng.toStringAsFixed(2)}';

  void _logDrop(String reason, [String? detail]) {
    if (kReleaseMode) return;
    debugPrint('BleRoadReportService: drop[$reason]'
        '${detail != null ? ' $detail' : ''}');
  }

  // ---------------------------------------------------------------------------
  // ライフサイクル
  // ---------------------------------------------------------------------------

  Future<void> start() async {
    if (_isRunning) return;

    // iOS: CBCentralManager 初期化前に状態復元オプションを有効化
    // アプリがBLEイベントで再起動された際、既存接続・スキャン状態が復元される
    if (Platform.isIOS) {
      await FlutterBluePlus.setOptions(restoreState: true);
    }

    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        _scheduleScan();
      } else {
        _isRunning = false;
        notifyListeners();
      }
    });

    final state = await FlutterBluePlus.adapterState.first;
    if (state == BluetoothAdapterState.on) {
      _isRunning = true;
      await _runScan();
    }
  }

  Future<void> stop() async {
    _isRunning = false;
    _scanTimer?.cancel();
    _scanSub?.cancel();
    _adapterSub?.cancel();
    await FlutterBluePlus.stopScan();
    _pendingConnect.clear();
    _connected.clear();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 省電力連携
  // ---------------------------------------------------------------------------

  void setSavingMode(bool saving) {
    _currentScanInterval =
        saving ? _savingScanInterval : _normalScanInterval;
    _scanTimer?.cancel();
    if (_isRunning) _scheduleScan();
    debugPrint('BleRoadReportService: scan interval → $_currentScanInterval');
  }

  /// PowerManager の多段階モードに対応したスキャン間隔更新
  void setPowerMode(PowerMode mode) {
    _currentScanInterval = switch (mode) {
      PowerMode.normal    => PowerManager.bleScanNormal,
      PowerMode.reduced   => PowerManager.bleScanReduced,
      PowerMode.saving    => PowerManager.bleScanSaving,
      PowerMode.ultra     => PowerManager.bleScanUltra,
      PowerMode.emergency => PowerManager.bleScanEmergency,
    };
    _scanTimer?.cancel();
    if (_isRunning) _scheduleScan();
    debugPrint('BleRoadReportService: power mode $mode → interval $_currentScanInterval');
  }

  // ---------------------------------------------------------------------------
  // 避難所ステータス
  // ---------------------------------------------------------------------------

  /// 自端末が避難所に到着したことをキューに積む（BLEすれ違い時に周囲へ伝播）
  void enqueueShelterStatus(Shelter shelter, {bool isOccupied = true}) {
    final report = ShelterStatusReport(
      shelterId: shelter.id,
      lat: shelter.lat,
      lng: shelter.lng,
      isOccupied: isOccupied,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      deviceId: _outgoingBleId(),
    );
    _shelterQueue.add(report);
    _shelterStatuses[shelter.id] = report;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // レポート送信キューへの追加
  // ---------------------------------------------------------------------------

  /// 自端末のレポートをキューに積む
  void enqueueReport({
    required double lat,
    required double lng,
    required double accuracyM,
    required bool passable,
    bool isDrActive = false,
    double drErrorM = 0.0,
  }) {
    final reportId =
        DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final report = PeerRoadReport.create(
      reportId: reportId,
      deviceId: _outgoingBleId(),
      lat: lat,
      lng: lng,
      accuracyM: accuracyM,
      passable: passable,
      isDrActive: isDrActive,
      drErrorM: drErrorM,
    );
    _queue.add(report);
    scorer.addReport(report); // 自端末のスコアにも即時反映
    if (!kReleaseMode) {
      debugPrint('BleRoadReportService: enqueued report '
          '(seg=${report.segmentId}, status=${report.status})');
    }
  }

  /// SOSビーコンをキューに積む（長押しボタンから呼ぶ）
  void enqueueSos({required double lat, required double lng}) {
    if (!BlePacket.isValidGeo(lat, lng)) {
      _logDrop('local_sos_invalid_geo');
      return;
    }
    final report =
        SosReport.create(deviceId: _outgoingBleId(), lat: lat, lng: lng);
    _sosQueue.add(report);
    if (!kReleaseMode) {
      debugPrint('BleRoadReportService: SOS enqueued @ ${_redactGeo(lat, lng)}');
    }
  }

  /// 受信済みSOSのうち期限切れを除去
  void purgeSos() {
    _receivedSos.removeWhere((r) => r.isExpired);
  }

  /// 全dataType対応の報告（クイック報告から呼ぶ）
  /// BleRepositoryに永続化し、スコアにも即時反映する
  Future<void> enqueueFullReport({
    required double lat,
    required double lng,
    required double accuracyM,
    required BleDataType dataType,
    String payload = '',
    bool isDrActive = false,
    double drErrorM = 0.0,
  }) async {
    final deviceId = _outgoingBleId();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final packet = BlePacket(
      senderDeviceId: DeviceIdService.instance.deviceId ?? deviceId,
      timestamp: now,
      lat: lat,
      lng: lng,
      accuracyMeters: accuracyM,
      dataType: dataType,
      payload: payload,
    );

    // DB に永続化
    await BleRepository.instance.insert(packet);

    // 通行可 / 通行不可 はスコアにも即時反映
    if (dataType == BleDataType.passable || dataType == BleDataType.blocked) {
      final reportId = now.toRadixString(16);
      final report = PeerRoadReport.create(
        reportId: reportId,
        deviceId: deviceId,
        lat: lat,
        lng: lng,
        accuracyM: accuracyM,
        passable: dataType == BleDataType.passable,
        isDrActive: isDrActive,
        drErrorM: drErrorM,
      );
      _queue.add(report);
      scorer.addReport(report);
    }

    if (!kReleaseMode) {
      debugPrint('BleRoadReportService: enqueueFullReport $dataType @ '
          '${_redactGeo(lat, lng)}');
    }
  }

  // ---------------------------------------------------------------------------
  // BLEスキャン
  // ---------------------------------------------------------------------------

  void _scheduleScan() {
    _scanTimer?.cancel();
    _scanTimer = Timer(_currentScanInterval, () async {
      if (_isRunning) await _runScan();
      _scheduleScan();
    });
  }

  Future<void> _runScan() async {
    debugPrint('BleRoadReportService: スキャン開始');
    await FlutterBluePlus.startScan(
      withServices: [_serviceUuid],
      timeout: const Duration(seconds: 10),
    );

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (!_connected.contains(r.device.remoteId) &&
            !_pendingConnect.contains(r.device.remoteId)) {
          _pendingConnect.add(r.device.remoteId);
          _exchangeWithPeer(r.device);
        }
      }
    });
  }

  // ---------------------------------------------------------------------------
  // GATT接続 & データ交換
  // ---------------------------------------------------------------------------

  Future<void> _exchangeWithPeer(BluetoothDevice device) async {
    // iOS: バックグラウンドでGATT交換が完了するまでの実行時間を確保（最大30秒）
    int _bgTaskId = -1;
    if (Platform.isIOS) {
      try {
        _bgTaskId =
            await _bgTaskChannel.invokeMethod<int>('begin') ?? -1;
      } catch (_) {}
    }

    try {
      await device.connect(timeout: const Duration(seconds: 8));
      _connected.add(device.remoteId);
      notifyListeners();

      final services = await device.discoverServices();
      BluetoothService? gaplessService;
      for (final s in services) {
        if (s.serviceUuid == _serviceUuid) {
          gaplessService = s;
          break;
        }
      }
      if (gaplessService == null) {
        await device.disconnect();
        return;
      }

      BluetoothCharacteristic? txChar;
      BluetoothCharacteristic? rxChar;
      for (final c in gaplessService.characteristics) {
        if (c.characteristicUuid == _txRoadCharUuid) txChar = c;
        if (c.characteristicUuid == _rxRoadCharUuid) rxChar = c;
      }

      // 受信 (Notify)
      if (rxChar != null && rxChar.properties.notify) {
        await rxChar.setNotifyValue(true);
        rxChar.lastValueStream.listen(_handleReceivedBytes);
      }

      // MTU を要求（失敗してもデフォルト値にフォールバック）
      int mtu = 180;
      try {
        mtu = await device.requestMtu(512);
        // ATT ヘッダ 3 バイトを除いたペイロード上限
        mtu = (mtu - 3).clamp(20, 512);
      } catch (_) {}

      // 送信 (Write) — 直前にGPS軌跡スナップショットを自動生成
      _autoEnqueueTrackSnapshot();
      if (txChar != null && txChar.properties.write &&
          (_queue.isNotEmpty || _relayQueue.isNotEmpty || _shelterQueue.isNotEmpty || _sosQueue.isNotEmpty || _pendingTrack != null)) {
        await _writeQueueToChar(txChar, chunkSize: mtu);
      }

      await Future.delayed(const Duration(seconds: 2));
      await device.disconnect();
    } catch (e) {
      debugPrint('BleRoadReportService: ピア交換エラー $e');
    } finally {
      _connected.remove(device.remoteId);
      _pendingConnect.remove(device.remoteId);
      // iOS: バックグラウンドタスクを終了してシステムリソースを解放
      if (Platform.isIOS && _bgTaskId >= 0) {
        try {
          await _bgTaskChannel.invokeMethod<void>('end', _bgTaskId);
        } catch (_) {}
      }
    }
  }

  /// BLE交換直前にGPSバッファから最新スナップショットを生成してセット
  void _autoEnqueueTrackSnapshot() {
    final entries = GpsLogger.instance.recentEntries;
    if (entries.length < 3) return;

    // 10m間隔に間引き・最新15点
    const minDistM = 10.0;
    const maxPts = 15;
    final dist = const Distance();
    final decimated = <GpsLogEntry>[entries.first];
    for (int i = 1; i < entries.length; i++) {
      if (dist(decimated.last.latLng, entries[i].latLng) >= minDistM) {
        decimated.add(entries[i]);
      }
    }
    final recent = decimated.length > maxPts
        ? decimated.sublist(decimated.length - maxPts)
        : decimated;

    _pendingTrack = GpsTrackSnapshot(
      deviceId: _outgoingBleId(),
      timestamp: recent.last.timestamp,
      points: recent
          .map((e) => GpsPoint(e.lat, e.lng, e.timestamp))
          .toList(),
    );
  }

  /// キュー内の全レポートを Characteristic に書き込み、送信済みをクリアする
  Future<void> _writeQueueToChar(BluetoothCharacteristic txChar, {int chunkSize = 180}) async {
    final toSend = List<PeerRoadReport>.from(_queue);
    _queue.clear();
    final relayToSend = List<PeerRoadReport>.from(_relayQueue);
    _relayQueue.clear();
    final shelterToSend = List<ShelterStatusReport>.from(_shelterQueue);
    _shelterQueue.clear();
    final sosToSend = List<SosReport>.from(_sosQueue);
    _sosQueue.clear();
    final track = _pendingTrack;
    _pendingTrack = null;

    final lines = [
      ...toSend.map((r) => r.toCompactJson()),
      ...relayToSend.map((r) => r.toCompactJson()),
      ...shelterToSend.map((r) => r.toCompactJson()),
      ...sosToSend.map((r) => r.toCompactJson()),
      if (track != null) track.toCompactJson(),
    ];
    if (lines.isEmpty) return;

    final bytes = utf8.encode(lines.join('\n'));
    for (int i = 0; i < bytes.length; i += chunkSize) {
      final end = (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
      await txChar.write(bytes.sublist(i, end), withoutResponse: false);
    }
  }

  // ---------------------------------------------------------------------------
  // 受信処理
  // ---------------------------------------------------------------------------

  void _handleReceivedBytes(List<int> bytes) {
    if (bytes.isEmpty) return;

    // payload長 ≤ 256バイト（仕様）。1パケット内に複数行が入る前提なので
    // 全体としては数KBもありうるが、明らかな巨大データはここで切る。
    if (bytes.length > 8 * 1024) {
      _logDrop('packet_too_large', 'len=${bytes.length}');
      return;
    }

    final String decoded;
    try {
      decoded = utf8.decode(bytes, allowMalformed: true);
    } catch (e) {
      _logDrop('utf8_decode_failed', '$e');
      return;
    }

    final lines = decoded.split('\n');
    final reports = <PeerRoadReport>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.length > BlePacket.maxPayloadBytes * 4) {
        _logDrop('line_too_large', 'len=${trimmed.length}');
        continue;
      }

      Map<String, dynamic> json;
      try {
        final raw = jsonDecode(trimmed);
        if (raw is! Map<String, dynamic>) {
          _logDrop('not_json_object');
          continue;
        }
        json = raw;
      } catch (e) {
        _logDrop('json_parse_failed', '$e');
        continue;
      }

      final type = json['type'] as String?;
      try {
        if (type == 'sos') {
          _ingestSos(json);
        } else if (type == 'sh') {
          _ingestShelter(json);
        } else if (type == 'tr') {
          _ingestTrack(json);
        } else {
          // README仕様: type=="r" が道路レポート。type欠落も後方互換で受ける。
          final report = PeerRoadReport.fromCompactJson(json);
          if (!_validateRoadReport(report)) continue;
          reports.add(report);
        }
      } on FormatException catch (e) {
        _logDrop('schema_violation', '${type ?? "?"}: ${e.message}');
      } catch (e) {
        _logDrop('ingest_error', '${type ?? "?"}: $e');
      }
    }

    if (reports.isNotEmpty) {
      scorer.addReports(reports);
      _receivedCount += reports.length;
      final myId8 = _outgoingBleId();
      for (final r in reports) {
        final packet = BlePacket(
          senderDeviceId: r.deviceId,
          timestamp: r.timestamp,
          lat: r.lat,
          lng: r.lng,
          accuracyMeters: r.accuracyM,
          dataType: r.passable ? BleDataType.passable : BleDataType.blocked,
          payload: '',
        );
        BleRepository.instance.insert(packet).catchError((_) {});

        if (r.deviceId != myId8 &&
            r.hops < _maxRelayHops &&
            _relayQueue.length < _maxRelayQueue) {
          _relayQueue.add(r.withNextHop());
        }
      }
      if (!kReleaseMode) {
        debugPrint('BleRoadReportService: ${reports.length}件 受信, '
            '合計=$_receivedCount, リレー=${_relayQueue.length}');
      }
    }
    notifyListeners();
  }

  // ── 受信検証ヘルパー ────────────────────────────────────────────────

  bool _validateRoadReport(PeerRoadReport r) {
    final reason = BlePacket.validateFields(
      lat: r.lat,
      lng: r.lng,
      timestamp: r.timestamp,
    );
    if (reason != null) {
      _logDrop('road_$reason');
      return false;
    }
    if (r.isExpired) {
      _logDrop('road_expired');
      return false;
    }
    return true;
  }

  void _ingestSos(Map<String, dynamic> json) {
    final sos = SosReport.fromJson(json); // throws FormatException
    final reason = BlePacket.validateFields(
      lat: sos.lat,
      lng: sos.lng,
      timestamp: sos.timestamp,
    );
    if (reason != null) {
      _logDrop('sos_$reason');
      return;
    }
    if (sos.isExpired) {
      _logDrop('sos_expired');
      return;
    }

    // 偽SOSスパム抑止 (1): 同 deviceId & 60秒未満
    final alreadyKnown = _receivedSos.any((r) =>
        r.deviceId == sos.deviceId &&
        (r.timestamp - sos.timestamp).abs() < 60);
    if (alreadyKnown) {
      _logDrop('sos_dup_recent');
      return;
    }

    // 偽SOSスパム抑止 (1.5): 同一 100m グリッドからの複数 SOS は 5分間に1件まで
    // (deviceId をローテートするスパム攻撃をフィルタ。
    //  100m は約 lat/lng 0.001 度。)
    final cellKey =
        '${(sos.lat * 1000).round()}_${(sos.lng * 1000).round()}';
    final lastCellTs = _sosCellLastTs[cellKey];
    if (lastCellTs != null && (sos.timestamp - lastCellTs).abs() < 300) {
      _logDrop('sos_cell_rate_limited');
      return;
    }
    _sosCellLastTs[cellKey] = sos.timestamp;
    if (_sosCellLastTs.length > _maxSosCells) {
      _sosCellLastTs.remove(_sosCellLastTs.keys.first);
    }

    // 偽SOSスパム抑止 (2): 1分以内に 10km 以上の異常飛躍
    final prev = _sosOriginByDevice[sos.deviceId];
    if (prev != null) {
      final dtSec = (sos.timestamp - prev.timestamp).abs();
      if (dtSec < 60) {
        final dist = const Distance()
            .as(LengthUnit.Meter, LatLng(prev.lat, prev.lng),
                LatLng(sos.lat, sos.lng));
        // 1分未満で10km超 → 物理的にありえない移動 = 偽装の可能性大
        if (dist > _maxSosJumpMetersPerMinute) {
          _logDrop('sos_impossible_jump', 'dist=${dist.toStringAsFixed(0)}m');
          return;
        }
      }
    }

    // LRU evict (最古を捨てる)
    while (_receivedSos.length >= _maxReceivedSos) {
      _receivedSos.removeAt(0);
    }

    _receivedSos.add(sos);
    _receivedSosCount++;

    // 送信元位置記録もLRU化
    if (_sosOriginByDevice.length >= _maxReceivedSos) {
      _sosOriginByDevice.remove(_sosOriginByDevice.keys.first);
    }
    _sosOriginByDevice[sos.deviceId] =
        _SosOriginRecord(sos.lat, sos.lng, sos.timestamp);

    if (!kReleaseMode) {
      debugPrint('BleRoadReportService: SOS 受信 ${sos.deviceId} @ '
          '${_redactGeo(sos.lat, sos.lng)}');
    }
  }

  void _ingestShelter(Map<String, dynamic> json) {
    final sr = ShelterStatusReport.fromJson(json); // throws FormatException
    final reason = BlePacket.validateFields(
      lat: sr.lat,
      lng: sr.lng,
      timestamp: sr.timestamp,
    );
    if (reason != null) {
      _logDrop('shelter_$reason');
      return;
    }
    if (sr.isExpired) {
      _logDrop('shelter_expired');
      return;
    }
    // 距離検証: 報告者がそのシェルター近傍 (≤500m) からの送信であることを要求。
    // 既知のシェルター ID のみ受理する（未知IDの自由な追加を防ぐ）。
    final knownLoc = _knownShelterLocations[sr.shelterId];
    if (knownLoc == null) {
      _logDrop('shelter_unknown_id');
      return;
    }
    final distM = const Distance().as(
      LengthUnit.Meter,
      knownLoc,
      LatLng(sr.lat, sr.lng),
    );
    if (distM > _shelterReportMaxDistanceM) {
      _logDrop('shelter_too_far_${distM.round()}m');
      return;
    }
    if (_shelterStatuses.containsKey(sr.shelterId) ||
        _shelterStatuses.length < _maxShelterStatuses) {
      _shelterStatuses[sr.shelterId] = sr;
    } else {
      _logDrop('shelter_capacity');
    }
  }

  void _ingestTrack(Map<String, dynamic> json) {
    final snap = GpsTrackSnapshot.fromJson(json);
    if (snap.isExpired || snap.points.length < 2) {
      _logDrop('track_invalid');
      return;
    }
    if (_peerTracks.containsKey(snap.deviceId) ||
        _peerTracks.length < _maxPeerTracks) {
      _peerTracks[snap.deviceId] = snap;
    } else {
      _logDrop('track_capacity');
    }
  }
}
