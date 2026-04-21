import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// ============================================================================
/// MagneticDeclinationConfig - 地域別地磁気偏角管理システム
/// ============================================================================
///
/// 【設計方針】
/// 偏角の大きい地域（例：ニュージーランド +20度、カナダ北部 -15度など）へ
/// 展開することを見据え、**すべてのエリアで真北（True North）基準に統一する設計**。
///
/// 【技術的背景】
/// 地磁気偏角（Magnetic Declination）は、地球上の位置と時間によって変化します。
/// - 日本: 約-7〜-10度（西偏）
/// - ニュージーランド: 約+18〜+23度（東偏）
/// - カナダ・イエローナイフ: 約-15度（西偏）
///
/// この差異を無視すると、1kmの移動で最大350mの誤差が生じます。
/// 災害時の避難誘導では、この誤差が命取りになる可能性があります。
///
/// 【データソース】
/// - NOAA World Magnetic Model (WMM) 2020-2025
/// - 国土地理院 地磁気偏角データ
/// ============================================================================

/// 地域コード
enum GeoRegion {
  /// 日本（東京都）
  jpTokyo('jp_tokyo', '日本（東京）', 'Japan (Tokyo)', -7.5),

  /// 日本（札幌市）
  jpSapporo('jp_sapporo', '日本（札幌）', 'Japan (Sapporo)', -9.5),

  /// 日本（大阪府）
  jpOsaka('jp_osaka', '日本（大阪）', 'Japan (Osaka)', -7.0),

  /// 日本（福岡県）
  jpFukuoka('jp_fukuoka', '日本（福岡）', 'Japan (Fukuoka)', -6.5),

  /// 日本（沖縄県）
  jpOkinawa('jp_okinawa', '日本（沖縄）', 'Japan (Okinawa)', -5.0),

  /// ニュージーランド（オークランド）- 将来拡張用
  /// 東偏（Easterly Declination）: 磁北が真北より東
  nzAuckland('nz_auckland', 'NZ（オークランド）', 'New Zealand (Auckland)', 20.0),

  /// カナダ（バンクーバー）- 将来拡張用
  /// 東偏（Easterly Declination）
  caVancouver('ca_vancouver', 'カナダ（バンクーバー）', 'Canada (Vancouver)', 16.0),

  /// アメリカ（ロサンゼルス）- 将来拡張用
  /// 東偏（Easterly Declination）
  usLosAngeles('us_los_angeles', 'US（ロサンゼルス）', 'USA (Los Angeles)', 11.5),

  /// グローバルデフォルト（偏角0）
  globalDefault('global', 'グローバル', 'Global', 0.0);

  /// 地域コード
  final String code;

  /// 日本語名
  final String nameJa;

  /// 英語名
  final String nameEn;

  /// 地磁気偏角（度）
  /// 負: 西偏（磁北が真北より西）
  /// 正: 東偏（磁北が真北より東）
  final double declination;

  const GeoRegion(this.code, this.nameJa, this.nameEn, this.declination);

  /// コードから地域を取得
  static GeoRegion fromCode(String code) {
    return GeoRegion.values.firstWhere(
      (r) => r.code == code,
      orElse: () => GeoRegion.globalDefault,
    );
  }

  /// 座標から最寄りの地域を推定
  static GeoRegion fromCoordinates(double latitude, double longitude) {
    // 日本（24-46N, 123-154E）
    if (latitude >= 24 &&
        latitude <= 46 &&
        longitude >= 123 &&
        longitude <= 154) {
      // 日本国内の細分化
      if (latitude >= 42) return GeoRegion.jpSapporo;
      if (longitude >= 138) return GeoRegion.jpTokyo;
      if (longitude >= 134) return GeoRegion.jpOsaka;
      if (latitude <= 27) return GeoRegion.jpOkinawa;
      return GeoRegion.jpFukuoka;
    }

    // ニュージーランド（-47〜-34, 166〜179）
    if (latitude >= -47 &&
        latitude <= -34 &&
        longitude >= 166 &&
        longitude <= 179) {
      return GeoRegion.nzAuckland;
    }

    // カナダ西海岸（48-60N, 115-140W）
    if (latitude >= 48 &&
        latitude <= 60 &&
        longitude >= -140 &&
        longitude <= -115) {
      return GeoRegion.caVancouver;
    }

    // アメリカ西海岸（32-42N, 114-125W）
    if (latitude >= 32 &&
        latitude <= 42 &&
        longitude >= -125 &&
        longitude <= -114) {
      return GeoRegion.usLosAngeles;
    }

    return GeoRegion.globalDefault;
  }
}

/// ============================================================================
/// MagneticDeclinationConfig - 偏角設定クラス
/// ============================================================================
class MagneticDeclinationConfig {
  MagneticDeclinationConfig._(); // インスタンス化防止

