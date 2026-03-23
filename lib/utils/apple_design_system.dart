import 'package:flutter/material.dart';
import 'localization.dart';

/// Apple Human Interface Guidelines (HIG) に準拠したデザインシステム
/// 
/// コンセプト: "Safety & Clarity"
/// 災害時のパニック状態でも誤操作を防ぐ、
/// Apple流の「コンテンツファースト」なデザイン

// =============================================================================
// SEMANTIC COLORS - Apple標準の意味論的カラーパレット
// =============================================================================

class AppleColors {
  AppleColors._();
  
  // Primary Actions
  static const Color actionBlue = Color(0xFF007AFF);
  static const Color actionBluePressed = Color(0xFF0051D5);
  
  // Safety & Status
  static const Color safetyGreen = Color(0xFF34C759);
  static const Color warningOrange = Color(0xFFFF9500);
  static const Color dangerRed = Color(0xFFFF3B30);
  
  // Neutral Grays (Light Mode)
  static const Color label = Color(0xFF000000);
  static const Color secondaryLabel = Color(0xFF3C3C43);
  static const Color tertiaryLabel = Color(0xFF48484A);
  static const Color quaternaryLabel = Color(0xFF636366);
  
  // Backgrounds (Light Mode)
  static const Color systemBackground = Color(0xFFFFFFFF);
  static const Color secondaryBackground = Color(0xFFF2F2F7);
  static const Color tertiaryBackground = Color(0xFFE5E5EA);
  
  // Separators
  static const Color separator = Color(0xFFC6C6C8);
  static const Color opaqueSeparator = Color(0xFFE5E5EA);
  
  // Glass Effect
  static const Color glassWhite = Color(0xCCFFFFFF); // 80% opacity
  static const Color glassBorder = Color(0x33FFFFFF); // 20% opacity
  
  // Gradients
  static const LinearGradient compassGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFF1C1C1E),
      Color(0xFF2C2C2E),
    ],
  );
  
  // Dark Mode variants
  static const Color darkLabel = Color(0xFFFFFFFF);
  static const Color darkSecondaryLabel = Color(0xFFEBEBF5);
  static const Color darkBackground = Color(0xFF000000);
  static const Color darkSecondaryBackground = Color(0xFF1C1C1E);
  static const Color darkTertiaryBackground = Color(0xFF2C2C2E);
  static const Color glassDark = Color(0xB3000000); // 70% opacity
}

// =============================================================================
// TYPOGRAPHY - San Francisco風のタイポグラフィ階層
// =============================================================================

class AppleTypography {
  AppleTypography._();

  // 豆腐・文字化け防止: 全スタイルにNotoSansフォントチェーンを付与
  static String get _font => GapLessL10n.currentFont;
  static List<String> get _fallback => GapLessL10n.fallbackFonts;

  // Large Title (Navigation bars)
  static TextStyle get largeTitle => TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 34, fontWeight: FontWeight.w700,
    letterSpacing: 0.37, height: 1.2,
  );

  // Title 1
  static TextStyle get title1 => TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 28, fontWeight: FontWeight.w700,
    letterSpacing: 0.36, height: 1.2,
  );

  // Title 2
  static TextStyle get title2 => TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 22, fontWeight: FontWeight.w700,
    letterSpacing: 0.35, height: 1.3,
  );

  // Title 3
  static TextStyle get title3 => TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 20, fontWeight: FontWeight.w600,
    letterSpacing: 0.38, height: 1.3,
  );

  // Headline
  static TextStyle get headline => TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 17, fontWeight: FontWeight.w600,
    letterSpacing: -0.41, height: 1.3,
  );

  // Body
  static TextStyle get body => TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 17, fontWeight: FontWeight.w400,
    letterSpacing: -0.41, height: 1.4,
  );

  // Callout
  static TextStyle get callout => TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 16, fontWeight: FontWeight.w400,
    letterSpacing: -0.32, height: 1.4,
  );

  // Subhead
  static TextStyle get subhead => TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 15, fontWeight: FontWeight.w400,
    letterSpacing: -0.24, height: 1.4,
  );

  // Footnote
  static TextStyle get footnote => TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 13, fontWeight: FontWeight.w400,
    letterSpacing: -0.08, height: 1.4,
  );

  // Caption 1
  static TextStyle get caption1 => TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 12, fontWeight: FontWeight.w400,
    letterSpacing: 0, height: 1.3,
  );

  // Caption 2
  static TextStyle get caption2 => TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 11, fontWeight: FontWeight.w400,
    letterSpacing: 0.07, height: 1.3,
  );

  // Emergency Mode - 大きく太く
  static TextStyle get emergencyLarge => TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 48, fontWeight: FontWeight.w800,
    letterSpacing: -1.0, height: 1.1,
  );

  static TextStyle get emergencyMedium => TextStyle(
    fontFamily: _font, fontFamilyFallback: _fallback,
    fontSize: 32, fontWeight: FontWeight.w700,
    letterSpacing: -0.5, height: 1.2,
  );
}

