import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
import 'shelter_dashboard_screen.dart';
import '../models/shelter.dart';
import '../services/compass_permission_service.dart';
import '../services/magnetic_declination_config.dart';

/// ============================================================================
/// DisasterCompassScreen - 防災コンパス画面
/// ============================================================================
///
/// DIRECTIVES IMPLEMENTATION:
/// 1. UI: Navy (#1A237E) / Orange (#FF6F00), Radius 30.0, Height 56.0, Padding 24.0.
/// 2. NAV: Visualizes Waypoint-based navigation (List<LatLng>).
/// 3. LOGIC: Displays active logic (Japan=Road Width, Thailand=Electric Shock).
class DisasterCompassScreen extends StatefulWidget {
  const DisasterCompassScreen({super.key});

  @override
  State<DisasterCompassScreen> createState() => _DisasterCompassScreenState();
}

class _DisasterCompassScreenState extends State<DisasterCompassScreen> {
  // --- DIRECTIVE 1: UI CONSTANTS ---
  static const Color _navyPrimary = Color(0xFF1A237E);
  static const Color _orangeAccent = Color(0xFFFF6F00);
  static const double _btnHeight = 56.0;
  static const double _btnRadius = 30.0;
  static const double _screenPadding = 24.0;

  Timer? _voiceTimer;
  double? _lastSpokenDistance;
  bool _dismissPermissionBanner = false;

