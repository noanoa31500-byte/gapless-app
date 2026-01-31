import 'package:flutter/material.dart';
import 'localization.dart';

// 共通のスタイル定義
TextStyle emergencyTextStyle({double size = 16, bool isBold = false, Color color = Colors.black}) {
  bool isThai = AppLocalizations.lang == 'th';
  
  return TextStyle(
    fontFamily: isThai ? 'NotoSansThai' : 'NotoSansJP',
    fontFamilyFallback: isThai ? const ['NotoSansJP', 'sans-serif', 'Arial'] : const ['NotoSansThai', 'sans-serif', 'Arial'],
    fontSize: size,
    fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
    height: 1.4,
    color: color,
  );
}

// トーフ対策済みの共通スタイル
TextStyle safeStyle({double size = 16, bool isBold = false, Color color = Colors.black}) {
  bool isThai = AppLocalizations.lang == 'th';

  return TextStyle(
    fontFamily: isThai ? 'NotoSansThai' : 'NotoSansJP',
    fontFamilyFallback: isThai ? const ['NotoSansJP', 'sans-serif', 'Arial'] : const ['NotoSansThai', 'sans-serif', 'Arial'],
    fontSize: size,
    fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
    height: 1.4,
    color: color,
  );
}
