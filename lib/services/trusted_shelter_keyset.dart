// ============================================================================
// trusted_shelter_keyset.dart  — 避難所ステータス署名の信頼鍵セット
// ============================================================================
//
// 目的: ShelterStatusReport (v2 wire) の署名検証に使う、信頼済み発行元
//       (自治体・指定管理者) の Ed25519 公開鍵テーブル。
//
// 配布: アプリにバンドル。鍵ローテーション時はアプリ更新で更新する
//       (証明書の中間 CA 風モデル)。
//
// モード:
//   advisory (default) — 鍵未登録 / 検証失敗時にログするが受理
//   enforce            — 検証失敗で drop[shelter_sig_invalid]
//
// 注意:
//   - 本ファイルはデフォルトで空。本番投入時に各発行元の公開鍵 (32B base64)
//     を `register` または直接 `_keys` に追加する。
//   - keyId は 0–255 の範囲。0 は予約 (= 鍵なし) としない方針。
// ============================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'identity_keystore.dart';

enum ShelterPinningMode { advisory, enforce }

class TrustedShelterKeyset {
  TrustedShelterKeyset._();

  static final Map<int, Uint8List> _keys = <int, Uint8List>{
    // 例: 1: base64.decode('...32 bytes base64...')
    // 本番投入前に発行元から取得した公開鍵を登録する。
  };

  static ShelterPinningMode mode = ShelterPinningMode.advisory;

  /// 鍵 ID から公開鍵を取得。未登録なら null。
  static Uint8List? lookup(int keyId) => _keys[keyId];

  /// `ShelterStatusReport` の署名を検証する。
  /// 戻り値: 受理してよいか (advisory はミスマッチ時も true)
  static Future<bool> verifyReport({
    required int keyId,
    required Uint8List signature,
    required Uint8List canonicalBytes,
  }) async {
    final pk = _keys[keyId];
    if (pk == null) {
      debugPrint('TrustedShelterKeyset: unknown keyId=$keyId, mode=$mode');
      return mode == ShelterPinningMode.advisory;
    }
    final ok = await IdentityKeystore.verify(
      message: canonicalBytes,
      signatureBytes: signature,
      publicKeyBytes: pk,
    );
    if (!ok) {
      debugPrint('TrustedShelterKeyset: sig invalid for keyId=$keyId, mode=$mode');
      return mode == ShelterPinningMode.advisory;
    }
    return true;
  }

  /// 起動時に登録するためのヘルパ (将来は assets/json から読み込み想定)。
  static void register(int keyId, String publicKeyBase64) {
    _keys[keyId] = base64.decode(publicKeyBase64);
  }

  @visibleForTesting
  static void debugSetKey(int keyId, Uint8List publicKey) {
    _keys[keyId] = publicKey;
  }

  @visibleForTesting
  static void debugClearAll() => _keys.clear();
}
