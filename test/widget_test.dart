import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gapless/models/shelter.dart';
import 'package:gapless/services/ble_road_report_service.dart';
import 'package:gapless/services/gplb_parser.dart';
import 'package:gapless/services/identity_keystore.dart';
import 'package:gapless/services/pinned_http_client.dart';
import 'package:gapless/services/trusted_shelter_keyset.dart';
import 'package:gapless/models/sos_report.dart';
import 'package:gapless/models/shelter_status_report.dart';

class _FakeX509 implements X509Certificate {
  @override
  final Uint8List der;
  _FakeX509(this.der);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  group('GplbParser', () {
    test('rejects unsupported future versions', () {
      final bytes = Uint8List.fromList([
        0x47, 0x50, 0x4C, 0x42, // "GPLB"
        0xFF,                    // version 255 (future)
        0x00,                    // sectionCount = 0
      ]);
      expect(
        () => GplbParser.parse(bytes),
        throwsA(isA<GplbUnsupportedVersionException>()),
      );
    });

    test('parses an empty v1 file with zero sections', () {
      final bytes = Uint8List.fromList([
        0x47, 0x50, 0x4C, 0x42,
        0x01,
        0x00,
      ]);
      final data = GplbParser.parse(bytes);
      expect(data.version, 1);
      expect(data.isEmpty, isTrue);
    });

    test('rejects non-GPLB magic bytes', () {
      final bytes = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x00,
        0x01,
        0x00,
      ]);
      expect(() => GplbParser.parse(bytes), throwsException);
    });

