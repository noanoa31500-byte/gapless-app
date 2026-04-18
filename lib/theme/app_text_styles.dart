// ============================================================
// app_text_styles.dart
// Apple Design System のタイポグラフィスケール
// fontFamily は null（iOS では SF Pro が自動適用される）。
// 多言語フォント（Noto Sans）はテーマ生成時に apply() で重ねる。
// ============================================================

import 'package:flutter/material.dart';

class AppTextStyles {
  AppTextStyles._();

  static const TextStyle displayLarge = TextStyle(
    fontSize: 56,
    fontWeight: FontWeight.w600,
    height: 1.07,
    letterSpacing: -0.28,
  );

  static const TextStyle displayMedium = TextStyle(
    fontSize: 40,
    fontWeight: FontWeight.w600,
    height: 1.10,
    letterSpacing: -0.28,
  );

  static const TextStyle displaySmall = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w400,
    height: 1.14,
    letterSpacing: 0.196,
  );

  static const TextStyle titleLarge = TextStyle(
    fontSize: 21,
    fontWeight: FontWeight.w700,
    height: 1.19,
    letterSpacing: 0.231,
  );

  static const TextStyle titleMedium = TextStyle(
    fontSize: 21,
    fontWeight: FontWeight.w400,
    height: 1.19,
    letterSpacing: 0.231,
  );

  static const TextStyle bodyLarge = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    height: 1.47,
    letterSpacing: -0.374,
  );

  static const TextStyle bodyEmphasis = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 1.24,
    letterSpacing: -0.374,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 1.43,
    letterSpacing: -0.224,
  );

  static const TextStyle bodySmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.33,
    letterSpacing: -0.12,
  );

  static const TextStyle labelLarge = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.224,
  );

  static const TextStyle labelSmall = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

  static const TextStyle nano = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w400,
    height: 1.47,
    letterSpacing: -0.08,
  );

  static const TextTheme textTheme = TextTheme(
    displayLarge: displayLarge,
    displayMedium: displayMedium,
    displaySmall: displaySmall,
    titleLarge: titleLarge,
    titleMedium: titleMedium,
    bodyLarge: bodyLarge,
    bodyMedium: bodyMedium,
    bodySmall: bodySmall,
    labelLarge: labelLarge,
    labelSmall: labelSmall,
  );
}
