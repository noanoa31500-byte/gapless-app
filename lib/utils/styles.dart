import 'package:flutter/material.dart';
import 'localization.dart';

// 共通のスタイル定義
TextStyle emergencyTextStyle({double size = 16, bool isBold = false, Color color = Colors.black}) {
  return TextStyle(
    fontFamily: GapLessL10n.currentFont,
    fontFamilyFallback: GapLessL10n.fallbackFonts,
    fontSize: size,
    fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
    height: 1.4,
    color: color,
  );
}

// トーフ対策済みの共通スタイル
TextStyle safeStyle({double size = 16, bool isBold = false, Color color = Colors.black}) {
  return TextStyle(
    fontFamily: GapLessL10n.currentFont,
    fontFamilyFallback: GapLessL10n.fallbackFonts,
    fontSize: size,
    fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
    height: 1.4,
    color: color,
  );
}
