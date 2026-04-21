// ============================================================================
// identity_keystore.dart  — 端末固有 Ed25519 鍵ペアの管理
// ============================================================================
//
// 目的: BLE で発信する SOS 等を端末バウンドの署名で守り、別端末による
//       deviceId の詐称を防ぐ。
//
// 鍵モデル:
//   - 初回起動時に Ed25519 鍵ペアを生成、秘密鍵 (32B シード) を
//     flutter_secure_storage に保管 (iOS Keychain / Android EncryptedSP)。
//   - 公開鍵は派生して導出 (永続化不要)。
//   - deviceId = hex(SHA-256(publicKey)[:4])  ← 8 文字 hex
//     既存スキーマの "v":"devId8" 文字列形式と互換、かつ暗号学的バインド。
//
// 注意:
//   - 鍵をユーザーが消すと別の deviceId に切り替わる (端末ローテートと同等)。
//     復旧 UX は今後 (#TODO recovery seed)。
//   - 秘密鍵は読み出した後はメモリから消去できない (Dart の制約)。
// ============================================================================

import 'dart:convert';

import 'package:crypto/crypto.dart' as ch;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class IdentityKeystore {
  IdentityKeystore._();
  static final IdentityKeystore instance = IdentityKeystore._();

  static const _seedKey = 'gapless.identity.ed25519.seed.v1';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final Ed25519 _ed = Ed25519();

  SimpleKeyPair? _keyPair;
  Uint8List? _publicKeyBytes;
  String? _deviceId;

  /// 初回呼び出し時に鍵をロード or 生成する。アプリ起動時に await しておく。
  Future<void> ensureInitialized() async {
    if (_keyPair != null) return;
    final stored = await _storage.read(key: _seedKey);
    final List<int> seed;
    if (stored != null) {
      seed = base64.decode(stored);
    } else {
      final tmp = await _ed.newKeyPair();
      seed = await tmp.extractPrivateKeyBytes();
      await _storage.write(key: _seedKey, value: base64.encode(seed));
    }
    _keyPair = await _ed.newKeyPairFromSeed(seed);
    final pk = await _keyPair!.extractPublicKey();
    _publicKeyBytes = Uint8List.fromList(pk.bytes);
    final hash = ch.sha256.convert(_publicKeyBytes!).bytes;
    _deviceId =
        hash.take(4).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    debugPrint('IdentityKeystore: device=$_deviceId');
  }

  /// 派生 deviceId (8 文字 hex)。`ensureInitialized` 後に使用。
  String get deviceId {
    final id = _deviceId;
    if (id == null) {
      throw StateError('IdentityKeystore.ensureInitialized() not awaited');
    }
    return id;
  }

  Uint8List get publicKeyBytes {
    final pk = _publicKeyBytes;
    if (pk == null) {
      throw StateError('IdentityKeystore.ensureInitialized() not awaited');
    }
    return pk;
  }

  /// 任意のメッセージに署名 (64B)。
  Future<Uint8List> sign(Uint8List message) async {
    if (_keyPair == null) {
      throw StateError('IdentityKeystore.ensureInitialized() not awaited');
    }
    final sig = await _ed.sign(message, keyPair: _keyPair!);
    return Uint8List.fromList(sig.bytes);
  }

  /// 署名検証ヘルパ (静的)。受信パケットの検証に使う。
  static Future<bool> verify({
    required Uint8List message,
    required Uint8List signatureBytes,
    required Uint8List publicKeyBytes,
  }) async {
    if (signatureBytes.length != 64 || publicKeyBytes.length != 32) {
      return false;
    }
    final ed = Ed25519();
    final sig = Signature(
      signatureBytes,
      publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
    );
    return ed.verify(message, signature: sig);
  }

  /// pk → deviceId (8 文字 hex) を導出する。受信側の整合性チェック用。
  static String deviceIdFromPublicKey(Uint8List publicKeyBytes) {
    final hash = ch.sha256.convert(publicKeyBytes).bytes;
    return hash.take(4).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @visibleForTesting
  Future<void> debugReset() async {
    await _storage.delete(key: _seedKey);
    _keyPair = null;
    _publicKeyBytes = null;
    _deviceId = null;
  }

  /// テスト用: 既知シードから鍵ペアを差し込む (Storage を使わない)。
  @visibleForTesting
  Future<void> debugLoadFromSeed(List<int> seed) async {
    _keyPair = await _ed.newKeyPairFromSeed(seed);
    final pk = await _keyPair!.extractPublicKey();
    _publicKeyBytes = Uint8List.fromList(pk.bytes);
    _deviceId = deviceIdFromPublicKey(_publicKeyBytes!);
  }
}
