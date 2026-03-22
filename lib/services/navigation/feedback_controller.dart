import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import '../../utils/apple_design_system.dart';

/// ============================================================================
/// FeedbackController - ユーザーへのフィードバック（振動・音声・視覚）統括
/// ============================================================================
class FeedbackController {
  final FlutterTts _tts = FlutterTts();
  bool _hapticEnabled = true;
  bool _voiceEnabled = true;

  // Visual State
  Color? _overlayColor;
  String? _alertMessage;
  
  Color? get overlayColor => _overlayColor;
  String? get alertMessage => _alertMessage;

  Future<void> init() async {
    await _tts.setLanguage('ja-JP');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    // iOS/Android settings
    await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.ambient,
        [IosTextToSpeechAudioCategoryOptions.mixWithOthers]);
  }

  // --- Haptic Feedback Methods ---

  /// 正しいルート上 (Light Impact)
  Future<void> vibrateOnRoute() async {
    if (!_hapticEnabled) return;
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 15, amplitude: 60); // Light
    }
  }

  /// 目的地到着 (Success Pattern)
  Future<void> vibrateArrrival() async {
    if (!_hapticEnabled) return;
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(pattern: [0, 100, 50, 100]); // Two pulses
    }
  }

  /// 危険/逸脱警告 (Warning Pattern)
  Future<void> vibrateWarning() async {
    if (!_hapticEnabled) return;
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(duration: 500); // Long heavy
    }
  }

  // --- Voice Feedback Methods ---

  Future<void> speak(String text) async {
    if (!_voiceEnabled) return;
    await _tts.speak(text);
  }

  Future<void> speakNavigationUpdate(double distance, String direction) async {
    // "およそ300メートル先、南東です"
    String distStr;
    if (distance >= 1000) {
      distStr = '${(distance / 1000).toStringAsFixed(1)}キロ';
    } else {
      distStr = '${distance.round()}メートル';
    }
    
    await speak('およそ$distStr先、$directionです');
  }

  // --- Visual Alert Management ---

  void updateVisualState({
    required bool isSafe,
    required bool isOffRoute,
    required bool isNearHazard,
  }) {
    if (isNearHazard) {
      _overlayColor = AppleColors.dangerRed.withValues(alpha: 0.3);
      _alertMessage = "DANGER ZONE";
    } else if (isOffRoute) {
       _overlayColor = AppleColors.warningOrange.withValues(alpha: 0.2);
       _alertMessage = "REROUTING";
    } else if (isSafe) {
       _overlayColor = AppleColors.safetyGreen.withValues(alpha: 0.1);
       _alertMessage = "ON ROUTE";
    } else {
      _overlayColor = null;
      _alertMessage = null;
    }
  }

  void dispose() {
    _tts.stop();
  }
}
