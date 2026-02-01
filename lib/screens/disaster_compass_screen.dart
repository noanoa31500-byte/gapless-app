import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

// Providers
import '../providers/compass_provider.dart';
import '../providers/shelter_provider.dart';
import '../providers/location_provider.dart';
import '../providers/alert_provider.dart';
import '../providers/region_mode_provider.dart';

// Utils
import '../utils/localization.dart';
import '../services/haptic_service.dart';
import '../services/compass_permission_service.dart';
import '../services/magnetic_declination_config.dart';

// Widgets
import '../widgets/smart_compass.dart';
import 'shelter_dashboard_screen.dart';
import '../models/shelter.dart';

/// ============================================================================
/// DisasterCompassScreen (Rewrite)
/// ============================================================================
/// 
/// DIRECTIVES IMPLEMENTATION:
/// 1. UI: Navy (#1A237E) / Orange (#FF6F00) Palette.
///        BorderRadius 30.0, Height 56.0, Padding 24.0+.
/// 2. NAV: Visualizes Waypoint-based navigation (Next Waypoint, Progress).
/// 3. LOGIC: Displays active logic mode (Japan=Road Width, Thailand=Anti-Shock).
class DisasterCompassScreen extends StatefulWidget {
  const DisasterCompassScreen({super.key});

  @override
  State<DisasterCompassScreen> createState() => _DisasterCompassScreenState();
}

class _DisasterCompassScreenState extends State<DisasterCompassScreen> {
  // Theme Constants (Directive 1)
  static const Color _navyPrimary = Color(0xFF1A237E);
  static const Color _navyDark = Color(0xFF121858);
  static const Color _orangeAccent = Color(0xFFFF6F00);
  static const double _uiRadius = 30.0;
  static const double _uiHeight = 56.0;
  static const double _uiPadding = 24.0;

  Timer? _voiceTimer;
  bool _dismissPermissionBanner = false;
  double? _lastSpokenDistance;

