import 'package:flutter/material.dart';
import '../utils/apple_design_system.dart';
import '../utils/apple_animations.dart';

/// ============================================================================
/// Apple HIG準拠の状態表示ウィジェット
/// ============================================================================
/// 
/// エラー、空状態、ローディングなどの状態を統一されたApple風デザインで表示

/// 空状態（データがない場合）
class AppleEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;

  const AppleEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon with subtle background
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppleColors.tertiaryBackground,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 40,
                color: AppleColors.tertiaryLabel,
              ),
            ),
            const SizedBox(height: 24),
            
            // Title
            Text(
              title,
              style: AppleTypography.title2.copyWith(
                color: AppleColors.label,
              ),
              textAlign: TextAlign.center,
            ),
            
            // Description
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(
                description!,
                style: AppleTypography.body.copyWith(
                  color: AppleColors.secondaryLabel,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            
            // Action Button
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppleColors.actionBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  actionLabel!,
                  style: AppleTypography.headline.copyWith(color: Colors.white),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// エラー状態
class AppleErrorState extends StatelessWidget {
  final String title;
  final String? description;
  final String? retryLabel;
  final VoidCallback? onRetry;
  final bool isWarning;

  const AppleErrorState({
    super.key,
    required this.title,
    this.description,
    this.retryLabel,
    this.onRetry,
    this.isWarning = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isWarning ? AppleColors.warningOrange : AppleColors.dangerRed;
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Error Icon
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isWarning ? Icons.warning_amber_rounded : Icons.error_outline_rounded,
                size: 44,
                color: color,
              ),
            ),
            const SizedBox(height: 24),
            
            // Title
            Text(
              title,
              style: AppleTypography.title2.copyWith(
                color: AppleColors.label,
              ),
              textAlign: TextAlign.center,
            ),
            
            // Description
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(
                description!,
                style: AppleTypography.body.copyWith(
                  color: AppleColors.secondaryLabel,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            
            // Retry Button
            if (retryLabel != null && onRetry != null) ...[
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(retryLabel!),
                style: OutlinedButton.styleFrom(
                  foregroundColor: color,
                  side: BorderSide(color: color),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// ネットワークエラー状態
class AppleNetworkError extends StatelessWidget {
  final VoidCallback? onRetry;
  final String? customMessage;

  const AppleNetworkError({
    super.key,
    this.onRetry,
    this.customMessage,
  });

  @override
  Widget build(BuildContext context) {
    return AppleErrorState(
      title: 'No Connection',
      description: customMessage ?? 'Please check your internet connection and try again.',
      retryLabel: 'Try Again',
      onRetry: onRetry,
      isWarning: true,
    );
  }
}

/// 位置情報エラー状態
class AppleLocationError extends StatelessWidget {
  final VoidCallback? onEnableLocation;

  const AppleLocationError({
    super.key,
    this.onEnableLocation,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: AppleColors.actionBlue.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_off_rounded,
                size: 44,
                color: AppleColors.actionBlue,
              ),
            ),
            const SizedBox(height: 24),
            
            Text(
              'Location Required',
              style: AppleTypography.title2.copyWith(
                color: AppleColors.label,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Enable location services for accurate navigation to shelters.',
              style: AppleTypography.body.copyWith(
                color: AppleColors.secondaryLabel,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            
            if (onEnableLocation != null)
              ElevatedButton.icon(
                onPressed: onEnableLocation,
                icon: const Icon(Icons.location_on_rounded),
                label: const Text('Enable Location'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppleColors.actionBlue,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 成功状態（一時的なフィードバック）
class AppleSuccessState extends StatelessWidget {
  final String title;
  final String? description;
  final VoidCallback? onDismiss;

  const AppleSuccessState({
    super.key,
    required this.title,
    this.description,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppleScaleIn(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Success Icon with animation
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppleColors.safetyGreen.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle_rounded,
                  size: 48,
                  color: AppleColors.safetyGreen,
                ),
              ),
              const SizedBox(height: 24),
              
              Text(
                title,
                style: AppleTypography.title2.copyWith(
                  color: AppleColors.label,
                ),
                textAlign: TextAlign.center,
              ),
              
              if (description != null) ...[
                const SizedBox(height: 8),
                Text(
                  description!,
                  style: AppleTypography.body.copyWith(
                    color: AppleColors.secondaryLabel,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// インラインエラーメッセージ（フォーム用）
class AppleInlineError extends StatelessWidget {
  final String message;

  const AppleInlineError({
    super.key,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.error_outline_rounded,
          size: 16,
          color: AppleColors.dangerRed,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: AppleTypography.caption1.copyWith(
              color: AppleColors.dangerRed,
            ),
          ),
        ),
      ],
    );
  }
}

/// 情報バナー（注意喚起用）
class AppleInfoBanner extends StatelessWidget {
  final String title;
  final String? description;
  final IconData icon;
  final Color color;
  final VoidCallback? onDismiss;

  const AppleInfoBanner({
    super.key,
    required this.title,
    this.description,
    this.icon = Icons.info_outline_rounded,
    this.color = AppleColors.actionBlue,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppleTypography.headline.copyWith(
                    color: color,
                  ),
                ),
                if (description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    description!,
                    style: AppleTypography.subhead.copyWith(
                      color: color.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onDismiss != null)
            IconButton(
              icon: Icon(Icons.close_rounded, color: color),
              onPressed: onDismiss,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
        ],
      ),
    );
  }
}
