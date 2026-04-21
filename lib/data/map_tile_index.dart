// ============================================================
// map_tile_index.dart
// index.json のモデル・URL解決・ハバーサイン距離計算
// ============================================================

import 'dart:math';

// ────────────────────────────────────────
// 都道府県 → リージョン マッピング
// ────────────────────────────────────────
const Map<String, String> prefToRegion = {
  'hokkaido': 'hokkaido',
  'aomori': 'tohoku',
  'iwate': 'tohoku',
  'miyagi': 'tohoku',
  'akita': 'tohoku',
  'yamagata': 'tohoku',
  'fukushima': 'tohoku',
  'ibaraki': 'kanto',
  'tochigi': 'kanto',
  'gunma': 'kanto',
  'saitama': 'kanto',
  'chiba': 'kanto',
  'tokyo': 'kanto',
  'kanagawa': 'kanto',
  'niigata': 'chubu',
  'toyama': 'chubu',
  'ishikawa': 'chubu',
  'fukui': 'chubu',
  'yamanashi': 'chubu',
  'nagano': 'chubu',
  'gifu': 'chubu',
  'shizuoka': 'chubu',
  'aichi': 'chubu',
  'mie': 'chubu',
  'shiga': 'kinki',
  'kyoto': 'kinki',
  'osaka': 'kinki',
  'hyogo': 'kinki',
  'nara': 'kinki',
  'wakayama': 'kinki',
  'tottori': 'chugoku',
  'shimane': 'chugoku',
  'okayama': 'chugoku',
  'hiroshima': 'chugoku',
  'yamaguchi': 'chugoku',
  'tokushima': 'shikoku',
  'kagawa': 'shikoku',
  'ehime': 'shikoku',
  'kochi': 'shikoku',
  'fukuoka': 'kyushu',
  'saga': 'kyushu',
  'nagasaki': 'kyushu',
  'kumamoto': 'kyushu',
  'oita': 'kyushu',
  'miyazaki': 'kyushu',
  'kagoshima': 'kyushu',
  'okinawa': 'kyushu',
};

const String _baseUrl =
    'https://raw.githubusercontent.com/noanoa31500-byte/maps/main';

// ────────────────────────────────────────
// ハバーサイン距離（km）
// ────────────────────────────────────────
double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLng = (lng2 - lng1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) *
          cos(lat2 * pi / 180) *
          sin(dLng / 2) *
          sin(dLng / 2);
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}

// ────────────────────────────────────────
// TileEntry: タイル1件分のデータ
// ────────────────────────────────────────
class TileEntry {
  final String id;
  final double latMin;
  final double latMax;
  final double lngMin;
  final double lngMax;
  final Map<String, String> files;
  final int sizeKb;
  final String updatedAt;

  const TileEntry({
    required this.id,
    required this.latMin,
    required this.latMax,
    required this.lngMin,
    required this.lngMax,
    required this.files,
    required this.sizeKb,
    required this.updatedAt,
  });

  factory TileEntry.fromJson(Map<String, dynamic> json) {
    final rawFiles = json['files'] as Map<String, dynamic>? ?? {};
    return TileEntry(
      id: json['id'] as String,
      latMin: (json['lat_min'] as num).toDouble(),
      latMax: (json['lat_max'] as num).toDouble(),
      lngMin: (json['lng_min'] as num).toDouble(),
      lngMax: (json['lng_max'] as num).toDouble(),
      files: rawFiles.map((k, v) => MapEntry(k, v as String)),
      sizeKb: (json['size_kb'] as num?)?.toInt() ?? 0,
      updatedAt: json['updated_at'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'lat_min': latMin,
        'lat_max': latMax,
        'lng_min': lngMin,
        'lng_max': lngMax,
        'files': files,
        'size_kb': sizeKb,
        'updated_at': updatedAt,
      };

  // area_id から pref_key（最初の _ までの部分）を返す
  String get prefKey => id.split('_').first;

  // pref_key から region を返す
  String get region => prefToRegion[prefKey] ?? prefKey;

  // 旧構造・新構造の両方のURLを返す（先頭から順に試みる）
  List<String> candidateUrls(String fileKey) {
    final filename = files[fileKey];
    if (filename == null) return [];
    return [
      '$_baseUrl/$prefKey/$filename', // 旧構造
      '$_baseUrl/$region/$prefKey/$id/$filename', // 新構造
    ];
  }

  // bbox 最近傍点までのハバーサイン距離（km）
  double distanceFromPoint(double lat, double lng) {
    final clampedLat = lat.clamp(latMin, latMax);
    final clampedLng = lng.clamp(lngMin, lngMax);
    return haversineKm(lat, lng, clampedLat, clampedLng);
  }
}

// ────────────────────────────────────────
// TileIndex: index.json 全体
// ────────────────────────────────────────
class TileIndex {
  final int version;
  final String updatedAt;
  final List<TileEntry> tiles;

  const TileIndex({
    required this.version,
    required this.updatedAt,
    required this.tiles,
  });

  factory TileIndex.fromJson(Map<String, dynamic> json) {
    final rawTiles = json['tiles'] as List<dynamic>? ?? [];
    return TileIndex(
      version: (json['version'] as num?)?.toInt() ?? 1,
      updatedAt: json['updated_at'] as String? ?? '',
      tiles: rawTiles
          .map((t) => TileEntry.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'updated_at': updatedAt,
        'tiles': tiles.map((t) => t.toJson()).toList(),
      };

  // 現在地から radiusKm 以内に重なるタイルを返す
  List<TileEntry> tilesNear(double lat, double lng, {double radiusKm = 3.0}) {
    return tiles
        .where((t) => t.distanceFromPoint(lat, lng) <= radiusKm)
        .toList();
  }
}
