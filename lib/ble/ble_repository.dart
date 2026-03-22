import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'ble_packet.dart';

// ============================================================================
// BleRepository — BlePacket の永続化（sqflite）
// ============================================================================
//
// テーブル: ble_reports
//   id          INTEGER PRIMARY KEY AUTOINCREMENT
//   device_id   TEXT
//   timestamp   INTEGER   (UNIX秒)
//   lat         REAL
//   lng         REAL
//   accuracy    REAL
//   data_type   INTEGER
//   payload     TEXT
//   received_at INTEGER   (受信時刻 UNIX秒)
//
// 鮮度:
//   < 30分  → opacity 1.0
//   30分〜2時間 → opacity 0.5
//   > 2時間 → 除外（クリーンアップ対象）
//
// ============================================================================

class ReceivedReport {
  final BlePacket packet;
  final int receivedAt; // UNIX秒

  const ReceivedReport({required this.packet, required this.receivedAt});

  /// 鮮度に基づく不透明度
  double get opacity {
    final age = DateTime.now().millisecondsSinceEpoch ~/ 1000 - receivedAt;
    if (age < 30 * 60)  return 1.0;
    if (age < 2 * 3600) return 0.5;
    return 0.0; // 除外対象
  }
}

class BleRepository {
  static final BleRepository instance = BleRepository._();
  BleRepository._();

  static const String _tableName = 'ble_reports';
  static const Duration _maxAge = Duration(hours: 2);

  Database? _db;

  Future<Database> get _database async {
    _db ??= await _openDb();
    return _db!;
  }

  // ---------------------------------------------------------------------------
  // 初期化
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    await _database;
    await _cleanup();
    debugPrint('BleRepository: 初期化完了');
  }

  Future<Database> _openDb() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'ble_reports.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id          INTEGER PRIMARY KEY AUTOINCREMENT,
            device_id   TEXT    NOT NULL,
            timestamp   INTEGER NOT NULL,
            lat         REAL    NOT NULL,
            lng         REAL    NOT NULL,
            accuracy    REAL    NOT NULL,
            data_type   INTEGER NOT NULL,
            payload     TEXT    NOT NULL DEFAULT '',
            received_at INTEGER NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_received_at ON $_tableName (received_at)',
        );
        await db.execute(
          'CREATE UNIQUE INDEX idx_dedup ON $_tableName (device_id, timestamp)',
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 書き込み
  // ---------------------------------------------------------------------------

  Future<void> insert(BlePacket packet) async {
    final db = await _database;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    try {
      await db.insert(
        _tableName,
        {
          'device_id':   packet.senderDeviceId,
          'timestamp':   packet.timestamp,
          'lat':         packet.lat,
          'lng':         packet.lng,
          'accuracy':    packet.accuracyMeters,
          'data_type':   packet.dataType.value,
          'payload':     packet.payload,
          'received_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore, // 重複は無視
      );
    } catch (e) {
      debugPrint('BleRepository: 書き込みエラー $e');
    }
  }

  // ---------------------------------------------------------------------------
  // クエリ
  // ---------------------------------------------------------------------------

  /// 指定座標から半径 [radiusMeters] 以内の有効な報告を返す
  /// 2時間超のデータは除外する
  Future<List<ReceivedReport>> queryNearby({
    required double lat,
    required double lng,
    required double radiusMeters,
  }) async {
    final db = await _database;
    final cutoff = DateTime.now()
            .subtract(_maxAge)
            .millisecondsSinceEpoch ~/
        1000;

    // 矩形で大まかにフィルタ（緯度1度≒111km）
    final dLat = radiusMeters / 111320.0;
    final dLng = radiusMeters /
        (111320.0 * math.cos(lat * math.pi / 180.0));

    final rows = await db.query(
      _tableName,
      where: '''
        received_at >= ?
        AND lat BETWEEN ? AND ?
        AND lng BETWEEN ? AND ?
      ''',
      whereArgs: [
        cutoff,
        lat - dLat, lat + dLat,
        lng - dLng, lng + dLng,
      ],
    );

    final results = <ReceivedReport>[];
    for (final row in rows) {
      final packet = _rowToPacket(row);
      final received = row['received_at'] as int;

      // 精密な距離フィルタ
      final dist = _haversineM(
        lat, lng,
        row['lat'] as double,
        row['lng'] as double,
      );
      if (dist <= radiusMeters) {
        results.add(ReceivedReport(packet: packet, receivedAt: received));
      }
    }
    return results;
  }

  // ---------------------------------------------------------------------------
  // クリーンアップ（起動時に1回）
  // ---------------------------------------------------------------------------

  Future<void> _cleanup() async {
    final db = await _database;
    final cutoff = DateTime.now()
            .subtract(_maxAge)
            .millisecondsSinceEpoch ~/
        1000;
    final deleted = await db.delete(
      _tableName,
      where: 'received_at < ?',
      whereArgs: [cutoff],
    );
    if (deleted > 0) {
      debugPrint('BleRepository: $deleted 件の古いデータを削除');
    }
  }

  // ---------------------------------------------------------------------------
  // ヘルパー
  // ---------------------------------------------------------------------------

  BlePacket _rowToPacket(Map<String, dynamic> row) {
    return BlePacket(
      senderDeviceId: row['device_id'] as String,
      timestamp:      row['timestamp'] as int,
      lat:            row['lat'] as double,
      lng:            row['lng'] as double,
      accuracyMeters: row['accuracy'] as double,
      dataType:       BleDataType.fromValue(row['data_type'] as int),
      payload:        row['payload'] as String? ?? '',
    );
  }

  /// Haversine 距離 (メートル)
  static double _haversineM(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}
