import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:vibration/vibration.dart';

/// ============================================================================
/// SmartCompassJapan - 日本版スマートコンパス（地震・倒壊リスク回避モード）
/// ============================================================================
/// 
/// 【設計思想】
/// 地震発生直後、被災者はパニック状態にあり、地図を読む認知的余裕がありません。
/// 本システムは「時計の針」という日常的な概念を使い、
/// 「2時の方向に歩いて」という直感的な音声/視覚/触覚ガイダンスを提供します。
/// 
/// 【技術的特徴】
/// 1. 磁気偏角補正: 大崎市周辺の偏角（約8.5度西）を考慮した真方位計算
/// 2. クロックナビゲーション: 12方位を時計の文字盤に対応付け
/// 3. ハプティックフィードバック: 正しい方向を向いた瞬間に振動
/// 4. 視覚障害者対応: 画面を見なくても進路がわかる
/// ============================================================================

/// クロック方向（時計の文字盤）
enum ClockDirection {
  twelve,   // 12時 - 真っすぐ
  one,      // 1時 - 右斜め前
  two,      // 2時 - 右前
  three,    // 3時 - 真右
  four,     // 4時 - 右後ろ
  five,     // 5時 - 右斜め後ろ
  six,      // 6時 - 真後ろ
  seven,    // 7時 - 左斜め後ろ
  eight,    // 8時 - 左後ろ
  nine,     // 9時 - 真左
  ten,      // 10時 - 左前
  eleven,   // 11時 - 左斜め前
}

/// クロックナビゲーション結果
class ClockNavigationResult {
  /// 時計方向
  final ClockDirection clockDirection;
  
  /// 角度差（-180〜180度）
  final double angleDifference;
  
  /// 正しい方向を向いているか（±15度以内）
  final bool isOnTarget;
  
  /// ほぼ正しい方向か（±30度以内）
  final bool isNearTarget;
  
  /// ターゲットへの距離（メートル）
  final double distanceToTarget;
  
  /// 補正済み方位角（真北基準）
  final double trueBearing;
  
  /// 端末の向き（磁北基準）
  final double deviceHeading;
  
  /// 偏角補正値
  final double declinationCorrection;

  ClockNavigationResult({
    required this.clockDirection,
    required this.angleDifference,
    required this.isOnTarget,
    required this.isNearTarget,
    required this.distanceToTarget,
    required this.trueBearing,
    required this.deviceHeading,
    required this.declinationCorrection,
  });

  /// 日本語での方向指示
  String get japaneseDirection {
    switch (clockDirection) {
      case ClockDirection.twelve:
        return 'そのまま真っすぐ';
      case ClockDirection.one:
        return '1時の方向（右斜め前）';
      case ClockDirection.two:
        return '2時の方向（右前）';
      case ClockDirection.three:
        return '右を向いて';
      case ClockDirection.four:
        return '4時の方向（右後ろ）';
      case ClockDirection.five:
        return '5時の方向';
      case ClockDirection.six:
        return 'Uターンしてください';
      case ClockDirection.seven:
        return '7時の方向';
      case ClockDirection.eight:
        return '8時の方向（左後ろ）';
      case ClockDirection.nine:
        return '左を向いて';
      case ClockDirection.ten:
        return '10時の方向（左前）';
      case ClockDirection.eleven:
        return '11時の方向（左斜め前）';
    }
  }

  /// 英語での方向指示
  String get englishDirection {
    switch (clockDirection) {
      case ClockDirection.twelve:
        return 'Go straight ahead';
      case ClockDirection.one:
        return '1 o\'clock (slight right)';
      case ClockDirection.two:
        return '2 o\'clock (right front)';
      case ClockDirection.three:
        return 'Turn right';
      case ClockDirection.four:
        return '4 o\'clock';
      case ClockDirection.five:
        return '5 o\'clock';
      case ClockDirection.six:
        return 'Turn around';
      case ClockDirection.seven:
        return '7 o\'clock';
      case ClockDirection.eight:
        return '8 o\'clock (left rear)';
      case ClockDirection.nine:
        return 'Turn left';
      case ClockDirection.ten:
        return '10 o\'clock (left front)';
      case ClockDirection.eleven:
        return '11 o\'clock (slight left)';
    }
  }

