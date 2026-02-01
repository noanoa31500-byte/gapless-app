import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:math';

/// セキュリティ管理（キー管理と復号）を担うサービス
class SecurityService {
  static final SecurityService _instance = SecurityService._internal();
  factory SecurityService() => _instance;
  SecurityService._internal();

  final _storage = const FlutterSecureStorage();
  late encrypt.Key _key;
  late encrypt.IV _iv;
  bool _isInitialized = false;

  /// 初期化：ストレージからキーを読み込む。存在しない場合は作成。
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // セキュアストレージからキーを読み込む
      String? keyString = await _storage.read(key: 'encryption_key');
      String? ivString = await _storage.read(key: 'encryption_iv');

      if (keyString != null && ivString != null) {
        // 既存のキーを使用
        _key = encrypt.Key.fromBase64(keyString);
        _iv = encrypt.IV.fromBase64(ivString);
      } else {
        // 新しいキーを生成（デバイス固有）
        _key = _generateSecureKey();
        _iv = _generateSecureIV();
        
        // ストレージに保存
        await _storage.write(key: 'encryption_key', value: _key.base64);
        await _storage.write(key: 'encryption_iv', value: _iv.base64);
      }
    } catch (e) {
      // エラー時はデフォルトキーを使用（後方互換性のため）
      _key = encrypt.Key.fromUtf8('my32lengthsupersecretnooneknows1');
      _iv = encrypt.IV.fromUtf8('8888888888888888');
    }

    _isInitialized = true;
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

  /// 暗号化されたアセットファイルを読み込み、文字列として返す
  Future<String> loadEncryptedAsset(String path) async {
    if (!_isInitialized) await init();

    try {
      // 暗号化されていないファイルはそのまま読み込む
      if (path.endsWith('.json') || path.endsWith('.geojson') || path.endsWith('.csv')) {
        return await rootBundle.loadString(path);
      }

      final ByteData data = await rootBundle.load(path);
      final Uint8List encryptedBytes = data.buffer.asUint8List();
      
      final encrypter = encrypt.Encrypter(encrypt.AES(_key));
      final decrypted = encrypter.decryptBytes(encrypt.Encrypted(encryptedBytes), iv: _iv);
      
      return utf8.decode(decrypted);
    } catch (e) {
      // 復号化失敗時は平文として読み込みを試行
      return await rootBundle.loadString(path);
    }
  }
}
