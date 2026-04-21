import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../providers/location_provider.dart';
import '../providers/shelter_provider.dart';
import '../services/ble_road_report_service.dart';
import '../services/navigation_announcer.dart';
import '../services/power_manager.dart';
import '../theme/app_colors.dart';
import '../utils/accessibility.dart';
import '../utils/localization.dart';
import 'risk_radar_compass_screen.dart';

// ============================================================================
// EmergencySimpleScreen — 災害時緊急操作UI
// ============================================================================
//
// 【3ゾーン構成】
//   Zone 1 (赤): SOSビーコン送信ボタン（ダブルタップ→3秒長押し）
//   Zone 2 (暗): 最寄り避難所への方位矢印 + 距離
//   Zone 3 (灰): 緊急アクションボタン群
//
// 【ボリュームキーTTS】
//   音量アップキー → 現在の案内テキストを再読み上げ
//
// ============================================================================

class EmergencySimpleScreen extends StatefulWidget {
  const EmergencySimpleScreen({super.key});

  @override
  State<EmergencySimpleScreen> createState() => _EmergencySimpleScreenState();
}

class _EmergencySimpleScreenState extends State<EmergencySimpleScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  static const MethodChannel _brightnessCh = MethodChannel('gapless/brightness');
  final _announcer = NavigationAnnouncer();

  // SOS 長押し進捗 (RestorationMixinの代替: KeepAlive + フィールド保持)
  Timer? _sosProgressTimer;
  double _sosHoldProgress = 0.0;
  DateTime? _sosHoldStartedAt;
  int _sosHapticStage = 0;
  bool _sosArmed = false; // ダブルタップ後にtrue
  DateTime? _firstTapAt;
  bool _sosSent = false;

  // 自動再送
  Timer? _resendTimer;
  int _resendCount = 0;
  static const int _maxResend = 5;

  // ボリュームキー用フォーカス
  final _focusNode = FocusNode();

  // 現在のTTS再読み上げテキスト
  String _currentTtsText = '';

  // 輝度復元用
  double? _savedBrightness;

  // アニメーション（SOSボタン脈動 — ホールド中は停止）
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _pulseAnim = Tween(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );

    _maximizeBrightness();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _announcer.init();
      _focusNode.requestFocus();
      _speakCurrentGuide();
    });
  }

  @override
  void dispose() {
    _sosProgressTimer?.cancel();
    _resendTimer?.cancel();
    _pulseCtrl.dispose();
    _focusNode.dispose();
    _announcer.dispose();
    _restoreBrightness();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 輝度制御 (gapless/brightness MethodChannel)
  // ---------------------------------------------------------------------------

  Future<void> _maximizeBrightness() async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    try {
      final cur = await _brightnessCh.invokeMethod<double>('getBrightness');
      _savedBrightness = cur ?? 0.5;
      await _brightnessCh.invokeMethod('setBrightness', {'value': 1.0});
    } catch (_) {
      // silent fallback (未実装プラットフォーム等)
    }
  }

  Future<void> _restoreBrightness() async {
    if (_savedBrightness == null) return;
    try {
      await _brightnessCh
          .invokeMethod('setBrightness', {'value': _savedBrightness});
    } catch (_) {}
    _savedBrightness = null;
  }

  // ---------------------------------------------------------------------------
  // TTS
  // ---------------------------------------------------------------------------

  void _speakCurrentGuide() {
    final loc = context.read<LocationProvider>().currentLocation;
    final shelterProv = context.read<ShelterProvider>();
    final nearest = loc != null ? shelterProv.getAbsoluteNearest(loc) : null;
    if (nearest != null) {
      final distM = loc != null
          ? Geolocator.distanceBetween(
              loc.latitude, loc.longitude, nearest.lat, nearest.lng)
          : null;
      final distText = distM != null
          ? (distM >= 1000
              ? '${(distM / 1000).toStringAsFixed(1)} km'
              : '${distM.round()} m')
          : '';
      _currentTtsText =
          '${GapLessL10n.t('emergency_nearest')} ${nearest.name} $distText';
    } else {
      _currentTtsText = GapLessL10n.t('nav_no_shelter');
    }
    _announcer.announceAlert(_currentTtsText);
  }

  // ---------------------------------------------------------------------------
  // SOS ガード付き長押し (ダブルタップ→armed→3秒ホールド)
  // ---------------------------------------------------------------------------

  void _onSosTap() {
    if (_sosSent) return;
    final now = DateTime.now();
    if (_firstTapAt != null &&
        now.difference(_firstTapAt!) < const Duration(milliseconds: 600)) {
      // 2回目のタップ
      setState(() => _sosArmed = true);
      HapticFeedback.selectionClick();
      _announcer.announceAlert(GapLessL10n.t('sos_armed'));
    } else {
      _announcer.announceAlert(GapLessL10n.t('sos_hold_3s_hint'));
    }
    _firstTapAt = now;
  }

  void _onSosLongPressStart() {
    if (_sosSent || !_sosArmed) return;
    // 脈動停止 (進捗リングと干渉しない)
    _pulseCtrl.stop();
    _sosHoldStartedAt = DateTime.now();
    _sosHapticStage = 0;
    _sosProgressTimer?.cancel();
    _sosProgressTimer =
        Timer.periodic(const Duration(milliseconds: 30), (t) {
      if (!mounted || _sosHoldStartedAt == null) {
        t.cancel();
        return;
      }
      final ms =
          DateTime.now().difference(_sosHoldStartedAt!).inMilliseconds;
      final p = (ms / 3000.0).clamp(0.0, 1.0);
      // 段階的ハプティック
      if (_sosHapticStage < 1 && ms >= 1000) {
        _sosHapticStage = 1;
        HapticFeedback.lightImpact();
      } else if (_sosHapticStage < 2 && ms >= 2000) {
        _sosHapticStage = 2;
        HapticFeedback.mediumImpact();
      }
      setState(() => _sosHoldProgress = p);
      if (p >= 1.0) {
        t.cancel();
        _fireSos();
      }
    });
  }

  void _onSosLongPressEnd() {
    _sosProgressTimer?.cancel();
    _sosHoldStartedAt = null;
    if (!_sosSent) {
      setState(() {
        _sosHoldProgress = 0.0;
      });
      try {
        _pulseCtrl.repeat(reverse: true);
      } catch (_) {}
    }
  }

  void _fireSos() {
    final loc = context.read<LocationProvider>().currentLocation;
    if (loc != null) {
      BleRoadReportService.instance
          .enqueueSos(lat: loc.latitude, lng: loc.longitude);
    }
    HapticFeedback.heavyImpact();
    _announcer.announceAlert(GapLessL10n.t('sos_sent'));
    if (mounted) {
      setState(() {
        _sosSent = true;
        _sosArmed = false;
        _sosHoldProgress = 1.0;
      });
    }
    _startAutoResend();
  }

  void _startAutoResend() {
    _resendTimer?.cancel();
    _resendCount = 0;
    _resendTimer = Timer.periodic(const Duration(seconds: 30), (t) {
      if (!mounted || _resendCount >= _maxResend) {
        t.cancel();
        return;
      }
      _resendCount++;
      final loc = context.read<LocationProvider>().currentLocation;
      if (loc != null) {
        BleRoadReportService.instance
            .enqueueSos(lat: loc.latitude, lng: loc.longitude);
      }
      HapticFeedback.lightImpact();
      _announcer.announceAlert(
          '${GapLessL10n.t('sos_auto_resend')} ($_resendCount/$_maxResend)');
      if (mounted) setState(() {});
    });
  }

  void _stopAutoResend() {
    _resendTimer?.cancel();
    _resendTimer = null;
    if (mounted) setState(() {});
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    super.build(context); // KeepAlive
    context.watch<LocationProvider>();
    final reduce = AppleAccessibility.reduceMotion(context);
    if (reduce && _pulseCtrl.isAnimating) {
      _pulseCtrl.stop();
    } else if (!reduce && !_pulseCtrl.isAnimating) {
      _pulseCtrl.repeat(reverse: true);
    }
    return PopScope(
      // 緊急画面からハードウェア戻る/スワイプで離脱しない。
      // 災害コア画面なので誤操作脱出を防ぐ (DisasterCompassScreen と同設計)。
      canPop: false,
      child: KeyboardListener(
      focusNode: _focusNode,
      onKeyEvent: (event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.audioVolumeUp) {
          _announcer.announceAlert(_currentTtsText);
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A2E),
          foregroundColor: Colors.white,
          automaticallyImplyLeading: false,
          elevation: 0,
          title: Text(
            GapLessL10n.t('emergency_screen_title'),
            style: GapLessL10n.safeStyle(const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 19,
                letterSpacing: 0.3)),
          ),
          actions: [
            // RiskRadar 360° (深水・激流方位) への導線。
            // README 機能 6「RiskRadar」の唯一のエントリ。
            Semantics(
              button: true,
              label: GapLessL10n.t('risk_radar_title'),
              child: IconButton(
                icon: const Icon(Icons.radar, size: 22),
                tooltip: GapLessL10n.t('risk_radar_title'),
                onPressed: () =>
                    Navigator.of(context).pushNamed('/risk_radar'),
              ),
            ),
            // バッテリー残量 (18pt以上 / コントラスト強化)
            ListenableBuilder(
              listenable: PowerManager.instance,
              builder: (_, __) => Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Semantics(
                  label:
                      'Battery ${PowerManager.instance.batteryLevel} percent',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.battery_alert, size: 22),
                      const SizedBox(width: 4),
                      Text('${PowerManager.instance.batteryLevel}%',
                          style: GapLessL10n.safeStyle(const TextStyle(
                              fontSize: 18,
                              color: Colors.white,
                              fontWeight: FontWeight.bold))),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            // SOS を画面の 40% 確保 (README「上半分=SOS」要件準拠)。
            Expanded(flex: 4, child: _buildSosZone()),
            Expanded(flex: 3, child: _buildNavZone()),
            Expanded(flex: 3, child: _buildActionsZone()),
          ],
        ),
      ),
      ),
    );
  }

  // ── Zone 1: SOS ─────────────────────────────────────────────────────────

  Widget _buildSosZone() {
    final hint = _sosSent
        ? GapLessL10n.t('sos_sent')
        : (_sosArmed
            ? GapLessL10n.t('sos_armed')
            : GapLessL10n.t('sos_hold_3s_hint'));
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _sosSent
              ? [AppColors.emergencyRedSurface, const Color(0xFF3A0000)]
              : [AppColors.emergencyRedDark, const Color(0xFF8B0000)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                hint,
                textAlign: TextAlign.center,
                style: GapLessL10n.safeStyle(const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3)),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Semantics(
            button: true,
            label: GapLessL10n.t('sos_button_a11y'),
            hint: GapLessL10n.t('sos_hold_3s_hint'),
            child: GestureDetector(
              onTap: _onSosTap,
              onLongPressStart: (_) => _onSosLongPressStart(),
              onLongPressEnd: (_) => _onSosLongPressEnd(),
              onLongPressCancel: _onSosLongPressEnd,
              child: ScaleTransition(
                scale: (_sosSent || _sosHoldStartedAt != null)
                    ? const AlwaysStoppedAnimation(1.0)
                    : _pulseAnim,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 208,
                      height: 208,
                      child: CircularProgressIndicator(
                        value: _sosHoldProgress > 0 ? _sosHoldProgress : null,
                        valueColor:
                            const AlwaysStoppedAnimation(Colors.white),
                        strokeWidth: 9,
                        backgroundColor: Colors.white24,
                      ),
                    ),
                    Container(
                      width: 184,
                      height: 184,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: _sosSent
                              ? [AppColors.emergencyRedMuted, const Color(0xFF3A0000)]
                              : (_sosArmed
                                  ? [AppColors.emergencyRed, const Color(0xFFB00020)]
                                  : [AppColors.emergencyRedDark, const Color(0xFF6B0000)]),
                          center: const Alignment(-0.3, -0.3),
                          radius: 1.0,
                        ),
                        border: Border.all(
                          color: Colors.white,
                          width: _sosArmed ? 4.5 : 3.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.emergencyRed.withValues(alpha: 0.5),
                            blurRadius: 32,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: Icon(
                        _sosSent ? Icons.check_circle : Icons.sos,
                        color: Colors.white,
                        size: 92,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_sosSent) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              alignment: WrapAlignment.center,
              children: [
                Semantics(
                  button: true,
                  label: GapLessL10n.t('emergency_sos_resend'),
                  child: TextButton.icon(
                    onPressed: () {
                      setState(() {
                        _sosSent = false;
                        _sosHoldProgress = 0.0;
                        _sosArmed = false;
                      });
                      _stopAutoResend();
                    },
                    icon: const Icon(Icons.refresh,
                        color: Colors.white, size: 20),
                    label: Text(GapLessL10n.t('emergency_sos_resend'),
                        style: GapLessL10n.safeStyle(const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600))),
                  ),
                ),
                if (_resendTimer != null)
                  Semantics(
                    button: true,
                    label: GapLessL10n.t('sos_stop_resend'),
                    child: TextButton.icon(
                      onPressed: _stopAutoResend,
                      icon: const Icon(Icons.stop_circle,
                          color: Colors.white, size: 20),
                      label: Text(
                          '${GapLessL10n.t('sos_stop_resend')} ($_resendCount/$_maxResend)',
                          style: GapLessL10n.safeStyle(const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w600))),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Zone 2: 方位矢印 ──────────────────────────────────────────────────────

  Widget _buildNavZone() {
    final loc = context.read<LocationProvider>().currentLocation;
    final shelterProv = context.read<ShelterProvider>();
    final nearest = loc != null ? shelterProv.getAbsoluteNearest(loc) : null;

    double? bearingDeg;
    double? distM;
    if (loc != null && nearest != null) {
      distM = Geolocator.distanceBetween(
          loc.latitude, loc.longitude, nearest.lat, nearest.lng);
      bearingDeg = (Geolocator.bearingBetween(
                  loc.latitude, loc.longitude, nearest.lat, nearest.lng) +
              360) %
          360;
    }

    final distText = distM != null
        ? (distM >= 1000
            ? '${(distM / 1000).toStringAsFixed(1)} km'
            : '${distM.round()} m')
        : '---';

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1A1A2E), Color(0xFF16213E)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Arrow with soft glow
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF00C896).withValues(alpha: 0.12),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00C896).withValues(alpha: 0.25),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Semantics(
              label: bearingDeg != null
                  ? 'Direction ${bearingDeg.round()} degrees'
                  : 'No direction',
              child: bearingDeg != null
                  ? Transform.rotate(
                      angle: bearingDeg * math.pi / 180,
                      child: const Icon(Icons.navigation_rounded,
                          size: 56, color: Color(0xFF00C896)),
                    )
                  : const Icon(Icons.explore_rounded,
                      size: 56, color: Colors.white54),
            ),
          ),
          const SizedBox(height: 10),
          Semantics(
            label: 'Distance $distText',
            child: Text(
              distText,
              style: GapLessL10n.safeStyle(const TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5)),
            ),
          ),
          if (nearest != null) ...[
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Semantics(
                label: 'Nearest shelter ${nearest.name}',
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    nearest.name,
                    style: GapLessL10n.safeStyle(const TextStyle(
                        color: Colors.white70,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3)),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Zone 3: アクションボタン群 ───────────────────────────────────────────

  Widget _buildActionsZone() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF1E1E2E), Color(0xFF12121A)],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  icon: Icons.explore_rounded,
                  label: GapLessL10n.t('nav_compass'),
                  semanticLabel: GapLessL10n.t('nav_compass'),
                  color: const Color(0xFF1565C0),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RiskRadarCompassScreen(),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  icon: Icons.water_drop,
                  label: GapLessL10n.t('emergency_water'),
                  semanticLabel: GapLessL10n.t('water_a11y'),
                  color: AppColors.darkSurface3,
                  onTap: () => _announcer
                      .announceAlert(GapLessL10n.t('emergency_water_tip')),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  icon: Icons.medical_services,
                  label: GapLessL10n.t('emergency_first_aid'),
                  semanticLabel: GapLessL10n.t('first_aid_a11y'),
                  color: AppColors.primaryGreenMuted,
                  onTap: () => _announcer.announceAlert(
                      GapLessL10n.t('emergency_first_aid_tip')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  icon: Icons.record_voice_over,
                  label: GapLessL10n.t('emergency_repeat'),
                  semanticLabel: GapLessL10n.t('tts_replay_a11y'),
                  color: AppColors.darkSurface2,
                  onTap: _speakCurrentGuide,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required String semanticLabel,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 96,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.40),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.10),
              width: 1.0,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 34),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: GapLessL10n.safeStyle(const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2)),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
