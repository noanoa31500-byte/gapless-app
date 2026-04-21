import 'package:flutter/services.dart';

// ============================================================================
// BlePeripheralChannel — iOS CoreBluetooth ペリフェラルへのブリッジ
// ============================================================================

class BlePeripheralChannel {
  static const _ch = MethodChannel('gapless/ble_peripheral');

  static final BlePeripheralChannel instance = BlePeripheralChannel._();
  BlePeripheralChannel._() {
    _ch.setMethodCallHandler(_onNativeCall);
  }

  bool _advertising = false;
  bool get isAdvertising => _advertising;

  /// ペリフェラルとして Central から書き込みを受信したときのコールバック
  void Function(Uint8List bytes)? onDataReceived;

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'onDataReceived') {
      final bytes = call.arguments as Uint8List;
      onDataReceived?.call(bytes);
    }
  }

  Future<void> startAdvertising() async {
    try {
      await _ch.invokeMethod<void>('startAdvertising');
      _advertising = true;
    } on PlatformException catch (e) {
      _advertising = false;
      if (e.code != 'UNIMPLEMENTED') rethrow;
    } on MissingPluginException {
      _advertising = false;
    }
  }

  Future<void> stopAdvertising() async {
    try {
      await _ch.invokeMethod<void>('stopAdvertising');
    } catch (_) {}
    _advertising = false;
  }

  Future<Map<String, dynamic>?> getStatus() async {
    try {
      final r = await _ch.invokeMethod<Map>('getStatus');
      if (r == null) return null;
      return r.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {
      return null;
    }
  }

  Future<void> updateData(Uint8List bytes) async {
    if (!_advertising) return;
    try {
      await _ch.invokeMethod<void>('updateData', bytes);
    } catch (_) {}
  }
}
