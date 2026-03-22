import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'offline_risk_scanner.dart';

/// ============================================================================
/// RiskRadarScanner - 洪水時リスク回避レーダースキャナー
/// ============================================================================
/// 
/// 【設計思想】
/// 「画面の赤い方向・雷の方向さえ避ければ生き残れる」
/// を実現するための高度なリスク検知・ルート補正エンジン
/// 
/// 【なぜこの機能が、泥水で視界が悪い洪水時に有効なのか】
/// 
/// ## 1. 感電死は「見えない死」
/// タイの洪水では、水没した電柱・電線からの漏電による感電死が深刻です。
/// 濁った水の中では、電線が沈んでいることを目視で確認することは不可能です。
/// 本機能は、OSMデータから抽出した電力インフラの位置情報を活用し、
/// 「近づいてはいけない方向」を事前に警告します。
/// 
/// ## 2. 激流は突然来る
/// 洪水時、川や排水溝からの水流は予測困難です。
/// 特に膝上（0.5m以上）の水深がある場所では、大人でも流される危険があります。
/// 浸水シミュレーションデータを使い、「深くなる方向」を避けることで
/// 巻き込まれるリスクを低減します。
/// 
/// ## 3. パニック時の認知負荷軽減
/// 災害時、人は複雑な判断ができません。
/// 地図を読んで「どの道が安全か」を判断する余裕はありません。
/// 本機能は「色だけで判断できるUI」を提供します:
/// - 黄色 = 感電危険（雷マーク⚡）
/// - 青色 = 激流危険（波マーク🌊）
/// - 緑色 = 安全方向（矢印✅）
/// 
/// ## 4. 360度全方位の危険を一目で把握
/// 地図アプリでは「前方」しか見えませんが、
/// レーダー表示なら「背後から迫る激流」も同時に把握できます。
/// ============================================================================

/// 危険ゾーンの詳細情報
class DangerZone {
  /// リスクの種類
  final RiskType type;
  
  /// 開始方位角（度）
  final double startBearing;
  
  /// 終了方位角（度）
  final double endBearing;
  
  /// 危険度（0.0-1.0）
  final double severity;
  
  /// 最も近い危険物までの距離（メートル）
  final double distance;
  
  /// 危険物の名称（送電線名など）
  final String name;
  
  /// 詳細情報（電圧、水深など）
  final String details;
  
  /// 元となった座標
  final LatLng? sourceLocation;

  DangerZone({
    required this.type,
    required this.startBearing,
    required this.endBearing,
    required this.severity,
    required this.distance,
    required this.name,
    required this.details,
    this.sourceLocation,
  });

  /// 角度範囲の幅
  double get angularWidth {
    double width = endBearing - startBearing;
    if (width < 0) width += 360;
    return width;
  }

  /// この方位が危険ゾーン内かチェック
  bool containsBearing(double bearing) {
    double b = bearing % 360;
    if (b < 0) b += 360;
    
    double start = startBearing % 360;
    double end = endBearing % 360;
    
    // 境界をまたぐ場合（例: 350度〜10度）
    if (start > end) {
      return b >= start || b <= end;
    }
    return b >= start && b <= end;
  }

  @override
  String toString() => 
    'DangerZone($type: ${startBearing.toInt()}°-${endBearing.toInt()}°, '
    'severity: ${(severity * 100).toInt()}%, dist: ${distance.toInt()}m)';
}

/// 安全方向ガイダンス
class SafetyGuidance {
  /// 推奨方位角
  final double recommendedBearing;
  
  /// 安全範囲の開始
  final double safeBearingStart;
  
  /// 安全範囲の終了
  final double safeBearingEnd;
  
  /// ターゲットへの元の方位角
  final double originalTargetBearing;
  
  /// 補正角度（元の方位からのずれ）
  final double correctionAngle;
  
  /// 補正理由
  final String reason;
  
  /// 補正が必要かどうか
  final bool needsCorrection;
  
  /// 次のウェイポイントまでの距離
  final double? distanceToWaypoint;

  SafetyGuidance({
    required this.recommendedBearing,
    required this.safeBearingStart,
    required this.safeBearingEnd,
    required this.originalTargetBearing,
    required this.correctionAngle,
    required this.reason,
    required this.needsCorrection,
    this.distanceToWaypoint,
  });

