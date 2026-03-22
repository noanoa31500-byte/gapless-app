import 'package:flutter/material.dart';
import 'apple_design_system.dart';

/// ============================================================================
/// Apple HIG準拠のアニメーション定義
/// ============================================================================
/// 
/// Apple Human Interface Guidelinesに基づくアニメーション設定:
/// - iOS/macOSの標準アニメーションカーブを採用
/// - 一貫したデュレーションとカーブで統一感を演出
/// - ユーザーの注意を引きすぎないサブトルなモーション

class AppleAnimations {
  // ============================================
  // Standard Durations
  // ============================================
  
  /// 超高速アニメーション（マイクロインタラクション）
  static const Duration instant = Duration(milliseconds: 100);
  
  /// 高速アニメーション（ボタンフィードバック、トグル）
  static const Duration fast = Duration(milliseconds: 200);
  
  /// 標準アニメーション（ほとんどのUI変更）
  static const Duration standard = Duration(milliseconds: 300);
  
  /// 強調アニメーション（モーダル、画面遷移）
  static const Duration emphasis = Duration(milliseconds: 400);
  
  /// スローアニメーション（大きな画面変更）
  static const Duration slow = Duration(milliseconds: 500);

  // ============================================
  // Standard Curves
  // ============================================
  
  /// 標準イーズアウト（Apple標準）
  static const Curve standard_curve = Curves.easeOutCubic;
  
  /// イーズイン（開始アニメーション）
  static const Curve easeIn = Curves.easeInCubic;
  
  /// イーズアウト（終了アニメーション）
  static const Curve easeOut = Curves.easeOutCubic;
  
  /// イーズインアウト（往復アニメーション）
  static const Curve easeInOut = Curves.easeInOutCubic;
  
  /// バウンス（強調したいインタラクション）
  static const Curve bounce = Curves.elasticOut;
  
  /// スプリング（自然な物理演算風）
  static const Curve spring = Curves.easeOutBack;
}

/// ============================================================================
/// Apple風画面遷移
/// ============================================================================

class ApplePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final bool slideFromRight;

  ApplePageRoute({
    required this.page,
    this.slideFromRight = true,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: AppleAnimations.standard,
          reverseTransitionDuration: AppleAnimations.standard,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: AppleAnimations.easeOut,
              reverseCurve: AppleAnimations.easeIn,
            );

            // iOS風のスライド遷移
            final offsetTween = Tween<Offset>(
              begin: Offset(slideFromRight ? 1.0 : -1.0, 0.0),
              end: Offset.zero,
            );

            // フェードも併用
            final fadeTween = Tween<double>(begin: 0.0, end: 1.0);

            return SlideTransition(
              position: offsetTween.animate(curvedAnimation),
              child: FadeTransition(
                opacity: fadeTween.animate(curvedAnimation),
                child: child,
              ),
            );
          },
        );
}

/// モーダル風画面遷移（下からスライド）
class AppleModalRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  AppleModalRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: AppleAnimations.emphasis,
          reverseTransitionDuration: AppleAnimations.standard,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: AppleAnimations.easeOut,
              reverseCurve: AppleAnimations.easeIn,
            );

            final offsetTween = Tween<Offset>(
              begin: const Offset(0.0, 1.0),
              end: Offset.zero,
            );

            return SlideTransition(
              position: offsetTween.animate(curvedAnimation),
              child: child,
            );
          },
        );
}

/// フェードインページ遷移
class AppleFadeRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  AppleFadeRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: AppleAnimations.standard,
          reverseTransitionDuration: AppleAnimations.fast,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curvedAnimation = CurvedAnimation(
              parent: animation,
              curve: AppleAnimations.easeOut,
            );

            return FadeTransition(
              opacity: curvedAnimation,
              child: child,
            );
          },
        );
}

/// ============================================================================
/// Apple風ローディングインジケーター
/// ============================================================================

class AppleLoadingIndicator extends StatelessWidget {
  final double size;
  final Color? color;

  const AppleLoadingIndicator({
    super.key,
    this.size = 24,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CircularProgressIndicator(
        strokeWidth: size * 0.1,
        strokeCap: StrokeCap.round,
        valueColor: AlwaysStoppedAnimation<Color>(
          color ?? AppleColors.actionBlue,
        ),
      ),
    );
  }
}

/// フルスクリーンローディング（オーバーレイ）
class AppleLoadingOverlay extends StatelessWidget {
  final String? message;

  const AppleLoadingOverlay({
    super.key,
    this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.3),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppleColors.secondaryBackground,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppleLoadingIndicator(size: 48),
              if (message != null) ...[
                const SizedBox(height: 16),
                Text(
                  message!,
                  style: AppleTypography.subhead.copyWith(
                    color: AppleColors.secondaryLabel,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// スケルトンローディング（プレースホルダー）
class AppleSkeletonLoader extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const AppleSkeletonLoader({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<AppleSkeletonLoader> createState() => _AppleSkeletonLoaderState();
}

class _AppleSkeletonLoaderState extends State<AppleSkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                AppleColors.separator,
                AppleColors.separator.withValues(alpha: 0.5),
                AppleColors.separator,
              ],
              stops: [
                (_animation.value - 0.3).clamp(0.0, 1.0),
                _animation.value.clamp(0.0, 1.0),
                (_animation.value + 0.3).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// ============================================================================
/// アニメーション付きウィジェット
/// ============================================================================

/// フェードインウィジェット
class AppleFadeIn extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;
  final Curve curve;

  const AppleFadeIn({
    super.key,
    required this.child,
    this.duration = AppleAnimations.standard,
    this.delay = Duration.zero,
    this.curve = AppleAnimations.easeOut,
  });

  @override
  State<AppleFadeIn> createState() => _AppleFadeInState();
}

class _AppleFadeInState extends State<AppleFadeIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: widget.curve,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(_fadeAnimation);

    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}

/// スケールインウィジェット
class AppleScaleIn extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Duration delay;

  const AppleScaleIn({
    super.key,
    required this.child,
    this.duration = AppleAnimations.standard,
    this.delay = Duration.zero,
  });

  @override
  State<AppleScaleIn> createState() => _AppleScaleInState();
}

class _AppleScaleInState extends State<AppleScaleIn>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: AppleAnimations.spring),
    );

    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: FadeTransition(
        opacity: _controller,
        child: widget.child,
      ),
    );
  }
}