  @override
  void initState() {
    super.initState();

    // Start voice guidance loop
    _voiceTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _speakNavigationUpdate();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryStartAutoNavigation();
      _speakNavigationUpdate();

      // Ensure background routes are fresh
      final locProvider = context.read<LocationProvider>();
      locProvider.addListener(_onLocationChanged);
      if (locProvider.currentLocation != null) {
        context.read<ShelterProvider>().updateBackgroundRoutes(locProvider.currentLocation!);
      }
    });
  }

  void _onLocationChanged() {
    if (!mounted) return;
    final loc = context.read<LocationProvider>().currentLocation;
    if (loc != null) {
      context.read<ShelterProvider>().updateBackgroundRoutes(loc);
    }
  }

  void _tryStartAutoNavigation() {
    final shelterProvider = context.read<ShelterProvider>();
    final compassProvider = context.read<CompassProvider>();
    final locationProvider = context.read<LocationProvider>();

    if (compassProvider.isNavigating) return;

    final target = shelterProvider.navTarget;
    final userLoc = locationProvider.currentLocation;

    if (target != null && userLoc != null) {
      _findAndStartNavigation(target.type, typeLabel: target.name);
    }
  }

  @override
  void dispose() {
    _voiceTimer?.cancel();
    final locProvider = context.read<LocationProvider>();
    locProvider.removeListener(_onLocationChanged);
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

    double distance;
    if (compassProvider.isSafeNavigating) {
      distance = compassProvider.remainingDistance;
    } else {
      final cachedDist = shelterProvider.getDistanceToTargetIfCached(target);
      if (cachedDist != null) {
        distance = cachedDist;
      } else {
        return;
      }
    }

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
    final normalizedBearing = (bearing + 360) % 360;
    if (normalizedBearing >= 337.5 || normalizedBearing < 22.5) return AppLocalizations.t('dir_north');
    if (normalizedBearing >= 22.5 && normalizedBearing < 67.5) return AppLocalizations.t('dir_northeast');
    if (normalizedBearing >= 67.5 && normalizedBearing < 112.5) return AppLocalizations.t('dir_east');
    if (normalizedBearing >= 112.5 && normalizedBearing < 157.5) return AppLocalizations.t('dir_southeast');
    if (normalizedBearing >= 157.5 && normalizedBearing < 202.5) return AppLocalizations.t('dir_south');
    if (normalizedBearing >= 202.5 && normalizedBearing < 247.5) return AppLocalizations.t('dir_southwest');
    if (normalizedBearing >= 247.5 && normalizedBearing < 292.5) return AppLocalizations.t('dir_west');
    return AppLocalizations.t('dir_northwest');
  }

  @override
  Widget build(BuildContext context) {
    final shelterProvider = context.watch<ShelterProvider>();
    final region = shelterProvider.currentAppRegion;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Header (Padding 24)
                Padding(
                  padding: const EdgeInsets.all(_screenPadding),
                  child: _buildHeader(region),
                ),
                
                // Destination Card (Padding 24 Horizontal)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _screenPadding),
                  child: _buildDestinationPanel(),
                ),
                
                // Main Compass
                Expanded(
                  child: _buildCompassArea(),
                ),
                
                // Logic Indicator (Directive 3)
                _buildLogicStatusIndicator(region),
                
                // Quick Select Chips
                _buildDestinationButtons(),
                
                // Arrival Button (Height 56, Radius 30)
                Padding(
                  padding: const EdgeInsets.fromLTRB(_screenPadding, 8, _screenPadding, _screenPadding),
                  child: _buildArrivalButton(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppRegion region) {
    return Row(
      children: [
        _buildIconButton(
          icon: Icons.close_rounded,
          onPressed: () => Navigator.pop(context),
        ),
        const Spacer(),
        Column(
          children: [
            const Text(
              "SAFE NAV",
              style: TextStyle(
                color: _navyPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 2.0,
              ),
            ),
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: _navyPrimary.withValues(alpha: 0.1),
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
        const Spacer(),
        Consumer<AlertProvider>(
          builder: (context, alertProvider, _) {
            return _buildIconButton(
              icon: alertProvider.isVoiceGuidanceEnabled
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
              onPressed: () {
                alertProvider.toggleVoiceGuidance();
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildIconButton({required IconData icon, required VoidCallback onPressed}) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: _navyPrimary),
        onPressed: onPressed,
      ),
    );
  }

  /// --- DIRECTIVE 3: LOGIC VISUALIZATION ---
  Widget _buildLogicStatusIndicator(AppRegion region) {
    final bool isJapan = region == AppRegion.japan;
    final String text = isJapan
        ? "JAPAN MODE: Road Width Priority (Blockage Avoidance)"
        : "THAI MODE: Avoid Electric Shock Risk";
    final IconData icon = isJapan ? Icons.add_road : Icons.flash_off;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: _screenPadding, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _navyPrimary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _navyPrimary.withValues(alpha: 0.1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: _navyPrimary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: _navyPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDestinationPanel() {
    return Consumer3<LocationProvider, ShelterProvider, CompassProvider>(
      builder: (context, locationProvider, shelterProvider, compassProvider, _) {
        final target = shelterProvider.navTarget;
        final currentLocation = locationProvider.currentLocation;

        if (currentLocation == null) {
          return _buildInfoCard(
            title: AppLocalizations.t('loc_acquiring'),
            icon: Icons.location_searching,
            isLoading: true,
          );
        }

        if (target == null) {
          return _buildInfoCard(
            title: AppLocalizations.t('loc_no_destination'),
            subtitle: AppLocalizations.t('loc_select_in_chat'),
            icon: Icons.flag_outlined,
          );
        }

        double distance;
        String modeText = "DIRECT";
        
        // --- DIRECTIVE 2: WAYPOINT NAV ---
        if (compassProvider.isSafeNavigating) {
          distance = compassProvider.remainingDistance;
          modeText = "WAYPOINT NAV";
        } else {
          final cachedDist = shelterProvider.getDistanceToTargetIfCached(target);
          if (cachedDist != null) {
            distance = cachedDist;
            modeText = "CACHED ROUTE";
          } else {
            distance = -1.0;
          }
        }

        final distanceText = distance < 0
            ? 'Calculating...'
            : distance < 1000
                ? '${distance.toStringAsFixed(0)}m'
                : '${(distance / 1000).toStringAsFixed(1)}km';

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: _navyPrimary.withValues(alpha: 0.08),
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
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _orangeAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.flag_rounded, color: _orangeAccent),
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
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.0,
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
                  _buildStat("DISTANCE", distanceText),
                  _buildStat("MODE", modeText),
                  _buildStat("ETA", distance < 0 ? "--" : "${(distance / 60).ceil()} min"),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoCard({required String title, String? subtitle, required IconData icon, bool isLoading = false}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
                if (subtitle != null) Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey[400])),
              ],
            ),
          ),
          if (isLoading) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[400], fontSize: 10, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(color: _navyPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildCompassArea() {
    return Consumer3<CompassProvider, LocationProvider, ShelterProvider>(
      builder: (context, compassProvider, locationProvider, shelterProvider, _) {
        final target = shelterProvider.navTarget;
        final currentLocation = locationProvider.currentLocation;
        
        final region = shelterProvider.currentAppRegion;
        if (compassProvider.currentGeoRegion.code != (region == AppRegion.japan ? 'jp_osaki' : 'th_satun')) {
           Future.microtask(() {
             compassProvider.setGeoRegion(region == AppRegion.japan ? GeoRegion.jpOsaki : GeoRegion.thSatun);
           });
        }

        double? safeBearing;
        if (compassProvider.isNavigating && compassProvider.magnetResult != null) {
          safeBearing = compassProvider.magnetResult!.bearingToTarget;
        } else if (target != null && currentLocation != null) {
          safeBearing = Geolocator.bearingBetween(
            currentLocation.latitude, currentLocation.longitude,
            target.lat, target.lng,
          );
        }

        Color? overlayColor;
        if (currentLocation != null) {
           final heading = compassProvider.trueHeading ?? 0.0;
           final riskInfo = shelterProvider.getRoadRiskInDirection(currentLocation, heading);
           
           if (riskInfo != null && riskInfo['isSafe'] == false) {
             overlayColor = Colors.red.withValues(alpha: 0.1);
           } else if (compassProvider.isSafeNavigating && safeBearing != null) {
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
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: overlayColor,
                  boxShadow: [BoxShadow(color: overlayColor!, blurRadius: 60, spreadRadius: 20)],
                ),
                width: 280, height: 280,
              ),
            
            SmartCompass(
              heading: compassProvider.trueHeading ?? compassProvider.heading ?? 0.0,
              safeBearing: safeBearing,
              dangerBearings: const [],
              size: 260,
            ),

            if (!compassProvider.hasSensorData && !_dismissPermissionBanner)
              _buildPermissionRequest(),
          ],
        );
      },
    );
  }

  Widget _buildPermissionRequest() {
    return Positioned.fill(
      child: Container(
        color: Colors.white.withValues(alpha: 0.9),
        child: Center(
          child: GestureDetector(
            onTap: () async {
              final result = await requestIOSCompassPermission();
              if (result == 'granted' || result == 'not_supported') {
                setState(() => _dismissPermissionBanner = true);
              }
            },
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _navyPrimary,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Text("Tap to Enable Compass", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDestinationButtons() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: _screenPadding),
      child: Row(
        children: [
          _buildChip(Icons.water_drop_rounded, 'Water', 'water'),
          const SizedBox(width: 12),
          _buildChip(Icons.local_hospital_rounded, 'Hospital', 'hospital'),
          const SizedBox(width: 12),
          _buildChip(Icons.store_rounded, 'Store', 'convenience'),
          const SizedBox(width: 12),
          _buildChip(Icons.home_rounded, 'Shelter', 'shelter'),
        ],
      ),
    );
  }

  Widget _buildChip(IconData icon, String label, String type) {
    return GestureDetector(
      onTap: () => _findAndStartNavigation(type, typeLabel: label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: _navyPrimary),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: _navyPrimary, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  // --- DIRECTIVE 1: UI BUTTON SPECS ---
  Widget _buildArrivalButton() {
    return SizedBox(
      width: double.infinity,
      height: _btnHeight, // Directive: Height 56.0
      child: ElevatedButton(
        onPressed: () => _confirmArrival(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: _navyPrimary, // Directive: Navy
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_btnRadius), // Directive: Radius 30.0
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline_rounded),
            const SizedBox(width: 12),
            Text(
              AppLocalizations.t('btn_arrived_label'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.0),
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

    // Try starting from cache first
    if (shelterProvider.startCachedNavigation(type)) {
      final nearest = shelterProvider.navTarget!;
      final safeRoute = shelterProvider.getSafestRouteAsLatLng();
      if (safeRoute.isNotEmpty) {
        // --- DIRECTIVE 2: START WAYPOINT NAV ---
        context.read<CompassProvider>().startRouteNavigation(safeRoute);
        HapticService.destinationSet();
        _showSnackBar("Navigating to ${nearest.name}", _navyPrimary);
        return;
      }
    }

    // Fallback: search and calculate
    List<String> types = [type];
    if (type == 'water') types = ['water', 'convenience', 'store'];
    
    final nearest = shelterProvider.getNearestShelter(userLoc, includeTypes: types);
    
    if (nearest != null) {
      await shelterProvider.startNavigation(nearest, currentLocation: userLoc);
      final safeRoute = shelterProvider.getSafestRouteAsLatLng();
      if (safeRoute.isNotEmpty) {
        // --- DIRECTIVE 2: START WAYPOINT NAV ---
        context.read<CompassProvider>().startRouteNavigation(safeRoute);
      }
      HapticService.destinationSet();
      _showSnackBar("Calculated Safe Route to ${nearest.name}", _navyPrimary);
    } else {
      _showSnackBar("No facilities found nearby", Colors.grey);
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

  void _confirmArrival(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(AppLocalizations.t('dialog_safety_title'), style: const TextStyle(color: _navyPrimary, fontWeight: FontWeight.bold)),
        content: Text(AppLocalizations.t('dialog_safety_desc')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.t('btn_cancel'))),
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