  // === 主要地域の偏角（定数） ===

  /// 日本・東京（2024-2026年）
  /// 国土地理院データ + WMM2020検証
  static const double declinationJpTokyo = -7.5;

  /// 偏角テーブル（座標 → 偏角のマッピング）
  /// キー: "lat_lon"（小数点1桁で丸め）
  static final Map<String, double> _declinationTable = {
    // 日本
    '43.1_141.3': -9.5, // 札幌
    '38.3_140.9': -8.6, // 仙台
    '35.7_139.7': -7.5, // 東京
    '35.2_136.9': -7.3, // 名古屋
    '34.7_135.5': -7.0, // 大阪
    '34.4_132.5': -6.6, // 広島
    '33.6_130.4': -6.5, // 福岡
    '26.2_127.7': -5.0, // 那覇
  };

  /// 座標から偏角を取得（テーブル参照 + 補間）
  static double getDeclination(double latitude, double longitude) {
    // テーブルキーを生成
    final key =
        '${latitude.toStringAsFixed(1)}_${longitude.toStringAsFixed(1)}';

    // 完全一致があれば返す
    if (_declinationTable.containsKey(key)) {
      return _declinationTable[key]!;
    }

    // 最近傍補間
    return _interpolateDeclination(latitude, longitude);
  }

  /// 偏角の補間計算
  static double _interpolateDeclination(double lat, double lon) {
    double totalWeight = 0;
    double weightedSum = 0;

    for (final entry in _declinationTable.entries) {
      final parts = entry.key.split('_');
      final tableLat = double.parse(parts[0]);
      final tableLon = double.parse(parts[1]);

      // 逆距離加重法（IDW）
      final distance = _haversineDistance(lat, lon, tableLat, tableLon);
      if (distance < 1) {
        // 1km以内なら直接返す
        return entry.value;
      }

      // 500km以内のポイントのみ使用
      if (distance < 500) {
        final weight = 1 / (distance * distance);
        weightedSum += entry.value * weight;
        totalWeight += weight;
      }
    }

    if (totalWeight > 0) {
      return weightedSum / totalWeight;
    }

    // フォールバック: 座標から地域を推定
    final region = GeoRegion.fromCoordinates(lat, lon);
    return region.declination;
  }

  /// ハーバーサイン距離（km）
  static double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371.0;
    final dLat = (lat2 - lat1) * (math.pi / 180);
    final dLon = (lon2 - lon1) * (math.pi / 180);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * (math.pi / 180)) *
            math.cos(lat2 * (math.pi / 180)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }
}

/// ============================================================================
/// CompassCalibrator - コンパス補正クラス
/// ============================================================================
///
/// 【設計思想】
/// 本クラスは、磁北（Magnetic North）を真北（True North）に変換する
/// 「ブラックボックス」として機能します。
///
/// 使用者は内部の偏角計算を意識する必要がなく、
/// 単に `calibrate(magneticHeading)` を呼ぶだけで真方位を取得できます。
///
/// 【将来拡張性】
/// - リアルタイムWMM計算への差し替え
/// - センサー融合（ジャイロ + 加速度計）の追加
/// - 磁気干渉検出・補正
class CompassCalibrator with ChangeNotifier {
  // === 状態 ===
  GeoRegion _currentRegion;
  double _currentDeclination;
  double? _customDeclination; // カスタム偏角（オーバーライド用）
  bool _isEnabled = true;

  // === 統計情報（デバッグ用） ===
  int _calibrationCount = 0;
  double _lastMagneticHeading = 0;
  double _lastTrueHeading = 0;

  CompassCalibrator({
    GeoRegion initialRegion = GeoRegion.jpTokyo,
  })  : _currentRegion = initialRegion,
        _currentDeclination = initialRegion.declination;

  // === Getters ===
  GeoRegion get currentRegion => _currentRegion;
  double get currentDeclination => _customDeclination ?? _currentDeclination;
  bool get isEnabled => _isEnabled;
  int get calibrationCount => _calibrationCount;
  double get lastMagneticHeading => _lastMagneticHeading;
  double get lastTrueHeading => _lastTrueHeading;

  /// ============================================================================
  /// calibrate - メイン補正メソッド
  /// ============================================================================
  ///
  /// 磁北方位を真北方位に変換します。
  ///
  /// @param magneticHeading 磁北基準の方位（0-360度）
  /// @return 真北基準の方位（0-360度）
  ///
  /// 【計算式】
  /// TrueHeading = (MagneticHeading - Declination) mod 360
  ///
  /// 【例: 東京（偏角 -7.5度）】
  /// 磁北0度 → 真北 0 - (-7.5) = 7.5度
  double calibrate(double magneticHeading) {
    _lastMagneticHeading = magneticHeading;
    _calibrationCount++;

    if (!_isEnabled) {
      _lastTrueHeading = magneticHeading;
      return magneticHeading;
    }

    final declination = _customDeclination ?? _currentDeclination;

    // 真北方位 = 磁北方位 + 偏角 (標準的な計算式)
    // 西偏（負の偏角）の場合、真北は磁北より東 → + で正しい
    double trueHeading = magneticHeading + declination;

    // 0-360度に正規化
    while (trueHeading < 0) trueHeading += 360;
    while (trueHeading >= 360) trueHeading -= 360;

    _lastTrueHeading = trueHeading;
    return trueHeading;
  }

