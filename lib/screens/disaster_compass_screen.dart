import 'dart:async';
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
import '../services/compass_permission_service.dart';
import '../widgets/smart_compass.dart';
import 'shelter_dashboard_screen.dart';

/// ============================================================================
/// DisasterCompassScreen - 防災コンパス画面
/// ============================================================================
/// 
/// ABSOLUTE DIRECTIVES IMPLEMENTATION:
/// 1. UI: Navy (#1A237E) / Orange (#FF6F00) Palette. 
///    - BorderRadius: 30.0
///    - Button Height: 56.0
///    - Padding: 24.0+
/// 2. NAV: Waypoint-based navigation visualization.
/// 3. LOGIC: Explicit active logic display (Japan: Road Width vs Thailand: Electric Shock).
/// ============================================================================
class DisasterCompassScreen extends StatefulWidget {
  const DisasterCompassScreen({super.key});

  @override
  State<DisasterCompassScreen> createState() => _DisasterCompassScreenState();
}

class _DisasterCompassScreenState extends State<DisasterCompassScreen> {
  // --- DIRECTIVE 1: UI CONSTANTS ---
  static const Color _navyPrimary = Color(0xFF1A237E);
  static const Color _orangeAccent = Color(0xFFFF6F00);
  static const double _uiRadius = 30.0;
  static const double _btnHeight = 56.0;
  static const double _padding = 24.0;

  Timer? _voiceTimer;
  double? _lastSpokenDistance;
  bool _dismissPermissionBanner = false;

  @override
  void initState() {
    super.initState();
    _initLifeCycle();
  }

