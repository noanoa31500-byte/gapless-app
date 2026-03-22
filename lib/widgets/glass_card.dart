import 'dart:ui';
import 'package:flutter/material.dart';
import '../utils/apple_design_system.dart';

/// Apple風のすりガラス効果を持つカードウィジェット
/// 
/// グラスモーフィズム (Glassmorphism) を採用し、
/// 地図やコンテンツの上に浮く情報パネルに使用します。
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final double borderRadius;
  final double blurAmount;
  final Color? backgroundColor;
  final Color? borderColor;
  final double borderWidth;
  final List<BoxShadow>? shadow;
  final bool isDark;
  final VoidCallback? onTap;
  
  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.borderRadius = 20.0,
    this.blurAmount = 10.0,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1.0,
    this.shadow,
    this.isDark = false,
    this.onTap,
  });
  
  /// 小さめのカード（チップやバッジ向け）
  const GlassCard.small({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.margin,
    this.width,
    this.height,
    this.borderRadius = 12.0,
    this.blurAmount = 8.0,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 0.5,
    this.shadow,
    this.isDark = false,
    this.onTap,
  });
  
  /// 大きめのカード（パネルやモーダル向け）
  const GlassCard.large({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.margin,
    this.width,
    this.height,
    this.borderRadius = 24.0,
    this.blurAmount = 15.0,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 1.0,
    this.shadow,
    this.isDark = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBackgroundColor = backgroundColor ?? 
        (isDark ? AppleColors.glassDark : AppleColors.glassWhite);
    final effectiveBorderColor = borderColor ?? 
        (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.white.withValues(alpha: 0.3));
    final effectiveShadow = shadow ?? (isDark ? null : AppleShadows.medium);
    
    Widget card = ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurAmount, sigmaY: blurAmount),
        child: Container(
          width: width,
          height: height,
          padding: padding ?? const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: effectiveBackgroundColor,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: effectiveBorderColor,
              width: borderWidth,
            ),
            boxShadow: effectiveShadow,
          ),
          child: child,
        ),
      ),
    );
    
    if (margin != null) {
      card = Padding(padding: margin!, child: card);
    }
    
    if (onTap != null) {
      return GestureDetector(
        onTap: onTap,
        child: card,
      );
    }
    
    return card;
  }
}

/// ステータスを示すグラスカード（安全/警告/危険）
class StatusGlassCard extends StatelessWidget {
  final Widget child;
  final StatusType status;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final VoidCallback? onTap;
  
  const StatusGlassCard({
    super.key,
    required this.child,
    required this.status,
    this.padding,
    this.margin,
    this.borderRadius = 16.0,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    Color backgroundColor;
    
    switch (status) {
      case StatusType.safe:
        statusColor = AppleColors.safetyGreen;
        backgroundColor = AppleColors.safetyGreen.withValues(alpha: 0.15);
        break;
      case StatusType.warning:
        statusColor = AppleColors.warningOrange;
        backgroundColor = AppleColors.warningOrange.withValues(alpha: 0.15);
        break;
      case StatusType.danger:
        statusColor = AppleColors.dangerRed;
        backgroundColor = AppleColors.dangerRed.withValues(alpha: 0.15);
        break;
      case StatusType.info:
        statusColor = AppleColors.actionBlue;
        backgroundColor = AppleColors.actionBlue.withValues(alpha: 0.1);
        break;
    }
    
    return GlassCard(
      padding: padding ?? const EdgeInsets.all(16),
      margin: margin,
      borderRadius: borderRadius,
      backgroundColor: backgroundColor,
      borderColor: statusColor.withValues(alpha: 0.4),
      borderWidth: 1.5,
      onTap: onTap,
      child: child,
    );
  }
}

enum StatusType {
  safe,
  warning,
  danger,
  info,
}

/// コンパス画面用のフローティングパネル
class CompassInfoPanel extends StatelessWidget {
  final String title;
  final String value;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final bool isDark;
  
  const CompassInfoPanel({
    super.key,
    required this.title,
    required this.value,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.isDark = true,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      borderRadius: 16,
      isDark: isDark,
      backgroundColor: isDark 
          ? Colors.black.withValues(alpha: 0.6) 
          : Colors.white.withValues(alpha: 0.85),
      borderColor: isDark 
          ? Colors.white.withValues(alpha: 0.15) 
          : Colors.black.withValues(alpha: 0.1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 24,
              color: iconColor ?? (isDark ? Colors.white : AppleColors.actionBlue),
            ),
            const SizedBox(width: 12),
          ],
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppleTypography.caption1.copyWith(
                  color: isDark 
                      ? Colors.white.withValues(alpha: 0.7) 
                      : AppleColors.secondaryLabel,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: AppleTypography.headline.copyWith(
                  color: isDark ? Colors.white : AppleColors.label,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: AppleTypography.caption2.copyWith(
                    color: isDark 
                        ? Colors.white.withValues(alpha: 0.5) 
                        : AppleColors.tertiaryLabel,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// ナビゲーションボタン（Apple風）
class AppleNavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool isActive;
  final Color? activeColor;
  
  const AppleNavButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.isActive = false,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveActiveColor = activeColor ?? AppleColors.actionBlue;
    
    return GestureDetector(
      onTap: onPressed,
      child: GlassCard.small(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        backgroundColor: isActive 
            ? effectiveActiveColor.withValues(alpha: 0.15)
            : Colors.white.withValues(alpha: 0.9),
        borderColor: isActive 
            ? effectiveActiveColor.withValues(alpha: 0.4)
            : Colors.black.withValues(alpha: 0.1),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive ? effectiveActiveColor : AppleColors.secondaryLabel,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: AppleTypography.subhead.copyWith(
                color: isActive ? effectiveActiveColor : AppleColors.label,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
