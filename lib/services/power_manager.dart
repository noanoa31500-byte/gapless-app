import 'dart:async';
import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// ============================================================================
// PowerManager — バッテリー監視 & 多段階省電力モード管理
// ============================================================================
//
// 【モード移行条件】
//   残量 > 30%  : PowerMode.normal    — 通常動作
//   残量 21-30% : PowerMode.reduced   — 抑制（タイル取得停止・BLE 60s）
//   残量 11-20% : PowerMode.saving    — 省電力（GPS 5s・輝度最小・BLE 3分）
//   残量  6-10% : PowerMode.ultra     — 超省電力（GPS 30s・地図非表示・BLE 5分）
//   残量  ≤5%  : PowerMode.emergency  — 救命（GPS 60s・最小UI・BLE 10分）
//
// 【各モードでの変更内容】
//   GPS間隔  : 1s → 3s → 5s → 30s → 60s
//   BLEスキャン: 30s → 60s → 3min → 5min → 10min
//   画面背景色 : null → null → 黒 → 黒 → 黒
//   地図表示   : true → true → true → false → false
//   TTS      : フル → フル → 重要のみ → 重要のみ → 無効
//
// ============================================================================

enum PowerMode { normal, reduced, saving, ultra, emergency }

class PowerManager extends ChangeNotifier {
  static final PowerManager instance = PowerManager._();
  PowerManager._();

  // ── 閾値 ────────────────────────────────────────────────────
  static const int _reducedThreshold  = 30;
  static const int _savingThreshold   = 20;
  static const int _ultraThreshold    = 10;
  static const int _emergencyThreshold = 5;

  // GPS 間隔（秒）
  static const int gpsIntervalNormalSec    = 1;
  static const int gpsIntervalReducedSec   = 3;
  static const int gpsIntervalSavingSec    = 5;
  static const int gpsIntervalUltraSec     = 30;
  static const int gpsIntervalEmergencySec = 60;

  // BLE スキャン間隔
  static const Duration bleScanNormal    = Duration(seconds: 30);
  static const Duration bleScanReduced   = Duration(seconds: 60);
  static const Duration bleScanSaving    = Duration(minutes: 3);
  static const Duration bleScanUltra     = Duration(minutes: 5);
  static const Duration bleScanEmergency = Duration(minutes: 10);

  // ── 状態 ──────────────────────────────────────────────────
  PowerMode _mode = PowerMode.normal;
  int _batteryLevel = 100;
  BatteryState _batteryState = BatteryState.unknown;

  PowerMode get mode => _mode;
  int get batteryLevel => _batteryLevel;
  BatteryState get batteryState => _batteryState;

  /// 後方互換: saving 以上なら true
  bool get isPowerSaving => _mode.index >= PowerMode.saving.index;

  /// 地図レイヤーを表示すべきか（ultra/emergency では非表示でバッテリー節約）
  bool get showMap => _mode.index < PowerMode.ultra.index;

  // ナビゲーション中はGPS間隔を省電力でも維持する
  bool _navigationActive = false;

  void setNavigationActive(bool active) {
    if (_navigationActive == active) return;
    _navigationActive = active;
    notifyListeners();
  }

  /// 省電力モード時に UI 側へ通知する背景色
  int? get backgroundColorValue =>
      isPowerSaving ? 0xFF000000 : null;

  /// GPS 取得間隔（秒）— ナビ中は常に通常間隔を維持
  int get gpsIntervalSec {
    if (_navigationActive) return gpsIntervalNormalSec;
    return switch (_mode) {
      PowerMode.normal    => gpsIntervalNormalSec,
      PowerMode.reduced   => gpsIntervalReducedSec,
      PowerMode.saving    => gpsIntervalSavingSec,
      PowerMode.ultra     => gpsIntervalUltraSec,
      PowerMode.emergency => gpsIntervalEmergencySec,
    };
  }

  /// BLE スキャン間隔
  Duration get bleScanInterval => switch (_mode) {
    PowerMode.normal    => bleScanNormal,
    PowerMode.reduced   => bleScanReduced,
    PowerMode.saving    => bleScanSaving,
    PowerMode.ultra     => bleScanUltra,
    PowerMode.emergency => bleScanEmergency,
  };

  // ── 内部 ──────────────────────────────────────────────────
  final Battery _battery = Battery();
  StreamSubscription<BatteryState>? _stateSub;
  Timer? _levelTimer;
  bool _disposed = false;

  // ---------------------------------------------------------------------------
  // ライフサイクル
  // ---------------------------------------------------------------------------

  Future<void> start() async {
    await _fetchLevel();
    _stateSub = _battery.onBatteryStateChanged.listen((state) {
      _batteryState = state;
      _fetchLevel();
    });
    _levelTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _fetchLevel();
    });
  }

  @override
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
    final newMode = _classifyMode(_batteryLevel);
    if (newMode == _mode) return;

    final prev = _mode;
    _mode = newMode;

    // 輝度制御: saving以上に入る/抜けるタイミングで操作
    if (isPowerSaving && prev.index < PowerMode.saving.index) {
      _applyBrightness(min: true);
    } else if (!isPowerSaving) {
      _applyBrightness(min: false);
    }

    notifyListeners();
    debugPrint('PowerManager: モード変更 $prev → $_mode (battery: $_batteryLevel%)');
  }

  static PowerMode _classifyMode(int level) {
    if (level <= _emergencyThreshold) return PowerMode.emergency;
    if (level <= _ultraThreshold)     return PowerMode.ultra;
    if (level <= _savingThreshold)    return PowerMode.saving;
    if (level <= _reducedThreshold)   return PowerMode.reduced;
    return PowerMode.normal;
  }

  // ---------------------------------------------------------------------------
  // iOS 画面輝度制御
  // ---------------------------------------------------------------------------

  double? _savedBrightness;

  Future<void> _applyBrightness({required bool min}) async {
    if (!Platform.isIOS) return;
    const channel = MethodChannel('gapless/brightness');
    try {
      if (min) {
        final current =
            await channel.invokeMethod<double>('getBrightness') ?? 0.5;
        _savedBrightness = current;
        await channel.invokeMethod('setBrightness', {'value': 0.05});
      } else {
        if (_savedBrightness == null) return;
        await channel.invokeMethod('setBrightness', {'value': _savedBrightness});
        _savedBrightness = null;
      }
    } catch (_) {}
  }
}
