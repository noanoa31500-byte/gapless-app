import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'apple_design_system.dart';

/// ============================================================================
/// Apple HIG準拠のアクセシビリティユーティリティ
/// ============================================================================
/// 
/// WCAG 2.1 AA基準とApple HIGに準拠したアクセシビリティ機能:
/// - 最小タップターゲット44x44pt
/// - コントラスト比4.5:1以上
/// - VoiceOver/TalkBack対応のセマンティクス
/// - 動的テキストサイズ対応

class AppleAccessibility {
  AppleAccessibility._();

  // ============================================
  // 最小タップターゲットサイズ (Apple HIG: 44pt)
  // ============================================
  static const double minTapTarget = 44.0;
  
  // ============================================
  // コントラスト比チェック
  // ============================================
  
  /// 2色間のコントラスト比を計算
  /// WCAG 2.1 AA基準: 通常テキスト4.5:1、大きなテキスト3:1
  static double calculateContrastRatio(Color foreground, Color background) {
    final l1 = _relativeLuminance(foreground);
    final l2 = _relativeLuminance(background);
    final lighter = l1 > l2 ? l1 : l2;
    final darker = l1 > l2 ? l2 : l1;
    return (lighter + 0.05) / (darker + 0.05);
  }
  
  static double _relativeLuminance(Color color) {
    final r = _luminanceComponent((color.r * 255.0).round().clamp(0, 255) / 255);
    final g = _luminanceComponent((color.g * 255.0).round().clamp(0, 255) / 255);
    final b = _luminanceComponent((color.b * 255.0).round().clamp(0, 255) / 255);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }
  
  static double _luminanceComponent(double value) {
    return value <= 0.03928 ? value / 12.92 : ((value + 0.055) / 1.055);
  }
  
  /// コントラスト比が十分かチェック
  static bool hasAdequateContrast(Color foreground, Color background, {bool isLargeText = false}) {
    final ratio = calculateContrastRatio(foreground, background);
    return isLargeText ? ratio >= 3.0 : ratio >= 4.5;
  }

  // ============================================
  // Reduce Motion (前庭障害・モーション過敏配慮)
  // ============================================

  /// OS の「視差効果を減らす」設定が有効か
  static bool reduceMotion(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context);

  /// reduce-motion ON のときは Duration.zero、OFF のときは [normal] を返す。
  /// AnimationController の duration パラメータに直接渡せる。
  static Duration motionDuration(BuildContext context, Duration normal) =>
      reduceMotion(context) ? Duration.zero : normal;

  /// reduce-motion ON のときは [reduced]（既定 0）、OFF のときは [normal] を返す。
  /// 視覚エフェクト用の数値（pulse 振幅など）に。
  static double motionAmount(BuildContext context, double normal,
          {double reduced = 0.0}) =>
      reduceMotion(context) ? reduced : normal;
}

/// ============================================================================
/// アクセシブルボタン（最小タップターゲット保証）
/// ============================================================================

class AccessibleButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onPressed;
  final String? semanticLabel;
  final String? semanticHint;
  final bool excludeFromSemantics;

  const AccessibleButton({
    super.key,
    required this.child,
    this.onPressed,
    this.semanticLabel,
    this.semanticHint,
    this.excludeFromSemantics = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      hint: semanticHint,
      button: true,
      enabled: onPressed != null,
      excludeSemantics: excludeFromSemantics,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppleSpacing.radiusMd),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: AppleAccessibility.minTapTarget,
            minHeight: AppleAccessibility.minTapTarget,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// ============================================================================
/// アクセシブルアイコンボタン
/// ============================================================================

class AccessibleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String semanticLabel;
  final Color? color;
  final double size;

  const AccessibleIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    this.onPressed,
    this.color,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      button: true,
      enabled: onPressed != null,
      child: IconButton(
        icon: Icon(icon, size: size, color: color),
        onPressed: onPressed,
        constraints: const BoxConstraints(
          minWidth: AppleAccessibility.minTapTarget,
          minHeight: AppleAccessibility.minTapTarget,
        ),
        tooltip: semanticLabel,
      ),
    );
  }
}

/// ============================================================================
/// セマンティックラベル付きテキスト
/// ============================================================================

class AccessibleText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final String? semanticLabel;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const AccessibleText(
    this.text, {
    super.key,
    this.style,
    this.semanticLabel,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel ?? text,
      child: Text(
        text,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      ),
    );
  }
}

/// ============================================================================
/// アクセシブル画像
/// ============================================================================

class AccessibleImage extends StatelessWidget {
  final ImageProvider image;
  final String semanticLabel;
  final double? width;
  final double? height;
  final BoxFit? fit;

  const AccessibleImage({
    super.key,
    required this.image,
    required this.semanticLabel,
    this.width,
    this.height,
    this.fit,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      image: true,
      child: Image(
        image: image,
        width: width,
        height: height,
        fit: fit,
        semanticLabel: semanticLabel,
      ),
    );
  }
}

/// ============================================================================
/// アクセシブルカード
/// ============================================================================

class AccessibleCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final String? semanticLabel;
  final String? semanticHint;
  final EdgeInsetsGeometry? padding;
  final Color? color;

  const AccessibleCard({
    super.key,
    required this.child,
    this.onTap,
    this.semanticLabel,
    this.semanticHint,
    this.padding,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cardContent = Container(
      padding: padding ?? const EdgeInsets.all(AppleSpacing.md),
      decoration: BoxDecoration(
        color: color ?? AppleColors.secondaryBackground,
        borderRadius: BorderRadius.circular(AppleSpacing.radiusLg),
      ),
      child: child,
    );

    if (onTap != null) {
      return Semantics(
        label: semanticLabel,
        hint: semanticHint,
        button: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppleSpacing.radiusLg),
          child: cardContent,
        ),
      );
    }

    return Semantics(
      label: semanticLabel,
      container: true,
      child: cardContent,
    );
  }
}

