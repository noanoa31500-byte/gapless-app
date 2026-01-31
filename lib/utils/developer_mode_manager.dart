import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';

/// デベロッパーモード管理クラス
/// 
/// イースターエッグ機能で使用。
/// デモ時にタイ・サトゥン校へ瞬時にジャンプできる隠し機能を提供。
class DeveloperModeManager {
  static const String _devModeKey = 'developer_mode_active';
  static const String _targetLocationKey = 'dev_target_location';
  
  /// PCSHS Satun（タイ）の座標
  static const LatLng satunCoordinates = LatLng(6.7371225, 100.0798828);
  
  /// デベロッパーモードをアクティブ化
  /// 
  /// @param targetLocation ジャンプ先の座標
  /// @param region 強制的に設定する地域コード（'TH', 'JP'など）
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
    
    debugPrint('🚀 Developer Mode Activated!');
    debugPrint('   Target: ${targetLocation.latitude}, ${targetLocation.longitude}');
    debugPrint('   Region: $region');
  }
  
  /// サトゥンへジャンプ（デモ用ショートカット）
  static Future<void> jumpToSatun() async {
    await activateDeveloperMode(
      targetLocation: satunCoordinates,
      region: 'th_satun',
    );
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
  
  /// イースターエッグトリガー（設定画面用）
  /// 
  /// 使い方: バージョン表示箇所でonLongPressに設定
  static Future<void> triggerEasterEgg(BuildContext context) async {
    // サトゥンへジャンプ
    await jumpToSatun();
    
    // SnackBarで通知
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.rocket_launch, color: Colors.white),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  '🚀 Developer Mode: Jumping to Satun...\n🇹🇭 AI switching to Thai Flood Mode!',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.deepPurple,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
      
      // 地図画面に戻る
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }
  
  /// RegionModeProviderと統合してタイモードへ切り替え
  /// 
  /// AIの振る舞いも同時に変更
  static Future<void> triggerEasterEggWithAI(
    BuildContext context,
    dynamic regionProvider, // RegionModeProvider
  ) async {
    // サトゥンへジャンプ
    await jumpToSatun();
    
    // 地域モードをタイに強制変更（デベロッパーモード）
    if (regionProvider != null) {
      // AppRegion.thailand に変更
      // regionProvider.setRegion(AppRegion.thailand, devMode: true);
      // 実際の実装では、適切にキャストして使用
    }
    
    // SnackBarで通知（AI切り替えも表示）
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.rocket_launch, color: Colors.white),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '🚀 Developer Mode Activated!',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 4),
                    Text(
                      '🗺️ Jumping to Satun, Thailand\n🤖 AI → Thai Flood Expert Mode',
                      style: TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: Colors.deepPurple,
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: 'OK',
            textColor: Colors.white,
            onPressed: () {},
          ),
        ),
      );
      
      // 地図画面に戻る
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }
}
