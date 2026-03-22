import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================================
/// DeviceIdService - iOS ネイティブ専用 匿名デバイスID管理
/// ============================================================================
///
/// 【iOS最適化方針】
/// - dart:js_interop / @JS外部関数を完全削除（iOSで実行時クラッシュ）
/// - SharedPreferences → iOS NSUserDefaults にネイティブで永続化
/// - UUID生成は dart:math の Random.secure() を使った純Dartで実装
///   （crypto.randomUUID() はブラウザ専用API）
///
/// 【プライバシー設計】
/// - UUIDのみ・個人情報一切なし
/// - NSUserDefaultsはiCloudバックアップから除外不要（匿名IDのため問題なし）
/// ============================================================================
class DeviceIdService {
  static final DeviceIdService instance = DeviceIdService._internal();
  DeviceIdService._internal();

  static const String _storageKey = 'gapless_device_uuid';

  String? _deviceId;
  bool get isInitialized => _deviceId != null;
  String? get deviceId => _deviceId;

  /// アプリ起動時に一度だけ呼ぶ
  /// NSUserDefaultsからUUIDを読み取り、なければ生成して保存
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? existingId = prefs.getString(_storageKey);

      if (existingId == null || existingId.isEmpty) {
        existingId = _generateUUIDv4();
        await prefs.setString(_storageKey, existingId);
        debugPrint('🆔 DeviceIdService: 新規UUID生成 → NSUserDefaults保存');
      } else {
        debugPrint('🆔 DeviceIdService: 既存UUID読み込み');
      }
      _deviceId = existingId;
    } catch (e) {
      // フォールバック: セッション中のみ有効なUUIDを使用
      _deviceId = _generateUUIDv4();
      debugPrint('⚠️ DeviceIdService: SharedPreferences失敗、一時UUID使用: $e');
    }

    debugPrint('🆔 DeviceId: ${_deviceId?.substring(0, 8)}****');
  }

  /// UUID v4 を純Dartで生成 (RFC 4122準拠)
  /// dart:math の Random.secure() は iOS の SecRandomCopyBytes を内部で使用
  String _generateUUIDv4() {
    final random = math.Random.secure();

    // 128ビット乱数をバイト列として生成
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));

    // UUID v4 のビット設定
    bytes[6] = (bytes[6] & 0x0F) | 0x40; // version = 4
    bytes[8] = (bytes[8] & 0x3F) | 0x80; // variant = RFC 4122

    // xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx 形式に整形
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-'
           '${hex.substring(8, 12)}-'
           '${hex.substring(12, 16)}-'
           '${hex.substring(16, 20)}-'
           '${hex.substring(20, 32)}';
  }

  /// デバッグ用リセット（本番では使用しない）
  Future<void> resetForDebug() async {
    if (!kDebugMode) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    _deviceId = null;
    debugPrint('🆔 DeviceIdService: UUID削除（デバッグ用）');
  }
}