/// ============================================================================
/// 緊急アラート用のセマンティクスラッパー
/// ============================================================================

class EmergencySemantics extends StatelessWidget {
  final Widget child;
  final String emergencyMessage;
  final bool isUrgent;

  const EmergencySemantics({
    super.key,
    required this.child,
    required this.emergencyMessage,
    this.isUrgent = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: emergencyMessage,
      liveRegion: isUrgent,
      child: child,
    );
  }
}

/// ============================================================================
/// ナビゲーション情報のセマンティクス
/// ============================================================================

class NavigationSemantics extends StatelessWidget {
  final Widget child;
  final String direction;
  final String distance;
  final String? destination;

  const NavigationSemantics({
    super.key,
    required this.child,
    required this.direction,
    required this.distance,
    this.destination,
  });

  @override
  Widget build(BuildContext context) {
    String label = '$direction, $distance';
    if (destination != null) {
      label = '$destination: $label';
    }
    
    return Semantics(
      label: label,
      liveRegion: true, // 変更時に自動読み上げ
      child: child,
    );
  }
}

/// ============================================================================
/// アクセシビリティ設定に基づくスケーリング
/// ============================================================================

extension AccessibilityExtension on BuildContext {
  /// 動的テキストサイズスケール
  double get textScaleFactor => MediaQuery.textScalerOf(this).scale(1.0);
  
  /// アニメーション減少モードかどうか
  bool get reduceMotion => MediaQuery.disableAnimationsOf(this);
  
  /// 高コントラストモードかどうか
  bool get highContrast => MediaQuery.highContrastOf(this);
  
  /// VoiceOver/TalkBackが有効かどうか
  bool get accessibleNavigation => MediaQuery.accessibleNavigationOf(this);
  
  /// 太字テキストモードかどうか
  bool get boldText => MediaQuery.boldTextOf(this);
}

/// ============================================================================
/// 緊急画面用「長押しで実行」ボタン (3秒ホールドガード付き)
/// - ダブルタップで armed 状態にしてから長押しで実行
/// - 1秒/2秒/3秒で段階的ハプティック
/// ============================================================================

class GuardedHoldButton extends StatefulWidget {
  final VoidCallback onConfirmed;
  final Widget Function(BuildContext, double progress, bool armed) builder;
  final Duration holdDuration;
  final String? semanticLabel;
  final String? semanticHint;

  const GuardedHoldButton({
    super.key,
    required this.onConfirmed,
    required this.builder,
    this.holdDuration = const Duration(seconds: 3),
    this.semanticLabel,
    this.semanticHint,
  });

  @override
  State<GuardedHoldButton> createState() => _GuardedHoldButtonState();
}

class _GuardedHoldButtonState extends State<GuardedHoldButton> {
  bool _armed = false;
  DateTime? _firstTapAt;
  double _progress = 0.0;
  // ignore: unused_field
  // Timer-like: we use a periodic ticker via Stream from Future.delayed.
  // Implementation kept lightweight to avoid importing dart:async here.
  bool _holding = false;
  int _hapticStage = 0;

  void _onTap() {
    final now = DateTime.now();
    if (_firstTapAt != null &&
        now.difference(_firstTapAt!) < const Duration(milliseconds: 600)) {
      setState(() => _armed = true);
    }
    _firstTapAt = now;
  }

  Future<void> _tick() async {
    final start = DateTime.now();
    while (_holding && mounted) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      if (!_holding || !mounted) break;
      final elapsed = DateTime.now().difference(start).inMilliseconds;
      final p = (elapsed / widget.holdDuration.inMilliseconds).clamp(0.0, 1.0);
      // Staged haptics
      if (_hapticStage < 1 && elapsed >= 1000) {
        _hapticStage = 1;
        HapticFeedback.lightImpact();
      } else if (_hapticStage < 2 && elapsed >= 2000) {
        _hapticStage = 2;
        HapticFeedback.mediumImpact();
      }
      setState(() => _progress = p);
      if (p >= 1.0) {
        HapticFeedback.heavyImpact();
        _holding = false;
        widget.onConfirmed();
        if (mounted) {
          setState(() {
            _armed = false;
            _progress = 0.0;
            _hapticStage = 0;
          });
        }
        return;
      }
    }
    if (mounted) {
      setState(() {
        _progress = 0.0;
        _hapticStage = 0;
      });
    }
  }

  void _onPressStart() {
    if (!_armed) return;
    _holding = true;
    _hapticStage = 0;
    _tick();
  }

  void _onPressEnd() {
    _holding = false;
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      hint: widget.semanticHint,
      button: true,
      child: GestureDetector(
        onTap: _onTap,
        onLongPressStart: (_) => _onPressStart(),
        onLongPressEnd: (_) => _onPressEnd(),
        onLongPressCancel: _onPressEnd,
        onTapCancel: _onPressEnd,
        child: widget.builder(context, _progress, _armed),
      ),
    );
  }
}

/// ============================================================================
/// アクセシブルなフォームフィールド
/// ============================================================================

class AccessibleTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String label;
  final String? hint;
  final String? errorText;
  final bool obscureText;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  const AccessibleTextField({
    super.key,
    this.controller,
    required this.label,
    this.hint,
    this.errorText,
    this.obscureText = false,
    this.keyboardType,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      textField: true,
      child: TextField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: errorText,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppleSpacing.radiusMd),
          ),
          contentPadding: const EdgeInsets.all(AppleSpacing.md),
        ),
      ),
    );
  }
}