  /// タイ語での方向指示
  String get thaiDirection {
    switch (clockDirection) {
      case ClockDirection.twelve:
        return 'ตรงไปเลย';
      case ClockDirection.one:
        return '1 นาฬิกา (เฉียงขวา)';
      case ClockDirection.two:
        return '2 นาฬิกา (ขวาหน้า)';
      case ClockDirection.three:
        return 'เลี้ยวขวา';
      case ClockDirection.four:
        return '4 นาฬิกา';
      case ClockDirection.five:
        return '5 นาฬิกา';
      case ClockDirection.six:
        return 'กลับหลัง';
      case ClockDirection.seven:
        return '7 นาฬิกา';
      case ClockDirection.eight:
        return '8 นาฬิกา (ซ้ายหลัง)';
      case ClockDirection.nine:
        return 'เลี้ยวซ้าย';
      case ClockDirection.ten:
        return '10 นาฬิกา (ซ้ายหน้า)';
      case ClockDirection.eleven:
        return '11 นาฬิกา (เฉียงซ้าย)';
    }
  }

  /// 言語に応じた方向指示を取得
  String getDirection(String lang) {
    switch (lang) {
      case 'ja':
        return japaneseDirection;
      case 'th':
        return thaiDirection;
      default:
        return englishDirection;
    }
  }

  /// 短い方向指示（UI表示用）
  String get shortDirection {
    switch (clockDirection) {
      case ClockDirection.twelve:
        return '12時';
      case ClockDirection.one:
        return '1時';
      case ClockDirection.two:
        return '2時';
      case ClockDirection.three:
        return '3時';
      case ClockDirection.four:
        return '4時';
      case ClockDirection.five:
        return '5時';
      case ClockDirection.six:
        return '6時';
      case ClockDirection.seven:
        return '7時';
      case ClockDirection.eight:
        return '8時';
      case ClockDirection.nine:
        return '9時';
      case ClockDirection.ten:
        return '10時';
      case ClockDirection.eleven:
        return '11時';
    }
  }

  /// アイコンを取得（回転角度を示す）
  double get iconRotation => angleDifference * (math.pi / 180);
}

/// ============================================================================
/// SmartCompassJapan - メインクラス
/// ============================================================================
class SmartCompassJapan with ChangeNotifier {
  /// ============================================================================
  /// 磁気偏角設定（日本各地）
  /// ============================================================================
  /// 
  /// 【磁気偏角とは】
  /// 磁北（コンパスが指す北）と真北（地図の北）のずれ。
  /// 日本では西偏（磁北が真北より西）しています。
  /// 
  /// 【なぜ補正が必要か】
  /// GPSは真北基準、コンパスは磁北基準。
  /// この差を補正しないと、被災者を間違った方向に誘導してしまいます。
  /// 
  /// 【地域別偏角（2024年時点の概算値）】
  /// - 北海道（札幌）: 約9.5度西
  /// - 東北（大崎市）: 約8.5度西
  /// - 関東（東京）: 約7.5度西
  /// - 関西（大阪）: 約7.0度西
  /// - 九州（福岡）: 約6.5度西
  /// - 沖縄（那覇）: 約5.0度西
  static const Map<String, double> regionalDeclination = {
    'hokkaido': -9.5,
    'tohoku': -8.5,    // 大崎市はここ
    'kanto': -7.5,
    'chubu': -7.5,
    'kansai': -7.0,
    'chugoku': -6.5,
    'shikoku': -6.5,
    'kyushu': -6.5,
    'okinawa': -5.0,
  };

  /// 大崎市（宮城県）の偏角
  /// 負の値 = 西偏（磁北が真北より西にある）
  static const double osakiDeclination = -8.5;

  /// ハプティックフィードバックのクールダウン（連続振動を防ぐ）
  static const Duration hapticCooldown = Duration(milliseconds: 500);

  /// 正しい方向の判定閾値（度）
  static const double onTargetThreshold = 15.0;

  /// ほぼ正しい方向の判定閾値（度）
  static const double nearTargetThreshold = 30.0;

  // === 状態 ===
  double _currentDeclination = osakiDeclination;
  DateTime? _lastHapticTime;
  bool _hapticEnabled = true;
  bool _isOnTargetPrevious = false;

  // === Getters ===
  double get currentDeclination => _currentDeclination;
  bool get hapticEnabled => _hapticEnabled;

  /// 偏角を設定（地域変更時）
  void setDeclination(double declination) {
    _currentDeclination = declination;
    notifyListeners();
  }

  /// 地域名から偏角を設定
  void setRegion(String region) {
    _currentDeclination = regionalDeclination[region] ?? osakiDeclination;
    notifyListeners();
    
    if (kDebugMode) {
      debugPrint('🧭 偏角設定: $region = ${_currentDeclination}度');
    }
  }

  /// ハプティックフィードバックの有効/無効切り替え
  void setHapticEnabled(bool enabled) {
    _hapticEnabled = enabled;
    notifyListeners();
  }