    test('v2 CRC32 roundtrip: valid footer parses, tampered footer rejected', () {
      final body = Uint8List.fromList([
        0x47, 0x50, 0x4C, 0x42, // "GPLB"
        0x02,                    // version 2
        0x00,                    // sectionCount = 0
      ]);
      final crc = GplbParser.debugCrc32(body);
      final valid = Uint8List.fromList([
        ...body,
        (crc >> 24) & 0xFF,
        (crc >> 16) & 0xFF,
        (crc >> 8) & 0xFF,
        crc & 0xFF,
      ]);
      final parsed = GplbParser.parse(valid);
      expect(parsed.version, 2);
      expect(parsed.isEmpty, isTrue);

      final tampered = Uint8List.fromList(valid)
        ..[valid.length - 1] ^= 0xFF;
      expect(
        () => GplbParser.parse(tampered),
        throwsA(isA<GplbCrcMismatchException>()),
      );
    });
  });

  group('CertificatePinner', () {
    final fakeDer = Uint8List.fromList([1, 2, 3, 4, 5]);
    final fp = base64.encode(sha256.convert(fakeDer).bytes);
    final cert = _FakeX509(fakeDer);

    tearDown(CertificatePinner.debugClearAll);

    test('allows when no pins configured for host', () {
      expect(CertificatePinner.verify('unknown.example', cert), isTrue);
    });

    test('allows when pin matches', () {
      CertificatePinner.debugSetPin('host.example', {fp});
      CertificatePinner.mode = PinningMode.enforce;
      expect(CertificatePinner.verify('host.example', cert), isTrue);
    });

    test('advisory mode allows mismatch but logs', () {
      CertificatePinner.debugSetPin('host.example', {'AAAA'});
      CertificatePinner.mode = PinningMode.advisory;
      expect(CertificatePinner.verify('host.example', cert), isTrue);
    });

    test('enforce mode rejects mismatch', () {
      CertificatePinner.debugSetPin('host.example', {'AAAA'});
      CertificatePinner.mode = PinningMode.enforce;
      expect(CertificatePinner.verify('host.example', cert), isFalse);
      CertificatePinner.mode = PinningMode.advisory;
    });
  });

  group('IdentityKeystore + SOS signing', () {
    final ks = IdentityKeystore.instance;
    final seed = List<int>.generate(32, (i) => i + 1);

    setUp(() async => ks.debugLoadFromSeed(seed));

    test('deviceId is derived from public key', () {
      final derived = IdentityKeystore.deviceIdFromPublicKey(ks.publicKeyBytes);
      expect(ks.deviceId, derived);
      expect(ks.deviceId.length, 8);
    });

    test('valid signature roundtrip verifies', () async {
      final sos = SosReport.create(deviceId: ks.deviceId, lat: 35.68, lng: 139.75);
      final sig = await ks.sign(sos.canonicalBytes());
      final ok = await IdentityKeystore.verify(
        message: sos.canonicalBytes(),
        signatureBytes: sig,
        publicKeyBytes: ks.publicKeyBytes,
      );
      expect(ok, isTrue);
    });

    test('tampered message fails verification', () async {
      final sos = SosReport.create(deviceId: ks.deviceId, lat: 35.68, lng: 139.75);
      final sig = await ks.sign(sos.canonicalBytes());
      final tampered = SosReport.create(
          deviceId: ks.deviceId, lat: 35.69, lng: 139.75);
      final ok = await IdentityKeystore.verify(
        message: tampered.canonicalBytes(),
        signatureBytes: sig,
        publicKeyBytes: ks.publicKeyBytes,
      );
      expect(ok, isFalse);
    });

    test('SOS JSON roundtrip preserves signature', () async {
      final sos = SosReport.create(deviceId: ks.deviceId, lat: 35.68, lng: 139.75);
      final sig = await ks.sign(sos.canonicalBytes());
      final signed = sos.withSignature(publicKey: ks.publicKeyBytes, signature: sig);
      final wire = signed.toCompactJson();
      final decoded = SosReport.fromJson(jsonDecode(wire) as Map<String, dynamic>);
      expect(decoded.isSigned, isTrue);
      expect(decoded.publicKey, ks.publicKeyBytes);
      expect(decoded.signature, sig);
    });
  });

  group('BleRoadReportService SOS signature ingest', () {
    final svc = BleRoadReportService.instance;
    final ks = IdentityKeystore.instance;
    final seed = List<int>.generate(32, (i) => i + 7);
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    setUp(() async {
      svc.debugReset();
      await ks.debugLoadFromSeed(seed);
    });

    test('signed SOS with valid sig is accepted', () async {
      final sos = SosReport.create(
          deviceId: ks.deviceId, lat: 35.68, lng: 139.75);
      final sig = await ks.sign(sos.canonicalBytes());
      final signed = sos.withSignature(publicKey: ks.publicKeyBytes, signature: sig);
      await svc.debugIngestSos(jsonDecode(signed.toCompactJson()) as Map<String, dynamic>);
      expect(svc.receivedSosReports.length, 1);
    });

    test('signed SOS with tampered lat is rejected', () async {
      final sos = SosReport.create(
          deviceId: ks.deviceId, lat: 35.68, lng: 139.75);
      final sig = await ks.sign(sos.canonicalBytes());
      // 緯度を改ざんしてから署名と組み合わせる
      final tampered = SosReport(
        deviceId: ks.deviceId,
        lat: 35.99,
        lng: 139.75,
        timestamp: sos.timestamp,
        publicKey: ks.publicKeyBytes,
        signature: sig,
      );
      await svc.debugIngestSos(jsonDecode(tampered.toCompactJson()) as Map<String, dynamic>);
      expect(svc.receivedSosReports, isEmpty);
    });

    test('deviceId not matching pubkey hash is rejected', () async {
      final sos = SosReport.create(
          deviceId: 'deadbeef', lat: 35.68, lng: 139.75);
      final sig = await ks.sign(sos.canonicalBytes());
      final signed = sos.withSignature(publicKey: ks.publicKeyBytes, signature: sig);
      await svc.debugIngestSos(jsonDecode(signed.toCompactJson()) as Map<String, dynamic>);
      expect(svc.receivedSosReports, isEmpty);
    });

    test('unsigned v1 SOS still accepted (advisory mode)', () async {
      // v1 互換: pk/sig なしでも通る
      await svc.debugIngestSos({
        'type': 'sos', 'v': 'legacy01', 'a': 35.68, 'o': 139.75, 't': nowSec,
      });
      expect(svc.receivedSosReports.length, 1);
    });
  });

  group('TrustedShelterKeyset + Shelter signing', () {
    final svc = BleRoadReportService.instance;
    final ks = IdentityKeystore.instance;
    final seed = List<int>.generate(32, (i) => i + 23);
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    const kid = 7;

    setUp(() async {
      svc.debugReset();
      await ks.debugLoadFromSeed(seed);
      TrustedShelterKeyset.debugClearAll();
      TrustedShelterKeyset.debugSetKey(kid, ks.publicKeyBytes);
      svc.setKnownShelters([
        const Shelter(
          id: 'known-1',
          name: 'A',
          lat: 35.68,
          lng: 139.75,
          type: 'shelter',
          verified: true,
        ),
      ]);
    });

    tearDown(() {
      TrustedShelterKeyset.mode = ShelterPinningMode.advisory;
    });

    test('signed shelter status with valid sig is accepted', () async {
      final sr = ShelterStatusReport(
        shelterId: 'known-1',
        lat: 35.68,
        lng: 139.75,
        isOccupied: true,
        timestamp: nowSec,
        deviceId: 'dev00000',
      );
      final sig = await ks.sign(sr.canonicalBytes());
      final signed = sr.withSignature(keyId: kid, signature: sig);
      await svc.debugIngestShelter(
          jsonDecode(signed.toCompactJson()) as Map<String, dynamic>);
      expect(svc.shelterStatuses.containsKey('known-1'), isTrue);
    });

    test('enforce mode rejects unknown keyId', () async {
      TrustedShelterKeyset.mode = ShelterPinningMode.enforce;
      final sr = ShelterStatusReport(
        shelterId: 'known-1',
        lat: 35.68,
        lng: 139.75,
        isOccupied: true,
        timestamp: nowSec,
        deviceId: 'dev00000',
      );
      final sig = await ks.sign(sr.canonicalBytes());
      final signed = sr.withSignature(keyId: 99, signature: sig); // 99 未登録
      await svc.debugIngestShelter(
          jsonDecode(signed.toCompactJson()) as Map<String, dynamic>);
      expect(svc.shelterStatuses, isEmpty);
    });

    test('enforce mode rejects tampered signed shelter status', () async {
      TrustedShelterKeyset.mode = ShelterPinningMode.enforce;
      final original = ShelterStatusReport(
        shelterId: 'known-1',
        lat: 35.68,
        lng: 139.75,
        isOccupied: true,
        timestamp: nowSec,
        deviceId: 'dev00000',
      );
      final sig = await ks.sign(original.canonicalBytes());
      // st を 0 に改ざんしてから署名と組み合わせる
      final tampered = ShelterStatusReport(
        shelterId: 'known-1',
        lat: 35.68,
        lng: 139.75,
        isOccupied: false,
        timestamp: nowSec,
        deviceId: 'dev00000',
        keyId: kid,
        signature: sig,
      );
      await svc.debugIngestShelter(
          jsonDecode(tampered.toCompactJson()) as Map<String, dynamic>);
      expect(svc.shelterStatuses, isEmpty);
    });
  });

  group('BleRoadReportService security', () {
    final svc = BleRoadReportService.instance;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    setUp(svc.debugReset);

    Map<String, dynamic> sosJson({
      required String dev,
      required double lat,
      required double lng,
      int? t,
    }) =>
        {'type': 'sos', 'v': dev, 'a': lat, 'o': lng, 't': t ?? nowSec};

    test('SOS rate-limited within 100m grid for 5 minutes', () {
      svc.debugIngestSos(sosJson(dev: 'aaa', lat: 35.6800, lng: 139.7500));
      // 同じ 100m セル内、別 deviceId、4分後 → drop
      svc.debugIngestSos(sosJson(
        dev: 'bbb',
        lat: 35.68009,
        lng: 139.75009,
        t: nowSec + 240,
      ));
      expect(svc.receivedSosReports.length, 1);

      // 6分後 → 受理
      svc.debugIngestSos(sosJson(
        dev: 'ccc',
        lat: 35.68009,
        lng: 139.75009,
        t: nowSec + 360,
      ));
      expect(svc.receivedSosReports.length, 2);
    });

    test('SOS accepted in different 100m cell even within 5min', () {
      svc.debugIngestSos(sosJson(dev: 'aaa', lat: 35.6800, lng: 139.7500));
      // ≈110m 離れた場所 (lat +0.001) → 別セル
      svc.debugIngestSos(sosJson(
        dev: 'bbb',
        lat: 35.6810,
        lng: 139.7500,
        t: nowSec + 60,
      ));
      expect(svc.receivedSosReports.length, 2);
    });

    test('Shelter status rejects unknown shelter id', () {
      svc.setKnownShelters([
        const Shelter(
          id: 'known-1',
          name: 'A',
          lat: 35.68,
          lng: 139.75,
          type: 'shelter',
          verified: true,
        ),
      ]);
      svc.debugIngestShelter({
        'type': 'sh',
        'id': 'unknown-x',
        'a': 35.68,
        'o': 139.75,
        'st': 1,
        't': nowSec,
        'v': 'dev00000',
      });
      expect(svc.shelterStatuses, isEmpty);
    });

    test('Shelter status rejects reports from >500m away', () {
      svc.setKnownShelters([
        const Shelter(
          id: 'known-1',
          name: 'A',
          lat: 35.68,
          lng: 139.75,
          type: 'shelter',
          verified: true,
        ),
      ]);
      // ≈1.1km 北 (lat +0.01) → drop
      svc.debugIngestShelter({
        'type': 'sh',
        'id': 'known-1',
        'a': 35.69,
        'o': 139.75,
        'st': 1,
        't': nowSec,
        'v': 'dev00000',
      });
      expect(svc.shelterStatuses, isEmpty);

      // 同地点 → 受理
      svc.debugIngestShelter({
        'type': 'sh',
        'id': 'known-1',
        'a': 35.68,
        'o': 139.75,
        'st': 1,
        't': nowSec,
        'v': 'dev00000',
      });
      expect(svc.shelterStatuses.containsKey('known-1'), isTrue);
    });
  });
}
