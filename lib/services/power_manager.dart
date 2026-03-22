import 'dart:async';
import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// ============================================================================
// PowerManager — バッテリー監視 & 超省電力モード管理
// ============================================================================
//
// 【省電力モード移行条件】
//   バッテリー残量 < 20%  →  PowerMode.saving
//   バッテリー残量 ≥ 20%  →  PowerMode.normal
//
// 【省電力モード時の変更内容】
//   ① GPS取得間隔  : 1 秒 → 10 秒
//   ② 画面輝度     : SystemChrome で最小値 (iOS: UIScreen.brightness)
//   ③ BLEスキャン  : BleRoadReportService.setSavingMode(true) で頻度最小化
//   ④ 画面背景色    : PowerManager.backgroundColor で完全な黒 (Colors.black) を提供
//   ⑤ TTS読み上げ  : 重要な曲がり角の直前のみに制限
//      → NavigationAnnouncer が isPowerSaving を参照して制御
//
// ============================================================================

enum PowerMode { normal, saving }

class PowerManager extends ChangeNotifier {
  static final PowerManager instance = PowerManager._();
  PowerManager._();

  // ── 閾値 ────────────────────────────────────────────────────
  static const int _savingThresholdPercent = 20;

  // GPS 間隔（秒）
  static const int gpsIntervalNormalSec = 1;
  static const int gpsIntervalSavingSec = 10;

  // ── 状態 ──────────────────────────────────────────────────
  PowerMode _mode = PowerMode.normal;
  int _batteryLevel = 100;
  BatteryState _batteryState = BatteryState.unknown;

  PowerMode get mode => _mode;
  int get batteryLevel => _batteryLevel;
  BatteryState get batteryState => _batteryState;
  bool get isPowerSaving => _mode == PowerMode.saving;

  /// 省電力モード時に UI 側へ通知する背景色
  /// 通常: null（既存テーマに委ねる）、省電力: 完全な黒
  int? get backgroundColorValue =>
      isPowerSaving ? 0xFF000000 : null;

  /// GPS 取得間隔（秒）
  int get gpsIntervalSec =>
      isPowerSaving ? gpsIntervalSavingSec : gpsIntervalNormalSec;

  // ── 内部 ──────────────────────────────────────────────────
  final Battery _battery = Battery();
  StreamSubscription<BatteryState>? _stateSub;
  Timer? _levelTimer;
  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // ライフサイクル
  // ---------------------------------------------------------------------------

  /// 監視を開始する（アプリ起動時に呼ぶ）
  Future<void> start() async {
    // 初回読み取り
    await _fetchLevel();

    // バッテリー状態変化（充電開始/終了等）を購読
    _stateSub = _battery.onBatteryStateChanged.listen((state) {
      _batteryState = state;
      _fetchLevel();
    });

    // 1分ごとに残量をポーリング
    _levelTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _fetchLevel();
    });
  }

  /// 監視を停止する
  void dispose() {
    _disposed = true;
    _stateSub?.cancel();
    _levelTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // バッテリー残量取得 & モード切替
  // ---------------------------------------------------------------------------

  Future<void> _fetchLevel() async {
    try {
      _batteryLevel = await _battery.batteryLevel;
      _updateMode();
    } catch (e) {
      debugPrint('PowerManager: バッテリー取得失敗 $e');
    }
  }

  void _updateMode() {
    if (_disposed) return;
    final shouldSave = _batteryLevel < _savingThresholdPercent;
    final newMode = shouldSave ? PowerMode.saving : PowerMode.normal;

    if (newMode == _mode) return;
    _mode = newMode;

    if (_mode == PowerMode.saving) {
      _applySavingSettings();
    } else {
      _restoreNormalSettings();
    }

    notifyListeners();
    debugPrint(
        'PowerManager: モード変更 → $_mode (battery: $_batteryLevel%)');
  }

  // ---------------------------------------------------------------------------
  // iOS 画面輝度制御
  // ---------------------------------------------------------------------------

  double? _savedBrightness;

  void _applySavingSettings() {
    if (Platform.isIOS) {
      _saveBrightnessAndSetMinimum();
    }
  }

  void _restoreNormalSettings() {
    if (Platform.isIOS) {
      _restoreBrightness();
    }
  }

  Future<void> _saveBrightnessAndSetMinimum() async {
    try {
      // flutter/services の SystemChrome では輝度制御が限定的なため
      // iOS では MethodChannel 経由で UIScreen.main.brightness を制御する
      // （Info.plist の NSBrightnessUsageDescription が不要な範囲内）
      const channel = MethodChannel('gapless/brightness');
      final current =
          await channel.invokeMethod<double>('getBrightness') ?? 0.5;
      _savedBrightness = current;
      await channel.invokeMethod('setBrightness', {'value': 0.05});
    } catch (_) {
      // MethodChannelが未実装の場合は無視（デグレードなし）
    }
  }

  Future<void> _restoreBrightness() async {
    if (_savedBrightness == null) return;
    try {
      const channel = MethodChannel('gapless/brightness');
      await channel.invokeMethod(
          'setBrightness', {'value': _savedBrightness});
      _savedBrightness = null;
    } catch (_) {}
  }
}
