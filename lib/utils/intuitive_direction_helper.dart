import 'dart:ui';
import 'package:flutter/material.dart';

/// 超直感的方向変換ヘルパー
/// 
/// 防災エンジニアとしての哲学:
/// パニック状態では「北北東」という言葉は理解できません。
/// しかし「2時の方角（右斜め前）」なら、誰でも瞬時に理解できます。
/// 
/// 災害時のUI設計原則:
/// 1. 認知負荷を最小化
/// 2. 日常的な言葉を使用
/// 3. 視覚的なフィードバック（色）
class IntuitiveDirectionHelper {
  /// 方向情報
  static DirectionInfo getIntuitiveDirection(
    double bearing, // 進むべき方向（0-360度）
    double deviceHeading, // デバイスの向き（0-360度）
  ) {
    // 差分を計算（-180～180度に正規化）
    double diff = bearing - deviceHeading;
    while (diff > 180) diff -= 360;
    while (diff < -180) diff += 360;
    
    final absDiff = diff.abs();
    
    // === 正面付近（±11.25度以内）===
    if (absDiff <= 11.25) {
      return DirectionInfo(
        mainMessage: 'そのまま真っすぐ！',
        clockPosition: '12時',
        relativeDirection: '正面',
        color: const Color(0xFF4CAF50), // 緑
        urgency: DirectionUrgency.onTrack,
        compassLabel: 'N',
        glowIntensity: 1.0, // 最大発光
      );
    }
    
    // === 右側のズレ ===
    if (diff > 0) {
      if (diff <= 33.75) {
        // 右斜め前（1時）
        return DirectionInfo(
          mainMessage: '少し右へ',
          clockPosition: '1時',
          relativeDirection: '右斜め前',
          color: const Color(0xFFFDD835), // 黄色
          urgency: DirectionUrgency.slight,
          compassLabel: 'NNE',
        );
      } else if (diff <= 56.25) {
        // 右斜め前（2時）
        return DirectionInfo(
          mainMessage: '右斜め前へ',
          clockPosition: '2時',
          relativeDirection: '右斜め前',
          color: const Color(0xFFFBC02D), // 濃い黄色
          urgency: DirectionUrgency.moderate,
          compassLabel: 'NE',
        );
      } else if (diff <= 78.75) {
        // 右（2-3時間）
        return DirectionInfo(
          mainMessage: '右に曲がれ',
          clockPosition: '2-3時',
          relativeDirection: '右',
          color: const Color(0xFFFF9800), // オレンジ
          urgency: DirectionUrgency.significant,
          compassLabel: 'ENE',
        );
      } else if (diff <= 101.25) {
        // 右（3時）
        return DirectionInfo(
          mainMessage: '真右へ曲がれ',
          clockPosition: '3時',
          relativeDirection: '真右',
          color: const Color(0xFFFF6F00), // 濃いオレンジ
          urgency: DirectionUrgency.significant,
          compassLabel: 'E',
        );
      } else if (diff <= 123.75) {
        // 右後ろ（4時）
        return DirectionInfo(
          mainMessage: '大きく右へ',
          clockPosition: '4時',
          relativeDirection: '右後ろ',
          color: const Color(0xFFE64A19), // 赤オレンジ
          urgency: DirectionUrgency.major,
          compassLabel: 'ESE',
        );
      } else if (diff <= 146.25) {
        // 右後ろ（5時）
        return DirectionInfo(
          mainMessage: '後ろを向け',
          clockPosition: '5時',
          relativeDirection: '右後ろ',
          color: const Color(0xFFD32F2F), // 赤
          urgency: DirectionUrgency.major,
          compassLabel: 'SE',
        );
      } else {
        // 真後ろ（6時）
        return DirectionInfo(
          mainMessage: '⚠️ 逆方向！戻れ',
          clockPosition: '6時',
          relativeDirection: '真後ろ',
          color: const Color(0xFFC62828), // 濃い赤
          urgency: DirectionUrgency.critical,
          compassLabel: 'S',
          glowIntensity: 0.0, // 発光なし
        );
      }
    }
    
    // === 左側のズレ ===
    else {
      if (diff >= -33.75) {
        // 左斜め前（11時）
        return DirectionInfo(
          mainMessage: '少し左へ',
          clockPosition: '11時',
          relativeDirection: '左斜め前',
          color: const Color(0xFFFDD835), // 黄色
          urgency: DirectionUrgency.slight,
          compassLabel: 'NNW',
        );
      } else if (diff >= -56.25) {
        // 左斜め前（10時）
        return DirectionInfo(
          mainMessage: '左斜め前へ',
          clockPosition: '10時',
          relativeDirection: '左斜め前',
          color: const Color(0xFFFBC02D), // 濃い黄色
          urgency: DirectionUrgency.moderate,
          compassLabel: 'NW',
        );
      } else if (diff >= -78.75) {
        // 左（9-10時）
        return DirectionInfo(
          mainMessage: '左に曲がれ',
          clockPosition: '9-10時',
          relativeDirection: '左',
          color: const Color(0xFFFF9800), // オレンジ
          urgency: DirectionUrgency.significant,
          compassLabel: 'WNW',
        );
      } else if (diff >= -101.25) {
        // 左（9時）
        return DirectionInfo(
          mainMessage: '真左へ曲がれ',
          clockPosition: '9時',
          relativeDirection: '真左',
          color: const Color(0xFFFF6F00), // 濃いオレンジ
          urgency: DirectionUrgency.significant,
          compassLabel: 'W',
        );
      } else if (diff >= -123.75) {
        // 左後ろ（8時）
        return DirectionInfo(
          mainMessage: '大きく左へ',
          clockPosition: '8時',
          relativeDirection: '左後ろ',
          color: const Color(0xFFE64A19), // 赤オレンジ
          urgency: DirectionUrgency.major,
          compassLabel: 'WSW',
        );
      } else if (diff >= -146.25) {
        // 左後ろ（7時）
        return DirectionInfo(
          mainMessage: '後ろを向け',
          clockPosition: '7時',
          relativeDirection: '左後ろ',
          color: const Color(0xFFD32F2F), // 赤
          urgency: DirectionUrgency.major,
          compassLabel: 'SW',
        );
      } else {
        // 真後ろ（6時）
        return DirectionInfo(
          mainMessage: '⚠️ 逆方向！戻れ',
          clockPosition: '6時',
          relativeDirection: '真後ろ',
          color: const Color(0xFFC62828), // 濃い赤
          urgency: DirectionUrgency.critical,
          compassLabel: 'S',
          glowIntensity: 0.0,
        );
      }
    }
  }
  
