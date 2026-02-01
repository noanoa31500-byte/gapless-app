import 'dart:ui';
import 'dart:async';
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
import '../services/compass_permission_service.dart';
import '../services/magnetic_declination_config.dart';
import 'shelter_dashboard_screen.dart';
import '../models/shelter.dart';

/// ============================================================================
/// DisasterCompassScreen - Navy/Orange Design System
/// ============================================================================
/// 
/// UI Directive: Navy Primary (#1A237E) + Orange Accent (#FF6F00)
/// Dimensional Constraints: BorderRadius 30.0, Height 56.0, Padding 24.0
/// Navigation: Waypoint-based routing with region-specific hazard logic
/// 
/// Region Logic:
/// - Japan (Osaki): Earthquake + Road Width Priority
/// - Thailand (Satun): Flood + Electric Shock Avoidance
class DisasterCompassScreen extends StatefulWidget {
  const DisasterCompassScreen({super.key});

  @override
  State<DisasterCompassScreen> createState() => _DisasterCompassScreenState();
}

class _DisasterCompassScreenState extends State<DisasterCompassScreen> {
  // UI Constants - Navy/Orange Palette
  static const Color _navyPrimary = Color(0xFF1A237E);
  static const Color _orangeAccent = Color(0xFFFF6F00);
  static const Color _navySecondary = Color(0xFF283593);
  static const Color _safetyGreen = Color(0xFF4CAF50);
  static const Color _dangerRed = Color(0xFFD32F2F);
  
  // Dimensional Constraints
  static const double _borderRadius = 30.0;
  static const double _targetHeight = 56.0;
  static const double _basePadding = 24.0;

  Timer? _voiceTimer;
  double? _lastSpokenDistance;
  bool _dismissPermissionBanner = false;

