import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:latlong2/latlong.dart';
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

  static String _truncateId(String id) =>
      id.length > 8 ? id.substring(0, 8) : id;

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
    final deviceId = DeviceIdService.instance.deviceId ?? 'unknown';
    final report = ShelterStatusReport(
      shelterId: shelter.id,
      lat: shelter.lat,
      lng: shelter.lng,
      isOccupied: isOccupied,
      timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      deviceId: _truncateId(deviceId),
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
    final deviceId =
        DeviceIdService.instance.deviceId ?? 'unknown';
    final reportId =
        DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final report = PeerRoadReport.create(
      reportId: reportId,
      deviceId: deviceId,
      lat: lat,
      lng: lng,
      accuracyM: accuracyM,
      passable: passable,
      isDrActive: isDrActive,
      drErrorM: drErrorM,
    );
    _queue.add(report);
    scorer.addReport(report); // 自端末のスコアにも即時反映
    debugPrint('BleRoadReportService: enqueued $report');
  }

  /// SOSビーコンをキューに積む（長押しボタンから呼ぶ）
  void enqueueSos({required double lat, required double lng}) {
    final deviceId = DeviceIdService.instance.deviceId ?? 'unknown';
    final report = SosReport.create(deviceId: deviceId, lat: lat, lng: lng);
    _sosQueue.add(report);
    debugPrint('BleRoadReportService: SOS enqueued @ $lat/$lng');
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
    final deviceId = DeviceIdService.instance.deviceId ?? 'unknown';
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final packet = BlePacket(
      senderDeviceId: deviceId,
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

    debugPrint('BleRoadReportService: enqueueFullReport $dataType @ $lat/$lng');
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

    final deviceId = DeviceIdService.instance.deviceId ?? 'unknown';
    _pendingTrack = GpsTrackSnapshot(
      deviceId: _truncateId(deviceId),
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
    try {
      final lines = utf8.decode(bytes, allowMalformed: true).split('\n');
      final reports = <PeerRoadReport>[];

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        try {
          final json = jsonDecode(trimmed) as Map<String, dynamic>;
          final type = json['type'] as String?;
          if (type == 'sos') {
            // SOSビーコン
            final sos = SosReport.fromJson(json);
            if (!sos.isExpired) {
              final alreadyKnown = _receivedSos.any((r) =>
                  r.deviceId == sos.deviceId &&
                  (r.timestamp - sos.timestamp).abs() < 60);
              if (!alreadyKnown && _receivedSos.length < _maxReceivedSos) {
                _receivedSos.add(sos);
                _receivedSosCount++;
                debugPrint('BleRoadReportService: SOS 受信 ${sos.deviceId} @ ${sos.lat}/${sos.lng}');
              }
            }
          } else if (type == 'sh') {
            // 避難所ステータスレポート
            final sr = ShelterStatusReport.fromJson(json);
            if (!sr.isExpired &&
                (_shelterStatuses.containsKey(sr.shelterId) ||
                    _shelterStatuses.length < _maxShelterStatuses)) {
              _shelterStatuses[sr.shelterId] = sr;
            }
          } else if (type == 'tr') {
            // GPS軌跡スナップショット
            final snap = GpsTrackSnapshot.fromJson(json);
            // 既存ピアの更新は常に許可、新規ピアはキャップ内のみ
            if (!snap.isExpired && snap.points.length >= 2 &&
                (_peerTracks.containsKey(snap.deviceId) ||
                    _peerTracks.length < _maxPeerTracks)) {
              _peerTracks[snap.deviceId] = snap;
            }
          } else {
            // 道路通行可否レポート
            final report = PeerRoadReport.fromCompactJson(json);
            if (!report.isExpired) reports.add(report);
          }
        } catch (e) {
          debugPrint('BleRoadReportService: パース失敗 "$trimmed": $e');
        }
      }

      if (reports.isNotEmpty) {
        scorer.addReports(reports);
        _receivedCount += reports.length;
        // 再起動後も利用できるよう DB に永続化（重複はDBの UNIQUE 制約で無視）
        final myDeviceId = DeviceIdService.instance.deviceId ?? '';
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

          // メッシュリレー: 自端末以外の報告かつホップ上限未満なら次ピアへ中継
          final myId8 = _truncateId(myDeviceId);
          if (r.deviceId != myId8 && r.hops < _maxRelayHops &&
              _relayQueue.length < _maxRelayQueue) {
            _relayQueue.add(r.withNextHop());
          }
        }
        debugPrint(
            'BleRoadReportService: ${reports.length}件 受信, 合計=$_receivedCount, リレーキュー=${_relayQueue.length}');
      }
      notifyListeners();
    } catch (e) {
      debugPrint('BleRoadReportService: 受信処理エラー $e');
    }
  }
}
