import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'device_id_service.dart';
import 'road_report_scorer.dart';
import '../ble/ble_packet.dart';
import '../ble/ble_repository.dart';
import '../models/peer_road_report.dart';

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

  /// 送信待ちレポートのキュー（フィールド名を _queue に統一）
  final List<PeerRoadReport> _queue = [];

  /// スコアリングエンジン
  final RoadReportScorer scorer = RoadReportScorer();

  // ---------------------------------------------------------------------------
  // ライフサイクル
  // ---------------------------------------------------------------------------

  Future<void> start() async {
    if (_isRunning) return;

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

  // ---------------------------------------------------------------------------
  // レポート送信キューへの追加
  // ---------------------------------------------------------------------------

  /// 自端末のレポートをキューに積む
  void enqueueReport({
    required double lat,
    required double lng,
    required double accuracyM,
    required bool passable,
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
    );
    _queue.add(report);
    scorer.addReport(report); // 自端末のスコアにも即時反映
    debugPrint('BleRoadReportService: enqueued $report');
  }

  /// 全dataType対応の報告（クイック報告から呼ぶ）
  /// BleRepositoryに永続化し、スコアにも即時反映する
  Future<void> enqueueFullReport({
    required double lat,
    required double lng,
    required double accuracyM,
    required BleDataType dataType,
    String payload = '',
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

      // 送信 (Write)
      if (txChar != null && txChar.properties.write && _queue.isNotEmpty) {
        await _writeQueueToChar(txChar);
      }

      await Future.delayed(const Duration(seconds: 2));
      await device.disconnect();
    } catch (e) {
      debugPrint('BleRoadReportService: ピア交換エラー $e');
    } finally {
      _connected.remove(device.remoteId);
      _pendingConnect.remove(device.remoteId);
    }
  }

  /// キュー内の全レポートを Characteristic に書き込む
  Future<void> _writeQueueToChar(BluetoothCharacteristic txChar) async {
    final payload = _queue.map((r) => r.toCompactJson()).join('\n');
    final bytes = utf8.encode(payload);
    const chunkSize = 180; // MTU 183 - 3 バイト ATTヘッダー
    for (int i = 0; i < bytes.length; i += chunkSize) {
      final end =
          (i + chunkSize < bytes.length) ? i + chunkSize : bytes.length;
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
          final report = PeerRoadReport.fromCompactJsonString(trimmed);
          if (!report.isExpired) reports.add(report);
        } catch (e) {
          debugPrint('BleRoadReportService: パース失敗 "$trimmed": $e');
        }
      }

      if (reports.isNotEmpty) {
        scorer.addReports(reports);
        _receivedCount += reports.length;
        notifyListeners();
        debugPrint(
            'BleRoadReportService: ${reports.length}件 受信, 合計=$_receivedCount');
      }
    } catch (e) {
      debugPrint('BleRoadReportService: 受信処理エラー $e');
    }
  }
}
