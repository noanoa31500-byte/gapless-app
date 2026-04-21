import 'dart:convert';
import 'dart:typed_data';

// ============================================================================
// BlePacket — BLE 送受信パケット定義
// ============================================================================
//
// バイナリフォーマット（最小35バイト、最大235バイト）:
//   magic(2)      : 0x47 0x4C  ("GL")
//   version(1)    : 0x01
//   dataType(1)   : 1=歩行記録 2=通行可 3=通行不可 4=危険報告
//   timestamp(4)  : uint32 LE — UNIX秒
//   lat_i32(4)    : int32 LE  — lat * 1e6
//   lng_i32(4)    : int32 LE  — lng * 1e6
//   accuracy(2)   : uint16 LE — accuracyMeters * 10
//   deviceId(16)  : UUID bytes (ハイフンなし)
//   payloadLen(1) : 0–200
//   payload(N)    : UTF-8
//
// ============================================================================

enum BleDataType {
  walk(1),
  passable(2),
  blocked(3),
  danger(4),
  shelterStatus(5),
  sos(6);

  final int value;
  const BleDataType(this.value);

  static BleDataType fromValue(int v) => BleDataType.values
      .firstWhere((e) => e.value == v, orElse: () => BleDataType.walk);
}

class BlePacket {
  static const List<int> _magic = [0x47, 0x4C]; // "GL"
  static const int _version = 0x01;
  static const int _headerSize =
      35; // magic2 + ver1 + type1 + ts4 + lat4 + lng4 + acc2 + id16 + len1

  final String senderDeviceId; // UUID v4 文字列（ハイフン含む）
  final int timestamp; // UNIX秒
  final double lat;
  final double lng;
  final double accuracyMeters;
  final BleDataType dataType;
  final String payload; // JSON文字列（最大200バイト）

  const BlePacket({
    required this.senderDeviceId,
    required this.timestamp,
    required this.lat,
    required this.lng,
    required this.accuracyMeters,
    required this.dataType,
    this.payload = '',
  });

  // ── シリアライズ ─────────────────────────────────────────────────────────

  Uint8List toBytes() {
    final payloadBytes = utf8.encode(payload);
    final clampedPayload =
        payloadBytes.length > 200 ? payloadBytes.sublist(0, 200) : payloadBytes;

    final buf = ByteData(_headerSize + clampedPayload.length);
    int off = 0;

    // magic
    buf.setUint8(off++, _magic[0]);
    buf.setUint8(off++, _magic[1]);
    // version
    buf.setUint8(off++, _version);
    // dataType
    buf.setUint8(off++, dataType.value);
    // timestamp (uint32 LE)
    buf.setUint32(off, timestamp, Endian.little);
    off += 4;
    // lat (int32 LE)
    buf.setInt32(off, (lat * 1e6).round(), Endian.little);
    off += 4;
    // lng (int32 LE)
    buf.setInt32(off, (lng * 1e6).round(), Endian.little);
    off += 4;
    // accuracy (uint16 LE)
    buf.setUint16(
        off, (accuracyMeters * 10).round().clamp(0, 65535), Endian.little);
    off += 2;
    // deviceId (16 bytes UUID)
    final idBytes = _uuidToBytes(senderDeviceId);
    for (int i = 0; i < 16; i++) {
      buf.setUint8(off++, idBytes[i]);
    }
    // payloadLen
    buf.setUint8(off++, clampedPayload.length);
    // payload
    for (int i = 0; i < clampedPayload.length; i++) {
      buf.setUint8(off++, clampedPayload[i]);
    }

    return buf.buffer.asUint8List();
  }

  // ── デシリアライズ ────────────────────────────────────────────────────────

  /// 受信時バリデーション共通ヘルパー
  /// - lat ∈ [-90, 90], lng ∈ [-180, 180]、有限値のみ
  /// - timestamp が現在時刻 ±24h 以内
  /// - payload長 ≤ 256 バイト
  static bool isValidGeo(double lat, double lng) {
    if (!lat.isFinite || !lng.isFinite) return false;
    if (lat < -90.0 || lat > 90.0) return false;
    if (lng < -180.0 || lng > 180.0) return false;
    return true;
  }

  static bool isValidTimestamp(int tsSeconds,
      {int toleranceSeconds = 24 * 3600}) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return (tsSeconds - now).abs() <= toleranceSeconds;
  }

  static const int maxPayloadBytes = 256;

  /// 軽量バリデーション。失敗理由を返す（null = OK）。
  static String? validateFields({
    required double lat,
    required double lng,
    required int timestamp,
    int payloadByteLength = 0,
  }) {
    if (!isValidGeo(lat, lng)) return 'invalid_geo';
    if (!isValidTimestamp(timestamp)) return 'invalid_timestamp';
    if (payloadByteLength > maxPayloadBytes) return 'payload_too_large';
    return null;
  }

  static BlePacket? fromBytes(Uint8List bytes) {
    if (bytes.length < _headerSize) return null;
    if (bytes.length > _headerSize + maxPayloadBytes) return null;
    final buf = ByteData.sublistView(bytes);
    int off = 0;

    // magic チェック
    if (buf.getUint8(off++) != _magic[0]) return null;
    if (buf.getUint8(off++) != _magic[1]) return null;
    // version チェック
    if (buf.getUint8(off++) != _version) return null;

    final dataTypeVal = buf.getUint8(off++);
    final ts = buf.getUint32(off, Endian.little);
    off += 4;
    final latI = buf.getInt32(off, Endian.little);
    off += 4;
    final lngI = buf.getInt32(off, Endian.little);
    off += 4;
    final accRaw = buf.getUint16(off, Endian.little);
    off += 2;

    final idBytes = bytes.sublist(off, off + 16);
    off += 16;
    final payloadLen = buf.getUint8(off++);

    if (bytes.length < _headerSize + payloadLen) return null;
    final payloadStr = payloadLen > 0
        ? utf8.decode(bytes.sublist(off, off + payloadLen),
            allowMalformed: true)
        : '';

    final lat = latI / 1e6;
    final lng = lngI / 1e6;
    if (validateFields(
            lat: lat, lng: lng, timestamp: ts, payloadByteLength: payloadLen) !=
        null) {
      return null;
    }
    return BlePacket(
      senderDeviceId: _bytesToUuid(idBytes),
      timestamp: ts,
      lat: lat,
      lng: lng,
      accuracyMeters: accRaw / 10.0,
      dataType: BleDataType.fromValue(dataTypeVal),
      payload: payloadStr,
    );
  }

  // ── UUID ヘルパー ────────────────────────────────────────────────────────

  static Uint8List _uuidToBytes(String uuid) {
    final hex = uuid.replaceAll('-', '');
    if (hex.length != 32) return Uint8List(16);
    final result = Uint8List(16);
    try {
      for (int i = 0; i < 16; i++) {
        result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      }
    } catch (_) {
      return Uint8List(16);
    }
    return result;
  }

  static String _bytesToUuid(Uint8List bytes) {
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  @override
  String toString() =>
      'BlePacket($senderDeviceId, ${dataType.name}, $lat/$lng, ts=$timestamp)';
}