// =============================================================================
// SPACING & LAYOUT - 一貫した間隔システム
// =============================================================================

class AppleSpacing {
  AppleSpacing._();
  
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;
  
  // 角丸
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 20.0;
  static const double radiusFull = 9999.0;
}

// =============================================================================
// SHADOWS - 洗練された影効果
// =============================================================================

class AppleShadows {
  AppleShadows._();
  
  static const List<BoxShadow> small = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 4,
      offset: Offset(0, 2),
    ),
  ];
  
  static const List<BoxShadow> medium = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 10,
      offset: Offset(0, 4),
    ),
  ];
  
  static const List<BoxShadow> large = [
    BoxShadow(
      color: Color(0x26000000),
      blurRadius: 20,
      offset: Offset(0, 8),
    ),
  ];
  
  static const List<BoxShadow> floatingCard = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 16,
      offset: Offset(0, 4),
      spreadRadius: 0,
    ),
    BoxShadow(
      color: Color(0x0D000000),
      blurRadius: 32,
      offset: Offset(0, 16),
      spreadRadius: 0,
    ),
  ];
}

// =============================================================================
// THEME DATA - アプリ全体のテーマ
// =============================================================================

ThemeData buildAppleTheme({bool isDark = false}) {
  final colorScheme = isDark
      ? const ColorScheme.dark(
          primary: AppleColors.actionBlue,
          secondary: AppleColors.safetyGreen,
          error: AppleColors.dangerRed,
          surface: AppleColors.darkSecondaryBackground,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onError: Colors.white,
          onSurface: AppleColors.darkLabel,
        )
      : const ColorScheme.light(
          primary: AppleColors.actionBlue,
          secondary: AppleColors.safetyGreen,
          error: AppleColors.dangerRed,
          surface: AppleColors.systemBackground,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onError: Colors.white,
          onSurface: AppleColors.label,
        );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    brightness: isDark ? Brightness.dark : Brightness.light,
    
    // Scaffold
    scaffoldBackgroundColor: isDark 
        ? AppleColors.darkBackground 
        : AppleColors.systemBackground,
    
    // AppBar
    appBarTheme: AppBarTheme(
      backgroundColor: isDark 
          ? AppleColors.darkSecondaryBackground.withValues(alpha: 0.9)
          : AppleColors.systemBackground.withValues(alpha: 0.9),
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: true,
      titleTextStyle: AppleTypography.headline.copyWith(
        color: isDark ? AppleColors.darkLabel : AppleColors.label,
      ),
      iconTheme: IconThemeData(
        color: AppleColors.actionBlue,
      ),
    ),
    
    // Cards
    cardTheme: CardThemeData(
      color: isDark 
          ? AppleColors.darkSecondaryBackground 
          : AppleColors.systemBackground,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppleSpacing.radiusLg),
      ),
      margin: const EdgeInsets.symmetric(
        horizontal: AppleSpacing.md,
        vertical: AppleSpacing.sm,
      ),
    ),
    
    // Buttons
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppleColors.actionBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: AppleSpacing.lg,
          vertical: AppleSpacing.md,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppleSpacing.radiusMd),
        ),
        textStyle: AppleTypography.headline,
      ),
    ),
    
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppleColors.actionBlue,
        textStyle: AppleTypography.headline,
      ),
    ),
    
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppleColors.actionBlue,
        side: const BorderSide(color: AppleColors.actionBlue),
        padding: const EdgeInsets.symmetric(
          horizontal: AppleSpacing.lg,
          vertical: AppleSpacing.md,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppleSpacing.radiusMd),
        ),
        textStyle: AppleTypography.headline,
      ),
    ),
    
    // Floating Action Button
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppleColors.actionBlue,
      foregroundColor: Colors.white,
      elevation: 4,
      shape: CircleBorder(),
    ),
    
    // Bottom Navigation
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: isDark 
          ? AppleColors.darkSecondaryBackground.withValues(alpha: 0.95)
          : AppleColors.systemBackground.withValues(alpha: 0.95),
      selectedItemColor: AppleColors.actionBlue,
      unselectedItemColor: AppleColors.quaternaryLabel,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    
    // Chip
    chipTheme: ChipThemeData(
      backgroundColor: isDark 
          ? AppleColors.darkTertiaryBackground 
          : AppleColors.secondaryBackground,
      selectedColor: AppleColors.actionBlue.withValues(alpha: 0.15),
      labelStyle: AppleTypography.subhead,
      padding: const EdgeInsets.symmetric(
        horizontal: AppleSpacing.sm,
        vertical: AppleSpacing.xs,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppleSpacing.radiusFull),
      ),
    ),
    
    // Divider
    dividerTheme: DividerThemeData(
      color: isDark ? AppleColors.separator.withValues(alpha: 0.3) : AppleColors.separator,
      thickness: 0.5,
      space: AppleSpacing.md,
    ),
    
    // Snackbar
    snackBarTheme: SnackBarThemeData(
      backgroundColor: isDark 
          ? AppleColors.darkTertiaryBackground 
          : AppleColors.label.withValues(alpha: 0.9),
      contentTextStyle: AppleTypography.subhead.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppleSpacing.radiusMd),
      ),
      behavior: SnackBarBehavior.floating,
    ),
    
    // Dialog
    dialogTheme: DialogThemeData(
      backgroundColor: isDark 
          ? AppleColors.darkSecondaryBackground 
          : AppleColors.systemBackground,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppleSpacing.radiusXl),
      ),
      titleTextStyle: AppleTypography.title3.copyWith(
        color: isDark ? AppleColors.darkLabel : AppleColors.label,
      ),
      contentTextStyle: AppleTypography.body.copyWith(
        color: isDark ? AppleColors.darkSecondaryLabel : AppleColors.secondaryLabel,
      ),
    ),
    
    // Text Theme
    textTheme: TextTheme(
      displayLarge: AppleTypography.largeTitle.copyWith(
        color: isDark ? AppleColors.darkLabel : AppleColors.label,
      ),
      displayMedium: AppleTypography.title1.copyWith(
        color: isDark ? AppleColors.darkLabel : AppleColors.label,
      ),
      displaySmall: AppleTypography.title2.copyWith(
        color: isDark ? AppleColors.darkLabel : AppleColors.label,
      ),
      headlineMedium: AppleTypography.title3.copyWith(
        color: isDark ? AppleColors.darkLabel : AppleColors.label,
      ),
      headlineSmall: AppleTypography.headline.copyWith(
        color: isDark ? AppleColors.darkLabel : AppleColors.label,
      ),
      titleLarge: AppleTypography.headline.copyWith(
        color: isDark ? AppleColors.darkLabel : AppleColors.label,
      ),
      bodyLarge: AppleTypography.body.copyWith(
        color: isDark ? AppleColors.darkLabel : AppleColors.label,
      ),
      bodyMedium: AppleTypography.callout.copyWith(
        color: isDark ? AppleColors.darkSecondaryLabel : AppleColors.secondaryLabel,
      ),
      bodySmall: AppleTypography.footnote.copyWith(
        color: isDark ? AppleColors.darkSecondaryLabel : AppleColors.secondaryLabel,
      ),
      labelLarge: AppleTypography.headline.copyWith(
        color: isDark ? AppleColors.darkLabel : AppleColors.label,
      ),
      labelSmall: AppleTypography.caption1.copyWith(
        color: isDark ? AppleColors.darkSecondaryLabel : AppleColors.tertiaryLabel,
      ),
    ),
  );
}
