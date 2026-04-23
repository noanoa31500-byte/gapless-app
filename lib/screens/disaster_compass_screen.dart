import 'dart:async';
import 'dart:ui';
import 'dart:io' show Platform;
import '../services/connectivity_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../providers/compass_provider.dart';
import '../providers/shelter_provider.dart';
import '../providers/location_provider.dart';
import '../providers/alert_provider.dart';
import '../providers/region_mode_provider.dart';
import '../providers/language_provider.dart';
import '../utils/localization.dart';
import '../services/haptic_service.dart';
import '../widgets/smart_compass.dart';
import '../services/magnetic_declination_config.dart';
import 'shelter_dashboard_screen.dart';

/// ============================================================================
/// DisasterCompassScreen - 防災コンパス画面 (iOSネイティブ専用)
/// ============================================================================
///
/// ABSOLUTE DIRECTIVES IMPLEMENTATION:
/// 1. UI: Navy (#C62828) / Orange (#FF6F00) Palette.
///        BorderRadius 30.0 for buttons/cards.
///        Height 56.0 for primary actions.
///        Padding 24.0+ for layout breathing room.
///
/// 2. NAV: Visualizes Waypoint-based navigation (List of LatLng).
///        Shows "WAYPOINT MODE" when following a calculated safe route.
///
/// 3. LOGIC: Road Width Priority (Blockage Avoidance).
///
/// 【iOS最適化】
/// - compass_permission_service (Web JS API) を削除
/// - flutter_compass が CoreMotion を通じて自動的に権限要求
/// ============================================================================
class DisasterCompassScreen extends StatefulWidget {
  const DisasterCompassScreen({super.key});

  @override
  State<DisasterCompassScreen> createState() => _DisasterCompassScreenState();
}

class _DisasterCompassScreenState extends State<DisasterCompassScreen> {
  // --- DESIGN SYSTEM COLORS ---
  static const Color _emerald = Color(0xFF00C896);
  static const Color _amber = Color(0xFFFF6B35);
  static const Color _darkBg = Color(0xFF0A0A1A);
  static const Color _cardDarker = Color(0xFF1A1A38);

  static const MethodChannel _brightnessCh =
      MethodChannel('gapless/brightness');
  double? _savedBrightness;

  static const double _btnHeight = 56.0;
  static const double _btnRadius = 28.0;
  static const double _cardRadius = 20.0;
  static const double _screenPadding = 24.0;

