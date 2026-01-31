import 'package:flutter/material.dart';
import '../utils/clock_navigation_helper.dart';

/// ============================================================================
/// ClockNavigationDisplay - 0.1秒判断のためのナビゲーションUI
/// ============================================================================
/// 
/// 【設計思想】
/// パニック状態の被災者が、一瞬で行動を決定できるUI。
/// 
/// - 画面全体を「色」で染める（緑=GO、黄=調整、赤=戻れ）
/// - 中央に大きな「言葉」を表示
/// - 矢印アイコンで直感的に方向を示す
/// 
/// 【アクセシビリティ】
/// - 高コントラストカラー
/// - 大きなフォント
/// - アイコンによる視覚補助
/// ============================================================================

class ClockNavigationDisplay extends StatelessWidget {
  /// ナビゲーション状態
  final ClockNavState state;
  
  /// 言語設定
  final String lang;
  
  /// 残り距離（メートル）
  final double? distanceMeters;
  
  /// コンパクトモード（小さく表示）
  final bool compact;

  const ClockNavigationDisplay({
    super.key,
    required this.state,
    this.lang = 'ja',
    this.distanceMeters,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompactView();
    }
    return _buildFullView();
  }

  /// フルサイズ表示（コンパス画面用）
  Widget _buildFullView() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: state.backgroundColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: state.backgroundColor.withValues(alpha: 0.4),
            blurRadius: 20,
            spreadRadius: 5,
          ),
        ],
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // アイコン（大きく、回転付き）
          _buildIcon(size: 120),
          
          const SizedBox(height: 24),
          
          // 短縮メッセージ（超大文字）
          Text(
            state.shortMessage,
            style: TextStyle(
              fontSize: 64,
              fontWeight: FontWeight.w900,
              color: state.textColor,
              letterSpacing: 4,
              shadows: [
                Shadow(
                  color: Colors.black26,
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 詳細メッセージ
          Text(
            state.getMessage(lang),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: state.textColor.withValues(alpha: 0.9),
            ),
            textAlign: TextAlign.center,
          ),
          
          // 残り距離
          if (distanceMeters != null) ...[
            const SizedBox(height: 16),
            _buildDistanceChip(),
          ],
        ],
      ),
    );
  }

  /// コンパクト表示（マップ上のオーバーレイ用）
  Widget _buildCompactView() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: state.backgroundColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // アイコン
          _buildIcon(size: 32),
          
          const SizedBox(width: 12),
          
          // メッセージ
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                state.shortMessage,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: state.textColor,
                ),
              ),
              if (distanceMeters != null)
                Text(
                  _formatDistance(distanceMeters!),
                  style: TextStyle(
                    fontSize: 14,
                    color: state.textColor.withValues(alpha: 0.8),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// アイコンウィジェット
  Widget _buildIcon({required double size}) {
    return AnimatedRotation(
      turns: state.iconRotation / (2 * 3.14159265359),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      child: Icon(
        state.icon,
        size: size,
        color: state.textColor,
        shadows: [
          Shadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }

  /// 距離チップ
  Widget _buildDistanceChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Text(
        _formatDistance(distanceMeters!),
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: state.textColor,
        ),
      ),
    );
  }

  /// 距離フォーマット
  String _formatDistance(double meters) {
    if (meters < 100) {
      return '${meters.toStringAsFixed(0)}m';
    } else if (meters < 1000) {
      return '${(meters / 10).round() * 10}m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)}km';
    }
  }
}

/// ============================================================================
/// ClockNavigationOverlay - 画面全体を覆うオーバーレイ表示
/// ============================================================================
/// 
/// 緊急時に画面全体を色で染め、最優先で方向を伝える。
class ClockNavigationOverlay extends StatelessWidget {
  final ClockNavState state;
  final String lang;
  final double? distanceMeters;
  final VoidCallback? onTap;

  const ClockNavigationOverlay({
    super.key,
    required this.state,
    this.lang = 'ja',
    this.distanceMeters,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        color: state.backgroundColor,
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 巨大アイコン
                AnimatedRotation(
                  turns: state.iconRotation / (2 * 3.14159265359),
                  duration: const Duration(milliseconds: 300),
                  child: Icon(
                    state.icon,
                    size: 180,
                    color: state.textColor,
                    shadows: const [
                      Shadow(
                        color: Colors.black38,
                        blurRadius: 20,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 40),
                
                // 超巨大テキスト
                Text(
                  state.shortMessage,
                  style: TextStyle(
                    fontSize: 96,
                    fontWeight: FontWeight.w900,
                    color: state.textColor,
                    letterSpacing: 8,
                    shadows: const [
                      Shadow(
                        color: Colors.black38,
                        blurRadius: 15,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // 詳細メッセージ
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    state.getMessage(lang),
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: state.textColor.withValues(alpha: 0.9),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                
                // 残り距離
                if (distanceMeters != null) ...[
                  const SizedBox(height: 32),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: Text(
                      _formatDistance(distanceMeters!),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: state.textColor,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatDistance(double meters) {
    if (meters < 100) {
      return 'あと ${meters.toStringAsFixed(0)}m';
    } else if (meters < 1000) {
      return 'あと ${(meters / 10).round() * 10}m';
    } else {
      return 'あと ${(meters / 1000).toStringAsFixed(1)}km';
    }
  }
}

/// ============================================================================
/// ClockNavigationBadge - 小さなバッジ表示（マップ上など）
/// ============================================================================
class ClockNavigationBadge extends StatelessWidget {
  final ClockNavState state;

  const ClockNavigationBadge({
    super.key,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: state.backgroundColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            state.icon,
            size: 20,
            color: state.textColor,
          ),
          const SizedBox(width: 6),
          Text(
            state.shortMessage,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: state.textColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// ============================================================================
/// クロックナビゲーション使用例
/// ============================================================================
/// 
/// ```dart
/// // 状態を計算
/// final state = ClockNavigationHelper.calculateState(
///   targetBearing: 45.0,  // 目的地への方位
///   deviceHeading: 30.0,  // 端末の向き
/// );
/// 
/// // フル表示（コンパス画面）
/// ClockNavigationDisplay(
///   state: state,
///   lang: 'ja',
///   distanceMeters: 150.0,
/// )
/// 
/// // コンパクト表示（マップオーバーレイ）
/// ClockNavigationDisplay(
///   state: state,
///   compact: true,
/// )
/// 
/// // 画面全体オーバーレイ（緊急時）
/// ClockNavigationOverlay(
///   state: state,
///   lang: 'ja',
/// )
/// 
/// // バッジ表示（ミニマル）
/// ClockNavigationBadge(state: state)
/// ```
