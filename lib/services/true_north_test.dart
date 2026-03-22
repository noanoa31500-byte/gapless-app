// ignore_for_file: avoid_print
/// ============================================================================
/// TrueNorthProvider - テストコード
/// ============================================================================
/// 
/// 大崎市（緯度: 38.57, 経度: 140.95）の座標を入力した際、
/// 正しく偏角（約-8.5度）が適用されるかを確認します。
/// 
/// 実行方法:
/// flutter run -d chrome --target=lib/services/true_north_test.dart

import 'package:flutter/foundation.dart';
import 'true_north_provider.dart';

void main() {
  debugPrint('');
  debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  debugPrint('🧭 TrueNorthProvider テスト');
  debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  debugPrint('');
  
  // === テスト1: 大崎市のWMM偏角計算 ===
  _testOsakiDeclination();
  
  // === テスト2: 日本各地の偏角計算 ===
  _testJapanCities();
  
  // === テスト3: 真方位変換の検証 ===
  _testTrueHeadingConversion();
  
  // === テスト4: フィルタリング動作確認 ===
  _testFiltering();
  
  debugPrint('');
  debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  debugPrint('✅ 全テスト完了');
  debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
}

/// テスト1: 大崎市の偏角
void _testOsakiDeclination() {
  debugPrint('📍 テスト1: 大崎市（宮城県）の偏角計算');
  debugPrint('');
  
  const osakiLat = 38.5775;
  const osakiLon = 140.9518;
  
  // WMM計算
  final declination = WMMCalculator.calculateDeclination(osakiLat, osakiLon);
  debugPrint('   座標: (${osakiLat.toStringAsFixed(4)}°N, ${osakiLon.toStringAsFixed(4)}°E)');
  debugPrint('   WMM計算結果: ${declination.toStringAsFixed(2)}°');
  
  // 高速参照
  final quickDec = WMMCalculator.getQuickDeclination(osakiLat, osakiLon);
  debugPrint('   高速参照結果: ${quickDec.toStringAsFixed(2)}°');
  
  // 検証
  final isValid = declination < -7.0 && declination > -10.0;
  debugPrint('   期待範囲: -7.0° 〜 -10.0°（西偏）');
  debugPrint('   結果: ${isValid ? "✅ PASS" : "❌ FAIL"}');
  debugPrint('');
}

/// テスト2: 日本各地の偏角
void _testJapanCities() {
  debugPrint('📍 テスト2: 日本各地の偏角計算');
  debugPrint('');
  
  const cities = {
    '札幌': [43.0642, 141.3469, -9.0, -10.0],
    '仙台': [38.2682, 140.8694, -8.0, -9.5],
    '大崎': [38.5775, 140.9518, -8.0, -9.5],
    '東京': [35.6762, 139.6503, -7.0, -8.5],
    '名古屋': [35.1815, 136.9066, -6.5, -8.0],
    '大阪': [34.6937, 135.5023, -6.5, -8.0],
    '広島': [34.3853, 132.4553, -6.0, -7.5],
    '福岡': [33.5904, 130.4017, -6.0, -7.5],
    '那覇': [26.2124, 127.6809, -4.5, -6.0],
  };
  
  bool allPassed = true;
  
  for (final entry in cities.entries) {
    final name = entry.key;
    final lat = entry.value[0];
    final lon = entry.value[1];
    final minDec = entry.value[2];
    final maxDec = entry.value[3];
    
    final declination = WMMCalculator.calculateDeclination(lat, lon);
    final isValid = declination >= maxDec && declination <= minDec;
    
    debugPrint('   $name: ${declination.toStringAsFixed(2)}° '
        '(期待: ${maxDec.toStringAsFixed(1)}° 〜 ${minDec.toStringAsFixed(1)}°) '
        '${isValid ? "✅" : "❌"}');
    
    if (!isValid) allPassed = false;
  }
  
  debugPrint('');
  debugPrint('   全体結果: ${allPassed ? "✅ ALL PASS" : "❌ SOME FAILED"}');
  debugPrint('');
}

