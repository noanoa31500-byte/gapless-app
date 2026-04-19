import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:math';

/// セキュリティ初期化の致命的失敗を表す例外。
/// 旧実装はハードコードAES鍵にフォールバックしていたが、
/// それは恒久的に削除済み。失敗時は本例外を投げて呼出側に明示的に通知する。
class SecurityInitException implements Exception {
  final String message;
  final Object? cause;
  SecurityInitException(this.message, [this.cause]);
  @override
  String toString() => 'SecurityInitException: $message'
      '${cause != null ? ' (cause=$cause)' : ''}';
}

/// 暗号化アセットの復号失敗を表す例外（平文フォールバックは禁止）。
class EncryptedAssetException implements Exception {
  final String message;
  final Object? cause;
  EncryptedAssetException(this.message, [this.cause]);
  @override
  String toString() => 'EncryptedAssetException: $message'
      '${cause != null ? ' (cause=$cause)' : ''}';
}

/// セキュリティ管理（キー管理と復号）を担うサービス
class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  final _storage = const FlutterSecureStorage();
  encrypt.Key? _key;
  encrypt.IV? _iv;
  bool _isInitialized = false;

  bool get isInitialized => _isInitialized;

  /// 初期化：SecureStorageからキーを読み込む。存在しない場合は生成して保存。
  /// 失敗時は [SecurityInitException] を投げて abort する（ハードコード鍵 fallback は廃止）。
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      final keyString = await _storage.read(key: 'encryption_key');
      final ivString = await _storage.read(key: 'encryption_iv');

      if (keyString != null && ivString != null) {
        _key = encrypt.Key.fromBase64(keyString);
        _iv = encrypt.IV.fromBase64(ivString);
      } else {
        _key = _generateSecureKey();
        _iv = _generateSecureIV();
        await _storage.write(key: 'encryption_key', value: _key!.base64);
        await _storage.write(key: 'encryption_iv', value: _iv!.base64);
      }

      // 妥当性チェック: 32byte / 16byte
      if (_key!.bytes.length != 32 || _iv!.bytes.length != 16) {
        throw SecurityInitException(
            'Invalid key/iv length: key=${_key!.bytes.length}, iv=${_iv!.bytes.length}');
      }
      _isInitialized = true;
    } catch (e) {
      // SecureStorageが使えない端末では起動を拒否する。
      // 旧実装は "my32lengthsupersecretnooneknows1" の固定鍵にフォールバックしていた。
      _key = null;
      _iv = null;
      _isInitialized = false;
      throw SecurityInitException(
          'SecureStorage initialization failed; refusing to fall back to a hardcoded key',
          e);
    }
  }

  /// 暗号化されたアセットファイルを読み込み、文字列として返す。
  /// 復号に失敗した場合は [EncryptedAssetException] を投げる（平文フォールバックは廃止）。
  Future<String> loadEncryptedAsset(String path) async {
    if (!_isInitialized) {
      await init(); // throws SecurityInitException on failure
    }

    // 暗号化対象外のテキストアセットはそのまま返す
    if (path.endsWith('.json') ||
        path.endsWith('.geojson') ||
        path.endsWith('.csv')) {
      return rootBundle.loadString(path);
    }

    final ByteData data;
    try {
      data = await rootBundle.load(path);
    } catch (e) {
      throw EncryptedAssetException('Asset not found: $path', e);
    }

    try {
      final encryptedBytes = data.buffer.asUint8List();
      final encrypter = encrypt.Encrypter(encrypt.AES(_key!));
      final decrypted =
          encrypter.decryptBytes(encrypt.Encrypted(encryptedBytes), iv: _iv!);
      return utf8.decode(decrypted);
    } catch (e) {
      // 旧実装はここで rootBundle.loadString(path) にフォールバックしていたが、
      // 平文として読み込むのは「暗号化済みアセット」として配布した前提を破壊するため禁止。
      if (!kReleaseMode) {
        debugPrint('SecurityService: failed to decrypt asset $path: $e');
      }
      throw EncryptedAssetException('Failed to decrypt asset: $path', e);
    }
  }

  /// セキュアな暗号化キーを生成
  encrypt.Key _generateSecureKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    return encrypt.Key(Uint8List.fromList(bytes));
  }

  /// セキュアなIVを生成
  encrypt.IV _generateSecureIV() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return encrypt.IV(Uint8List.fromList(bytes));
  }
}
