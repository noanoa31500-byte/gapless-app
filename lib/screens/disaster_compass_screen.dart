import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../providers/compass_provider.dart';
import '../providers/shelter_provider.dart';
import '../providers/location_provider.dart';
import '../providers/alert_provider.dart';
import '../providers/region_mode_provider.dart';
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
/// 3. LOGIC: Explicitly displays the active safety logic based on region.
///        Japan = Road Width Priority (Blockage Avoidance).
///        Thailand = Avoid Electric Shock Risk (Flood + Power Infra).
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
  // --- DIRECTIVE 1: UI CONSTANTS ---
  static const Color _redPrimary = Color(0xFFC62828);
  static const Color _orangeAccent = Color(0xFFFF6F00);
  static const Color _bgWhite = Color(0xFFF5F7FA);

  static const double _btnHeight = 56.0;
  static const double _btnRadius = 30.0;
  static const double _cardRadius = 30.0;
  static const double _screenPadding = 24.0;

  Timer? _voiceTimer;
  double? _lastSpokenDistance;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  @override
  void initState() {
    super.initState();
    _initNavigation();
    _initConnectivityMonitor();
  }

  void _initNavigation() {
    // Start periodic voice guidance
    _voiceTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _speakNavigationUpdate();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryStartAutoNavigation();
      _speakNavigationUpdate();
      
      // Ensure background route calculation is active
      final locProvider = context.read<LocationProvider>();
      if (locProvider.currentLocation != null) {
        context.read<ShelterProvider>().updateBackgroundRoutes(locProvider.currentLocation!);
      }
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
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);
      if (hasNetwork) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              '📶 通信が回復しました。ホームに戻れます。',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            backgroundColor: const Color(0xFF2E7D32),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            margin: const EdgeInsets.all(24),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: '戻る',
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
    super.dispose();
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
      final cachedDist = shelterProvider.getDistanceToTargetIfCached(target);
      distance = cachedDist ?? -1.0;
    }

    if (distance < 0) return;

    // Debounce speech if distance hasn't changed much (e.g. standing still)
    if (_lastSpokenDistance != null && (distance - _lastSpokenDistance!).abs() < 20) {
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
    if (normalized >= 337.5 || normalized < 22.5) return GapLessL10n.t('dir_north');
    if (normalized >= 22.5 && normalized < 67.5) return GapLessL10n.t('dir_northeast');
    if (normalized >= 67.5 && normalized < 112.5) return GapLessL10n.t('dir_east');
    if (normalized >= 112.5 && normalized < 157.5) return GapLessL10n.t('dir_southeast');
    if (normalized >= 157.5 && normalized < 202.5) return GapLessL10n.t('dir_south');
    if (normalized >= 202.5 && normalized < 247.5) return GapLessL10n.t('dir_southwest');
    if (normalized >= 247.5 && normalized < 292.5) return GapLessL10n.t('dir_west');
    return GapLessL10n.t('dir_northwest');
  }

  @override
  Widget build(BuildContext context) {
    final shelterProvider = context.watch<ShelterProvider>();
    final region = shelterProvider.currentAppRegion;

    return PopScope(
      canPop: false,
      child: Scaffold(
      backgroundColor: _bgWhite,
      body: SafeArea(
        child: Column(
          children: [
            // 1. Header Area (Padding 12 top to preserve compass space)
            Padding(
              padding: const EdgeInsets.fromLTRB(_screenPadding, 12, _screenPadding, 12),
              child: _buildHeader(region),
            ),

            // 2. Destination Info Card (Directive 1: Radius 30)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _screenPadding),
              child: _buildDestinationCard(),
            ),

            // 3. Main Compass Visualization
            Expanded(
              child: _buildCompassCenter(),
            ),

            // 4. Logic Indicator (Directive 3: Explicit Logic Display)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _screenPadding),
              child: _buildLogicIndicator(region),
            ),
            
            const SizedBox(height: 16),

            // 5. Quick Select Chips
            _buildQuickSelectChips(),

            // 6. Arrival Button (Directive 1: Height 56, Radius 30)
            Padding(
              padding: const EdgeInsets.all(_screenPadding),
              child: _buildArrivalButton(),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildHeader(AppRegion region) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const SizedBox(width: 48), // placeholder to keep title centered
        Column(
          children: [
            const Text(
              "SAFE NAV",
              style: TextStyle(
                color: _redPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _redPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                region == AppRegion.japan ? "🇯🇵 MIYAGI" : "🇹🇭 SATUN",
                style: const TextStyle(
                  color: _redPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        Consumer<AlertProvider>(
          builder: (context, alert, _) => _buildCircleButton(
            icon: alert.isVoiceGuidanceEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            onPressed: () => alert.toggleVoiceGuidance(),
            active: alert.isVoiceGuidanceEnabled,
          ),
        ),
      ],
    );
  }

  Widget _buildCircleButton({required IconData icon, required VoidCallback onPressed, bool active = false}) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: active ? _orangeAccent : _redPrimary),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildDestinationCard() {
    return Consumer3<LocationProvider, ShelterProvider, CompassProvider>(
      builder: (context, locProv, shelterProv, compassProv, _) {
        final target = shelterProv.navTarget;
        final loc = locProv.currentLocation;

        if (loc == null) {
          return _buildStatusCard(GapLessL10n.t('loc_acquiring'), Icons.gps_fixed);
        }
        if (target == null) {
          return _buildStatusCard(GapLessL10n.t('loc_no_destination'), Icons.flag_outlined);
        }

        // DISTANCEのみ計算（MODE/ETAは非表示）
        double distance = -1;

        if (compassProv.isSafeNavigating) {
          distance = compassProv.remainingDistance;
        } else {
          final cachedDist = shelterProv.getDistanceToTargetIfCached(target);
          if (cachedDist != null) {
            distance = cachedDist;
          } else {
            distance = const Distance().as(LengthUnit.Meter, loc, LatLng(target.lat, target.lng));
          }
        }

        final distStr = distance < 0 
            ? "--" 
            : distance < 1000 
                ? "${distance.toStringAsFixed(0)}m" 
                : "${(distance / 1000).toStringAsFixed(1)}km";

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_cardRadius), // Directive 1
            boxShadow: [
              BoxShadow(
                color: _redPrimary.withValues(alpha: 0.08),
                blurRadius: 16,
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
                      color: _orangeAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.flag_rounded, color: _orangeAccent, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "DESTINATION",
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text(
                          target.name,
                          style: const TextStyle(
                            color: _redPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1),
              ),
              // DISTANCEのみ表示（MODE/ETAを削除してコンパスのスペースを確保）
              Row(
                children: [
                  _buildDetailItem("DISTANCE", distStr),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusCard(String title, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_cardRadius),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey, size: 28),
          const SizedBox(width: 16),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, {bool isHighlight = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: isHighlight ? _orangeAccent : _redPrimary,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildCompassCenter() {
    return Consumer3<CompassProvider, LocationProvider, ShelterProvider>(
      builder: (context, compassProv, locProv, shelterProv, _) {
        final target = shelterProv.navTarget;
        final loc = locProv.currentLocation;

        double? safeBearing;
        
        const targetGeoRegion = GeoRegion.jpOsaki;
        
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
            loc.latitude, loc.longitude, target.lat, target.lng
          );
        }

        // Color overlay indicating risk or on-track status
        Color? overlayColor;
        if (loc != null) {
          final heading = compassProv.trueHeading ?? 0.0;
          final riskInfo = shelterProv.getRoadRiskInDirection(loc, heading);
          
          if (riskInfo != null && riskInfo['isSafe'] == false) {
            overlayColor = Colors.red.withValues(alpha: 0.1);
          } else if (safeBearing != null) {
            double diff = (safeBearing - heading).abs();
            if (diff > 180) diff = 360 - diff;
            if (diff < 30) {
              overlayColor = Colors.green.withValues(alpha: 0.05);
            }
          }
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            if (overlayColor != null)
              Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: overlayColor,
                  boxShadow: [
                    BoxShadow(color: overlayColor, blurRadius: 60, spreadRadius: 20)
                  ],
                ),
              ),
            
            SmartCompass(
              heading: compassProv.trueHeading ?? compassProv.heading ?? 0.0,
              safeBearing: safeBearing,
              dangerBearings: const [],
              size: 290,
            ),

            // iOS: flutter_compassがCoreMotionを通じて自動的に権限要求する
            // センサーデータが取得できるまでは控えめなインジケーターを表示
            if (!compassProv.hasSensorData)
              _buildSensorWaitingIndicator(),
          ],
        );
      },
    );
  }

  /// iOSネイティブ: センサー取得待機インジケーター
  /// flutter_compassがCoreMotion経由でデータを取得するまで表示
  Widget _buildSensorWaitingIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: _redPrimary.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(width: 14, height: 14,
          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
        const SizedBox(width: 10),
        Text(GapLessL10n.t('sensor_loading'),
          style: GapLessL10n.safeStyle(const TextStyle(color: Colors.white, fontSize: 13))),
      ]),
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _redPrimary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _redPrimary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: _redPrimary.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: _redPrimary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _redPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(
                    color: _redPrimary.withValues(alpha: 0.8),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: _redPrimary),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: _redPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- DIRECTIVE 1: ARRIVAL BUTTON (Height 56, Radius 30) ---
  Widget _buildArrivalButton() {
    return SizedBox(
      width: double.infinity,
      height: _btnHeight,
      child: ElevatedButton(
        onPressed: () => _confirmArrival(),
        style: ElevatedButton.styleFrom(
          backgroundColor: _redPrimary,
          foregroundColor: Colors.white,
          elevation: 4,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_btnRadius),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline),
            const SizedBox(width: 12),
            Text(
              GapLessL10n.t('btn_arrived_label'),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _findAndStartNavigation(String type, {String? typeLabel}) async {
    final shelterProvider = context.read<ShelterProvider>();
    final locationProvider = context.read<LocationProvider>();
    final userLoc = locationProvider.currentLocation;

    if (userLoc == null) {
      _showSnackBar(GapLessL10n.t('bot_loc_error'), _orangeAccent);
      return;
    }

    // Try cached route first
    if (shelterProvider.startCachedNavigation(type)) {
      final nearest = shelterProvider.navTarget!;
      final safeRoute = shelterProvider.getSafestRouteAsLatLng();
      if (safeRoute.isNotEmpty) {
        context.read<CompassProvider>().startRouteNavigation(safeRoute);
        HapticService.destinationSet();
        _showSnackBar("Navigating to ${nearest.name}", _redPrimary);
        return;
      }
    }

    List<String> types = [type];
    
    // Find nearest
    final nearest = shelterProvider.getNearestShelter(userLoc, includeTypes: types);
    
    if (nearest != null) {
      // Start fresh calculation
      await shelterProvider.startNavigation(nearest, currentLocation: userLoc);
      if (!mounted) return;
      final safeRoute = shelterProvider.getSafestRouteAsLatLng();

      if (safeRoute.isNotEmpty) {
        context.read<CompassProvider>().startRouteNavigation(safeRoute);
      }

      HapticService.destinationSet();
      _showSnackBar("Route Calculated: ${nearest.name}", _redPrimary);
    } else {
      _showSnackBar("No facility found nearby", Colors.grey);
    }
  }

  void _showSnackBar(String message, Color bg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GapLessL10n.safeStyle(const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(GapLessL10n.t('dialog_safety_title'),
            style: GapLessL10n.safeStyle(const TextStyle(color: _redPrimary, fontWeight: FontWeight.bold))),
        content: Text(GapLessL10n.t('dialog_safety_desc'),
            style: GapLessL10n.safeStyle(const TextStyle())),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(GapLessL10n.t('btn_cancel'), style: GapLessL10n.safeStyle(const TextStyle(color: Colors.grey))),
          ),
          ElevatedButton(
            onPressed: () {
              HapticService.arrivedAtDestination();
              Navigator.pop(ctx);
              context.read<ShelterProvider>().setSafeInShelter(true);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ShelterDashboardScreen()));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _redPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: Text(GapLessL10n.t('btn_yes_arrived'), style: GapLessL10n.safeStyle(const TextStyle())),
          ),
        ],
      ),
    );
  }
}