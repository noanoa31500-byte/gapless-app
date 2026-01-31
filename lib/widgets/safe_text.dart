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

  bool _hasThaiCharacters(String str) {
    return str.codeUnits.any((c) => c >= 0x0E00 && c <= 0x0E7F);
  }

  @override
  Widget build(BuildContext context) {
    // Content-aware font selection
    // If the specific string contains Thai characters, prioritise Thai font ONLY for this widget.
    // Otherwise, default to Japanese font (which covers Latin + JP).
    // 3. 適切なフォントを選択 (フォントロード済みの場合のみ)
    // 未ロード（オフライン失敗時）は 'sans-serif' を指定してシステムフォントに倒す
    // null だと Theme の fontFamily (NotoSansJP) が残ってしまい Tofu になる
    String? family;
    List<String>? fallbacks;
    
    if (FontService.loaded) {
      family = _hasThaiCharacters(text) ? 'NotoSansThai' : 'NotoSansJP';
      fallbacks = ['NotoSansThai', 'NotoSansJP', 'sans-serif', 'Arial'];
    } else {
      family = 'sans-serif'; // Force system font
      fallbacks = null;
    }

    // 4. スタイルに適用
    // apply() を使うと既存スタイルとマージ可能
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
