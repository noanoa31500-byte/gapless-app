import '../ble/ble_packet.dart';

/// キャッシュTTLの単一ソース。READMEと実装の不整合を防ぐためここに集約する。
/// 既存仕様:
///   - 道路レポート (passable/blocked/danger/walk): 24h
///   - SOS ビーコン: 1h
///   - 避難所状況: 4h
///   - JMA 警報: 6h
///   - ハザード判定キャッシュ: 1h
class CacheTtl {
  CacheTtl._();

  static const Duration roadReport = Duration(hours: 24);
  static const Duration sos = Duration(hours: 1);
  static const Duration shelterStatus = Duration(hours: 4);
  static const Duration jmaAlert = Duration(hours: 6);
  static const Duration hazardJudgment = Duration(hours: 1);

  /// BLE dataType ごとの TTL を返す。
  static Duration forBleDataType(BleDataType type) {
    switch (type) {
      case BleDataType.sos:
        return sos;
      case BleDataType.shelterStatus:
        return shelterStatus;
      case BleDataType.walk:
      case BleDataType.passable:
      case BleDataType.blocked:
      case BleDataType.danger:
        return roadReport;
    }
  }
}
