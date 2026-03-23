import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';

/// デベロッパーモード管理クラス
class DeveloperModeManager {
  static const String _devModeKey = 'developer_mode_active';
  static const String _targetLocationKey = 'dev_target_location';

  /// デベロッパーモードをアクティブ化
  ///
  /// @param targetLocation ジャンプ先の座標
  /// @param region 強制的に設定する地域コード
  static Future<void> activateDeveloperMode({
    required LatLng targetLocation,
    required String region,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // デベロッパーモードフラグを立てる
    await prefs.setBool(_devModeKey, true);

    // ターゲット座標を保存
    await prefs.setString(
      _targetLocationKey,
      '${targetLocation.latitude},${targetLocation.longitude}',
    );

    // 地域を強制変更
    await prefs.setString('last_region', region);

    debugPrint('Developer Mode Activated!');
    debugPrint('   Target: ${targetLocation.latitude}, ${targetLocation.longitude}');
    debugPrint('   Region: $region');
  }

  /// デベロッパーモードが有効か確認
  static Future<bool> isDeveloperModeActive() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_devModeKey) ?? false;
  }

  /// ターゲット座標を取得
  static Future<LatLng?> getTargetLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final locationStr = prefs.getString(_targetLocationKey);

    if (locationStr == null) return null;

    final parts = locationStr.split(',');
    if (parts.length != 2) return null;

    final lat = double.tryParse(parts[0]);
    final lng = double.tryParse(parts[1]);

    if (lat == null || lng == null) return null;

    return LatLng(lat, lng);
  }

  /// デベロッパーモードを無効化
  static Future<void> deactivateDeveloperMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_devModeKey);
    await prefs.remove(_targetLocationKey);

    debugPrint('Developer Mode Deactivated');
  }
}