  /// ============================================================================
  /// calculateTrueBearing - 真方位角を計算
  /// ============================================================================
  /// 
  /// 【計算式】
  /// 真方位 = GPS方位 （GPSはすでに真北基準）
  /// 
  /// 【注意】
  /// Geolocator.bearingBetween() は真北基準の方位を返すため、
  /// この結果自体には偏角補正は不要。
  /// 
  /// 偏角補正が必要なのは「端末のコンパス（磁北基準）」との比較時。
  double calculateTrueBearing({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) {
    // Geolocatorは真北基準の方位を返す
    final bearing = Geolocator.bearingBetween(fromLat, fromLng, toLat, toLng);
    return bearing;
  }

  /// ============================================================================
  /// correctMagneticHeading - 磁北→真北への補正
  /// ============================================================================
  /// 
  /// 【計算式】
  /// 真北方位 = 磁北方位 + 偏角
  /// 
  /// 【例：大崎市の場合】
  /// 偏角 = -8.5度（西偏）
  /// コンパスが0度（磁北）を指している時、真北は -(-8.5) = +8.5度の方向
  /// つまり、磁北方位に偏角を加算すると真北方位になる
  /// 
  /// 【実装上の注意】
  /// 偏角は「西偏なら負、東偏なら正」で定義しているため、
  /// 真北方位 = 磁北方位 - 偏角 となる（符号に注意）
  double correctMagneticHeading(double magneticHeading) {
    // 真北方位 = 磁北方位 - 偏角（西偏は負なので、引くと足す効果）
    double trueHeading = magneticHeading - _currentDeclination;
    
    // 0-360度に正規化
    while (trueHeading < 0) trueHeading += 360;
    while (trueHeading >= 360) trueHeading -= 360;
    
    return trueHeading;
  }

  /// ============================================================================
  /// calculateClockDirection - クロックナビゲーション計算
  /// ============================================================================
  /// 
  /// 【アルゴリズム】
  /// 1. ターゲットへの真方位を計算
  /// 2. 端末の向き（磁北基準）を真北に補正
  /// 3. 方位差を計算（-180〜180度）
  /// 4. 時計の文字盤（12方位）に変換
  /// 
  /// 【なぜ「時計」なのか】
  /// - 誰でも直感的に理解できる
  /// - 「右」「左」より精度が高い（30度刻み）
  /// - 音声案内との親和性が高い
  /// - パニック時でも処理できる認知負荷
  ClockNavigationResult calculateClockDirection({
    required LatLng currentLocation,
    required LatLng targetLocation,
    required double deviceHeading, // 磁北基準のコンパス値
  }) {
    // 1. ターゲットへの真方位（GPSは真北基準）
    final trueBearing = calculateTrueBearing(
      fromLat: currentLocation.latitude,
      fromLng: currentLocation.longitude,
      toLat: targetLocation.latitude,
      toLng: targetLocation.longitude,
    );

    // 2. 端末の向きを真北基準に補正
    final truHeading = correctMagneticHeading(deviceHeading);

    // 3. 方位差を計算（正: 右回り、負: 左回り）
    double angleDiff = trueBearing - truHeading;
    
    // -180〜180度に正規化
    while (angleDiff > 180) angleDiff -= 360;
    while (angleDiff < -180) angleDiff += 360;

    // 4. 距離を計算
    final distance = Geolocator.distanceBetween(
      currentLocation.latitude,
      currentLocation.longitude,
      targetLocation.latitude,
      targetLocation.longitude,
    );

    // 5. 時計方向に変換
    final clockDir = _angleToClockDirection(angleDiff);

    // 6. ターゲット判定
    final isOnTarget = angleDiff.abs() <= onTargetThreshold;
    final isNearTarget = angleDiff.abs() <= nearTargetThreshold;

    // 7. ハプティックフィードバック
    if (_hapticEnabled && isOnTarget && !_isOnTargetPrevious) {
      _triggerHapticFeedback();
    }
    _isOnTargetPrevious = isOnTarget;

    return ClockNavigationResult(
      clockDirection: clockDir,
      angleDifference: angleDiff,
      isOnTarget: isOnTarget,
      isNearTarget: isNearTarget,
      distanceToTarget: distance,
      trueBearing: trueBearing,
      deviceHeading: deviceHeading,
      declinationCorrection: _currentDeclination,
    );
  }

  /// 角度差を時計方向に変換
  ClockDirection _angleToClockDirection(double angleDiff) {
    // 角度を0-360に正規化
    double normalized = angleDiff;
    while (normalized < 0) normalized += 360;
    while (normalized >= 360) normalized -= 360;

    // 30度刻みで12方位に変換
    // 各方向の中心: 0(12時), 30(1時), 60(2時), ...
    // 判定範囲: 中心±15度
    
    if (normalized >= 345 || normalized < 15) return ClockDirection.twelve;
    if (normalized >= 15 && normalized < 45) return ClockDirection.one;
    if (normalized >= 45 && normalized < 75) return ClockDirection.two;
    if (normalized >= 75 && normalized < 105) return ClockDirection.three;
    if (normalized >= 105 && normalized < 135) return ClockDirection.four;
    if (normalized >= 135 && normalized < 165) return ClockDirection.five;
    if (normalized >= 165 && normalized < 195) return ClockDirection.six;
    if (normalized >= 195 && normalized < 225) return ClockDirection.seven;
    if (normalized >= 225 && normalized < 255) return ClockDirection.eight;
    if (normalized >= 255 && normalized < 285) return ClockDirection.nine;
    if (normalized >= 285 && normalized < 315) return ClockDirection.ten;
    return ClockDirection.eleven;
  }

  /// ============================================================================
  /// ハプティックフィードバック
  /// ============================================================================
  /// 
  /// 【なぜバイブレーションが重要か】
  /// 1. 視覚障害者への対応
  /// 2. 夜間・悪天候時の視認性低下
  /// 3. 画面を見続ける余裕がないパニック状態
  /// 4. 両手がふさがっている状況（子供を抱えている等）
  /// 
  /// 【フィードバックパターン】
  /// - 正解方向を向いた瞬間: 短い振動（確認）
  /// - 将来拡張: 距離に応じた振動パターン
  Future<void> _triggerHapticFeedback() async {
    // クールダウンチェック
    final now = DateTime.now();
    if (_lastHapticTime != null &&
        now.difference(_lastHapticTime!) < hapticCooldown) {
      return;
    }
    _lastHapticTime = now;

    try {
      // まずHapticFeedbackを試行（より軽量）
      await HapticFeedback.lightImpact();
      
      // Vibrationパッケージでより強いフィードバック（対応端末のみ）
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) {
        // 短いパルス振動（50ms × 2回）
        await Vibration.vibrate(pattern: [0, 50, 50, 50], intensities: [0, 128, 0, 128]);
      }
      
      if (kDebugMode) {
        debugPrint('📳 ハプティックフィードバック発生');
      }
    } catch (e) {
      // バイブレーション非対応デバイス（Web等）
      if (kDebugMode) {
        debugPrint('⚠️ ハプティックフィードバック非対応: $e');
      }
    }
  }

