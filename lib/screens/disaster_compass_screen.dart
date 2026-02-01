import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/foundation.dart';

import '../providers/compass_provider.dart';
import '../providers/shelter_provider.dart';
import '../providers/location_provider.dart';
import '../providers/alert_provider.dart';
import '../providers/region_mode_provider.dart';
import '../utils/localization.dart';
import '../widgets/smart_compass.dart';
import '../services/haptic_service.dart';
import '../services/waypoint_magnet_manager.dart';
import '../models/shelter.dart';
import '../services/compass_permission_service.dart';
import '../services/magnetic_declination_config.dart';

/// ============================================================================
/// DisasterCompassScreen (Navy/Orange UI + Waypoint Navigation)
/// ============================================================================
/// 
/// DIRECTIVES IMPLEMENTATION:
/// 1. UI: Navy (#1A237E) & Orange (#FF6F00) palette.
///    - BorderRadius: 30.0
///    - Button Height: 56.0
///    - Padding: 24.0+
/// 2. NAV: Visualizes Waypoint-based navigation (Next Waypoint Distance/Direction).
/// 3. LOGIC: Displays active logic based on region:
///    - Japan: "Prioritizing Road Width"
///    - Thailand: "Avoiding Electric Shock Risk"
class DisasterCompassScreen extends StatefulWidget {
  const DisasterCompassScreen({super.key});

  @override
  State<DisasterCompassScreen> createState() => _DisasterCompassScreenState();
}

class _DisasterCompassScreenState extends State<DisasterCompassScreen> {
  // UI Constants (Directive 1)
  static const Color _navyPrimary = Color(0xFF1A237E);
  static const Color _orangeAccent = Color(0xFFFF6F00);
  static const Color _surfaceWhite = Colors.white;
  static const double _borderRadius = 30.0;
  static const double _elementHeight = 56.0;
  static const double _standardPadding = 24.0;

  Timer? _statusUpdateTimer;
  Timer? _voiceTimer;
  double? _lastSpokenDistance;
  bool _dismissPermissionBanner = false;

