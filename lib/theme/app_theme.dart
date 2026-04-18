// ============================================================
// app_theme.dart
// Apple Design System に準拠した ThemeData ファクトリ
// 通常テーマ（緑プライマリ） / 緊急テーマ（赤プライマリ）の 2 種類
// ============================================================

import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_text_styles.dart';

class AppTheme {
  AppTheme._();

  /// 通常テーマ（緑プライマリ）。
  /// 言語ごとのフォント切替が不要な場合のショートカット。
  static ThemeData get normal => buildNormal();

  /// 緊急テーマ（赤プライマリ）。
  /// 言語ごとのフォント切替が不要な場合のショートカット。
  static ThemeData get emergency => buildEmergency();

  /// 通常テーマを生成。多言語フォント切替を渡せるよう拡張版。
  /// `fontFamily` を渡すとテキストテーマ全体に apply される。
  static ThemeData buildNormal({
    String? fontFamily,
    List<String>? fontFamilyFallback,
  }) {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.primaryGreenDark,
      onPrimary: AppColors.pureBlack,
      primaryContainer: AppColors.darkSurface1,
      onPrimaryContainer: AppColors.lightGray,
      secondary: AppColors.primaryGreen,
      onSecondary: AppColors.pureBlack,
      surface: AppColors.pureBlack,
      onSurface: AppColors.lightGray,
      surfaceContainerHigh: AppColors.darkSurface1,
      outline: AppColors.border,
      error: AppColors.emergencyRedDark,
      onError: AppColors.white,
    );

    return _buildBase(
      scheme: scheme,
      filledButtonBg: AppColors.nearBlack,
      filledButtonFg: AppColors.lightGray,
      outlineColor: AppColors.primaryGreenDark,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );
  }

  /// 緊急テーマを生成。多言語フォント切替を渡せるよう拡張版。
  static ThemeData buildEmergency({
    String? fontFamily,
    List<String>? fontFamilyFallback,
  }) {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.emergencyRedDark,
      onPrimary: AppColors.white,
      primaryContainer: AppColors.emergencyRedSurface,
      onPrimaryContainer: AppColors.white,
      secondary: AppColors.warningOrange,
      onSecondary: AppColors.pureBlack,
      surface: AppColors.pureBlack,
      onSurface: AppColors.white,
      surfaceContainerHigh: AppColors.emergencyRedSurface,
      outline: AppColors.emergencyRedMuted,
      error: AppColors.emergencyRedDark,
      onError: AppColors.white,
    );

    return _buildBase(
      scheme: scheme,
      filledButtonBg: AppColors.nearBlack,
      filledButtonFg: AppColors.white,
      outlineColor: AppColors.emergencyRedDark,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
    );
  }

  // ────────────────────────────────────────
  // 共通ベース：両テーマで使うコンポーネント定義
  // ────────────────────────────────────────
  static ThemeData _buildBase({
    required ColorScheme scheme,
    required Color filledButtonBg,
    required Color filledButtonFg,
    required Color outlineColor,
    String? fontFamily,
    List<String>? fontFamilyFallback,
  }) {
    final textTheme = AppTextStyles.textTheme.apply(
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );

    const pillShape = StadiumBorder();
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    );
    final inputShape = OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide(color: AppColors.border),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.pureBlack,
      fontFamily: fontFamily,
      fontFamilyFallback: fontFamilyFallback,
      textTheme: textTheme,
      primaryTextTheme: textTheme,

      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.navBgDark,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: AppTextStyles.titleLarge.copyWith(
          color: scheme.onSurface,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: pillShape,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
          elevation: 0,
          textStyle: AppTextStyles.bodyEmphasis.copyWith(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: scheme.primary,
          shape: pillShape,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
          side: BorderSide(color: outlineColor, width: 1),
          textStyle: AppTextStyles.bodyEmphasis.copyWith(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback,
          ),
        ),
      ),

      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: filledButtonBg,
          foregroundColor: filledButtonFg,
          shape: cardShape,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
          textStyle: AppTextStyles.bodyEmphasis.copyWith(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          textStyle: AppTextStyles.bodyEmphasis.copyWith(
            fontFamily: fontFamily,
            fontFamilyFallback: fontFamilyFallback,
          ),
        ),
      ),

      cardTheme: CardThemeData(
        color: scheme.surfaceContainerHigh,
        elevation: 0,
        shape: cardShape,
        shadowColor: const Color(0x80000000),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        border: inputShape,
        enabledBorder: inputShape,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.emergencyRedDark, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.emergencyRedDark, width: 1.5),
        ),
        labelStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.textSecondaryDark,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
        ),
      ),

      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),

      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainerHigh,
        selectedColor: scheme.primary,
        labelStyle: AppTextStyles.labelLarge.copyWith(
          color: scheme.onSurface,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
        ),
        secondaryLabelStyle: AppTextStyles.labelLarge.copyWith(
          color: scheme.onPrimary,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(11),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        shape: const CircleBorder(),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.darkSurface2,
        contentTextStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.lightGray,
          fontFamily: fontFamily,
          fontFamilyFallback: fontFamilyFallback,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.darkSurface1,
        modalBackgroundColor: AppColors.darkSurface1,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        ),
      ),
    );
  }
}
