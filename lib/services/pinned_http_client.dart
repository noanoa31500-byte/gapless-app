// ============================================================================
// pinned_http_client.dart  — TLS 証明書ピンニング
// ============================================================================
//
// 目的: マップデータ等の整合性が重要な配信元に対し、想定外の CA が発行した
// 証明書 (= 中間者攻撃) を検出する。
//
// ピン形式: 葉証明書 (DER) の SHA-256 ハッシュを base64 で保持。
//   生成例:
//     openssl s_client -servername host -connect host:443 </dev/null \
//       | openssl x509 -outform DER \
//       | openssl dgst -sha256 -binary | base64
//
// モード:
//   advisory (default) — ミスマッチをログするがリクエストは通す。
//                         CI 復旧難易度を抑え、本番投入前に観測する用。
//   enforce            — ミスマッチで HandshakeException を投げる。
//
// 注意: 葉証明書ピンは 60–90 日でローテーションが発生するため、必ず複数の
// バックアップピン (旧 + 新) を併記すること。SPKI ピンへの移行は ASN.1
// パーサーの導入後 (#TODO) を予定。
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

enum PinningMode { advisory, enforce }

class CertificatePinner {
  static final Map<String, Set<String>> _pins = <String, Set<String>>{
    // 値は本番投入前に上記コマンドで取得して埋める。
    // 空セット = ピンなし (検証スキップ)。
    'raw.githubusercontent.com': <String>{},
    'cdn.jsdelivr.net': <String>{},
    'www.data.jma.go.jp': <String>{},
  };

  static PinningMode mode = PinningMode.advisory;

  /// 証明書がピンに合致するかを返す。
  /// - ホストにピン設定がない / 空 → true (検証スキップ)
  /// - 一致 → true
  /// - 不一致 → advisory ならログのみで true、enforce なら false
  static bool verify(String host, X509Certificate cert) {
    final allowed = _pins[host];
    if (allowed == null || allowed.isEmpty) return true;

    final fp = base64.encode(sha256.convert(cert.der).bytes);
    if (allowed.contains(fp)) return true;

    debugPrint(
        'CertificatePinner: pin mismatch for $host (sha256=$fp, allowed=$allowed, mode=$mode)');
    return mode == PinningMode.advisory;
  }

  @visibleForTesting
  static void debugSetPin(String host, Set<String> hashes) {
    _pins[host] = hashes;
  }

  @visibleForTesting
  static void debugClearAll() => _pins.clear();
}

/// ピンニング有効な http.Client を生成する。
http.Client createPinnedClient() => _PinnedClient(HttpClient());

class _PinnedClient extends http.BaseClient {
  final HttpClient _http;
  _PinnedClient(this._http);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final ioReq = await _http.openUrl(request.method, request.url);
    request.headers.forEach(ioReq.headers.set);
    if (request is http.Request && request.bodyBytes.isNotEmpty) {
      ioReq.add(request.bodyBytes);
    }
    final ioRes = await ioReq.close();

    final cert = ioRes.certificate;
    if (cert != null && !CertificatePinner.verify(request.url.host, cert)) {
      ioRes.detachSocket().then((s) => s.destroy()).ignore();
      throw const HandshakeException('Certificate pin mismatch');
    }

    final headers = <String, String>{};
    ioRes.headers.forEach((k, v) => headers[k] = v.join(','));
    return http.StreamedResponse(
      ioRes,
      ioRes.statusCode,
      contentLength: ioRes.contentLength == -1 ? null : ioRes.contentLength,
      request: request,
      headers: headers,
      isRedirect: ioRes.isRedirect,
      persistentConnection: ioRes.persistentConnection,
      reasonPhrase: ioRes.reasonPhrase,
    );
  }

  @override
  void close() => _http.close(force: true);
}
