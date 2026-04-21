import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../utils/localization.dart';

/// アラート機能を管理するProvider（振動・視覚フィードバック・音声）
/// 多言語TTS対応版
class AlertProvider with ChangeNotifier {
  bool _isMonitoringActive = false;
  bool _isInHazardArea = false;
  bool _isFlashing = false;
  Color _currentBackgroundColor = Colors.white;
  Timer? _flashTimer;
  final FlutterTts _tts = FlutterTts();

  // 自動読み上げ制御
  bool _isVoiceGuidanceEnabled = true;
  DateTime? _lastSpokenTime;
  static const Duration _speakCooldown = Duration(seconds: 5); // 連続読み上げ防止

  // Getters
  bool get isMonitoringActive => _isMonitoringActive;
  bool get isInHazardArea => _isInHazardArea;
  bool get isFlashing => _isFlashing;
  Color get currentBackgroundColor => _currentBackgroundColor;
  bool get isVoiceGuidanceEnabled => _isVoiceGuidanceEnabled;

  AlertProvider() {
    _initializeTts();
  }

  /// TTS初期化（多言語対応）
  Future<void> _initializeTts() async {
    await _updateTtsLanguage();
    await _tts.setSpeechRate(0.5); // ゆっくり話す
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
  }

  /// 言語設定に応じてTTS言語を更新（18言語対応）
  Future<void> _updateTtsLanguage() async {
    final lang = GapLessL10n.lang;
    String ttsLang;

    switch (lang) {
      case 'ja':
        ttsLang = 'ja-JP';
        break;
      case 'th':
        ttsLang = 'th-TH';
        break;
      case 'zh':
        ttsLang = 'zh-CN';
        break;
      case 'zh_TW':
        ttsLang = 'zh-TW';
        break;
      case 'ko':
        ttsLang = 'ko-KR';
        break;
      case 'hi':
        ttsLang = 'hi-IN';
        break;
      case 'bn':
        ttsLang = 'bn-BD';
        break;
      case 'id':
        ttsLang = 'id-ID';
        break;
      case 'vi':
        ttsLang = 'vi-VN';
        break;
      case 'es':
        ttsLang = 'es-ES';
        break;
      case 'pt':
        ttsLang = 'pt-BR';
        break;
      case 'fil':
      case 'my':
      case 'si':
      case 'ne':
      case 'mn':
      case 'uz':
      case 'en':
      default:
        ttsLang = 'en-US';
        break;
    }

    await _tts.setLanguage(ttsLang);
  }

  /// 言語変更時に呼び出す
  Future<void> onLanguageChanged() async {
    await _updateTtsLanguage();
  }

  /// 音声ガイダンスのON/OFF切り替え
  void toggleVoiceGuidance() {
    _isVoiceGuidanceEnabled = !_isVoiceGuidanceEnabled;
    notifyListeners();
  }

  /// 音声ガイダンスを設定
  void setVoiceGuidance(bool enabled) {
    _isVoiceGuidanceEnabled = enabled;
    notifyListeners();
  }

  /// 監視を開始（ユーザーインタラクション必須 - Web AudioContext対応）
  Future<void> startMonitoring() async {
    _isMonitoringActive = true;
    notifyListeners();

    // 音声で確認（多言語）
    await _speak(_getLocalizedMessage('monitoring_start'));
  }

  /// 監視を停止
  void stopMonitoring() {
    _isMonitoringActive = false;
    _stopFlashing();
    notifyListeners();
  }

  /// ハザードエリアに入った時の処理
  Future<void> enterHazardArea() async {
    if (!_isMonitoringActive) return;

    _isInHazardArea = true;
    notifyListeners();

    // プラットフォームに応じたフィードバック
    if (kIsWeb) {
      // Web: 視覚的フィードバック（画面フラッシュ）
      _startFlashing();
    } else {
      // Native: 振動フィードバック
      await _triggerVibration();
    }

    // 音声警告（多言語）
    await _speak(_getLocalizedMessage('hazard_warning'));
  }

  /// ハザードエリアから出た時の処理
  Future<void> exitHazardArea() async {
    _isInHazardArea = false;
    _stopFlashing();
    notifyListeners();

    await _speak(_getLocalizedMessage('safe_area'));
  }

  /// 深水エリア警告
  Future<void> warnDeepWater(double depth) async {
    final depthText = depth.toStringAsFixed(1);
    await _speakWithCooldown(
        _getLocalizedMessage('deep_water').replaceAll('@depth', depthText));
  }