  /// 補正後の方向が右か左か
  String get correctionDirection {
    if (!needsCorrection) return '';
    return correctionAngle > 0 ? 'right' : 'left';
  }
}

/// レーダースキャン結果
class RadarScanResult {
  /// 検出された危険ゾーン
  final List<DangerZone> dangerZones;
  
  /// 安全方向ガイダンス
  final SafetyGuidance? safetyGuidance;
  
  /// スキャン半径（メートル）
  final double scanRadius;
  
  /// 現在地
  final LatLng currentLocation;
  
  /// スキャン時刻
  final DateTime timestamp;
  
  /// 全体リスクレベル（0.0-1.0）
  final double overallRiskLevel;
  
  /// 危険カバー率（360度中何%が危険か）
  final double dangerCoveragePercent;

  RadarScanResult({
    required this.dangerZones,
    required this.safetyGuidance,
    required this.scanRadius,
    required this.currentLocation,
    required this.timestamp,
    required this.overallRiskLevel,
    required this.dangerCoveragePercent,
  });

  /// 感電リスクゾーンのみ取得
  List<DangerZone> get electrocutionZones =>
      dangerZones.where((z) => z.type == RiskType.electrocution).toList();

  /// 浸水リスクゾーンのみ取得
  List<DangerZone> get deepWaterZones =>
      dangerZones.where((z) => z.type == RiskType.deepWater).toList();

  /// 激流リスクゾーンのみ取得
  List<DangerZone> get rapidFlowZones =>
      dangerZones.where((z) => z.type == RiskType.rapidFlow).toList();

  /// 指定方位のリスクを取得
  List<DangerZone> getRisksAtBearing(double bearing) =>
      dangerZones.where((z) => z.containsBearing(bearing)).toList();

  /// 指定方位が安全かチェック
  bool isSafe(double bearing) => getRisksAtBearing(bearing).isEmpty;

  /// 最も重大なリスクを取得
  DangerZone? get mostSevereRisk =>
      dangerZones.isEmpty ? null : 
      dangerZones.reduce((a, b) => a.severity > b.severity ? a : b);
}

/// ============================================================================
/// RiskRadarScanner - メインクラス
/// ============================================================================
class RiskRadarScanner {
  final OfflineRiskScanner _baseScanner;
  
  /// 補正時の最小角度ステップ（度）
  static const double _correctionStep = 10.0;
  
  /// 最大補正角度（度）
  static const double _maxCorrectionAngle = 90.0;

  RiskRadarScanner(this._baseScanner);

  /// データがロード済みかチェック
  bool get isReady => _baseScanner.isLoaded;

  /// データをロード
  Future<void> loadData() async {
    await _baseScanner.loadData();
  }

  /// ============================================================================
  /// scanRadar - 360度リスクスキャン
  /// ============================================================================
  /// 
  /// @param currentLocation 現在地
  /// @param targetLocation 目的地（ウェイポイント）
  /// @param waypoints ルートウェイポイント（オプション）
  /// @param scanRadius スキャン半径（メートル）
  /// @return RadarScanResult スキャン結果
  RadarScanResult scanRadar({
    required LatLng currentLocation,
    LatLng? targetLocation,
    List<LatLng>? waypoints,
    double scanRadius = 100.0,
  }) {
    // 基本スキャンを実行
    final baseResult = _baseScanner.scanRisks(currentLocation, radius: scanRadius);
    
    // RiskZone を DangerZone に変換
    final dangerZones = baseResult.riskZones.map((rz) => DangerZone(
      type: rz.type,
      startBearing: rz.startBearing,
      endBearing: rz.endBearing,
      severity: rz.severity,
      distance: rz.nearestDistance,
      name: _getRiskTypeName(rz.type),
      details: rz.details,
    )).toList();
    
    // 安全ガイダンスを計算
    SafetyGuidance? guidance;
    if (targetLocation != null) {
      guidance = _calculateSafetyGuidance(
        currentLocation: currentLocation,
        targetLocation: targetLocation,
        dangerZones: dangerZones,
        waypoints: waypoints,
      );
    }
    
    // 危険カバー率を計算
    final dangerCoverage = _calculateDangerCoverage(dangerZones);
    
    return RadarScanResult(
      dangerZones: dangerZones,
      safetyGuidance: guidance,
      scanRadius: scanRadius,
      currentLocation: currentLocation,
      timestamp: DateTime.now(),
      overallRiskLevel: baseResult.overallRisk,
      dangerCoveragePercent: dangerCoverage,
    );
  }

