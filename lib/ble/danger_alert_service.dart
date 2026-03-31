import 'dart:async';
import 'dart:math' as math;
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:latlong2/latlong.dart';
import 'ble_repository.dart';
import 'road_score.dart';
import '../utils/localization.dart';

// ============================================================================
// DangerAlertService — 危険接近の音声・振動警告
// ============================================================================
//
// 現在地から半径100m以内に score=0.0 または score=0.3 の報告がある場合:
//
//   通常モード:
//     TTS「この先に危険な場所があります。注意してください」
//     HapticFeedback.heavyImpact() × 2
//
//   省電力モード（バッテリー20%以下）:
//     HapticFeedback.heavyImpact() × 2 のみ（TTS省略）
//
//   同一地点への警告は10分間に1回のみ発動する。
//
// ============================================================================

class DangerAlertService {
  static final DangerAlertService instance = DangerAlertService._();
  DangerAlertService._();

  static const double _alertRadiusM     = 100.0;
  static const double _dedupeRadiusM    = 80.0;  // 同一地点とみなす半径
  static const Duration _cooldown       = Duration(minutes: 10);
  static const int _batteryThreshold    = 20;

  final FlutterTts _tts = FlutterTts();
  bool _isSavingMode = false;
  bool _initialized  = false;

  // 最後に警告した地点・時刻（重複抑制）
  final List<_AlertRecord> _history = [];

  // ---------------------------------------------------------------------------
  // 初期化
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    if (_initialized) return;
    await _tts.setLanguage(_ttsLocale(GapLessL10n.lang));
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    _initialized = true;

    // バッテリー確認
    _checkBattery();
  }

  Future<void> _checkBattery() async {
    try {
      final level = await Battery().batteryLevel;
      _isSavingMode = level <= _batteryThreshold;
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // 現在地をもとに危険チェック・警告発動
  // ---------------------------------------------------------------------------

  Future<void> checkNearby(LatLng currentPos) async {
    if (!_initialized) await init();

    final allReports = await BleRepository.instance.queryNearby(
      lat:          currentPos.latitude,
      lng:          currentPos.longitude,
      radiusMeters: _alertRadiusM,
    );
    if (allReports.isEmpty) return;

    // スコアが危険圏のものが存在するか
    final hasDanger = allReports.any((r) {
      final score = RoadScoreCalculator.calculate(
        [r],
        LatLng(r.packet.lat, r.packet.lng),
      );
      return score.isImpassable || score.isCaution;
    });
    if (!hasDanger) return;

    // クールダウン・重複チェック
    final now = DateTime.now();
    _history.removeWhere((h) => now.difference(h.time) > _cooldown);

    for (final h in _history) {
      if (_distM(h.lat, h.lng, currentPos.latitude, currentPos.longitude) < _dedupeRadiusM) {
        return; // 同一地点での警告は10分以内なら発動しない
      }
    }

    // 警告を記録してから発動
    _history.add(_AlertRecord(
      lat:  currentPos.latitude,
      lng:  currentPos.longitude,
      time: now,
    ));

    await _triggerAlert();
  }

  // ---------------------------------------------------------------------------
  // 警告発動
  // ---------------------------------------------------------------------------

  static String _ttsLocale(String lang) {
    switch (lang) {
      case 'ja':   return 'ja-JP';
      case 'en':   return 'en-US';
      case 'th':   return 'th-TH';
      case 'zh':   return 'zh-CN';
      case 'zh_TW': return 'zh-TW';
      case 'ko':   return 'ko-KR';
      case 'hi':   return 'hi-IN';
      case 'bn':   return 'bn-BD';
      case 'id':   return 'id-ID';
      case 'vi':   return 'vi-VN';
      case 'es':   return 'es-ES';
      case 'pt':   return 'pt-BR';
      case 'fil':
      case 'my':
      case 'si':
      case 'ne':
      case 'mn':
      case 'uz':
      default:     return 'en-US';
    }
  }

  Future<void> _triggerAlert() async {
    debugPrint('DangerAlertService: 危険警告発動 (省電力=$_isSavingMode)');

    if (!_isSavingMode) {
      await _tts.setLanguage(_ttsLocale(GapLessL10n.lang));
      await _tts.speak(GapLessL10n.t('tts_danger_ahead'));
    }

    // HapticFeedback × 2
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 400));
    await HapticFeedback.heavyImpact();
  }

  // ---------------------------------------------------------------------------
  // ユーティリティ
  // ---------------------------------------------------------------------------

  static double _distM(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLng = (lng2 - lng1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}

class _AlertRecord {
  final double lat;
  final double lng;
  final DateTime time;
  const _AlertRecord({required this.lat, required this.lng, required this.time});
}