  @override
  void initState() {
    super.initState();
    
    // Periodic UI refresh for smooth updates
    _statusUpdateTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });

    // Voice guidance timer (every 15 seconds)
    _voiceTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _speakNavigationUpdate();
    });

    // Auto-start navigation if target exists
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryStartAutoNavigation();
      _speakNavigationUpdate();

      // Background route caching
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

    if (target != null && userLoc != null && compassProvider.heading != null) {
      _findAndStartNavigation(target.type, typeLabel: target.name);
    }
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
        if (!shelterProvider.isRoutingLoading) {
          Future.microtask(() {
            shelterProvider.calculateSafestRoute(
              LatLng(currentLocation.latitude, currentLocation.longitude),
              LatLng(target.lat, target.lng),
              target: target
            );
          });
        }
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

    if (normalizedBearing >= 337.5 || normalizedBearing < 22.5) {
      return AppLocalizations.t('dir_north');
    } else if (normalizedBearing >= 22.5 && normalizedBearing < 67.5) {
      return AppLocalizations.t('dir_northeast');
    } else if (normalizedBearing >= 67.5 && normalizedBearing < 112.5) {
      return AppLocalizations.t('dir_east');
    } else if (normalizedBearing >= 112.5 && normalizedBearing < 157.5) {
      return AppLocalizations.t('dir_southeast');
    } else if (normalizedBearing >= 157.5 && normalizedBearing < 202.5) {
      return AppLocalizations.t('dir_south');
    } else if (normalizedBearing >= 202.5 && normalizedBearing < 247.5) {
      return AppLocalizations.t('dir_southwest');
    } else if (normalizedBearing >= 247.5 && normalizedBearing < 292.5) {
      return AppLocalizations.t('dir_west');
    } else {
      return AppLocalizations.t('dir_northwest');
    }
  }

  @override
  void dispose() {
    _statusUpdateTimer?.cancel();
    _voiceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shelterProvider = context.watch<ShelterProvider>();
    final compassProvider = context.watch<CompassProvider>();
    final locationProvider = context.watch<LocationProvider>();

    // Directive 3: Determine Logic Text based on Region
    final isJapan = shelterProvider.currentAppRegion == AppRegion.japan;
    final logicText = isJapan
        ? "🛣️ ROAD WIDTH PRIORITY (JAPAN)"
        : "⚡ AVOID ELECTRIC RISK (THAILAND)";
    final logicSubText = isJapan
        ? "Selecting wide roads to avoid blockage."
        : "Scanning for submerged power lines.";

    return Scaffold(
      backgroundColor: _navyPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header Area
            Padding(
              padding: const EdgeInsets.all(_standardPadding),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildIconButton(
                    icon: Icons.close,
                    onPressed: () => Navigator.pop(context),
                  ),
                  Column(
                    children: [
                      const Text(
                        "DISASTER NAV",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: _orangeAccent.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _orangeAccent, width: 1),
                        ),
                        child: Text(
                          isJapan ? "EARTHQUAKE MODE" : "FLOOD MODE",
                          style: const TextStyle(
                            color: _orangeAccent,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  _buildIconButton(
                    icon: Icons.settings,
                    onPressed: () {},
                  ),
                ],
              ),
            ),

            // Main Compass Area
            Expanded(
              child: Center(
                child: _buildCompassView(
                  compassProvider,
                  locationProvider,
                  shelterProvider
                ),
              ),
            ),

            // Status & Logic Panel (Directive 1 & 3)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(_standardPadding),
              decoration: const BoxDecoration(
                color: _surfaceWhite,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(_borderRadius),
                  topRight: Radius.circular(_borderRadius),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Logic Indicator
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _navyPrimary.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _navyPrimary.withOpacity(0.1)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isJapan ? Icons.add_road : Icons.electrical_services,
                          color: _navyPrimary,
                          size: 32,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                logicText,
                                style: const TextStyle(
                                  color: _navyPrimary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                logicSubText,
                                style: TextStyle(
                                  color: _navyPrimary.withOpacity(0.7),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: _standardPadding),

                  // Waypoint Status (Directive 2)
                  _buildWaypointStatus(compassProvider),

                  const SizedBox(height: _standardPadding),

                  // Destination Buttons
                  _buildDestinationButtons(),

                  const SizedBox(height: 12),

                  // Primary Action Button (Directive 1)
                  SizedBox(
                    width: double.infinity,
                    height: _elementHeight,
                    child: ElevatedButton(
                      onPressed: () => _handleArrival(context, shelterProvider),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _orangeAccent,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(_borderRadius),
                        ),
                      ),
                      child: const Text(
                        "I HAVE ARRIVED / 到着",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton({required IconData icon, required VoidCallback onPressed}) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: Colors.white),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildCompassView(
    CompassProvider compass,
    LocationProvider location,
    ShelterProvider shelter,
  ) {
    final target = shelter.navTarget;
    final currentLocation = location.currentLocation;
    final heading = compass.trueHeading ?? compass.heading ?? 0.0;

    // Region sync
    final region = shelter.currentRegion;
    if (compass.currentGeoRegion.code != region) {
      Future.microtask(() {
        if (region.startsWith('th')) {
          compass.setGeoRegion(GeoRegion.thSatun);
        } else {
          compass.setGeoRegion(GeoRegion.jpOsaki);
        }
      });
    }

    // Directive 2: Target Bearing (Waypoints)
    double? targetBearing;
    if (compass.isNavigating && compass.magnetResult != null) {
      targetBearing = compass.magnetResult!.bearingToTarget;
    } else if (target != null && currentLocation != null) {
      targetBearing = Geolocator.bearingBetween(
        currentLocation.latitude,
        currentLocation.longitude,
        target.lat,
        target.lng,
      );
    }

    // Danger bearings
    List<double> hazards = [];
    if (currentLocation != null) {
      for (final point in shelter.hazardPoints) {
        final lat = point['lat'] as double?;
        final lng = point['lng'] as double?;
        if (lat != null && lng != null) {
          final bearing = Geolocator.bearingBetween(
            currentLocation.latitude,
            currentLocation.longitude,
            lat,
            lng,
          );
          hazards.add(bearing);
        }
      }

      for (final polygon in shelter.hazardPolygons) {
        if (polygon.isNotEmpty) {
          double avgLat = 0, avgLng = 0;
          for (final point in polygon) {
            avgLat += point.latitude;
            avgLng += point.longitude;
          }
          avgLat /= polygon.length;
          avgLng /= polygon.length;

          final distanceToHazard = Geolocator.distanceBetween(
            currentLocation.latitude,
            currentLocation.longitude,
            avgLat,
            avgLng,
          );

          if (distanceToHazard < 1000.0) {
            final bearing = Geolocator.bearingBetween(
              currentLocation.latitude,
              currentLocation.longitude,
              avgLat,
              avgLng,
            );
            hazards.add(bearing);
          }
        }
      }
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        // Pulsing Ring
        Container(
          width: 300,
          height: 300,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withOpacity(0.1),
              width: 1,
            ),
          ),
        ),
        
        // Smart Compass
        SmartCompass(
          heading: heading,
          safeBearing: targetBearing,
          dangerBearings: hazards,
          magneticDeclination: 0.0,
          size: 260,
          safeThreshold: 30.0,
          dangerThreshold: 15.0,
        ),

        // iOS Web Permission Overlay
        if (!compass.hasSensorData && !_dismissPermissionBanner)
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.6),
              child: Center(
                child: GestureDetector(
                  onTap: () async {
                    final result = await requestIOSCompassPermission();
                    if (!mounted) return;

                    if (result == 'granted' || result == 'not_supported') {
                      setState(() => _dismissPermissionBanner = true);
                      compass.stopListening();
                      compass.startListening();
                      Future.delayed(const Duration(milliseconds: 500), () {
                        if (mounted) _tryStartAutoNavigation();
                      });
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Compass permission $result. Please enable in settings.'),
                          backgroundColor: _orangeAccent,
                        ),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: _orangeAccent,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: _orangeAccent.withOpacity(0.4),
                          blurRadius: 20,
                          spreadRadius: 4,
                        )
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.compass_calibration, color: Colors.white, size: 40),
                        const SizedBox(height: 12),
                        const Text(
                          'Tap to Start Compass',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Required for iOS Web',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWaypointStatus(CompassProvider compass) {
    if (!compass.isNavigating || compass.magnetResult == null) {
      return const SizedBox(
        height: 60,
        child: Center(
          child: Text(
            "WAITING FOR DESTINATION...",
            style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    final result = compass.magnetResult!;
    final dist = result.distanceToTarget;
    final total = result.totalWaypoints;
    final current = result.currentWaypointIndex + 1;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "NEXT WAYPOINT",
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                dist < 1000
                    ? "${dist.toStringAsFixed(0)}m"
                    : "${(dist / 1000).toStringAsFixed(2)}km",
                style: const TextStyle(
                  color: _navyPrimary,
                  fontSize: 32,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _orangeAccent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              const Text(
                "WP PROGRESS",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                "$current / $total",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDestinationButtons() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildDestinationChip(
            icon: Icons.water_drop_rounded,
            label: _getLocalizedLabel('water'),
            type: 'water',
          ),
          const SizedBox(width: 10),
          _buildDestinationChip(
            icon: Icons.local_hospital_rounded,
            label: _getLocalizedLabel('hospital'),
            type: 'hospital',
          ),
          const SizedBox(width: 10),
          _buildDestinationChip(
            icon: Icons.store_rounded,
            label: _getLocalizedLabel('convenience'),
            type: 'convenience',
          ),
          const SizedBox(width: 10),
          _buildDestinationChip(
            icon: Icons.home_rounded,
            label: _getLocalizedLabel('shelter'),
            type: 'shelter',
          ),
        ],
      ),
    );
  }

  String _getLocalizedLabel(String type) {
    return AppLocalizations.translateShelterType(type);
  }

  Widget _buildDestinationChip({
    required IconData icon,
    required String label,
    required String type,
  }) {
    return GestureDetector(
      onTap: () => _findAndStartNavigation(type, typeLabel: label),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _navyPrimary.withOpacity(0.2),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _navyPrimary.withOpacity(0.3),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: _navyPrimary, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: _navyPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
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
      _showSnackBar(AppLocalizations.t('bot_loc_error'), _orangeAccent);
      return;
    }

    // Flash Cache Check
    if (shelterProvider.startCachedNavigation(type)) {
      final nearest = shelterProvider.navTarget!;
      final safeRoute = shelterProvider.getSafestRouteAsLatLng();

      if (safeRoute.isNotEmpty) {
        final compassProvider = context.read<CompassProvider>();
        compassProvider.startRouteNavigation(safeRoute);

        if (kDebugMode) print('⚡ Instant Start from Cache: $type -> ${nearest.name}');

        HapticService.destinationSet();
        final alertProvider = context.read<AlertProvider>();
        final tagLabel = typeLabel ?? AppLocalizations.translateShelterType(type);
        alertProvider.speakDestinationSet(tagLabel);
        _lastSpokenDistance = null;

        _showSnackBar(
          AppLocalizations.t('bot_dest_set').replaceAll('@name', nearest.name),
          Colors.green,
        );
        return;
      }
    }

    // Type Mapping
    List<String> targetTypes = [type];
    if (type == 'shelter') {
      targetTypes = ['shelter', 'school', 'gov', 'community_centre', 'temple'];
    } else if (type == 'hospital') {
      targetTypes = ['hospital'];
    } else if (type == 'convenience') {
      targetTypes = ['convenience', 'store'];
    } else if (type == 'water') {
      targetTypes = ['water', 'convenience', 'store'];
    }

    Shelter? nearest;

    if (type == 'water' && (shelterProvider.currentRegion.toLowerCase().contains('th') || shelterProvider.currentRegion.toLowerCase().contains('satun'))) {
      final waterStation = shelterProvider.getNearestSafeWaterStation(LatLng(userLoc.latitude, userLoc.longitude));
      if (waterStation != null) {
        nearest = Shelter(
          id: 'water_${waterStation.lat}_${waterStation.lng}',
          name: waterStation.getDisplayName(AppLocalizations.lang),
          lat: waterStation.lat,
          lng: waterStation.lng,
          type: 'water_station',
          verified: true,
          region: 'Thailand',
        );
      }
    }

    if (nearest == null) {
      nearest = shelterProvider.getNearestShelter(
        LatLng(userLoc.latitude, userLoc.longitude),
        includeTypes: targetTypes,
      );
    }

    if (nearest != null) {
      if (nearest.name.toLowerCase() == 'unknown' || nearest.name == '不明') {
        _showSnackBar(AppLocalizations.t('msg_unknown_location'), _orangeAccent);
        return;
      }

      final isInHazard = shelterProvider.isShelterInHazardZone(nearest);
      if (isInHazard) {
        final safeShelter = shelterProvider.getNearestSafeShelter(
          LatLng(userLoc.latitude, userLoc.longitude),
        );
        if (safeShelter != null) {
          nearest = safeShelter;
          _showSnackBar(
            AppLocalizations.t('msg_safer_location').replaceAll('@name', nearest.name),
            _orangeAccent,
          );
        }
      }

      final currentLatLng = LatLng(userLoc.latitude, userLoc.longitude);
      await shelterProvider.startNavigation(nearest, currentLocation: currentLatLng);

      final compassProvider = context.read<CompassProvider>();
      final safeRoute = shelterProvider.getSafestRouteAsLatLng();

      if (safeRoute.isNotEmpty) {
        compassProvider.startRouteNavigation(safeRoute);
        if (kDebugMode) {
          print('🧭 安全ルートでコンパスナビゲーション開始: ${safeRoute.length}ポイント');
        }
      } else {
        if (kDebugMode) {
          print('⚠️ 安全ルートが見つかりませんでした');
        }
      }

      HapticService.destinationSet();
      final alertProvider = context.read<AlertProvider>();
      final tagLabel = typeLabel ?? AppLocalizations.translateShelterType(type);
      alertProvider.speakDestinationSet(tagLabel);
      _lastSpokenDistance = null;

      _showSnackBar(
        AppLocalizations.t('bot_dest_set').replaceAll('@name', nearest.name),
        Colors.green,
      );
    } else {
      _showSnackBar(AppLocalizations.t('msg_no_facility_nearby'), Colors.grey);
    }
  }

  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _handleArrival(BuildContext context, ShelterProvider provider) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _navyPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          AppLocalizations.t('dialog_safety_title'),
          style: const TextStyle(color: Colors.white),
        ),
        content: Text(
          AppLocalizations.t('dialog_safety_desc'),
          style: TextStyle(
            color: Colors.white.withOpacity(0.8),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              AppLocalizations.t('btn_cancel'),
              style: const TextStyle(
                color: _orangeAccent,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              HapticService.arrivedAtDestination();
              Navigator.pop(ctx);
              provider.setSafeInShelter(true);
              Navigator.pushReplacementNamed(context, '/dashboard');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _orangeAccent,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              AppLocalizations.t('btn_yes_arrived'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}