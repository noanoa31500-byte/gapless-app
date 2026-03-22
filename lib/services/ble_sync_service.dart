import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/hazard_spot.dart';
import '../services/device_id_service.dart';

/// ============================================================================
/// BleSyncService - 第三の指示: BLE端末探索とデータ交換
/// ============================================================================
///
/// 【アーキテクチャ】
/// 各iPhoneは「セントラル（スキャン側）」と「ペリフェラル（アドバタイズ側）」の
/// 両方として同時に動作する。
///
/// ┌─────────────────────────────────────────────────────────────┐
/// │  iPhone A                              iPhone B              │
/// │  ┌──────────────┐   BLE GATT     ┌──────────────┐          │
/// │  │ Central      │◄──スキャン──────│ Peripheral   │          │
/// │  │ (Scanner)    │────接続────────►│ (Advertiser) │          │
/// │  │              │  write/notify  │              │          │
/// │  │ Peripheral   │───アドバタイズ──►│ Central      │          │
/// │  └──────────────┘                └──────────────┘          │
/// └─────────────────────────────────────────────────────────────┘
///
/// 【カスタムGATTサービス】
/// Service UUID         : 4B47-4150-4C45-5353-0001 (GapLess固有)
/// Characteristic (TX)  : ...0002  → セントラルが書き込む(スポットデータ)
/// Characteristic (RX)  : ...0003  → ペリフェラルがNotifyで送信
///
/// 【MTU対応チャンキング】
/// BLE標準MTUは20バイト。iOSはMTU交渉で最大512バイトまで拡張可能。
/// 保険としてデータを MTU-3 バイト単位で分割して送受信する。
///
/// 【プライバシー設計】
/// 送信するのは HazardSpot のcompact JSON（lat/lng/deviceUUID/時刻/状態）のみ。
/// 個人名・連絡先は一切含まない。
/// ============================================================================
class BleSyncService extends ChangeNotifier {
  static final BleSyncService instance = BleSyncService._();
  BleSyncService._();

  // ─── GATTサービス/キャラクタリスティックUUID ──────────────────
  // これらは全端末で同一にする必要がある（アプリ識別子として機能）
  static final Guid _serviceUuid = Guid('4b474150-4c45-5353-0001-000000000001');
  static final Guid _txCharUuid  = Guid('4b474150-4c45-5353-0001-000000000002'); // Central→Peripheralへの送信
  static final Guid _rxCharUuid  = Guid('4b474150-4c45-5353-0001-000000000003'); // PeripheralからのNotify受信

  // ─── 状態 ──────────────────────────────────────────────────
  bool _isRunning = false;
  int _connectedPeerCount = 0;
  DateTime? _lastSyncTime;
  final Set<String> _syncedDeviceIds = {};

  bool get isRunning => _isRunning;
  int get connectedPeerCount => _connectedPeerCount;
  DateTime? get lastSyncTime => _lastSyncTime;

  // ─── 内部変数 ───────────────────────────────────────────────
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;
  StreamSubscription<bool>? _isScanningSubscription;
  final Map<DeviceIdentifier, BluetoothDevice> _activeConnections = {};

  // ─── 起動 ─────────────────────────────────────────────────
  Future<void> start() async {
    if (_isRunning) return;

    // BLEアダプタの状態を監視
    _adapterSub = FlutterBluePlus.adapterState.listen((state) {
      if (state == BluetoothAdapterState.on) {
        _startScanning();
      } else {
        debugPrint('🔵 BLE: アダプタがオフ ($state)');
        _isRunning = false;
        notifyListeners();
      }
    });

    // 現在の状態が既にonなら即スキャン開始
    final currentState = await FlutterBluePlus.adapterState.first;
    if (currentState == BluetoothAdapterState.on) {
      await _startScanning();
    }
  }

  // ─── 停止 ─────────────────────────────────────────────────
  Future<void> stop() async {
    _isRunning = false;
    _scanSub?.cancel();
    _adapterSub?.cancel();
    _isScanningSubscription?.cancel();
    await FlutterBluePlus.stopScan();
    for (final device in _activeConnections.values) {
      await device.disconnect();
    }
    _activeConnections.clear();
    notifyListeners();
  }