/// テスト3: 真方位変換
void _testTrueHeadingConversion() {
  debugPrint('📍 テスト3: 真方位変換の検証');
  debugPrint('');
  
  // 大崎市の偏角 -8.5度を仮定
  const declination = -8.5;
  
  // 変換式: TrueHeading = MagneticHeading - Declination
  // 西偏の場合、Declinationは負なので、引くと足す効果
  
  final testCases = [
    [0.0, 8.5],     // 磁北0° → 真北8.5°
    [351.5, 0.0],   // 磁北351.5° → 真北0°
    [90.0, 98.5],   // 磁東90° → 真東98.5°
    [180.0, 188.5], // 磁南180° → 真南188.5°
    [270.0, 278.5], // 磁西270° → 真西278.5°
  ];
  
  bool allPassed = true;
  
  for (final tc in testCases) {
    final magnetic = tc[0];
    final expectedTrue = tc[1];
    
    double calculated = magnetic - declination;
    while (calculated < 0) calculated += 360;
    while (calculated >= 360) calculated -= 360;
    
    final diff = (calculated - expectedTrue).abs();
    final isValid = diff < 0.1;
    
    debugPrint('   磁北 ${magnetic.toStringAsFixed(1)}° → 真北 ${calculated.toStringAsFixed(1)}° '
        '(期待: ${expectedTrue.toStringAsFixed(1)}°) '
        '${isValid ? "✅" : "❌"}');
    
    if (!isValid) allPassed = false;
  }
  
  debugPrint('');
  debugPrint('   全体結果: ${allPassed ? "✅ ALL PASS" : "❌ SOME FAILED"}');
  debugPrint('');
}

/// テスト4: フィルタリング
void _testFiltering() {
  debugPrint('📍 テスト4: フィルタリング動作確認');
  debugPrint('');
  
  // カルマンフィルタテスト
  final kalman = CircularKalmanFilter();
  
  // ノイズを含む入力シーケンス（北向き付近で振動）
  final noisyInputs = [0.0, 2.0, -1.0, 3.0, -2.0, 1.0, 0.0, -1.0, 2.0, 0.0];
  
  debugPrint('   カルマンフィルタ（ノイズ除去テスト）:');
  debugPrint('   入力: $noisyInputs');
  
  final outputs = <double>[];
  for (final input in noisyInputs) {
    outputs.add(kalman.update(input < 0 ? input + 360 : input));
  }
  
  debugPrint('   出力: ${outputs.map((e) => e.toStringAsFixed(1)).toList()}');
  
  // 最終出力が0度付近であることを確認
  final finalOutput = outputs.last;
  final isStable = finalOutput < 5 || finalOutput > 355;
  debugPrint('   最終出力: ${finalOutput.toStringAsFixed(1)}° (0°付近であるべき)');
  debugPrint('   結果: ${isStable ? "✅ PASS" : "❌ FAIL"}');
  
  // ローパスフィルタテスト
  debugPrint('');
  debugPrint('   ローパスフィルタ（高周波除去テスト）:');
  
  final lowPass = LowPassFilter(alpha: 0.3);
  final lpOutputs = <double>[];
  
  // 急激な変化を含む入力
  final rapidInputs = [0.0, 50.0, 0.0, 50.0, 0.0, 50.0, 0.0];
  
  for (final input in rapidInputs) {
    lpOutputs.add(lowPass.update(input));
  }
  
  debugPrint('   入力: $rapidInputs');
  debugPrint('   出力: ${lpOutputs.map((e) => e.toStringAsFixed(1)).toList()}');
  
  // 出力の振幅が入力より小さいことを確認
  final maxOutput = lpOutputs.reduce((a, b) => a > b ? a : b);
  final minOutput = lpOutputs.reduce((a, b) => a < b ? a : b);
  final outputRange = maxOutput - minOutput;
  final inputRange = 50.0;
  
  final isSmoothed = outputRange < inputRange;
  debugPrint('   入力振幅: $inputRange°, 出力振幅: ${outputRange.toStringAsFixed(1)}°');
  debugPrint('   結果: ${isSmoothed ? "✅ PASS（振幅減少）" : "❌ FAIL"}');
  
  debugPrint('');
}
