import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ============================================================================
/// DisasterModeNotifier — 災害モード/緊急モード/言語の切替
/// ============================================================================
/// 旧 ShelterProvider から「災害モード/緊急モード/言語」を分離。
/// 災害モードは SharedPreferences に永続化される。
class DisasterModeNotifier extends ChangeNotifier {
  static const _kDisasterModeKey = 'disaster_mode_v1';

  bool _isEmergencyMode = true;
  bool _isDisasterMode = false;
  String _currentLanguage = 'ja';

  bool get isEmergencyMode => _isEmergencyMode;
  bool get isDisasterMode => _isDisasterMode;
  String get currentLanguage => _currentLanguage;

  /// SharedPreferences から状態をロード
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDisasterMode = prefs.getBool(_kDisasterModeKey) ?? false;
      notifyListeners();
    } catch (e) {
      debugPrint('DisasterModeNotifier load error: $e');
    }
  }

  void toggleEmergencyMode() {
    _isEmergencyMode = !_isEmergencyMode;
    notifyListeners();
  }

  void toggleDisasterMode() {
    _isDisasterMode = !_isDisasterMode;
    _persist();
    notifyListeners();
  }

  void setDisasterMode(bool value) {
    if (_isDisasterMode != value) {
      _isDisasterMode = value;
      _persist();
      notifyListeners();
    }
  }

  void setLanguage(String lang) {
    _currentLanguage = lang;
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kDisasterModeKey, _isDisasterMode);
    } catch (_) {}
  }
}