  /// リスクタイプの名前を取得
  String _getRiskTypeName(RiskType type) {
    switch (type) {
      case RiskType.electrocution:
        return '送電線/電力設備';
      case RiskType.deepWater:
        return '深水域';
      case RiskType.rapidFlow:
        return '激流';
    }
  }

  /// ============================================================================
  /// _calculateSafetyGuidance - 安全方向ガイダンスを計算
  /// ============================================================================
  SafetyGuidance _calculateSafetyGuidance({
    required LatLng currentLocation,
    required LatLng targetLocation,
    required List<DangerZone> dangerZones,
    List<LatLng>? waypoints,
  }) {
    // ターゲットへの方位角を計算
    final targetBearing = _calculateBearing(currentLocation, targetLocation);
    final distanceToTarget = _haversineDistance(currentLocation, targetLocation);
    
    // ターゲット方向にリスクがあるかチェック
    final risksInTargetDirection = dangerZones
        .where((z) => z.containsBearing(targetBearing))
        .toList();
    
    // リスクがなければ補正不要
    if (risksInTargetDirection.isEmpty) {
      return SafetyGuidance(
        recommendedBearing: targetBearing,
        safeBearingStart: (targetBearing - 30 + 360) % 360,
        safeBearingEnd: (targetBearing + 30) % 360,
        originalTargetBearing: targetBearing,
        correctionAngle: 0,
        reason: '',
        needsCorrection: false,
        distanceToWaypoint: distanceToTarget,
      );
    }
    
    // 補正角度を探索
    double bestCorrectionAngle = 0;
    String correctionReason = '';
    
    // 左右両方向で安全な角度を探す
    for (double offset = _correctionStep; 
         offset <= _maxCorrectionAngle; 
         offset += _correctionStep) {
      // 右方向をチェック
      final rightBearing = (targetBearing + offset) % 360;
      final rightRisks = dangerZones.where((z) => z.containsBearing(rightBearing)).toList();
      
      if (rightRisks.isEmpty) {
        bestCorrectionAngle = offset;
        correctionReason = _buildCorrectionReason(risksInTargetDirection, 'right');
        break;
      }
      
      // 左方向をチェック
      final leftBearing = (targetBearing - offset + 360) % 360;
      final leftRisks = dangerZones.where((z) => z.containsBearing(leftBearing)).toList();
      
      if (leftRisks.isEmpty) {
        bestCorrectionAngle = -offset;
        correctionReason = _buildCorrectionReason(risksInTargetDirection, 'left');
        break;
      }
    }
    
    // 補正後の方位
    final correctedBearing = (targetBearing + bestCorrectionAngle + 360) % 360;
    
    // 安全範囲を計算
    final safeRange = _findSafeRange(correctedBearing, dangerZones);
    
    return SafetyGuidance(
      recommendedBearing: correctedBearing,
      safeBearingStart: safeRange['start']!,
      safeBearingEnd: safeRange['end']!,
      originalTargetBearing: targetBearing,
      correctionAngle: bestCorrectionAngle,
      reason: correctionReason,
      needsCorrection: bestCorrectionAngle != 0,
      distanceToWaypoint: distanceToTarget,
    );
  }

  /// 補正理由を構築
  String _buildCorrectionReason(List<DangerZone> risks, String direction) {
    if (risks.isEmpty) return '';
    
    final mainRisk = risks.reduce((a, b) => a.severity > b.severity ? a : b);
    final riskName = _getRiskTypeNameShort(mainRisk.type);
    final distance = mainRisk.distance.toInt();
    
    return '$riskName($distance m)を避けて${direction == 'right' ? '右' : '左'}へ迂回';
  }

  /// リスクタイプの短い名前
  String _getRiskTypeNameShort(RiskType type) {
    switch (type) {
      case RiskType.electrocution:
        return '⚡感電危険';
      case RiskType.deepWater:
        return '🌊深水';
      case RiskType.rapidFlow:
        return '💨激流';
    }
  }

