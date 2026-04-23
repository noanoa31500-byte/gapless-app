// lib/data/poi_catalog.dart
// POI種別カタログ・バイナリパーサー（poi_definitions.dart の後継）
// convenience / supply / landmark カテゴリを分離し、
// GplbPoiParser.parseAndGroup() でグループ化して返す。

import 'dart:typed_data';
import 'dart:convert';

// ============================================================================
// PoiCategory — POIの大分類
// ============================================================================

enum PoiCategory {
  shelter, // 避難所
  hospital, // 病院・医療機関
  convenience, // コンビニ・スーパー（食料・日用品調達）
  supply, // 給水所・自販機（水・物資補給）
  landmark, // ランドマーク（その他施設）
}

// ============================================================================
// PoiType — gplb バイナリの type_id に対応する種別定義
// ============================================================================

class PoiType {
  final int id;
  final String labelJa;
  final PoiCategory category;

  const PoiType({
    required this.id,
    required this.labelJa,
    required this.category,
  });

  // --- 避難所 (20–29) ---
  static const shelterFlood = PoiType(
    id: 20,
    labelJa: '避難所（洪水対応）',
    category: PoiCategory.shelter,
  );
  static const shelterEarthquake = PoiType(
    id: 21,
    labelJa: '避難所（地震対応）',
    category: PoiCategory.shelter,
  );
  static const shelterGeneral = PoiType(
    id: 22,
    labelJa: '避難所',
    category: PoiCategory.shelter,
  );

  // --- コンビニ・スーパー (30–31) ---
  static const convenience = PoiType(
    id: 30,
    labelJa: 'コンビニ',
    category: PoiCategory.convenience,
  );
  static const supermarket = PoiType(
    id: 31,
    labelJa: 'スーパー',
    category: PoiCategory.convenience,
  );

  // --- 給水・補給 (32–33) ---
  static const drinkingWater = PoiType(
    id: 32,
    labelJa: '給水所',
    category: PoiCategory.supply,
  );
  static const vendingMachine = PoiType(
    id: 33,
    labelJa: '自販機',
    category: PoiCategory.supply,
  );

  // --- 病院 (40–49) ---
  static const hospital = PoiType(
    id: 40,
    labelJa: '病院',
    category: PoiCategory.hospital,
  );

  // --- ランドマーク (90+) ---
  static const landmark = PoiType(
    id: 90,
    labelJa: 'ランドマーク',
    category: PoiCategory.landmark,
  );

  /// type_id から PoiType を取得。未知のIDは landmark を返す。
  static PoiType fromId(int id) {
    return switch (id) {
      20 => shelterFlood,
      21 => shelterEarthquake,
      22 => shelterGeneral,
      30 => convenience,
      31 => supermarket,
      32 => drinkingWater,
      33 => vendingMachine,
      40 => hospital,
      _ => landmark,
    };
  }
}

// ============================================================================
// PoiFeature — バイナリパーサーが返す POI データモデル
// ============================================================================

class PoiFeature {
  final PoiType type;
  final double lat;
  final double lng;

  /// 収容人数（避難所のみ。それ以外は 0）
  final int capacity;

  /// 災害種別ビットフラグ（避難所のみ有効）
  ///   bit0=洪水 bit1=土砂 bit2=地震 bit3=津波 bit4=火災 bit5=浸水
  final int flags;

  final String name;

  const PoiFeature({
    required this.type,
    required this.lat,
    required this.lng,
    required this.capacity,
    required this.flags,
    required this.name,
  });

  // --- カテゴリ判定 ---
  bool get isShelter => type.category == PoiCategory.shelter;
  bool get isHospital => type.category == PoiCategory.hospital;
  bool get isConvenience => type.category == PoiCategory.convenience;
  bool get isSupply => type.category == PoiCategory.supply;
  bool get isLandmark => type.category == PoiCategory.landmark;

  // --- 災害種別フラグ（避難所のみ有効） ---
  bool get handlesFlood => flags & 1 != 0;
  bool get handlesLandslide => flags & 2 != 0;
  bool get handlesEarthquake => flags & 4 != 0;
  bool get handlesTsunami => flags & 8 != 0;
  bool get handlesFire => flags & 16 != 0;
  bool get handlesInundation => flags & 32 != 0;
}

// ============================================================================
// GplbPoiParser — POI バイナリを解析してグループ化して返す
//
// バイナリフォーマット（tokyo_center_poi.gplb など）:
//   [0-3]  マジック "GPLB"
//   [4]    バージョン UInt8
//   [5-8]  レコード数 UInt32 LittleEndian
//   レコード繰り返し:
//     [0]     type_id   UInt8
//     [1-4]   lat*1e6   Int32 LittleEndian
//     [5-8]   lng*1e6   Int32 LittleEndian
//     [9-10]  capacity  UInt16 LittleEndian
//     [11]    flags     UInt8
//     [12]    name_len  UInt8
//     [13+]   name      UTF-8 (name_len bytes)
// ============================================================================

class GplbPoiParser {
  /// バイナリを解析し、PoiFeature のリストを返す
  static List<PoiFeature> parse(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);

    if (bytes.length < 9) throw Exception('GPLBデータが短すぎます');
    final magic = String.fromCharCodes(bytes.sublist(0, 4));
    if (magic != 'GPLB') throw Exception('不正なGPLBファイルです (magic: $magic)');

    final count = bd.getUint32(5, Endian.little);
    int offset = 9;
    final result = <PoiFeature>[];

    for (int i = 0; i < count; i++) {
      if (offset + 13 > bytes.length) break;

      final typeId = bytes[offset];
      final lat = bd.getInt32(offset + 1, Endian.little) / 1e6;
      final lng = bd.getInt32(offset + 5, Endian.little) / 1e6;
      final capacity = bd.getUint16(offset + 9, Endian.little);
      final flags = bytes[offset + 11];
      final nameLen = bytes[offset + 12];
      final nameEnd = offset + 13 + nameLen;
      if (nameEnd > bytes.length) break;

      // utf8 デコード時に不正バイトは U+FFFD (置換文字 �) になるため、
      // 末尾の � を削除して表示時の豆腐文字を防ぐ。
      final rawName = nameLen > 0
          ? utf8.decode(bytes.sublist(offset + 13, nameEnd),
              allowMalformed: true)
          : '（名称不明）';
      final name = rawName.replaceAll('�', '').trim().isEmpty
          ? '（名称不明）'
          : rawName.replaceAll('�', '').trim();
      offset = nameEnd;

      result.add(PoiFeature(
        type: PoiType.fromId(typeId),
        lat: lat,
        lng: lng,
        capacity: capacity,
        flags: flags,
        name: name,
      ));
    }

    return result;
  }

  /// バイナリを解析し、PoiCategory をキーとするグループ Map を返す。
  /// 全カテゴリのキーが必ず存在する（空リストの場合もある）。
  static Map<PoiCategory, List<PoiFeature>> parseAndGroup(Uint8List bytes) {
    final features = parse(bytes);
    return {
      for (final cat in PoiCategory.values)
        cat: features.where((f) => f.type.category == cat).toList(),
    };
  }
}
