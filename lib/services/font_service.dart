
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class FontService {
  static bool _loaded = false;
  static bool get loaded => _loaded;

  static Future<void> loadFonts() async {
    if (_loaded) return;

    try {
      await Future.wait([
        _loadFont('NotoSansJP', 'assets/fonts/NotoSansJP-Regular.ttf'),
        _loadFont('NotoSansJP', 'assets/fonts/NotoSansJP-Bold.ttf', weight: FontWeight.bold),
        _loadFont('NotoSansThai', 'assets/fonts/NotoSansThai-Regular.ttf'),
        _loadFont('NotoSansThai', 'assets/fonts/NotoSansThai-Bold.ttf', weight: FontWeight.bold),
      ]);
      _loaded = true;
      print('--- [FontService] All fonts loaded successfully ---');
    } catch (e) {
      print('--- [FontService] Failed to load fonts: $e ---');
      // If fonts fail (e.g. offline and not cached), we stay _loaded = false.
      // SafeText should handle this by falling back to system fonts.
      _loaded = false;
    }
  }

  static Future<void> _loadFont(String family, String assetPath, {FontWeight weight = FontWeight.normal}) async {
    ByteData? byteData;

    try {
      // 1. Try rootBundle (Standard)
      byteData = await rootBundle.load(assetPath);
      _validateBytes(byteData, assetPath);
    } catch (e) {
      // 2. Try Direct HTTP (Fallback for Web 404s/Manifest issues)
      final rawUrl = 'assets/$assetPath'; 
      try {
        final response = await http.get(Uri.parse(rawUrl));
        if (response.statusCode == 200) {
          final data = ByteData.view(response.bodyBytes.buffer);
          _validateBytes(data, rawUrl);
          byteData = data;
        } else {
          throw Exception('HTTP ${response.statusCode}');
        }
      } catch (e2) {
         print('[FontService] Custom font $family ($assetPath) unavailable. Using System Font.');
         return; 
      }
    }

    // byteData is guaranteed non-null here by flow analysis (return on failure)
    final loader = FontLoader(family);
    loader.addFont(Future.value(byteData));
    await loader.load();
  }

  static void _validateBytes(ByteData data, String path) {
     // Thai fonts are smaller (~45KB), so we lower the threshold to 20KB.
     if (data.lengthInBytes < 20 * 1024) throw Exception('Too small');
     final uint32 = data.getUint32(0);
     if (uint32 != 0x00010000 && uint32 != 0x4F54544F && uint32 != 0x74746366) {
       throw Exception('Invalid Header');
     }
  }
}
