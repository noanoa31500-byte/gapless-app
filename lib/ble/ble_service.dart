import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../services/device_id_service.dart';
import 'ble_packet.dart';
import 'ble_peripheral_channel.dart';
import 'ble_repository.dart';

// ============================================================================
// BleService — BLE スキャン・アドバタイズ統合サービス
// ============================================================================
//
// Service UUID  : 6E400001-B5A3-F393-E0A9-E50E24DCCA9E (Nordic UART Service)
// Char UUID     : 6E400003-B5A3-F393-E0A9-E50E24DCCA9E (RX Notify)
//
// 【省電力モード】
//   バッテリー20%以下を検出したら自動で省電力モードに切り替わる。
//   通常: スキャン 5 秒間隔
//   省電力: スキャン 30 秒間隔
//
// 【アドバタイズ】
//   flutter_blue_plus 1.x は iOS でペリフェラルAPIを提供しないため、
//   スキャン発見 → GATT接続 → Characteristic 読み取りの形で実装する。
//   アドバタイズ側は将来 CoreBluetooth ネイティブプラグインで拡張可能。
//
// ============================================================================

class BleService extends ChangeNotifier {
  static final BleService instance = BleService._();
  BleService._();

  // ── GATT UUID ────────────────────────────────────────────────────────────
  static final Guid _serviceUuid = Guid('6E400001-B5A3-F393-E0A9-E50E24DCCA9E');
  static final Guid _rxCharUuid = Guid('6E400003-B5A3-F393-E0A9-E50E24DCCA9E');

  // ── スキャン間隔 ─────────────────────────────────────────────────────────
  static const Duration _normalScanInterval = Duration(seconds: 5);
  static const Duration _savingScanInterval = Duration(seconds: 30);
  static const int _batteryThreshold = 20; // 省電力閾値 (%)

  // ── 状態 ─────────────────────────────────────────────────────────────────
  bool _isRunning = false;
  bool _isSavingMode = false;
  int _receivedCount = 0;
  bool _disposed = false;

  bool get isRunning => _isRunning;
  bool get isSavingMode => _isSavingMode;
  int get receivedCount => _receivedCount;

  // ── 内部 ─────────────────────────────────────────────────────────────────
  StreamSubscription<List<ScanResult>>? _scanResultSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<BatteryState>? _batterySub;
  Timer? _scanTimer;
  Timer? _batteryCheckTimer;

  final Set<DeviceIdentifier> _connecting = {};
  // 重複排除: "deviceId:timestamp"
  final Set<String> _seenPackets = {};

  Duration get _scanInterval =>
      _isSavingMode ? _savingScanInterval : _normalScanInterval;

  // ── 送信キュー（直近10件） ────────────────────────────────────────────────
  final List<BlePacket> _sendQueue = [];

  void enqueue(BlePacket packet) {
    _sendQueue.add(packet);
    if (_sendQueue.length > 10) {
      _sendQueue.removeAt(0);
    }
    // ネイティブペリフェラル経由でアドバタイズ中の Characteristic を更新
    final bytes = packet.toBytes();
    BlePeripheralChannel.instance.updateData(bytes);
  }

  // ---------------------------------------------------------------------------
  // ライフサイクル
  // ---------------------------------------------------------------------------