  /// 激流警告
  Future<void> warnFastCurrent() async {
    await _speakWithCooldown(_getLocalizedMessage('fast_current'));
  }

  /// 画面フラッシュを開始（Web用）
  void _startFlashing() {
    if (_isFlashing) return;

    _isFlashing = true;
    _flashTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      _currentBackgroundColor = _currentBackgroundColor == Colors.white
          ? Colors.red.withValues(alpha: 0.3)
          : Colors.white;
      notifyListeners();
    });
  }

  /// 画面フラッシュを停止
  void _stopFlashing() {
    _isFlashing = false;
    _flashTimer?.cancel();
    _flashTimer = null;
    _currentBackgroundColor = Colors.white;
    notifyListeners();
  }

  /// 振動フィードバック（Native用）
  Future<void> _triggerVibration() async {
    try {
      final hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        // 強い振動パターン（危険を知らせる）
        await Vibration.vibrate(
          pattern: [0, 500, 200, 500, 200, 500],
          intensities: [0, 255, 0, 255, 0, 255],
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('振動エラー: $e');
      }
    }
  }

  /// 音声読み上げ（基本）
  Future<void> _speak(String text) async {
    if (!_isVoiceGuidanceEnabled) return;

    try {
      await _updateTtsLanguage(); // 言語を常に最新に
      await _tts.speak(text);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('TTS エラー: $e');
      }
    }
  }

  /// クールダウン付き音声読み上げ（連続読み上げ防止）
  Future<void> _speakWithCooldown(String text) async {
    if (!_isVoiceGuidanceEnabled) return;

    final now = DateTime.now();
    if (_lastSpokenTime != null &&
        now.difference(_lastSpokenTime!) < _speakCooldown) {
      return; // クールダウン中
    }

    _lastSpokenTime = now;
    await _speak(text);
  }

  /// 外部から直接読み上げ（公開メソッド）
  Future<void> speak(String text) async {
    await _speak(text);
  }

  /// 到着時の音声（多言語）
  Future<void> speakArrival() async {
    await _speak(_getLocalizedMessage('arrival'));
  }

  /// 距離と方向を音声で案内（多言語）
  Future<void> speakNavigation(double distanceMeters, String direction) async {
    final distanceText = distanceMeters < 1000
        ? GapLessL10n.t('tts_distance_m')
            .replaceAll('@dist', distanceMeters.toInt().toString())
        : GapLessL10n.t('tts_distance_km')
            .replaceAll('@dist', (distanceMeters / 1000).toStringAsFixed(1));
    await _speakWithCooldown('$distanceText $direction');
  }

  /// 曲がり角通知（多言語）
  Future<void> speakTurnAhead(
      String turnDirection, double distanceMeters) async {
    final distanceText = distanceMeters < 1000
        ? GapLessL10n.t('tts_distance_m')
            .replaceAll('@dist', distanceMeters.toInt().toString())
        : GapLessL10n.t('tts_distance_km')
            .replaceAll('@dist', (distanceMeters / 1000).toStringAsFixed(1));
    final message = GapLessL10n.t('tts_turn')
        .replaceAll('@dist', distanceText)
        .replaceAll('@direction', turnDirection);
    await _speakWithCooldown(message);
  }

  /// 方向指示（多言語）
  Future<void> speakDirection(String clockPosition) async {
    await _speakWithCooldown('$clockPosition');
  }

  /// 目的地設定時の音声（多言語）
  Future<void> speakDestinationSet(String destinationName) async {
    await _speak(
        GapLessL10n.t('bot_dest_set').replaceAll('@name', destinationName));
  }

  /// オフコース警告（多言語）
  Future<void> speakOffCourse() async {
    await _speakWithCooldown(_getLocalizedMessage('off_course'));
  }

  /// 多言語メッセージ取得（GapLessL10n経由で18言語対応）
  String _getLocalizedMessage(String key) {
    switch (key) {
      case 'monitoring_start':
        return GapLessL10n.t('tts_monitoring_start');
      case 'hazard_warning':
        return GapLessL10n.t('tts_hazard_warning');
      case 'safe_area':
        return GapLessL10n.t('tts_safe_area');
      case 'arrival':
        return GapLessL10n.t('tts_arrived');
      case 'deep_water':
        return GapLessL10n.t('tts_deep_water');
      case 'fast_current':
        return GapLessL10n.t('tts_fast_current');
      case 'off_course':
        return GapLessL10n.t('tts_off_course');
      default:
        return key;
    }
  }

  @override
  void dispose() {
    _stopFlashing();
    _tts.stop();
    super.dispose();
  }
}
