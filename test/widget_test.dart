import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gapless/models/shelter.dart';
import 'package:gapless/services/ble_road_report_service.dart';
import 'package:gapless/services/gplb_parser.dart';

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
