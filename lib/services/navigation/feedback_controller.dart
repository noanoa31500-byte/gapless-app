import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import '../../utils/apple_design_system.dart';
import '../../utils/localization.dart';

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
    await _tts.setLanguage(_ttsLocale(GapLessL10n.lang));
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    // iOS/Android settings
    await _tts.setIosAudioCategory(IosTextToSpeechAudioCategory.ambient,
        [IosTextToSpeechAudioCategoryOptions.mixWithOthers]);
  }

  /// GapLessL10n言語コードをTTSロケール文字列に変換（18言語対応）
  String _ttsLocale(String lang) {
    switch (lang) {
      case 'ja':    return 'ja-JP';
      case 'th':    return 'th-TH';
      case 'zh':    return 'zh-CN';
      case 'zh_TW': return 'zh-TW';
      case 'ko':    return 'ko-KR';
      case 'hi':    return 'hi-IN';
      case 'bn':    return 'bn-BD';
      case 'id':    return 'id-ID';
      case 'vi':    return 'vi-VN';
      case 'es':    return 'es-ES';
      case 'pt':    return 'pt-BR';
      default:      return 'en-US';
    }
  }

  // --- Haptic Feedback Methods ---

  /// 正しいルート上 (Light Impact)
  Future<void> vibrateOnRoute() async {
    if (!_hapticEnabled) return;
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: 15, amplitude: 60); // Light
    }
  }

  /// 目的地到着 (Success Pattern)
  Future<void> vibrateArrrival() async {
    if (!_hapticEnabled) return;
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(pattern: [0, 100, 50, 100]); // Two pulses
    }
  }

  /// 危険/逸脱警告 (Warning Pattern)
  Future<void> vibrateWarning() async {
    if (!_hapticEnabled) return;
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: 500); // Long heavy
    }
  }

  // --- Voice Feedback Methods ---

  Future<void> speak(String text) async {
    if (!_voiceEnabled) return;
    await _tts.speak(text);
  }

  Future<void> speakNavigationUpdate(double distance, String direction) async {
    final distStr = distance >= 1000
        ? GapLessL10n.t('tts_distance_km').replaceAll('@dist', (distance / 1000).toStringAsFixed(1))
        : GapLessL10n.t('tts_distance_m').replaceAll('@dist', distance.round().toString());
    await speak('$distStr $direction');
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
