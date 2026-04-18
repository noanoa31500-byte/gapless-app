import 'dart:async';
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
import '../utils/localization.dart';

// ============================================================================
// EmergencySimpleScreen — 災害時緊急操作UI
// ============================================================================
//
// 【3ゾーン構成】
//   Zone 1 (赤): SOSビーコン送信ボタン（長押し3秒）
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
    with SingleTickerProviderStateMixin {
  final _announcer = NavigationAnnouncer();

  // SOS 長押しタイマー
  Timer? _sosPressTimer;
  double _sosHoldProgress = 0.0;
  Timer? _sosProgressTimer;
  bool _sosSent = false;

  // ボリュームキー用フォーカス
  final _focusNode = FocusNode();

  // 現在のTTS再読み上げテキスト
  String _currentTtsText = '';

  // アニメーション（SOSボタン脈動）
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _announcer.init();
      _focusNode.requestFocus();
      _speakCurrentGuide();
    });
  }

  @override
  void dispose() {
    _sosPressTimer?.cancel();
    _sosProgressTimer?.cancel();
    _pulseCtrl.dispose();
    _focusNode.dispose();
    _announcer.dispose();
    super.dispose();
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
  // SOS 長押し送信
  // ---------------------------------------------------------------------------

  void _onSosPressStart() {
    if (_sosSent) return;
    _sosProgressTimer?.cancel();
    setState(() => _sosHoldProgress = 0.0);
    _sosProgressTimer = Timer.periodic(const Duration(milliseconds: 30), (t) {
      if (!mounted) { t.cancel(); return; }
      setState(() {
        _sosHoldProgress = (t.tick * 30) / 3000.0;
        if (_sosHoldProgress >= 1.0) _sosHoldProgress = 1.0;
      });
    });
    _sosPressTimer = Timer(const Duration(seconds: 3), () {
      final loc = context.read<LocationProvider>().currentLocation;
      if (loc != null) {
        BleRoadReportService.instance
            .enqueueSos(lat: loc.latitude, lng: loc.longitude);
      }
      HapticFeedback.heavyImpact();
      _announcer.announceAlert(GapLessL10n.t('sos_sent'));
      if (mounted) setState(() => _sosSent = true);
      _sosProgressTimer?.cancel();
    });
  }

  void _onSosPressEnd() {
    _sosPressTimer?.cancel();
    _sosProgressTimer?.cancel();
    if (!_sosSent) setState(() => _sosHoldProgress = 0.0);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    context.watch<LocationProvider>();
    return KeyboardListener(
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
          backgroundColor: const Color(0xFF8B0000),
          foregroundColor: Colors.white,
          title: Text(
            GapLessL10n.t('emergency_screen_title'),
            style: GapLessL10n.safeStyle(const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 18)),
          ),
          actions: [
            // バッテリー残量
            ListenableBuilder(
              listenable: PowerManager.instance,
              builder: (_, __) => Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.battery_alert, size: 18),
                    const SizedBox(width: 4),
                    Text('${PowerManager.instance.batteryLevel}%',
                        style: const TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(flex: 3, child: _buildSosZone()),
            Expanded(flex: 3, child: _buildNavZone()),
            Expanded(flex: 4, child: _buildActionsZone()),
          ],
        ),
      ),
    );
  }

  // ── Zone 1: SOS ─────────────────────────────────────────────────────────

  Widget _buildSosZone() {
    return Container(
      width: double.infinity,
      color: _sosSent ? const Color(0xFF4A0000) : const Color(0xFFB71C1C),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _sosSent
                ? GapLessL10n.t('sos_sent')
                : GapLessL10n.t('sos_hold_hint'),
            style: GapLessL10n.safeStyle(const TextStyle(
                color: Colors.white70, fontSize: 13)),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            onTapDown: (_) => _onSosPressStart(),
            onTapUp: (_) => _onSosPressEnd(),
            onTapCancel: _onSosPressEnd,
            child: ScaleTransition(
              scale: _sosSent ? const AlwaysStoppedAnimation(1.0) : _pulseAnim,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 100,
                    height: 100,
                    child: CircularProgressIndicator(
                      value: _sosHoldProgress > 0 ? _sosHoldProgress : null,
                      valueColor: const AlwaysStoppedAnimation(Colors.white),
                      strokeWidth: 5,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _sosSent
                          ? const Color(0xFF8B0000)
                          : const Color(0xFFD32F2F),
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: Icon(
                      _sosSent ? Icons.check : Icons.sos,
                      color: Colors.white,
                      size: 44,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_sosSent) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() {
                _sosSent = false;
                _sosHoldProgress = 0.0;
              }),
              child: Text(GapLessL10n.t('emergency_sos_resend'),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
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
          360) % 360;
    }

    final distText = distM != null
        ? (distM >= 1000
            ? '${(distM / 1000).toStringAsFixed(1)} km'
            : '${distM.round()} m')
        : '---';

    return Container(
      color: const Color(0xFF1A1A2E),
      width: double.infinity,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (bearingDeg != null)
            Transform.rotate(
              angle: bearingDeg * math.pi / 180,
              child: const Icon(Icons.navigation,
                  size: 72, color: Color(0xFF4CAF50)),
            )
          else
            const Icon(Icons.explore, size: 72, color: Colors.white38),
          const SizedBox(height: 8),
          Text(
            distText,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.bold),
          ),
          if (nearest != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                nearest.name,
                style: GapLessL10n.safeStyle(const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500)),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  // ── Zone 3: アクションボタン群 ───────────────────────────────────────────

  Widget _buildActionsZone() {
    return Container(
      color: const Color(0xFF212121),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Row(
            children: [
              Expanded(
                child: _actionButton(
                  icon: Icons.phone,
                  label: GapLessL10n.t('emergency_call'),
                  color: const Color(0xFF1565C0),
                  onTap: () => _callEmergency(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  icon: Icons.water_drop,
                  label: GapLessL10n.t('emergency_water'),
                  color: const Color(0xFF00838F),
                  onTap: () =>
                      _announcer.announceAlert(GapLessL10n.t('emergency_water_tip')),
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
                  color: const Color(0xFF558B2F),
                  onTap: () => _announcer
                      .announceAlert(GapLessL10n.t('emergency_first_aid_tip')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  icon: Icons.record_voice_over,
                  label: GapLessL10n.t('emergency_repeat'),
                  color: const Color(0xFF6A1B9A),
                  onTap: () => _speakCurrentGuide(),
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
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: GapLessL10n.safeStyle(const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold)),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _callEmergency() {
    _announcer.announceAlert(GapLessL10n.t('emergency_call_instruction'));
  }
}
