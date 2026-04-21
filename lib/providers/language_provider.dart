import 'package:flutter/material.dart';
import '../utils/localization.dart';

class LanguageProvider extends ChangeNotifier {
  String _currentLanguage = 'ja';

  String get currentLanguage => _currentLanguage;

  Future<void> setLanguage(String lang) async {
    if (_currentLanguage != lang) {
      _currentLanguage = lang;
      await GapLessL10n.setLanguage(lang);
      notifyListeners();
    }
  }

  Future<void> loadLanguage() async {
    await GapLessL10n.loadLanguage();
    _currentLanguage = GapLessL10n.lang;
    notifyListeners();
  }
}
