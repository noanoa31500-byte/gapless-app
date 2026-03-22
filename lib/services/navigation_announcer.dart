import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import '../utils/localization.dart';
import 'power_manager.dart';

// ============================================================================
// NavigationAnnouncer — TTS読み上げ & 触覚フィードバック（省電力対応）
// ============================================================================
//
// 【通常モード】
//   ・狭道進入（道幅 ≤ 2m）: TTS "この先の道幅は○メートルです。注意してください"
//   ・曲がり角            : HapticFeedback（中程度の振動）
//   ・ウェイポイント通過   : TTS "△メートル先、右/左に曲がります"
//
// 【省電力モード（バッテリー < 20%）】
//   ・狭道進入             : 省略（TTS なし）
//   ・曲がり角             : 重要な曲がり角（≤ 50m 手前）の直前のみ TTS + 振動
//   ・通過ウェイポイント   : 省略
//
// 【重要な曲がり角の定義】
//   距離が 50m 以内 かつ 進行方向変化 ≥ 30°
//
// ============================================================================

/// 曲がり角の重要度レベル
enum TurnImportance {
  /// 省電力モードでも読み上げる（≤ 50m かつ ≥ 30°の変化）
  critical,

  /// 通常モードのみ読み上げる
  normal,
}

class NavigationAnnouncer {
  final PowerManager _power;
  final FlutterTts _tts = FlutterTts();

  bool _initialized = false;
  String _lastSpokenText = '';
  DateTime? _lastSpeakTime;
  String _currentTtsLang = 'ja-JP';

  NavigationAnnouncer({PowerManager? powerManager})
      : _power = powerManager ?? PowerManager.instance;

  // ---------------------------------------------------------------------------
  // 初期化
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    if (_initialized) {
      // 再初期化時は言語だけ更新
      await _applyLanguage();
      return;
    }
    await _applyLanguage();
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    await _tts.setIosAudioCategory(
      IosTextToSpeechAudioCategory.ambient,
      [IosTextToSpeechAudioCategoryOptions.mixWithOthers],
    );
    _initialized = true;
    debugPrint('NavigationAnnouncer: 初期化完了 (言語: $_currentTtsLang)');
  }

  /// アプリ言語変更時に TTS 言語を更新する
  Future<void> updateLanguage() async {
    await _applyLanguage();
  }

  /// GapLessL10n.lang から TTS ロケールを解決して適用
  Future<void> _applyLanguage() async {
    final ttsLang = _ttsLocale(GapLessL10n.lang);
    if (ttsLang == _currentTtsLang && _initialized) return;
    _currentTtsLang = ttsLang;
    await _tts.setLanguage(ttsLang);
  }

  static String _ttsLocale(String lang) {
    switch (lang) {
      case 'en':
        return 'en-US';
      case 'th':
        return 'th-TH';
      default:
        return 'ja-JP';
    }
  }

  // ---------------------------------------------------------------------------
  // 狭道警告
  // ---------------------------------------------------------------------------

  /// 道幅 ≤ 2m の路地進入時に呼ぶ
  ///
  /// 通常モード : 読み上げ
  /// 省電力モード : 省略
  Future<void> announceNarrowRoad(double widthMeters) async {
    if (_power.isPowerSaving) return; // 省電力モード: スキップ

    final width = widthMeters.toStringAsFixed(1);
    await _speak(GapLessL10n.t('tts_narrow_road').replaceAll('@width', width));
  }

  // ---------------------------------------------------------------------------
  // 曲がり角案内
  // ---------------------------------------------------------------------------

  /// 曲がり角の事前案内
  ///
  /// [distanceM]    現在地から曲がり角までの距離（メートル）
  /// [directionJa]  "右" または "左"
  /// [turnAngleDeg] 進行方向変化角（絶対値、度）
  Future<void> announceTurn({
    required double distanceM,
    required bool isRight,
    required double turnAngleDeg,
  }) async {
    final importance = _getTurnImportance(distanceM, turnAngleDeg);

    // 省電力モードでは critical のみ
    if (_power.isPowerSaving && importance != TurnImportance.critical) return;

    final distStr = _formatDistance(distanceM);
    final dir = GapLessL10n.t(isRight ? 'tts_dir_right' : 'tts_dir_left');
    await _speak(
      GapLessL10n.t('tts_turn')
          .replaceAll('@dist', distStr)
          .replaceAll('@direction', dir),
    );
    await _hapticTurn(importance);
  }

  /// 曲がり角通過時の触覚フィードバック（省電力モードでは省略）
  Future<void> hapticOnTurn() async {
    if (_power.isPowerSaving) return;
    await HapticFeedback.mediumImpact();
  }

  // ---------------------------------------------------------------------------
  // ウェイポイント通過
  // ---------------------------------------------------------------------------

  /// ウェイポイント通過を音声案内する（省電力モード: 省略）
  Future<void> announceWaypointPassed(
      int index, int total, double remainingM) async {
    if (_power.isPowerSaving) return;
    if (index >= total - 1) {
      await _speak(GapLessL10n.t('tts_arrived'));
    } else {
      await _speak(
        GapLessL10n.t('tts_waypoint')
            .replaceAll('@dist', _formatDistance(remainingM)),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 帰還支援モード
  // ---------------------------------------------------------------------------

  /// 地図範囲外に出たことを通知する（省電力でも必ず読み上げ）
  Future<void> announceOutOfBounds() async {
    await _speakForced(GapLessL10n.t('tts_out_of_bounds'));
  }

  /// バックトラック開始通知
  Future<void> announceBacktrackStart() async {
    await _speakForced(GapLessL10n.t('tts_backtrack'));
  }

  // ---------------------------------------------------------------------------
  // 内部ヘルパー
  // ---------------------------------------------------------------------------

  TurnImportance _getTurnImportance(double distanceM, double turnAngleDeg) {
    if (distanceM <= 50 && turnAngleDeg >= 30) return TurnImportance.critical;
    return TurnImportance.normal;
  }

  Future<void> _hapticTurn(TurnImportance importance) async {
    if (_power.isPowerSaving && importance != TurnImportance.critical) return;
    try {
      if (await Vibration.hasVibrator() ?? false) {
        if (importance == TurnImportance.critical) {
          Vibration.vibrate(pattern: [0, 80, 60, 80]);
        } else {
          Vibration.vibrate(duration: 40);
        }
      }
    } catch (_) {}
  }

  /// 省電力モード時もスロットリングしつつ読み上げる
  Future<void> _speak(String text) async {
    if (!_initialized) await init();
    if (text == _lastSpokenText) return;

    final now = DateTime.now();
    // 2秒以内の連続読み上げを防ぐ
    if (_lastSpeakTime != null &&
        now.difference(_lastSpeakTime!) <
            const Duration(seconds: 2)) {
      return;
    }
    _lastSpokenText = text;
    _lastSpeakTime = now;
    await _tts.speak(text);
  }

  /// 重要度が高く必ず読み上げる（スロットリングなし）
  Future<void> _speakForced(String text) async {
    if (!_initialized) await init();
    _lastSpokenText = text;
    _lastSpeakTime = DateTime.now();
    await _tts.speak(text);
  }

  String _formatDistance(double m) {
    if (m >= 1000) {
      return GapLessL10n.t('tts_distance_km')
          .replaceAll('@dist', (m / 1000).toStringAsFixed(1));
    }
    return GapLessL10n.t('tts_distance_m')
        .replaceAll('@dist', '${m.round()}');
  }

  Future<void> dispose() async {
    await _tts.stop();
  }
}