  /// ============================================================================
  /// setRegion - 地域を設定
  /// ============================================================================
  void setRegion(GeoRegion region) {
    _currentRegion = region;
    _currentDeclination = region.declination;
    _customDeclination = null; // カスタム偏角をリセット

    if (kDebugMode) {
      debugPrint(
          '🧭 CompassCalibrator: 地域変更 → ${region.nameJa} (偏角: ${region.declination}°)');
    }

    notifyListeners();
  }

  /// ============================================================================
  /// setRegionFromCoordinates - 座標から地域を自動設定
  /// ============================================================================
  void setRegionFromCoordinates(double latitude, double longitude) {
    final region = GeoRegion.fromCoordinates(latitude, longitude);
    setRegion(region);

    // より精密な偏角を取得
    _currentDeclination =
        MagneticDeclinationConfig.getDeclination(latitude, longitude);

    if (kDebugMode) {
      debugPrint(
          '🧭 座標から偏角を取得: (${latitude.toStringAsFixed(4)}, ${longitude.toStringAsFixed(4)}) → ${_currentDeclination}°');
    }

    notifyListeners();
  }

  /// ============================================================================
  /// setCustomDeclination - カスタム偏角を設定（オーバーライド）
  /// ============================================================================
  void setCustomDeclination(double declination) {
    _customDeclination = declination;

    if (kDebugMode) {
      debugPrint('🧭 カスタム偏角設定: $declination°');
    }

    notifyListeners();
  }

  /// カスタム偏角をクリア
  void clearCustomDeclination() {
    _customDeclination = null;
    notifyListeners();
  }

  /// 補正を有効/無効切り替え
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    notifyListeners();
  }

  /// ============================================================================
  /// getDeclinationInfo - 偏角情報を取得（UI表示用）
  /// ============================================================================
  Map<String, dynamic> getDeclinationInfo() {
    final dec = currentDeclination;
    final direction = dec < 0
        ? '西偏 (West)'
        : dec > 0
            ? '東偏 (East)'
            : 'なし';

    return {
      'region': _currentRegion.nameJa,
      'regionEn': _currentRegion.nameEn,
      'declination': dec,
      'declinationAbs': dec.abs(),
      'direction': direction,
      'isCustom': _customDeclination != null,
      'isEnabled': _isEnabled,
      'description': _getDeclinationDescription(dec),
    };
  }

  String _getDeclinationDescription(double dec) {
    final absDec = dec.abs();

    if (absDec < 1) {
      return '偏角は無視できるレベルです（磁気赤道付近）';
    } else if (absDec < 5) {
      return '偏角は小さいですが、長距離移動では影響があります';
    } else if (absDec < 10) {
      return '偏角が大きいため、補正は必須です';
    } else {
      return '偏角が非常に大きいです。高精度な補正が必要です';
    }
  }

  /// ============================================================================
  /// デバッグ出力
  /// ============================================================================
  void printDebugInfo() {
    if (!kDebugMode) return;

    final info = getDeclinationInfo();

    debugPrint('''
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🧭 CompassCalibrator Status
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📍 Region: ${info['region']} (${info['regionEn']})
🔧 Declination: ${currentDeclination.toStringAsFixed(2)}° (${info['direction']})
📝 Description: ${info['description']}
⚙️ Enabled: $_isEnabled
🔢 Calibration Count: $_calibrationCount
📐 Last: Magnetic ${_lastMagneticHeading.toStringAsFixed(1)}° → True ${_lastTrueHeading.toStringAsFixed(1)}°
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
''');
  }
}

/// ============================================================================
/// CompassCalibratorFactory - ファクトリクラス
/// ============================================================================
///
/// 地域に応じたCompassCalibratorを生成します。
class CompassCalibratorFactory {
  CompassCalibratorFactory._();

  /// 座標から自動生成
  static CompassCalibrator createFromCoordinates(double lat, double lon) {
    final region = GeoRegion.fromCoordinates(lat, lon);
    final calibrator = CompassCalibrator(initialRegion: region);
    calibrator.setRegionFromCoordinates(lat, lon);
    return calibrator;
  }

  /// 地域コードから生成
  static CompassCalibrator createFromRegionCode(String code) {
    final region = GeoRegion.fromCode(code);
    return CompassCalibrator(initialRegion: region);
  }
}
