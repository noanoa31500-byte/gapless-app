import 'package:latlong2/latlong.dart';

/// 避難所データモデル
class Shelter {
  final String id;
  final String name;
  final double lat;
  final double lng;
  final String type; // 'school', 'hospital', 'gov', 'shelter', 'temple', etc.
  final bool verified; // 公式データかどうか
  final String? region; // 'Japan' or 'Thailand'
  final bool isFloodShelter; // 洪水時避難可能か（高台にある、など）

  const Shelter({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.type,
    required this.verified,
    this.region,
    this.isFloodShelter = false,
  });

  LatLng get position => LatLng(lat, lng);

  /// JSONからShelterオブジェクトを生成
  factory Shelter.fromJson(Map<String, dynamic> json) {
    return Shelter(
      id: json['id'] as String,
      name: json['name'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      type: json['type'] as String? ?? 'shelter',
      verified: json['verified'] as bool? ?? false,
      region: json['region'] as String?,
      isFloodShelter: json['isFloodShelter'] as bool? ?? false,
    );
  }

  /// ShelterオブジェクトをJSON形式に変換
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'lat': lat,
      'lng': lng,
      'type': type,
      'verified': verified,
      'isFloodShelter': isFloodShelter,
      if (region != null) 'region': region,
    };
  }

  @override
  String toString() {
    return 'Shelter(id: $id, name: $name, type: $type, lat: $lat, lng: $lng, verified: $verified)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Shelter && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