  @override
  void initState() {
    super.initState();
    
    // Auto-start Navigation Check
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryStartAutoNavigation();
      _startVoiceGuidance();
      
      // Offline Route Caching (Background Update)
      final locProvider = context.read<LocationProvider>();
      locProvider.addListener(_onLocationChanged);
      // Initial Trigger
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
      shelterProvider.startNavigation(target, currentLocation: userLoc);
    }
  }

  void _startVoiceGuidance() {
    _voiceTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _speakNavigationUpdate();
    });
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
    _voiceTimer?.cancel();
    final locProvider = context.read<LocationProvider>();
    locProvider.removeListener(_onLocationChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _navyPrimary,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                _buildWaypointInfo(),
                Expanded(child: _buildCompassArea()),
                _buildDestinationButtons(),
                _buildBottomActions(),
              ],
            ),
            _buildPermissionBanner(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Consumer<ShelterProvider>(
      builder: (context, provider, _) {
        final isJapan = provider.currentAppRegion == AppRegion.japan;
        
        final modeIcon = isJapan ? Icons.directions_car : Icons.electrical_services;
        final modeText = isJapan 
            ? "PRIORITY: ROAD WIDTH (JAPAN)"
            : "MODE: AVOID SHOCK (THAI)";
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: _uiPadding, vertical: 16),
          color: _navyDark,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _orangeAccent.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(modeIcon, color: _orangeAccent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "ACTIVE LOGIC",
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      modeText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWaypointInfo() {
    return Consumer3<CompassProvider, LocationProvider, ShelterProvider>(
      builder: (context, compass, location, shelter, _) {
        final target = shelter.navTarget;
        final result = compass.magnetResult;
        
        if (target == null) {
          return _buildInfoCard(
            title: "NO DESTINATION",
            value: "Select Target",
            isWarning: true,
          );
        }

        final dist = result?.distanceToTarget ?? 0.0;
        final waypointIdx = (result?.currentWaypointIndex ?? 0) + 1;
        final totalWaypoints = result?.totalWaypoints ?? 0;
        
        return Container(
          margin: const EdgeInsets.all(_uiPadding),
          padding: const EdgeInsets.all(_uiPadding),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(_uiRadius),
            border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "NEXT WAYPOINT ($waypointIdx/$totalWaypoints)",
                          style: const TextStyle(color: _orangeAccent, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "${dist.toStringAsFixed(0)}m",
                          style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    result?.isOffRoute == true ? Icons.warning_amber : Icons.turn_sharp_right,
                    color: result?.isOffRoute == true ? Colors.red : Colors.white,
                    size: 40,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: totalWaypoints > 0 ? waypointIdx / totalWaypoints : 0,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                valueColor: const AlwaysStoppedAnimation(_orangeAccent),
              ),
              const SizedBox(height: 8),
              Text(
                "DEST: ${target.name}",
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoCard({required String title, required String value, bool isWarning = false}) {
    return Container(
      margin: const EdgeInsets.all(_uiPadding),
      padding: const EdgeInsets.all(_uiPadding),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(_uiRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: isWarning ? Colors.red : Colors.white54, fontSize: 10)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildCompassArea() {
    return Consumer3<CompassProvider, LocationProvider, ShelterProvider>(
      builder: (context, compass, location, shelter, _) {
        final target = shelter.navTarget;
        final currentLocation = location.currentLocation;
        final heading = compass.trueHeading ?? compass.heading ?? 0.0;
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

        double? safeBearing;
        
        if (compass.isNavigating && compass.magnetResult != null) {
          safeBearing = compass.magnetResult!.bearingToTarget;
        } else if (target != null && currentLocation != null) {
          safeBearing = Geolocator.bearingBetween(
            currentLocation.latitude,
            currentLocation.longitude,
            target.lat,
            target.lng,
          );
        }
        
        List<double> dangerBearings = [];
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
              dangerBearings.add(bearing);
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
                dangerBearings.add(bearing);
              }
            }
          }
        }

        Color? overlayColor;
        
        if (currentLocation != null) {
          final latLng = LatLng(currentLocation.latitude, currentLocation.longitude);
          
          final headingForRisk = compass.trueHeading ?? compass.heading ?? 0.0;
          final riskInfo = shelter.getRoadRiskInDirection(latLng, headingForRisk);
          
          if (riskInfo != null && riskInfo['isSafe'] == false) {
            overlayColor = Colors.red.withValues(alpha: 0.3);
            if (compass.hapticEnabled) {
              // HapticService.heavyImpact();
            }
          } 
          else if (compass.isSafeNavigating && safeBearing != null) {
            double diff = (safeBearing - heading).abs();
            if (diff > 180) diff = 360 - diff;
            
            if (diff < 30) {
              overlayColor = Colors.green.withValues(alpha: 0.15);
            } else {
              overlayColor = null;
            }
          }
          else {
            final roadInfo = shelter.getRoadRiskInDirection(latLng, heading);
            if (roadInfo != null) {
              final isSafe = roadInfo['isSafe'] as bool;
              
              if (!isSafe) {
                overlayColor = Colors.red.withValues(alpha: 0.15);
              } else {
                overlayColor = Colors.green.withValues(alpha: 0.15);
              }
            }
          }
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            if (overlayColor != null)
              TweenAnimationBuilder<Color?>(
                duration: const Duration(milliseconds: 500),
                tween: ColorTween(begin: Colors.transparent, end: overlayColor),
                builder: (context, color, child) {
                  return Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                      boxShadow: [
                        BoxShadow(
                          color: color?.withValues(alpha: 0.6) ?? Colors.transparent,
                          blurRadius: 60,
                          spreadRadius: 30,
                        )
                      ]
                    ),
                    width: 320,
                    height: 320,
                  );
                },
              ),
              
            SmartCompass(
              heading: compass.trueHeading ?? compass.heading ?? 0.0,
              safeBearing: safeBearing,
              dangerBearings: dangerBearings,
              magneticDeclination: 0.0,
              size: 280,
              safeThreshold: 25.0,
              dangerThreshold: 20.0,
            ),
            
            if (!compass.hasSensorData && !_dismissPermissionBanner)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.6),
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
                              backgroundColor: Colors.red,
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
                              color: _orangeAccent.withValues(alpha: 0.4),
                              blurRadius: 20,
                              spreadRadius: 4,
                            )
                          ],
                        ),
                        child: const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.compass_calibration, color: Colors.white, size: 40),
                            SizedBox(height: 12),
                            Text(
                              'Tap to Start Compass',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white, 
                                fontSize: 16,
                                fontWeight: FontWeight.bold
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Required for iOS Web',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white70, 
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
      },
    );
  }

  Widget _buildDestinationButtons() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SingleChildScrollView(
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
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
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

  Widget _buildBottomActions() {
    return Container(
      padding: const EdgeInsets.all(_uiPadding),
      decoration: const BoxDecoration(
        color: _navyDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(_uiRadius)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: _uiHeight,
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _confirmArrival(),
              style: ElevatedButton.styleFrom(
                backgroundColor: _orangeAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_uiRadius),
                ),
                elevation: 4,
              ),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(
                AppLocalizations.t('btn_arrived_label'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: _uiHeight,
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Emergency SOS feature coming soon")),
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white30, width: 2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_uiRadius),
                ),
              ),
              icon: const Icon(Icons.sos),
              label: const Text("EMERGENCY HELP"),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmArrival() {
    HapticService.arrivedAtDestination();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _navyPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_uiRadius)),
        title: const Text("Safety Check", style: TextStyle(color: Colors.white)),
        content: const Text("Have you arrived safely at the shelter?", style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            child: const Text("Cancel", style: TextStyle(color: Colors.white)),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _orangeAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text("Yes, Arrived"),
            onPressed: () {
              Navigator.pop(ctx);
              context.read<ShelterProvider>().setSafeInShelter(true);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const ShelterDashboardScreen()),
              );
            },
          )
        ],
      ),
    );
  }

  Widget _buildPermissionBanner() {
    return Consumer<CompassProvider>(
      builder: (context, compass, _) {
        if (compass.hasSensorData || _dismissPermissionBanner) {
          return const SizedBox.shrink();
        }
        
        return const SizedBox.shrink();
      },
    );
  }

  Future<void> _findAndStartNavigation(String type, {String? typeLabel}) async {
    final shelterProvider = context.read<ShelterProvider>();
    final locationProvider = context.read<LocationProvider>();
    final userLoc = locationProvider.currentLocation;

    if (userLoc == null) {
      _showSnackBar(AppLocalizations.t('bot_loc_error'), Colors.orange);
      return;
    }

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
        _showSnackBar(AppLocalizations.t('msg_unknown_location'), Colors.orange);
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
            Colors.orange,
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
          print('🧭 安全ルートでコンパスナビゲーション開始 (