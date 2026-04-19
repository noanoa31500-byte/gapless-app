import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

/// リスク可視化データを管理するサービス
///
/// 防災エンジニアとしての視点:
/// 「どこが水没するのか」を一目で理解できることが
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
