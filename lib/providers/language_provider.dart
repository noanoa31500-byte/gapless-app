import 'package:flutter/material.dart';
import '../utils/localization.dart';

class LanguageProvider extends ChangeNotifier {
  String _currentLanguage = 'ja';

  String get currentLanguage => _currentLanguage;

  Future<void> setLanguage(String lang) async {
    if (_currentLanguage != lang) {
      _currentLanguage = lang;
      await AppLocalizations.setLanguage(lang);
      notifyListeners();
    }
  }
  
  Future<void> loadLanguage() async {
    await AppLocalizations.loadLanguage();
    _currentLanguage = AppLocalizations.lang;
    notifyListeners();
  }
}