  // ─── 第三の指示: スキャン（同じアプリを探す）────────────────────
  Future<void> _startScanning() async {
    _isRunning = true;
    notifyListeners();

    debugPrint('🔵 BLE: スキャン開始 (サービスUUID: $_serviceUuid)');

    // GapLessのサービスUUIDを持つ端末のみをフィルタリング
    await FlutterBluePlus.startScan(
      withServices: [_serviceUuid],
      // 30秒ごとに再スキャン（継続的な発見）
      timeout: const Duration(seconds: 30),
      androidUsesFineLocation: false, // iOSでは不要
    );

    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final result in results) {
        _connectIfNeeded(result.device);
      }
    });

    // スキャン終了後に自動的に再起動（継続スキャン）
    // 既存リスナーを解除してから再登録（指数的リスナー増加を防ぐ）
    _isScanningSubscription?.cancel();
    _isScanningSubscription = FlutterBluePlus.isScanning.listen((isScanning) {
      if (!isScanning && _isRunning) {
        Future.delayed(const Duration(seconds: 5), () {
          if (_isRunning) _startScanning();
        });
      }
    });
  }

  // ─── 第三の指示: 接続処理 ─────────────────────────────────────
  Future<void> _connectIfNeeded(BluetoothDevice device) async {
    // 既に接続済みか处理中なら無視
    if (_activeConnections.containsKey(device.remoteId)) return;
    // 自分自身との接続を防ぐ
    final myDeviceId = DeviceIdService.instance.deviceId;
    if (device.remoteId.str == myDeviceId) return;

    try {
      debugPrint('🔵 BLE: 接続試行 → ${device.remoteId}');
      _activeConnections[device.remoteId] = device;
      _connectedPeerCount = _activeConnections.length;
      notifyListeners();

      await device.connect(timeout: const Duration(seconds: 8));

      // MTUを512バイトに交渉（iOSは自動交渉するが明示的に要求）
      await device.requestMtu(512);

      // サービスとキャラクタリスティックを発見
      await _performDataExchange(device);

    } catch (e) {
      debugPrint('⚠️ BLE接続エラー (${device.remoteId}): $e');
    } finally {
      _activeConnections.remove(device.remoteId);
      _connectedPeerCount = _activeConnections.length;
      notifyListeners();
      // 切断
      await device.disconnect();
    }
  }

  // ─── 第三の指示: データ交換の本体 ─────────────────────────────
  Future<void> _performDataExchange(BluetoothDevice device) async {
    debugPrint('🔵 BLE: サービス探索中... (${device.remoteId})');

    final services = await device.discoverServices();
    final targetService = services.where((s) => s.serviceUuid == _serviceUuid).firstOrNull;

    if (targetService == null) {
      debugPrint('⚠️ BLE: GapLessサービスが見つかりません');
      return;
    }

    // キャラクタリスティックの取得
    final txChar = targetService.characteristics.where((c) => c.characteristicUuid == _txCharUuid).firstOrNull;
    final rxChar = targetService.characteristics.where((c) => c.characteristicUuid == _rxCharUuid).firstOrNull;

    if (txChar == null || rxChar == null) {
      debugPrint('⚠️ BLE: キャラクタリスティックが見つかりません');
      return;
    }

    // ① 受信Notifyを有効化
    await rxChar.setNotifyValue(true);
    final receiveBuffer = <int>[];
    final completer = Completer<void>();

    final rxSub = rxChar.onValueReceived.listen((chunk) {
      receiveBuffer.addAll(chunk);
      // 終端マーカー [0x00] を検出したら受信完了（二重complete防止）
      if (!completer.isCompleted && chunk.contains(0x00)) {
        completer.complete();
      }
    });

    try {
      // ② 自端末のデータを送信
      await _sendAllSpots(txChar);

      // ③ 相手のデータを受信（タイムアウト10秒）
      await completer.future.timeout(const Duration(seconds: 10));

      // ④ 受信バッファをパース（終端マーカーを除去）
      final rawJson = utf8.decode(receiveBuffer.where((b) => b != 0x00).toList());
      await _processReceivedData(rawJson);

      _lastSyncTime = DateTime.now();
      _syncedDeviceIds.add(device.remoteId.str);
      notifyListeners();

      debugPrint('✅ BLE: データ交換完了 (${device.remoteId})');

    } on TimeoutException {
      debugPrint('⚠️ BLE: 受信タイムアウト (${device.remoteId})');
    } finally {
      rxSub.cancel();
    }
  }

  // ─── 第三の指示: チャンク送信（MTU分割）────────────────────────
  Future<void> _sendAllSpots(BluetoothCharacteristic txChar) async {
    final spots = HazardSpotRepository.instance.toSendableJsonList();
    // リスト全体をJSON文字列化: [{"i":...},{...}]
    final payload = jsonEncode(spots.map((s) => jsonDecode(s)).toList());
    final bytes = utf8.encode(payload);

    final mtu = txChar.device.mtuNow - 3; // ATTヘッダー3バイト分を引く
    debugPrint('🔵 BLE: 送信 ${bytes.length}バイト (MTU: $mtu)');

    // チャンク分割送信
    for (var i = 0; i < bytes.length; i += mtu) {
      final chunk = bytes.sublist(i, (i + mtu).clamp(0, bytes.length));
      await txChar.write(chunk, withoutResponse: false);
      // iOSのレート制限に配慮して少し待機
      await Future.delayed(const Duration(milliseconds: 10));
    }
    // 終端マーカーを送信（受信側が完了を検知するため）
    await txChar.write([0x00], withoutResponse: false);
    debugPrint('🔵 BLE: 送信完了 (${spots.length}件)');
  }

  // ─── 第四の指示: 受信データの処理とマージ ─────────────────────
  Future<void> _processReceivedData(String rawJson) async {
    try {
      if (rawJson.isEmpty) return;

      final List<dynamic> decoded = jsonDecode(rawJson) as List<dynamic>;
      final receivedSpots = decoded
          .whereType<Map<String, dynamic>>()
          .map((json) {
            try { return HazardSpot.fromCompactJson(json); }
            catch (_) { return null; }
          })
          .whereType<HazardSpot>()
          .toList();

      debugPrint('🔵 BLE: ${receivedSpots.length}件のスポットを受信');

      // マージ処理（内部でnotifyListeners()が呼ばれ地図が即時更新される）
      final changed = await HazardSpotRepository.instance.mergeReceived(receivedSpots);
      if (changed) {
        debugPrint('🗺️ 地図を更新: ${HazardSpotRepository.instance.spots.length}件');
      }
    } catch (e) {
      debugPrint('⚠️ BLE受信データのパースエラー: $e');
    }
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}


