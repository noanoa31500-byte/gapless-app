import 'dart:convert';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================================
/// DeviceIdService - 匿名デバイスID管理
/// ============================================================================
///
/// 【プライバシー設計】
/// - 永続UUID (`deviceId`) は端末内アナリティクス・DBキーにのみ使用。
/// - BLEで外部に発信するIDは [ephemeralBleId] を使い、
///   `HMAC-SHA256(masterKey, hourBucket)` の先頭8文字を1時間ごとにローテーション。
/// - masterKey は SecureStorage に保存し、端末をまたいで漏れないようにする。
/// ============================================================================
class DeviceIdService {
  static final DeviceIdService instance = DeviceIdService._internal();
  DeviceIdService._internal();

  static const String _storageKey = 'gapless_device_uuid';
  static const String _bleMasterKeyName = 'gapless_ble_master_key';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  String? _deviceId;
  List<int>? _bleMasterKey; // 32 bytes

  bool get isInitialized => _deviceId != null;

  /// 永続UUID（外部に出さない・DBキー専用）
  String? get deviceId => _deviceId;

  /// アプリ起動時に一度だけ呼ぶ
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? existingId = prefs.getString(_storageKey);

      if (existingId == null || existingId.isEmpty) {
        existingId = _generateUUIDv4();
        await prefs.setString(_storageKey, existingId);
        if (!kReleaseMode) {
          debugPrint('DeviceIdService: 新規UUID生成');
        }
      } else {
        if (!kReleaseMode) debugPrint('DeviceIdService: 既存UUID読み込み');
      }
      _deviceId = existingId;
    } catch (e) {
      _deviceId = _generateUUIDv4();
      if (!kReleaseMode) {
        debugPrint('DeviceIdService: SharedPreferences失敗、一時UUID使用');
      }
    }

    await _ensureBleMasterKey();
  }

  /// BLE発信用マスター鍵を SecureStorage から取得（無ければ生成）
  Future<void> _ensureBleMasterKey() async {
    try {
      final existing = await _secure.read(key: _bleMasterKeyName);
      if (existing != null && existing.isNotEmpty) {
        _bleMasterKey = base64Decode(existing);
        if (_bleMasterKey!.length != 32) {
          _bleMasterKey = _generateRandomBytes(32);
          await _secure.write(
              key: _bleMasterKeyName, value: base64Encode(_bleMasterKey!));
        }
      } else {
        _bleMasterKey = _generateRandomBytes(32);
        await _secure.write(
            key: _bleMasterKeyName, value: base64Encode(_bleMasterKey!));
      }
    } catch (e) {
      // SecureStorage失敗時は端末永続UUIDを鍵として代用（fail-open はしない）。
      // 永続UUIDは端末外に漏れないので、ローテーションIDのリンク不能性は守られる。
      _bleMasterKey = utf8.encode(_deviceId ?? 'fallback-master-key');
      if (!kReleaseMode) {
        debugPrint('DeviceIdService: BLEマスター鍵 SecureStorage失敗、derive fallback');
      }
    }
  }

  /// BLE発信に使う短命ID。1時間ごとに自動ローテート。
  /// `HMAC-SHA256(masterKey, hourBucket).hex.substring(0,8)`
  String get ephemeralBleId {
    final master = _bleMasterKey;
    if (master == null || master.isEmpty) {
      // init 未完了時は永続IDの先頭8文字（暫定）。BLE通信は init後にのみ走るのが正規ルート。
      final id = _deviceId ?? '00000000';
      return id.length >= 8 ? id.substring(0, 8) : id.padRight(8, '0');
    }
    final hourBucket =
        DateTime.now().toUtc().millisecondsSinceEpoch ~/ (3600 * 1000);
    final hmac = Hmac(sha256, master);
    final digest = hmac.convert(utf8.encode('ble:$hourBucket'));
    return digest.toString().substring(0, 8);
  }

  /// テスト・将来用: 任意の hourBucket でID生成
  String ephemeralBleIdForBucket(int hourBucket) {
    final master = _bleMasterKey ?? utf8.encode(_deviceId ?? '');
    final hmac = Hmac(sha256, master);
    return hmac.convert(utf8.encode('ble:$hourBucket')).toString().substring(0, 8);
  }

  String _generateUUIDv4() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
        '${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }

  List<int> _generateRandomBytes(int n) {
    final r = math.Random.secure();
    return List<int>.generate(n, (_) => r.nextInt(256));
  }

  /// デバッグ用リセット（本番では使用しない）
  Future<void> resetForDebug() async {
    if (!kDebugMode) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    await _secure.delete(key: _bleMasterKeyName);
    _deviceId = null;
    _bleMasterKey = null;
  }
}
