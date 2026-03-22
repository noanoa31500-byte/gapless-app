import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

/// リスク可視化データを管理するサービス
/// 
/// 防災エンジニアとしての視点:
/// 「どこが水没し、どこで感電するのか」を一目で理解できることが
/// パニック状態のユーザーの命を救います。
class RiskVisualizationService {
  /// 浸水データをパースして円データに変換（compute用）
  static Future<List<FloodCircleData>> loadFloodRiskData(String path) async {
    try {
      final jsonString = await rootBundle.loadString(path);
      return await compute(_parseFloodData, jsonString);
    } catch (e) {
      if (kDebugMode) print('❌ 浸水データ読み込みエラー: $e');
      return [];
    }
  }

  /// 電力設備データをパースして円データに変換（compute用）
  static Future<List<PowerRiskCircleData>> loadPowerRiskData(String path) async {
    try {
      final jsonString = await rootBundle.loadString(path);
      return await compute(_parsePowerData, jsonString);
    } catch (e) {
      if (kDebugMode) print('❌ 電力設備データ読み込みエラー: $e');
      return [];
    }
  }

  /// 浸水データをパース（Isolateで実行）
  static List<FloodCircleData> _parseFloodData(String jsonString) {
    try {
      final List<dynamic> data = jsonDecode(jsonString);
      final List<FloodCircleData> circles = [];

      for (var item in data) {
        final riskScore = item['risk_score'] as int? ?? 0;
        
        // risk_score 0 は描画しない
        if (riskScore == 0) continue;

        final lat = item['lat'] as double?;
        final lon = item['lon'] as double?;
        final predDepth = (item['pred_depth'] as num?)?.toDouble() ?? 0.0;

        if (lat == null || lon == null) continue;

        circles.add(FloodCircleData(
          position: LatLng(lat, lon),
          riskScore: riskScore,
          predDepth: predDepth,
        ));
      }

      if (kDebugMode) {
        debugPrint('✅ 浸水データ: ${circles.length}地点を読み込み');
      }

      return circles;
    } catch (e) {
      if (kDebugMode) print('浸水データパースエラー: $e');
      return [];
    }
  }

  /// 電力設備データをパース（Isolateで実行）
  static List<PowerRiskCircleData> _parsePowerData(String jsonString) {
    try {
      final Map<String, dynamic> geoJson = jsonDecode(jsonString);
      final features = geoJson['features'] as List<dynamic>?;

      if (features == null) return [];

      final List<PowerRiskCircleData> circles = [];

      for (var feature in features) {
        try {
          final geometry = feature['geometry'] as Map<String, dynamic>?;
          final properties = feature['properties'] as Map<String, dynamic>?;

          if (geometry == null) continue;

          final type = geometry['type'] as String?;
          final coordinates = geometry['coordinates'];

          if (type != 'Point' || coordinates == null) continue;

          final coords = coordinates as List;
          if (coords.length < 2) continue;

          final lng = (coords[0] as num).toDouble();
          final lat = (coords[1] as num).toDouble();

          // 電力設備のタイプ
          final powerType = properties?['power'] as String? ?? 'unknown';

          circles.add(PowerRiskCircleData(
            position: LatLng(lat, lng),
            powerType: powerType,
            lat: lat,
            lng: lng,
          ));
        } catch (e) {
          continue;
        }
      }

      if (kDebugMode) {
        debugPrint('✅ 電力設備データ: ${circles.length}箇所を読み込み');
      }

      return circles;
    } catch (e) {
      if (kDebugMode) print('電力設備データパースエラー: $e');
      return [];
    }
  }
}

/// 浸水円データ
class FloodCircleData {
  final LatLng position;
  final int riskScore;
  final double predDepth;

  FloodCircleData({
    required this.position,
    required this.riskScore,
    required this.predDepth,
  });
}

/// 電力設備円データ
class PowerRiskCircleData {
  final LatLng position;
  final String powerType;
  final double lat;
  final double lng;

  PowerRiskCircleData({
    required this.position,
    required this.powerType,
    required this.lat,
    required this.lng,
  });
}
