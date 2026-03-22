import 'package:flutter/services.dart';

// ============================================================================
// BlePeripheralChannel — iOS CoreBluetooth ペリフェラルへのブリッジ
// ============================================================================
// ios/Runner/BlePeripheralManager.swift と対応。
// BleService.enqueue() 経由で呼び出され、アドバタイズ + データ更新を行う。
// ============================================================================

class BlePeripheralChannel {
  static const _ch = MethodChannel('gapless/ble_peripheral');

  static final BlePeripheralChannel instance = BlePeripheralChannel._();
  BlePeripheralChannel._();

  bool _advertising = false;
  bool get isAdvertising => _advertising;

  /// アドバタイズを開始する（BleService.start() から呼ぶ）
  Future<void> startAdvertising() async {
    try {
      await _ch.invokeMethod<void>('startAdvertising');
      _advertising = true;
    } on PlatformException catch (e) {
      _advertising = false;
      // プラットフォーム未対応 or BLE OFF は黙って続行
      if (e.code != 'UNIMPLEMENTED') {
        rethrow;
      }
    } on MissingPluginException {
      // テスト環境等でプラグイン未登録の場合は無視
      _advertising = false;
    }
  }

  /// アドバタイズを停止する（BleService.stop() から呼ぶ）
  Future<void> stopAdvertising() async {
    try {
      await _ch.invokeMethod<void>('stopAdvertising');
    } catch (_) {}
    _advertising = false;
  }

  /// Characteristic 値を更新して周囲の Central デバイスに通知する
  /// [bytes] : BlePacket.toBytes() の出力をそのまま渡す
  Future<void> updateData(Uint8List bytes) async {
    if (!_advertising) return;
    try {
      await _ch.invokeMethod<void>('updateData', bytes);
    } catch (_) {
      // 更新失敗は致命的でないのでログのみ
    }
  }
}
