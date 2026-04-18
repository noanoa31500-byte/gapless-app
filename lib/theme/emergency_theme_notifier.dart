// ============================================================
// emergency_theme_notifier.dart
// 緊急モードの ON/OFF を保持し、テーマ切替をトリガする ChangeNotifier
// ============================================================

import 'package:flutter/foundation.dart';

class EmergencyThemeNotifier extends ChangeNotifier {
  bool _isEmergency = false;
  bool get isEmergency => _isEmergency;

  void activateEmergency() {
    if (_isEmergency) return;
    _isEmergency = true;
    notifyListeners();
  }

  void deactivateEmergency() {
    if (!_isEmergency) return;
    _isEmergency = false;
    notifyListeners();
  }
}