  Future<void> start() async {
    if (_isRunning) return;
    _isRunning = true;

    // バッテリー監視
    await _checkBattery();
    _batteryCheckTimer =
        Timer.periodic(const Duration(minutes: 5), (_) => _checkBattery());
    _batterySub =
        Battery().onBatteryStateChanged.listen((_) => _checkBattery());

    // BLE アダプタ監視
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        _scheduleScan();
      } else {
        _scanTimer?.cancel();
        debugPrint('🔵 BleService: アダプタ OFF');
      }
    });

    final state = await FlutterBluePlus.adapterState.first;
    if (state == BluetoothAdapterState.on) {
      await BlePeripheralChannel.instance.startAdvertising();
      await _runScan();
      _scheduleScan();
    }

    notifyListeners();
    debugPrint('🔵 BleService: 開始 (省電力=$_isSavingMode)');
  }

  Future<void> stop() async {
    _isRunning = false;
    _scanTimer?.cancel();
    _batteryCheckTimer?.cancel();
    _scanResultSub?.cancel();
    _adapterSub?.cancel();
    _batterySub?.cancel();
    _scanResultSub = null;
    await FlutterBluePlus.stopScan();
    await BlePeripheralChannel.instance.stopAdvertising();
    _connecting.clear();
    if (!_disposed) notifyListeners();
    debugPrint('🔵 BleService: 停止');
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 省電力モード
  // ---------------------------------------------------------------------------

  Future<void> _checkBattery() async {
    try {
      final level = await Battery().batteryLevel;
      final saving = level <= _batteryThreshold;
      if (saving != _isSavingMode) {
        _isSavingMode = saving;
        // スキャン間隔を即時適用
        if (_isRunning) {
          _scanTimer?.cancel();
          _scheduleScan();
        }
        notifyListeners();
        debugPrint('🔵 BleService: 省電力モード → $saving (battery $level%)');
      }
    } catch (e) {
      debugPrint('🔵 BleService: バッテリー取得失敗 $e');
    }
  }

  // ---------------------------------------------------------------------------
  // スキャン
  // ---------------------------------------------------------------------------

  void _scheduleScan() {
    _scanTimer?.cancel();
    _scanTimer = Timer(_scanInterval, () async {
      if (_isRunning) {
        await _runScan();
        _scheduleScan();
      }
    });
  }

  Future<void> _runScan() async {
    if (!_isRunning) return;
    debugPrint('🔵 BleService: スキャン開始 (interval=$_scanInterval)');

    try {
      await FlutterBluePlus.startScan(
        withServices: [_serviceUuid],
        timeout: const Duration(seconds: 4),
      );
    } catch (e) {
      debugPrint('🔵 BleService: スキャン開始失敗 $e');
      return;
    }

    _scanResultSub?.cancel();
    _scanResultSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        if (!_connecting.contains(r.device.remoteId)) {
          _connecting.add(r.device.remoteId);
          _readFromPeer(r.device);
        }
      }
    });
  }

  // ---------------------------------------------------------------------------
  // GATT 接続 → Characteristic 読み取り
  // ---------------------------------------------------------------------------

  Future<void> _readFromPeer(BluetoothDevice device) async {
    try {
      await device.connect(
          license: License.free, timeout: const Duration(seconds: 6));

      final services = await device.discoverServices();
      BluetoothService? target;
      for (final s in services) {
        if (s.serviceUuid == _serviceUuid) {
          target = s;
          break;
        }
      }
      if (target == null) {
        await device.disconnect();
        return;
      }

      BluetoothCharacteristic? rxChar;
      for (final c in target.characteristics) {
        if (c.characteristicUuid == _rxCharUuid) {
          rxChar = c;
          break;
        }
      }
      if (rxChar == null) {
        await device.disconnect();
        return;
      }

      // Notify 購読
      if (rxChar.properties.notify) {
        await rxChar.setNotifyValue(true);
        final sub = rxChar.lastValueStream.listen(_handleBytes);
        await Future.delayed(const Duration(seconds: 2));
        sub.cancel();
      } else if (rxChar.properties.read) {
        final bytes = await rxChar.read();
        _handleBytes(bytes);
      }

      await device.disconnect();
    } catch (e) {
      debugPrint('🔵 BleService: ピア接続エラー (${device.remoteId}) $e');
      try {
        await device.disconnect();
      } catch (_) {}
    } finally {
      _connecting.remove(device.remoteId);
    }
  }

  // ---------------------------------------------------------------------------
  // 受信データ処理
  // ---------------------------------------------------------------------------

  void _handleBytes(List<int> rawBytes) {
    if (rawBytes.isEmpty) return;
    final packet = BlePacket.fromBytes(Uint8List.fromList(rawBytes));
    if (packet == null) return;

    // 自端末のパケットは無視
    final myId = DeviceIdService.instance.deviceId;
    if (myId != null && packet.senderDeviceId == myId) return;

    // 重複排除
    final key = '${packet.senderDeviceId}:${packet.timestamp}';
    if (_seenPackets.contains(key)) return;
    _seenPackets.add(key);
    // メモリ上限（10,000件）
    if (_seenPackets.length > 10000) _seenPackets.clear();

    BleRepository.instance.insert(packet).then((_) {
      _receivedCount++;
      if (!_disposed) notifyListeners();
      debugPrint('🔵 BleService: 受信 $packet');
    });
  }
}