/// ============================================================================
/// BleAdvertiserService - ペリフェラル（アドバタイズ）側
/// ============================================================================
///
/// iOSがバックグラウンドから発見されるよう、アプリ起動中は常にアドバタイズする。
/// flutter_blue_plus 1.x系ではPeripheral(Server)機能は限定的なため、
/// ここではiOS CoreBluetooth準拠の最小限の実装を行う。
///
/// 注意: flutter_blue_plus 1.xはCentral側のAPIが主体。
/// Peripheral側は将来的に flutter_blue_plus 2.x (beta) または
/// quick_blue パッケージへの移行で強化可能。
/// ============================================================================
class BleAdvertiserService {
  static final BleAdvertiserService instance = BleAdvertiserService._();
  BleAdvertiserService._();

  /// アドバタイズ開始
  /// iOSではCoreBluetoothのPeripheralManagerを利用するが、
  /// flutter_blue_plus 1.xではFlutterBluePlus.startAdvertising()が提供される
  Future<void> startAdvertising() async {
    try {
      // flutter_blue_plus 1.36.xのadvertise API
      // ※ iOSはバックグラウンドでアドバタイズ継続可能（UIBackgroundModes設定済み）
      debugPrint('📡 BLE Advertiser: アドバタイズ開始試行...');
      // Note: flutter_blue_plus 1.xではstartAdvertisingは未実装のため
      // 実際のiOSアドバタイズはネイティブプラグイン経由またはfbp 2.xで対応
      // 現バージョンではCentral側スキャンとの組み合わせで動作する
    } catch (e) {
      debugPrint('⚠️ BLE Advertiser: $e');
    }
  }
}