  @override
  void initState() {
    super.initState();
    
    _voiceTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _speakNavigationUpdate();
    });
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryStartAutoNavigation();
      _speakNavigationUpdate();
      
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
  
  @override
  void dispose() {
    _voiceTimer?.cancel();
    final locProvider = context.read<LocationProvider>();
    locProvider.removeListener(_onLocationChanged);
    super.dispose();
  }
  
  void _speakNavigationUpdate() {
    if (!mounted) return;
    final provider = context.read<ShelterProvider>();
    final location = context.read<LocationProvider>().currentLocation;
    final alert = context.read<AlertProvider>();
    final compass = context.read<CompassProvider>();
    
    final target = provider.navTarget;
    if (target == null || location == null) return;
    
    double distance;
    if (compass.isSafeNavigating) {
      distance = compass.remainingDistance;
    } else {
      final cached = provider.getDistanceToTargetIfCached(target);
      if (cached != null) {
        distance = cached;
      } else {
        return;
      }
    }
    
    if (_lastSpokenDistance != null && (distance - _lastSpokenDistance!).abs() < 50) {
      return;
    }
    _lastSpokenDistance = distance;
    
    final bearing = Geolocator.bearingBetween(
      location.latitude, location.longitude, target.lat, target.lng,
    );
    final direction = _getDirectionText(bearing);
    alert.speakNavigation(distance, direction);
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
    final regionMode = shelterProvider.currentAppRegion;

    return Scaffold(
      backgroundColor: _navyPrimary,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(regionMode),
            _buildDestinationPanel(),
            Expanded(child: _buildCompassArea()),
            _buildDestinationButtons(),
            _buildArrivalButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AppRegion region) {
    final isJapan = region == AppRegion.japan;
    final hazardText = isJapan 
        ? AppLocalizations.t('hazard_earthquake') 
        : AppLocalizations.t('hazard_flood');
    
    return Container(
      padding: const EdgeInsets.all(_basePadding),
      decoration: BoxDecoration(
        color: _navyPrimary,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildHeaderButton(
            icon: Icons.close_rounded,
            onPressed: () => Navigator.pop(context),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: _navySecondary,
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: _orangeAccent, width: 2),
            ),
            child: Row(
              children: [
                Icon(
                  isJapan ? Icons.warning_amber_rounded : Icons.water_drop,
                  color: _orangeAccent,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  hazardText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    fontFamily: 'NotoSansJP',
                  ),
                ),
              ],
            ),
          ),
          Consumer<AlertProvider>(
            builder: (context, alert, _) {
              return _buildHeaderButton(
                icon: alert.isVoiceGuidanceEnabled 
                    ? Icons.volume_up_rounded 
                    : Icons.volume_off_rounded,
                onPressed: () {
                  alert.toggleVoiceGuidance();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        alert.isVoiceGuidanceEnabled ? 'Voice ON' : 'Voice OFF',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: _orangeAccent,
                      duration: const Duration(milliseconds: 800),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(_borderRadius),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: _navySecondary,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }

  Widget _buildDestinationPanel() {
    return Consumer3<LocationProvider, ShelterProvider, CompassProvider>(
      builder: (context, location, shelter, compass, _) {
        final target = shelter.navTarget;
        final currentLoc = location.currentLocation;

        if (target == null) {
          return _buildInfoCard(
            title: AppLocalizations.t('loc_no_destination'),
            subtitle: AppLocalizations.t('loc_select_in_chat'),
            icon: Icons.flag_rounded,
            isActive: false,
          );
        }

        double distance;
        if (compass.isSafeNavigating) {
          distance = compass.remainingDistance;
        } else {
          distance = -1.0;
          if (!shelter.isRoutingLoading && currentLoc != null) {
            Future.microtask(() => shelter.calculateSafestRoute(
              LatLng(currentLoc.latitude, currentLoc.longitude),
              LatLng(target.lat, target.lng),
              target: target
            ));
          }
        }

        final distText = distance < 0 
            ? 'Calculating...' 
            : distance < 1000 
                ? '${distance.toStringAsFixed(0)}m' 
                : '${(distance / 1000).toStringAsFixed(1)}km';

        return _buildInfoCard(
          title: target.name,
          subtitle: 'WAYPOINT: $distText',
          icon: Icons.directions_run,
          isActive: true,
        );
      },
    );
  }

  Widget _buildInfoCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isActive,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_basePadding, 16, _basePadding, 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(_basePadding),
        decoration: BoxDecoration(
          color: isActive ? _navySecondary : _navyPrimary.withOpacity(0.5),
          borderRadius: BorderRadius.circular(_borderRadius),
          border: Border.all(
            color: isActive ? _orangeAccent : Colors.white.withOpacity(0.3),
            width: isActive ? 3 : 1.5,
          ),
          boxShadow: isActive ? [
            BoxShadow(
              color: _orangeAccent.withOpacity(0.3),
              blurRadius: 16,
              spreadRadius: 2,
            )
          ] : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isActive ? _orangeAccent : Colors.grey.shade700,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isActive 
                          ? _orangeAccent.withOpacity(0.9)
                          : Colors.white.withOpacity(0.7),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
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

  Widget _buildCompassArea() {
    return Consumer3<CompassProvider, LocationProvider, ShelterProvider>(
      builder: (context, compass, location, shelter, _) {
        final target = shelter.navTarget;
        final currentLoc = location.currentLocation;
        final heading = compass.trueHeading ?? compass.heading ?? 0.0;
        final region = shelter.currentAppRegion;

        if (compass.currentGeoRegion.code != (region == AppRegion.japan ? 'jp_osaki' : 'th_satun')) {
          Future.microtask(() => compass.setGeoRegion(
            region == AppRegion.japan ? GeoRegion.jpOsaki : GeoRegion.thSatun
          ));
        }

        double? safeBearing;
        if (compass.isNavigating && compass.magnetResult != null) {
          safeBearing = compass.magnetResult!.bearingToTarget;
        } else if (target != null && currentLoc != null) {
          safeBearing = Geolocator.bearingBetween(
            currentLoc.latitude, currentLoc.longitude, target.lat, target.lng
          );
        }

        List<double> dangerBearings = [];
        if (currentLoc != null) {
          for (final point in shelter.hazardPoints) {
            final d = Geolocator.distanceBetween(
              currentLoc.latitude, currentLoc.longitude, 
              point['lat'], point['lng']
            );
            if (d < 100) {
              dangerBearings.add(Geolocator.bearingBetween(
                currentLoc.latitude, currentLoc.longitude, 
                point['lat'], point['lng']
              ));
            }
          }
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    _navySecondary.withOpacity(0.3),
                    _navyPrimary.withOpacity(0.1),
                  ],
                ),
              ),
              width: 320,
              height: 320,
            ),
            
            SmartCompass(
              heading: heading,
              safeBearing: safeBearing,
              dangerBearings: dangerBearings,
              size: 280,
              safeThreshold: 30.0,
            ),
            
            Positioned(
              bottom: 30,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: _navySecondary.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(25),
                  border: Border.all(color: _orangeAccent.withOpacity(0.5), width: 1.5),
                ),
                child: Text(
                  region == AppRegion.japan 
                      ? "JAPAN MODE: Road Width Priority" 
                      : "THAI MODE: Avoid Electric Shock",
                  style: const TextStyle(
                    color: Colors.white, 
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            if (!compass.hasSensorData && !_dismissPermissionBanner)
              _buildPermissionOverlay(compass),
          ],
        );
      },
    );
  }

  Widget _buildPermissionOverlay(CompassProvider compass) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.85),
        child: Center(
          child: GestureDetector(
            onTap: () async {
              final res = await requestIOSCompassPermission();
              if (res == 'granted' || res == 'not_supported') {
                setState(() => _dismissPermissionBanner = true);
                compass.stopListening();
                compass.startListening();
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (mounted) _tryStartAutoNavigation();
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.all(_basePadding),
              decoration: BoxDecoration(
                color: _orangeAccent,
                borderRadius: BorderRadius.circular(_borderRadius),
                boxShadow: [
                  BoxShadow(
                    color: _orangeAccent.withOpacity(0.5),
                    blurRadius: 24,
                    spreadRadius: 6,
                  )
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.compass_calibration, color: Colors.white, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    'Tap to Start Compass',
                    style: TextStyle(
                      color: Colors.white, 
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Required for iOS Web',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8), 
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDestinationButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: _basePadding, vertical: 12),
      height: 90,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildNavChip('Water', 'water', Icons.water_drop),
            const SizedBox(width: 14),
            _buildNavChip('Hospital', 'hospital', Icons.local_hospital),
            const SizedBox(width: 14),
            _buildNavChip('Store', 'convenience', Icons.store),
            const SizedBox(width: 14),
            _buildNavChip('Shelter', 'shelter', Icons.night_shelter),
          ],
        ),
      ),
    );
  }

  Widget _buildNavChip(String label, String type, IconData icon) {
    return GestureDetector(
      onTap: () => _findAndStartNavigation(type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
        decoration: BoxDecoration(
          color: _navySecondary,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: Colors.white.withOpacity(0.3), width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: _orangeAccent, size: 22),
            const SizedBox(width: 10),
            Text(
              label, 
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildArrivalButton() {
    return Padding(
      padding: const EdgeInsets.all(_basePadding),
      child: SizedBox(
        width: double.infinity,
        height: _targetHeight,
        child: ElevatedButton(
          onPressed: _confirmArrival,
          style: ElevatedButton.styleFrom(
            backgroundColor: _orangeAccent,
            foregroundColor: Colors.white,
            elevation: 8,
            shadowColor: _orangeAccent.withOpacity(0.5),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_borderRadius),
            ),
          ),
          child: const Text(
            'I HAVE ARRIVED',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _findAndStartNavigation(String type, {String? typeLabel}) async {
    final shelter = context.read<ShelterProvider>();
    final loc = context.read<LocationProvider>().currentLocation;
    
    if (loc == null) return;

    if (shelter.startCachedNavigation(type)) {
      final route = shelter.getSafestRouteAsLatLng();
      if (route.isNotEmpty) {
        context.read<CompassProvider>().startRouteNavigation(route);
        HapticService.destinationSet();
        return;
      }
    }

    List<String> types = [type];
    if (type == 'water') types = ['water', 'convenience', 'store'];
    if (type == 'shelter') types = ['shelter', 'school', 'gov', 'community_centre'];
    
    Shelter? nearest;
    if (shelter.currentAppRegion == AppRegion.thailand && type == 'water') {
      final ws = shelter.getNearestSafeWaterStation(LatLng(loc.latitude, loc.longitude));
      if (ws != null) {
        nearest = Shelter(
          id: 'ws_${ws.lat}', 
          name: ws.nameEn, 
          lat: ws.lat, 
          lng: ws.lng, 
          type: 'water', 
          verified: true
        );
      }
    }
    
    if (nearest == null) {
      nearest = shelter.getNearestShelter(
        LatLng(loc.latitude, loc.longitude), 
        includeTypes: types
      );
    }

    if (nearest != null) {
      if (shelter.isShelterInHazardZone(nearest)) {
        final safe = shelter.getNearestSafeShelter(LatLng(loc.latitude, loc.longitude));
        if (safe != null) nearest = safe;
      }

      await shelter.startNavigation(nearest, currentLocation: LatLng(loc.latitude, loc.longitude));
      
      final routePoints = shelter.getSafestRouteAsLatLng();
      if (routePoints.isNotEmpty) {
        context.read<CompassProvider>().startRouteNavigation(routePoints);
      }
      
      HapticService.destinationSet();
    }
  }

  void _confirmArrival() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _navyPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_borderRadius)),
        title: const Text('Safety Check', style: TextStyle(color: Colors.white, fontSize: 20)),
        content: const Text(
          'Are you safe inside the shelter?', 
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _safetyGreen,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<ShelterProvider>().setSafeInShelter(true);
              Navigator.pushReplacement(
                context, 
                MaterialPageRoute(builder: (_) => const ShelterDashboardScreen())
              );
            },
            child: const Text(
              'Yes, I am Safe', 
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}