  /// 手動でハプティックフィードバックをトリガー（到着時など）
  Future<void> triggerArrivalHaptic() async {
    try {
      await HapticFeedback.heavyImpact();
      
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) {
        // 到着パターン（長めの振動）
        await Vibration.vibrate(pattern: [0, 200, 100, 200, 100, 200], intensities: [0, 255, 0, 255, 0, 255]);
      }
    } catch (e) {
      // 非対応デバイス
    }
  }

  /// ============================================================================
  /// getNavigationGuidance - 総合的なナビゲーションガイダンス
  /// ============================================================================
  String getNavigationGuidance({
    required ClockNavigationResult result,
    required String lang,
  }) {
    final direction = result.getDirection(lang);
    final distance = _formatDistance(result.distanceToTarget, lang);

    if (result.isOnTarget) {
      switch (lang) {
        case 'ja':
          return '✓ $direction\n$distance';
        case 'th':
          return '✓ $direction\n$distance';
        default:
          return '✓ $direction\n$distance';
      }
    } else {
      return '$direction\n$distance';
    }
  }

  String _formatDistance(double meters, String lang) {
    if (meters < 100) {
      switch (lang) {
        case 'ja':
          return 'あと ${meters.toStringAsFixed(0)}m';
        case 'th':
          return 'อีก ${meters.toStringAsFixed(0)} ม.';
        default:
          return '${meters.toStringAsFixed(0)}m left';
      }
    } else if (meters < 1000) {
      final rounded = (meters / 10).round() * 10;
      switch (lang) {
        case 'ja':
          return 'あと ${rounded}m';
        case 'th':
          return 'อีก $rounded ม.';
        default:
          return '${rounded}m left';
      }
    } else {
      final km = (meters / 1000).toStringAsFixed(1);
      switch (lang) {
        case 'ja':
          return 'あと ${km}km';
        case 'th':
          return 'อีก $km กม.';
        default:
          return '${km}km left';
      }
    }
  }

  /// デバッグ情報出力
  void printDebugInfo(ClockNavigationResult result) {
    if (!kDebugMode) return;
    
    debugPrint('''
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🧭 SmartCompassJapan Debug
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 True Bearing: ${result.trueBearing.toStringAsFixed(1)}°
📱 Device Heading: ${result.deviceHeading.toStringAsFixed(1)}°
🔧 Declination: ${result.declinationCorrection}°
📐 Angle Diff: ${result.angleDifference.toStringAsFixed(1)}°
🕐 Clock: ${result.shortDirection}
✅ On Target: ${result.isOnTarget}
📏 Distance: ${result.distanceToTarget.toStringAsFixed(1)}m
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''');
  }
}