  /// 16方位の名称を取得
  static String getCompassDirection(double bearing) {
    const directions = [
      'N', 'NNE', 'NE', 'ENE',
      'E', 'ESE', 'SE', 'SSE',
      'S', 'SSW', 'SW', 'WSW',
      'W', 'WNW', 'NW', 'NNW',
    ];
    
    final index = ((bearing + 11.25) / 22.5).floor() % 16;
    return directions[index];
  }
}

/// 方向情報
class DirectionInfo {
  /// メインメッセージ（大きく表示）
  final String mainMessage;
  
  /// 時計の位置（例: "11時"）
  final String clockPosition;
  
  /// 相対的な方向（例: "左斜め前"）
  final String relativeDirection;
  
  /// 誘導色
  final Color color;
  
  /// 緊急度
  final DirectionUrgency urgency;
  
  /// コンパス方位（補足情報）
  final String compassLabel;
  
  /// 発光強度（0.0-1.0）
  final double glowIntensity;
  
  DirectionInfo({
    required this.mainMessage,
    required this.clockPosition,
    required this.relativeDirection,
    required this.color,
    required this.urgency,
    required this.compassLabel,
    this.glowIntensity = 0.3,
  });
}

/// 方向のずれの緊急度
enum DirectionUrgency {
  onTrack,      // 正解（緑）
  slight,       // わずかなズレ（黄色）
  moderate,     // 中程度のズレ（濃い黄色）
  significant,  // 大きなズレ（オレンジ）
  major,        // 後方（赤オレンジ）
  critical,     // 逆方向（赤）
}