  /// 安全範囲を見つける
  Map<String, double> _findSafeRange(double bearing, List<DangerZone> zones) {
    // 指定方位から広がる安全範囲を探す
    double safeStart = bearing;
    double safeEnd = bearing;
    
    // 左方向に広げる
    for (double offset = 0; offset <= 180; offset += 5) {
      final testBearing = (bearing - offset + 360) % 360;
      if (zones.any((z) => z.containsBearing(testBearing))) {
        break;
      }
      safeStart = testBearing;
    }
    
    // 右方向に広げる
    for (double offset = 0; offset <= 180; offset += 5) {
      final testBearing = (bearing + offset) % 360;
      if (zones.any((z) => z.containsBearing(testBearing))) {
        break;
      }
      safeEnd = testBearing;
    }
    
    return {'start': safeStart, 'end': safeEnd};
  }

  /// 危険カバー率を計算
  double _calculateDangerCoverage(List<DangerZone> zones) {
    if (zones.isEmpty) return 0.0;
    
    // 重複を考慮して危険角度を計算
    final Set<int> dangerDegrees = {};
    
    for (final zone in zones) {
      double start = zone.startBearing;
      double end = zone.endBearing;
      
      if (start > end) {
        // 境界をまたぐ場合
        for (int d = start.toInt(); d < 360; d++) {
          dangerDegrees.add(d);
        }
        for (int d = 0; d <= end.toInt(); d++) {
          dangerDegrees.add(d);
        }
      } else {
        for (int d = start.toInt(); d <= end.toInt(); d++) {
          dangerDegrees.add(d % 360);
        }
      }
    }
    
    return dangerDegrees.length / 360.0 * 100;
  }

  /// 2点間の方位角を計算
  double _calculateBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLon = (to.longitude - from.longitude) * math.pi / 180;
    
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    
    final bearing = math.atan2(y, x) * 180 / math.pi;
    return (bearing + 360) % 360;
  }

  /// ハーバーサイン距離（メートル）
  double _haversineDistance(LatLng p1, LatLng p2) {
    const R = 6371000.0;
    final lat1 = p1.latitude * math.pi / 180;
    final lat2 = p2.latitude * math.pi / 180;
    final dLat = (p2.latitude - p1.latitude) * math.pi / 180;
    final dLon = (p2.longitude - p1.longitude) * math.pi / 180;
    
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    
    return R * c;
  }

  /// ============================================================================
  /// checkRouteSegmentSafety - ルートセグメントの安全性チェック
  /// ============================================================================
  /// 
  /// 指定した2点間の直線上にリスクがあるかチェックします。
  /// 
  /// @param from 始点
  /// @param to 終点
  /// @param scanRadius スキャン半径
  /// @return 発見されたリスク
  List<DangerZone> checkRouteSegmentSafety({
    required LatLng from,
    required LatLng to,
    double scanRadius = 50.0,
  }) {
    final result = scanRadar(
      currentLocation: from,
      targetLocation: to,
      scanRadius: scanRadius,
    );
    
    final targetBearing = _calculateBearing(from, to);
    return result.getRisksAtBearing(targetBearing);
  }

  /// デバッグ出力
  void printDebugInfo(RadarScanResult result) {
    if (!kDebugMode) return;
    
    debugPrint('''
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 RiskRadarScanner Results
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📍 Location: (${result.currentLocation.latitude.toStringAsFixed(5)}, ${result.currentLocation.longitude.toStringAsFixed(5)})
📡 Scan Radius: ${result.scanRadius}m
⚠️ Overall Risk: ${(result.overallRiskLevel * 100).toStringAsFixed(0)}%
🔴 Danger Coverage: ${result.dangerCoveragePercent.toStringAsFixed(1)}%

⚡ Electrocution Zones: ${result.electrocutionZones.length}
${result.electrocutionZones.map((z) => '   ${z.startBearing.toInt()}°-${z.endBearing.toInt()}° (${z.distance.toInt()}m)').join('\n')}

🌊 Deep Water Zones: ${result.deepWaterZones.length}
${result.deepWaterZones.map((z) => '   ${z.startBearing.toInt()}°-${z.endBearing.toInt()}° (${z.details})').join('\n')}

${result.safetyGuidance != null ? '''
🧭 Safety Guidance:
   Original: ${result.safetyGuidance!.originalTargetBearing.toInt()}°
   Corrected: ${result.safetyGuidance!.recommendedBearing.toInt()}°
   Correction: ${result.safetyGuidance!.correctionAngle.toInt()}°
   Reason: ${result.safetyGuidance!.reason}
''' : ''}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''');
  }
}
