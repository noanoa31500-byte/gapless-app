import 'package:flutter/services.dart';

/// ============================================================================
/// HapticService - Apple HIG準拠のハプティックフィードバック
/// ============================================================================
/// 
/// Apple Human Interface Guidelines に基づくハプティックパターン:
/// - Impact: 物理的な衝突感を伝える（ボタンタップ、スワイプ完了）
/// - Selection: 選択の確認（リスト選択、トグル切替）
/// - Notification: 重要な通知（成功、警告、エラー）
/// 
/// 使用場面:
/// - ボタンタップ時: light impact
/// - 重要なアクション完了時: success notification
/// - エラー発生時: error notification
/// - 目的地到着時: heavy impact + success
/// - 災害モード切替時: warning notification
class HapticService {
  // Singleton pattern
  static final HapticService _instance = HapticService._internal();
  factory HapticService() => _instance;
  HapticService._internal();

  // ============================================
  // Impact Feedback (物理的な衝突感)
  // ============================================
  
  /// 軽いタップ感 - 通常のボタンタップ
  static Future<void> lightImpact() async {
    await HapticFeedback.lightImpact();
  }
  
  /// 中程度のタップ感 - 重要なボタンタップ
  static Future<void> mediumImpact() async {
    await HapticFeedback.mediumImpact();
  }
  
  /// 強いタップ感 - 非常に重要なアクション
  static Future<void> heavyImpact() async {
    await HapticFeedback.heavyImpact();
  }

  // ============================================
  // Selection Feedback (選択の確認)
  // ============================================
  
  /// 選択確認 - ピッカー、トグル、チェックボックス
  static Future<void> selectionClick() async {
    await HapticFeedback.selectionClick();
  }

  // ============================================
  // Notification Feedback (通知)
  // ============================================
  
  /// 成功通知 - 操作成功、目的地到着
  static Future<void> success() async {
    // iOSではNotificationFeedbackTypeがないため、mediumImpactを連続で
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.mediumImpact();
  }
  
  /// 警告通知 - 注意が必要
  static Future<void> warning() async {
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 150));
    await HapticFeedback.lightImpact();
  }
  
  /// エラー通知 - エラー発生
  static Future<void> error() async {
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.heavyImpact();
  }

  // ============================================
  // 特殊パターン (GapLess専用)
  // ============================================
  
  /// 災害モード開始 - 緊急感を伝える
  static Future<void> disasterModeActivated() async {
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 200));
    await HapticFeedback.heavyImpact();
  }
  
  /// 目的地到着 - 安心感を伝える
  static Future<void> arrivedAtDestination() async {
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    await HapticFeedback.lightImpact();
  }
  
  /// コンパス方向変更 - 微細な確認
  static Future<void> directionChanged() async {
    await HapticFeedback.selectionClick();
  }
  
  /// ナビゲーション目的地設定
  static Future<void> destinationSet() async {
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.lightImpact();
  }
  
  /// 振動のバースト（緊急アラート用）
  static Future<void> emergencyAlert() async {
    for (int i = 0; i < 3; i++) {
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }
}