  void _initLifeCycle() {
    // Start periodic voice updates
    _voiceTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _speakNavigationUpdate();
    });

    // Initial setup after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoStartNavigationIfNeeded();
      _speakNavigationUpdate();
      
      // Update background route calculation
      final locProvider = context.read<LocationProvider>();
      if (locProvider.currentLocation != null) {
        context.read<ShelterProvider>().updateBackgroundRoutes(locProvider.currentLocation!);
      }
    });
  }

  /// Automatically start navigation if a target is set but compass isn't active
  void _autoStartNavigationIfNeeded() {
    final shelterProvider = context.read<ShelterProvider>();
    final compassProvider = context.read<CompassProvider>();
    final locationProvider = context.read<LocationProvider>();

    if (compassProvider.isNavigating) return;

    final target = shelterProvider.navTarget;
    final userLoc = locationProvider.currentLocation;

    if (target != null && userLoc != null) {
      // Re-trigger navigation logic to ensure routes are calculated
      _findAndStartNavigation(target.type, typeLabel: target.name);
    }
  }

  @override
  void dispose() {
    _voiceTimer?.cancel();
    super.dispose();
  }

  // --- VOICE GUIDANCE LOGIC ---
  void _speakNavigationUpdate() {
    if (!mounted) return;

    final shelterProvider = context.read<ShelterProvider>();
    final locationProvider = context.read<LocationProvider>();
    final alertProvider = context.read<AlertProvider>();
    final compassProvider = context.read<CompassProvider>();

    final target = shelterProvider.navTarget;
    final currentLocation = locationProvider.currentLocation;

    if (target == null || currentLocation == null) return;

    // Determine effective distance based on mode
    double distance;
    if (compassProvider.isSafeNavigating) {
      distance = compassProvider.remainingDistance;
    } else {
      final cachedDist = shelterProvider.getDistanceToTargetIfCached(target);
      distance = cachedDist ?? Geolocator.distanceBetween(
        currentLocation.latitude, currentLocation.longitude,
        target.lat, target.lng
      );
    }

    if (distance < 0) return;

    // Avoid spamming voice if distance hasn't changed much (threshold: 50m)
    if (_lastSpokenDistance != null && (distance - _lastSpokenDistance!).abs() < 50) {
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
    if (normalized >= 337.5 || normalized < 22.5) return AppLocalizations.t('dir_north');
    if (normalized >= 22.5 && normalized < 67.5) return AppLocalizations.t('dir_northeast');
    if (normalized >= 67.5 && normalized < 112.5) return AppLocalizations.t('dir_east');
    if (normalized >= 112.5 && normalized < 157.5) return AppLocalizations.t('dir_southeast');
    if (normalized >= 157.5 && normalized < 202.5) return AppLocalizations.t('dir_south');
    if (normalized >= 202.5 && normalized < 247.5) return AppLocalizations.t('dir_southwest');
    if (normalized >= 247.5 && normalized < 292.5) return AppLocalizations.t('dir_west');
    return AppLocalizations.t('dir_northwest');
  }

  @override
  Widget build(BuildContext context) {
    final shelterProvider = context.watch<ShelterProvider>();
    final region = shelterProvider.currentAppRegion;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Header (Padding 24)
            Padding(
              padding: const EdgeInsets.all(_padding),
              child: _buildHeader(region),
            ),

            // 2. Destination Info Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _padding),
              child: _buildDestinationCard(),
            ),

            // 3. Main Compass Visualization
            Expanded(
              child: _buildCompassCenter(),
            ),

            // 4. DIRECTIVE 3: LOGIC Indicator
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _padding),
              child: _buildLogicIndicator(region),
            ),
            
            const SizedBox(height: 16),

            // 5. Quick Select Chips
            _buildQuickSelectChips(),

            // 6. DIRECTIVE 1: Arrival Button (Height 56, Radius 30)
            Padding(
              padding: const EdgeInsets.all(_padding),
              child: _buildArrivalButton(),
            ),
          ],
        ),
      ),
    );
  }

  // --- WIDGETS ---

  Widget _buildHeader(AppRegion region) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildCircleButton(
          icon: Icons.close_rounded,
          onPressed: () => Navigator.pop(context),
        ),
        Column(
          children: [
            const Text(
              "SAFE NAV",
              style: TextStyle(
                color: _navyPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _navyPrimary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                region == AppRegion.japan ? "🇯🇵 MIYAGI" : "🇹🇭 SATUN",
                style: const TextStyle(
                  color: _navyPrimary,
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
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: active ? _orangeAccent : _navyPrimary),
        onPressed: onPressed,
      ),
    );
  }

  // --- DIRECTIVE 2: WAYPOINT VISUALIZATION ---
  Widget _buildDestinationCard() {
    return Consumer3<LocationProvider, ShelterProvider, CompassProvider>(
      builder: (context, locProv, shelterProv, compassProv, _) {
        final target = shelterProv.navTarget;
        final loc = locProv.currentLocation;

        if (loc == null) {
          return _buildStatusCard(AppLocalizations.t('loc_acquiring'), Icons.gps_fixed);
        }
        if (target == null) {
          return _buildStatusCard(AppLocalizations.t('loc_no_destination'), Icons.flag_outlined);
        }

        // Logic to determine navigation mode
        String modeText = "DIRECT";
        double distance = -1;
        IconData modeIcon = Icons.near_me;

        if (compassProv.isSafeNavigating) {
          modeText = "WAYPOINT NAV";
          modeIcon = Icons.alt_route;
          distance = compassProv.remainingDistance;
        } else {
          final cachedDist = shelterProv.getDistanceToTargetIfCached(target);
          if (cachedDist != null) {
            modeText = "CACHED ROUTE";
            modeIcon = Icons.save;
            distance = cachedDist;
          } else {
            // Straight line distance
            distance = const Distance().as(LengthUnit.Meter, loc, LatLng(target.lat, target.lng));
          }
        }

        final distStr = distance < 0 
            ? "--" 
            : distance < 1000 
                ? "${distance.toStringAsFixed(0)}m" 
                : "${(distance / 1000).toStringAsFixed(1)}km";

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_uiRadius),
            boxShadow: [
              BoxShadow(
                color: _navyPrimary.withOpacity(0.08),
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
                      color: _orangeAccent.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.flag_rounded, color: _orangeAccent, size: 28),
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
                            color: _navyPrimary,
                            fontSize: 18,
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
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Divider(height: 1),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildDetailItem("DISTANCE", distStr),
                  _buildDetailItem("MODE", modeText, icon: modeIcon),
                  _buildDetailItem("ETA", distance < 0 ? "--" : "${(distance / 60).ceil()} min"),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_uiRadius),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey),
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

  Widget _buildDetailItem(String label, String value, {IconData? icon}) {
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
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: _navyPrimary),
              const SizedBox(width: 4),
            ],
            Text(
              value,
              style: const TextStyle(
                color: _navyPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
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
        
        // Sync GeoRegion for declination correction
        final region = shelterProv.currentAppRegion;
        final targetGeoRegion = region == AppRegion.japan ? GeoRegion.jpOsaki : GeoRegion.thSatun;
        
        if (compassProv.currentGeoRegion.code != targetGeoRegion.code) {
          // Defer update to avoid build-time state changes
          Future.microtask(() => compassProv.setGeoRegion(targetGeoRegion));
        }

        // Determine target bearing (Waypoint or Direct)
        if (compassProv.isSafeNavigating && compassProv.magnetResult != null) {
          safeBearing = compassProv.magnetResult!.bearingToTarget;
        } else if (target != null && loc != null) {
          safeBearing = Geolocator.bearingBetween(
            loc.latitude, loc.longitude, target.lat, target.lng
          );
        }

        // Overlay color based on immediate risk
        Color? overlayColor;
        if (loc != null) {
          final heading = compassProv.trueHeading ?? 0.0;
          final riskInfo = shelterProv.getRoadRiskInDirection(loc, heading);
          
          if (riskInfo != null && riskInfo['isSafe'] == false) {
            overlayColor = Colors.red.withOpacity(0.1);
          } else if (safeBearing != null) {
            double diff = (safeBearing - heading).abs();
            if (diff > 180) diff = 360 - diff;
            if (diff < 30) {
              overlayColor = Colors.green.withOpacity(0.05);
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
              dangerBearings: const [], // Could inject from RadarScanner
              size: 260,
            ),

            if (!compassProv.hasSensorData && !_dismissPermissionBanner)
              _buildPermissionOverlay(),
          ],
        );
      },
    );
  }

  Widget _buildPermissionOverlay() {
    return Center(
      child: GestureDetector(
        onTap: () async {
          final result = await requestIOSCompassPermission();
          if (result == 'granted' || result == 'not_supported') {
            setState(() => _dismissPermissionBanner = true);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(
            color: _navyPrimary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Text(
            "Enable Compass",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }

  // --- DIRECTIVE 3: LOGIC INDICATOR (Explicit display) ---
  Widget _buildLogicIndicator(AppRegion region) {
    final isJapan = region == AppRegion.japan;
    final icon = isJapan ? Icons.add_road : Icons.flash_off;
    final title = isJapan ? "JAPAN LOGIC ACTIVE" : "THAI LOGIC ACTIVE";
    final desc = isJapan 
        ? "Priority: Road Width (Blockage Avoidance)" 
        : "Priority: Avoid Electric Shock & Flood Risk";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _navyPrimary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _navyPrimary.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: _navyPrimary.withOpacity(0.2)),
            ),
            child: Icon(icon, color: _navyPrimary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _navyPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                  ),
                ),
                Text(
                  desc,
                  style: TextStyle(
                    color: _navyPrimary.withOpacity(0.8),
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
      padding: const EdgeInsets.symmetric(horizontal: _padding),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: _navyPrimary),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: _navyPrimary,
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
          backgroundColor: _navyPrimary,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_uiRadius),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline),
            const SizedBox(width: 12),
            Text(
              AppLocalizations.t('btn_arrived_label'),
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
      _showSnackBar(AppLocalizations.t('bot_loc_error'), _orangeAccent);
      return;
    }

    // Try to start from cached route first (Background processed)
    if (shelterProvider.startCachedNavigation(type)) {
      final nearest = shelterProvider.navTarget!;
      final safeRoute = shelterProvider.getSafestRouteAsLatLng();
      if (safeRoute.isNotEmpty) {
        context.read<CompassProvider>().startRouteNavigation(safeRoute);
        HapticService.destinationSet();
        _showSnackBar("Route Found (Cached): ${nearest.name}", _navyPrimary);
        return;
      }
    }

    // Fallback: Real-time search and calculate
    List<String> types = [type];
    if (type == 'water') types = ['water', 'convenience', 'store'];
    
    final nearest = shelterProvider.getNearestShelter(userLoc, includeTypes: types);
    
    if (nearest != null) {
      await shelterProvider.startNavigation(nearest, currentLocation: userLoc);
      final safeRoute = shelterProvider.getSafestRouteAsLatLng();
      
      if (safeRoute.isNotEmpty) {
        context.read<CompassProvider>().startRouteNavigation(safeRoute);
        _showSnackBar("Safe Route Calculated: ${nearest.name}", _navyPrimary);
      } else {
        _showSnackBar("Direct Navigation: ${nearest.name}", _navyPrimary);
      }
      
      HapticService.destinationSet();
    } else {
      _showSnackBar("No facility found nearby", Colors.grey);
    }
  }

  void _showSnackBar(String message, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: bg,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.all(24),
      ),
    );
  }

  void _confirmArrival() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(AppLocalizations.t('dialog_safety_title'), 
            style: const TextStyle(color: _navyPrimary, fontWeight: FontWeight.bold)),
        content: Text(AppLocalizations.t('dialog_safety_desc')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.t('btn_cancel'), style: const TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              HapticService.arrivedAtDestination();
              Navigator.pop(ctx);
              context.read<ShelterProvider>().setSafeInShelter(true);
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ShelterDashboardScreen()));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _navyPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: Text(AppLocalizations.t('btn_yes_arrived')),
          ),
        ],
      ),
    );
  }
}