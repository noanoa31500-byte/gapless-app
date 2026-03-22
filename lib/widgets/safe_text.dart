import 'package:flutter/material.dart';
import '../services/font_service.dart';

class SafeText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextOverflow? overflow;
  final int? maxLines;

  const SafeText(
    this.text, {
    super.key,
    this.style,
    this.textAlign,
    this.overflow,
    this.maxLines,
  });

  /// テキスト内容に基づいて最適なフォントを返す
  String _fontForContent(String str) {
    for (final c in str.runes) {
      if (c >= 0x0E00 && c <= 0x0E7F) return 'NotoSansThai';       // Thai
      if (c >= 0x1000 && c <= 0x109F) return 'NotoSansMyanmar';     // Myanmar
      if (c >= 0x0D80 && c <= 0x0DFF) return 'NotoSansSinhala';     // Sinhala
      if (c >= 0x0900 && c <= 0x097F) return 'NotoSansDevanagari';  // Devanagari (Hindi/Nepali)
      if (c >= 0x0980 && c <= 0x09FF) return 'NotoSansBengali';     // Bengali
      if (c >= 0xAC00 && c <= 0xD7A3) return 'NotoSansKR';          // Hangul
      if (c >= 0x4E00 && c <= 0x9FFF) return 'NotoSansSC';          // CJK Unified (Chinese)
      if (c >= 0x3040 && c <= 0x30FF) return 'NotoSansJP';          // Hiragana/Katakana
    }
    return 'NotoSans'; // デフォルト（ラテン文字等）
  }

  @override
  Widget build(BuildContext context) {
    String? family;
    List<String>? fallbacks;

    if (FontService.loaded) {
      family = _fontForContent(text);
      fallbacks = const [
        'NotoSansJP', 'NotoSansSC', 'NotoSansTC', 'NotoSansKR',
        'NotoSansThai', 'NotoSansMyanmar', 'NotoSansSinhala',
        'NotoSansDevanagari', 'NotoSansBengali', 'NotoSans', 'sans-serif',
      ];
    } else {
      family = 'sans-serif';
      fallbacks = null;
    }

    final effectiveStyle = (style ?? const TextStyle()).copyWith(
      fontFamily: family,
      fontFamilyFallback: fallbacks,
    );

    return Text(
      text,
      style: effectiveStyle,
      textAlign: textAlign,
      overflow: overflow,
      maxLines: maxLines,
    );
  }
}