  Timer? _voiceTimer;
  double? _lastSpokenDistance;
  StreamSubscription<bool>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _initNavigation();
    _initConnectivityMonitor();
    _maximizeBrightness();
  }

  Future<void> _maximizeBrightness() async {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    try {
      final cur = await _brightnessCh.invokeMethod<double>('getBrightness');
      _savedBrightness = cur ?? 0.5;
      await _brightnessCh.invokeMethod('setBrightness', {'value': 1.0});
    } catch (_) {
      // silent fallback
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

  void _initNavigation() {
    // Start periodic voice guidance (60 秒間隔。連続案内うるさい問題対策)
    _voiceTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _speakNavigationUpdate();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryStartAutoNavigation();
      _speakNavigationUpdate();
    });
  }

  void _tryStartAutoNavigation() {
    final shelterProvider = context.read<ShelterProvider>();
    final compassProvider = context.read<CompassProvider>();
    final locationProvider = context.read<LocationProvider>();

    // If already navigating, do nothing
    if (compassProvider.isNavigating) return;

    final target = shelterProvider.navTarget;
    final userLoc = locationProvider.currentLocation;

    // If we have a target and location, ensure the navigation flow is active
    if (target != null && userLoc != null) {
      _findAndStartNavigation(target.type, typeLabel: target.name);
    }
  }

  void _initConnectivityMonitor() {
    _connectivitySub =
        ConnectivityService.onConnectivityChanged.listen((connected) {
      if (!mounted) return;
      final hasNetwork = connected;
      if (hasNetwork) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              GapLessL10n.t('connectivity_restored'),
              style: GapLessL10n.safeStyle(const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            backgroundColor: _emerald,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            margin: const EdgeInsets.all(24),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: GapLessL10n.t('triage_back'),
              textColor: Colors.white,
              onPressed: () {
                if (mounted) Navigator.pop(context);
              },
            ),
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _voiceTimer?.cancel();
    _connectivitySub?.cancel();
    _restoreBrightness();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // 災害モード復帰: AppBar右上「⚠誤検知?ホームへ」3秒長押しで戻る
  // ---------------------------------------------------------------------------
  double _exitHoldProgress = 0.0;
  Timer? _exitHoldTimer;
  DateTime? _exitHoldStart;

  void _onExitHoldStart() {
    _exitHoldStart = DateTime.now();
    _exitHoldTimer?.cancel();
    _exitHoldTimer = Timer.periodic(const Duration(milliseconds: 30), (t) {
      if (!mounted || _exitHoldStart == null) {
        t.cancel();
        return;
      }
      final ms = DateTime.now().difference(_exitHoldStart!).inMilliseconds;
      final p = (ms / 3000.0).clamp(0.0, 1.0);
      setState(() => _exitHoldProgress = p);
      if (p >= 1.0) {
        t.cancel();
        HapticService.destinationSet();
        _showSnackBar(
            GapLessL10n.t('disaster_mode_exit_done'), Colors.green.shade700);
        Navigator.of(context).maybePop();
      }
    });
  }

  void _onExitHoldEnd() {
    _exitHoldTimer?.cancel();
    _exitHoldStart = null;
    if (mounted) setState(() => _exitHoldProgress = 0.0);
  }

  void _speakNavigationUpdate() {
    if (!mounted) return;

    final shelterProvider = context.read<ShelterProvider>();
    final locationProvider = context.read<LocationProvider>();
    final alertProvider = context.read<AlertProvider>();
    final compassProvider = context.read<CompassProvider>();

    final target = shelterProvider.navTarget;
    final currentLocation = locationProvider.currentLocation;

    if (target == null || currentLocation == null) return;

    // Get distance based on active mode
    double distance;
    if (compassProvider.isSafeNavigating) {
      // Directive 2: Waypoint Navigation distance
      distance = compassProvider.remainingDistance;
    } else {
      distance = Geolocator.distanceBetween(
        currentLocation.latitude,
        currentLocation.longitude,
        target.lat,
        target.lng,
      );
    }

    if (distance < 0) return;

    // Debounce speech if distance hasn't changed much (e.g. standing still)
    // 50m 未満の差分では再読み上げしない (連続案内うるさい問題対策)
    if (_lastSpokenDistance != null &&
        (distance - _lastSpokenDistance!).abs() < 50) {
      return;
    }
    _lastSpokenDistance = distance;

    final bearing = Geolocator.bearingBetween(
      currentLocation.latitude,
      currentLocation.longitude,
      target.lat,
      target.lng,
    );

    final direction = _getDirectionText(bearing);
    alertProvider.speakNavigation(distance, direction);
  }

  String _getDirectionText(double bearing) {
    final normalized = (bearing + 360) % 360;
    // Simple 8-direction mapping
    if (normalized >= 337.5 || normalized < 22.5)
      return GapLessL10n.t('dir_north');
    if (normalized >= 22.5 && normalized < 67.5)
      return GapLessL10n.t('dir_northeast');
    if (normalized >= 67.5 && normalized < 112.5)
      return GapLessL10n.t('dir_east');
    if (normalized >= 112.5 && normalized < 157.5)
      return GapLessL10n.t('dir_southeast');
    if (normalized >= 157.5 && normalized < 202.5)
      return GapLessL10n.t('dir_south');
    if (normalized >= 202.5 && normalized < 247.5)
      return GapLessL10n.t('dir_southwest');
    if (normalized >= 247.5 && normalized < 292.5)
      return GapLessL10n.t('dir_west');
    return GapLessL10n.t('dir_northwest');
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>(); // 言語変更時に再描画
    final shelterProvider = context.watch<ShelterProvider>();
    final region = shelterProvider.currentAppRegion;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: _darkBg,
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.3),
              radius: 1.2,
              colors: [
                Color(0xFF0D0D2B),
                Color(0xFF0A0A1A),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // 1. Header Area
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                      _screenPadding, 12, _screenPadding, 12),
                  child: _buildHeader(region),
                ),

                // 2. Destination Info Card
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: _screenPadding),
                  child: _buildDestinationCard(),
                ),

                // 3. Main Compass Visualization
                Expanded(
                  child: _buildCompassCenter(),
                ),

                // 4. Logic Indicator
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: _screenPadding),
                  child: _buildLogicIndicator(region),
                ),

                const SizedBox(height: 16),

                // 5. Quick Select Chips
                _buildQuickSelectChips(),

                // 6. Arrival Button
                Padding(
                  padding: const EdgeInsets.all(_screenPadding),
                  child: _buildArrivalButton(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(AppRegion region) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 「⚠誤検知?ホームへ」常設エスケープボタン (3秒長押しガード)
        Semantics(
          button: true,
          label: GapLessL10n.t('disaster_mode_exit'),
          hint: GapLessL10n.t('disaster_mode_exit_confirm'),
          child: GestureDetector(
            onLongPressStart: (_) => _onExitHoldStart(),
            onLongPressEnd: (_) => _onExitHoldEnd(),
            onLongPressCancel: _onExitHoldEnd,
            onTap: () => _showSnackBar(
                GapLessL10n.t('disaster_mode_exit_confirm'), _amber),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  width: 56,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _amber.withValues(alpha: 0.6),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _amber.withValues(alpha: 0.25),
                        blurRadius: 12,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_exitHoldProgress > 0)
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            value: _exitHoldProgress,
                            strokeWidth: 3,
                            valueColor: const AlwaysStoppedAnimation(_amber),
                            backgroundColor: Colors.transparent,
                          ),
                        ),
                      const Icon(Icons.warning_amber_rounded,
                          color: _amber, size: 24),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Column(
          children: [
            const Text(
              "SAFE NAV",
              style: TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
              ),
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _emerald.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _emerald.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: const Text(
                    "🇯🇵 TOKYO",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        Consumer<AlertProvider>(
          builder: (context, alert, _) => _buildCircleButton(
            icon: alert.isVoiceGuidanceEnabled
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded,
            onPressed: () => alert.toggleVoiceGuidance(),
            active: alert.isVoiceGuidanceEnabled,
          ),
        ),
      ],
    );
  }

  Widget _buildCircleButton(
      {required IconData icon,
      required VoidCallback onPressed,
      bool active = false}) {
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            shape: BoxShape.circle,
            border: Border.all(
              color: (active ? _emerald : _amber).withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: (active ? _emerald : _amber).withValues(alpha: 0.2),
                blurRadius: 12,
                spreadRadius: 0,
              ),
            ],
          ),
          child: IconButton(
            icon: Icon(icon, color: active ? _emerald : _amber),
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }

  Widget _buildDestinationCard() {
    return Consumer3<LocationProvider, ShelterProvider, CompassProvider>(
      builder: (context, locProv, shelterProv, compassProv, _) {
        final target = shelterProv.navTarget;
        final loc = locProv.currentLocation;

        if (loc == null) {
          return _buildStatusCard(
              GapLessL10n.t('loc_acquiring'), Icons.gps_fixed);
        }
        if (target == null) {
          return _buildStatusCard(
              GapLessL10n.t('loc_no_destination'), Icons.flag_outlined);
        }

        // DISTANCEのみ計算（MODE/ETAは非表示）
        double distance = -1;

        if (compassProv.isSafeNavigating) {
          distance = compassProv.remainingDistance;
        } else {
          distance = const Distance()
              .as(LengthUnit.Meter, loc, LatLng(target.lat, target.lng));
        }

        final distStr = distance < 0
            ? "--"
            : distance < 1000
                ? "${distance.toStringAsFixed(0)}m"
                : "${(distance / 1000).toStringAsFixed(1)}km";

        return ClipRRect(
          borderRadius: BorderRadius.circular(_cardRadius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(_cardRadius),
                border: Border.all(
                  color: _emerald.withValues(alpha: 0.25),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _emerald.withValues(alpha: 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _amber.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: const Icon(Icons.flag_rounded,
                            color: _amber, size: 28),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "DESTINATION",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                              ),
                            ),
                            Semantics(
                              label: 'Destination ${target.name}',
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  target.name,
                                  style: GapLessL10n.safeStyle(const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.3,
                                  )),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  // DISTANCEのみ表示（MODE/ETAを削除してコンパスのスペースを確保）
                  Row(
                    children: [
                      _buildDetailItem("DISTANCE", distStr),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusCard(String title, IconData icon) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(_cardRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(_cardRadius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white.withValues(alpha: 0.4), size: 28),
              const SizedBox(width: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Semantics(
      label: '$label $value',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GapLessL10n.safeStyle(TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            )),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GapLessL10n.safeStyle(const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            )),
          ),
        ],
      ),
    );
  }

  Widget _buildCompassCenter() {
    return Consumer3<CompassProvider, LocationProvider, ShelterProvider>(
      builder: (context, compassProv, locProv, shelterProv, _) {
        final target = shelterProv.navTarget;
        final loc = locProv.currentLocation;

        double? safeBearing;

        const targetGeoRegion = GeoRegion.jpTokyo;

        // Sync GeoRegion if changed
        if (compassProv.currentGeoRegion.code != targetGeoRegion.code) {
          Future.microtask(() => compassProv.setGeoRegion(targetGeoRegion));
        }

        // DIRECTIVE 2: Using calculated Waypoint route bearing if available
        if (compassProv.isSafeNavigating && compassProv.magnetResult != null) {
          safeBearing = compassProv.magnetResult!.bearingToTarget;
        } else if (target != null && loc != null) {
          // Direct fallback
          safeBearing = Geolocator.bearingBetween(
              loc.latitude, loc.longitude, target.lat, target.lng);
        }

        // Color overlay indicating on-track status
        Color? overlayColor;
        if (loc != null && safeBearing != null) {
          final heading = compassProv.trueHeading ?? 0.0;
          double diff = (safeBearing - heading).abs();
          if (diff > 180) diff = 360 - diff;
          if (diff < 30) {
            overlayColor = _emerald.withValues(alpha: 0.06);
          }
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer radial glow ring
            Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _emerald.withValues(alpha: 0.04),
                    Colors.transparent,
                  ],
                ),
              ),
            ),

            if (overlayColor != null)
              Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: overlayColor,
                  boxShadow: [
                    BoxShadow(
                      color: _emerald.withValues(alpha: 0.15),
                      blurRadius: 60,
                      spreadRadius: 20,
                    )
                  ],
                ),
              ),

            // Compass ring glow border
            Container(
              width: 296,
              height: 296,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _emerald.withValues(alpha: 0.18),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _emerald.withValues(alpha: 0.12),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),

            Semantics(
              label: safeBearing != null
                  ? 'Compass, target bearing ${safeBearing.round()} degrees'
                  : 'Compass',
              liveRegion: true,
              child: SmartCompass(
                heading: compassProv.trueHeading ?? compassProv.heading ?? 0.0,
                safeBearing: safeBearing,
                dangerBearings: const [],
                size: 290,
              ),
            ),

            // iOS: flutter_compassがCoreMotionを通じて自動的に権限要求する
            // センサーデータが取得できるまでは控えめなインジケーターを表示
            if (!compassProv.hasSensorData) _buildSensorWaitingIndicator(),
          ],
        );
      },
    );
  }

  /// iOSネイティブ: センサー取得待機インジケーター
  /// flutter_compassがCoreMotion経由でデータを取得するまで表示
  Widget _buildSensorWaitingIndicator() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _emerald.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                color: _emerald,
                strokeWidth: 2,
              ),
            ),
            const SizedBox(width: 10),
            Text(GapLessL10n.t('sensor_loading'),
                style: GapLessL10n.safeStyle(TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ))),
          ]),
        ),
      ),
    );
  }

  // --- DIRECTIVE 3: LOGIC INDICATOR ---
  Widget _buildLogicIndicator(AppRegion region) {
    final isJapan = region == AppRegion.japan;
    final icon = isJapan ? Icons.add_road : Icons.flash_off;
    final title = isJapan ? "JAPAN LOGIC ACTIVE" : "THAI LOGIC ACTIVE";
    final desc = isJapan
        ? "Priority: Road Width (Blockage Avoidance)"
        : "Priority: Avoid Electric Shock & Flood";

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _emerald.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _emerald.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _emerald.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Icon(icon, color: _emerald, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GapLessL10n.safeStyle(TextStyle(
                        color: _emerald,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      )),
                    ),
                    Text(
                      desc,
                      style: GapLessL10n.safeStyle(TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      )),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickSelectChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: _screenPadding),
      child: Row(
        children: [
          _buildQuickChip(Icons.water_drop, "Water", "water"),
          const SizedBox(width: 12),
          _buildQuickChip(Icons.local_hospital, "Hospital", "hospital"),
          const SizedBox(width: 12),
          _buildQuickChip(Icons.store, "Store", "convenience"),
          const SizedBox(width: 12),
          _buildQuickChip(Icons.night_shelter, "Shelter", "shelter"),
        ],
      ),
    );
  }

  Widget _buildQuickChip(IconData icon, String label, String type) {
    return GestureDetector(
      onTap: () => _findAndStartNavigation(type, typeLabel: label),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _emerald.withValues(alpha: 0.25),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: _emerald.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: _emerald),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- DIRECTIVE 1: ARRIVAL BUTTON (Height 56, Radius 28) ---
  Widget _buildArrivalButton() {
    return SizedBox(
      width: double.infinity,
      height: _btnHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(_btnRadius),
          boxShadow: [
            BoxShadow(
              color: _emerald.withValues(alpha: 0.35),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: () => _confirmArrival(),
          style: ElevatedButton.styleFrom(
            backgroundColor: _emerald,
            foregroundColor: Colors.white,
            elevation: 0,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_btnRadius),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_outline, size: 22),
              const SizedBox(width: 12),
              Text(
                GapLessL10n.t('btn_arrived_label'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _findAndStartNavigation(String type, {String? typeLabel}) async {
    final shelterProvider = context.read<ShelterProvider>();
    final locationProvider = context.read<LocationProvider>();
    final userLoc = locationProvider.currentLocation;

    if (userLoc == null) {
      _showSnackBar(GapLessL10n.t('bot_loc_error'), _amber);
      return;
    }

    List<String> types = [type];

    // Find nearest
    final nearest =
        shelterProvider.getNearestShelter(userLoc, includeTypes: types);

    if (nearest != null) {
      // Start fresh calculation
      await shelterProvider.startNavigation(nearest, currentLocation: userLoc);
      if (!mounted) return;
      final safeRoute = shelterProvider.getSafestRouteAsLatLng();

      if (safeRoute.isNotEmpty) {
        context.read<CompassProvider>().startRouteNavigation(safeRoute);
      }

      HapticService.destinationSet();
      _showSnackBar("Route Calculated: ${nearest.name}", _emerald);
    } else {
      _showSnackBar("No facility found nearby", Colors.grey);
    }
  }

  void _showSnackBar(String message, Color bg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: GapLessL10n.safeStyle(const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold))),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(24),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _confirmArrival() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardDarker,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(GapLessL10n.t('dialog_safety_title'),
            style: GapLessL10n.safeStyle(const TextStyle(
              color: _emerald,
              fontWeight: FontWeight.w700,
            ))),
        content: Text(GapLessL10n.t('dialog_safety_desc'),
            style: GapLessL10n.safeStyle(TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
            ))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(GapLessL10n.t('btn_cancel'),
                style: GapLessL10n.safeStyle(TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                ))),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: _emerald.withValues(alpha: 0.3),
                  blurRadius: 12,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: () {
                HapticService.arrivedAtDestination();
                Navigator.pop(ctx);
                context.read<ShelterProvider>().setSafeInShelter(true);
                Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ShelterDashboardScreen()));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _emerald,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20)),
              ),
              child: Text(GapLessL10n.t('btn_yes_arrived'),
                  style: GapLessL10n.safeStyle(
                      const TextStyle(fontWeight: FontWeight.w700))),
            ),
          ),
        ],
      ),
    );
  }
}
