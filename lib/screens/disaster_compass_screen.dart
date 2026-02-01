import 'dart:async';
import 'dart:math' as math;
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

/// ============================================================================
/// DisasterCompassScreen - Navy/Orange Heavy Duty UI
/// ============================================================================
/// 
/// Directives Implementation:
/// 1. UI: Navy (#1A237E) / Orange (#FF6F00) Palette.
///    - BorderRadius: 30.0
///    - Height: 56.0 (Buttons)
///    - Padding: 24.0+ (Layout)
/// 
/// 2. NAV: Waypoint-based Navigation.
///    - Visualizes the list of waypoints from `safestRoute`.
///    - Shows progress "WP X / Total".
/// 
/// 3. LOGIC: Region Specific Logic Display.
///    - Japan: "Road Width Priority" (Building Collapse Risk)
///    - Thailand: "Avoid Electric Shock" (Flood Risk)
class DisasterCompassScreen extends StatefulWidget {
  const DisasterCompassScreen({super.key});

  @override
  State<DisasterCompassScreen> createState() => _DisasterCompassScreenState();
}

class _DisasterCompassScreenState extends State<DisasterCompassScreen> {
  // Theme Constants (Directive 1)
  static const Color _navyPrimary = Color(0xFF1A237E);
  static const Color _orangeAccent = Color(0xFFFF6F00);
  static const Color _surfaceColor = Color(0xFFF5F7FA);
  static const double _borderRadius = 30.0;
  static const double _buttonHeight = 56.0;
  static const EdgeInsets _contentPadding = EdgeInsets.all(24.0);

  Timer? _voiceTimer;
  double? _lastSpokenDistance;
  bool _dismissPermissionBanner = false;

  @override
  void initState() {
    super.initState();
    
    // Auto-start Navigation logic
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryStartAutoNavigation();
      _updateBackgroundCache();
    });

    // Voice Guidance Loop
    _voiceTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _speakNavigationUpdate();
    });
  }

  void _updateBackgroundCache() {
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
      // Assuming route is already calculated in onboarding/home
      final route = shelterProvider.getSafestRouteAsLatLng();
      if (route.isNotEmpty) {
        compassProvider.startRouteNavigation(route);
      }
    }
  }

  @override
  void dispose() {
    _voiceTimer?.cancel();
    super.dispose();
  }

  void _speakNavigationUpdate() {
    if (!mounted) return;
    final alertProvider = context.read<AlertProvider>();
    final compassProvider = context.read<CompassProvider>();
    
    if (!compassProvider.isNavigating) return;
    
    // Directive 2: Waypoint Nav Logic
    // We rely on the Engine's distance calculation
    final distance = compassProvider.remainingDistance;
    final direction = compassProvider.getDirectionName(); // Localized direction name
    
    if (_lastSpokenDistance != null && (distance - _lastSpokenDistance!).abs() < 50) return;
    _lastSpokenDistance = distance;
    
    alertProvider.speakNavigation(distance, direction);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _surfaceColor,
      appBar: _buildAppBar(),
      body: SafeArea(
        child: Padding(
          padding: _contentPadding, // Directive 1: Padding 24.0+
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Logic & Status Indicator (Directive 3)
              _buildLogicStatusBanner(),
              
              const SizedBox(height: 24),
              
              // 2. Main Compass & Navigation Info
              Expanded(
                child: _buildCompassSection(),
              ),
              
              const SizedBox(height: 24),
              
              // 3. Action Buttons (Directive 1: Height 56, Radius 30)
              _buildActionButtons(),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _navyPrimary, // Directive 1: Navy
      elevation: 0,
      centerTitle: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      title: const Text(
        'GAPLESS NAV',
        style: TextStyle(
          color: Colors.white, 
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
        ),
      ),
      actions: [
        Consumer<AlertProvider>(
          builder: (context, alert, _) {
            return IconButton(
              icon: Icon(
                alert.isVoiceGuidanceEnabled ? Icons.volume_up : Icons.volume_off,
                color: Colors.white,
              ),
              onPressed: () {
                alert.toggleVoiceGuidance();
                HapticService.selectionClick();
              },
            );
          },
        ),
      ],
    );
  }

  // Directive 3: LOGIC Display
  Widget _buildLogicStatusBanner() {
    return Consumer<ShelterProvider>(
      builder: (context, shelter, _) {
        final region = shelter.currentAppRegion;
        final isJapan = region == AppRegion.japan;
        
        // Logic Description based on Directive 3
        final String logicTitle = isJapan ? "ROAD WIDTH PRIORITY" : "AVOID ELECTRIC SHOCK";
        final String logicDesc = isJapan 
            ? "Routing avoids narrow alleys & block walls."
            : "Routing avoids flood zones & power lines.";
        final IconData logicIcon = isJapan ? Icons.landscape_rounded : Icons.bolt_rounded;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_borderRadius),
            border: Border.all(color: _navyPrimary.withOpacity(0.1), width: 2),
            boxShadow: [
              BoxShadow(
                color: _navyPrimary.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _orangeAccent.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(logicIcon, color: _orangeAccent, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      logicTitle,
                      style: const TextStyle(
                        color: _navyPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      logicDesc,
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompassSection() {
    return Consumer3<CompassProvider, LocationProvider, ShelterProvider>(
      builder: (context, compass, location, shelter, _) {
        final userLoc = location.currentLocation;
        final target = shelter.navTarget;
        final isNavigating = compass.isNavigating;
        
        // Waypoint Logic (Directive 2)
        // Accessing WaypointMagnetManager state implicitly via CompassProvider logic
        // We display the "Next Waypoint" direction
        
        double? safeBearing;
        if (isNavigating && compass.magnetResult != null) {
          safeBearing = compass.magnetResult!.bearingToTarget;
        } else if (target != null && userLoc != null) {
          // Fallback to direct bearing
          safeBearing = Geolocator.bearingBetween(
            userLoc.latitude, userLoc.longitude,
            target.lat, target.lng,
          );
        }

        // Distance Display
        String distanceText = "---";
        if (isNavigating) {
          final dist = compass.remainingDistance;
          distanceText = dist < 1000 
              ? "${dist.toStringAsFixed(0)} m" 
              : "${(dist / 1000).toStringAsFixed(1)} km";
        } else if (target != null && userLoc != null) {
           final dist = shelter.getDistanceToTargetIfCached(target) ?? -1;
           if (dist >= 0) {
             distanceText = dist < 1000 
                ? "${dist.toStringAsFixed(0)} m" 
                : "${(dist / 1000).toStringAsFixed(1)} km";
           } else {
             distanceText = "CALC...";
           }
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            // Background Circle (Navy)
            Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                color: _navyPrimary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _navyPrimary.withOpacity(0.3),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
            ),
            
            // Smart Compass Widget (Orange Accent)
            SmartCompass(
              heading: compass.heading ?? 0.0,
              safeBearing: safeBearing, // Waypoint bearing
              magneticDeclination: 0.0, // Pre-corrected in Provider
              size: 240,
              safeThreshold: 25.0,
              // Orange for danger/neutral, Green for Safe
            ),
            
            // Distance Overlay (Center)
            if (target != null)
              Positioned(
                bottom: 40,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    distanceText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ),
              ),

            // Waypoint Progress (Directive 2)
            if (isNavigating && compass.magnetResult != null)
              Positioned(
                top: 40,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _orangeAccent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "WAYPOINT ${compass.magnetResult!.currentWaypointIndex + 1}/${compass.magnetResult!.totalWaypoints}",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              
            // iOS Web Fallback Overlay
            if (!compass.hasSensorData && !_dismissPermissionBanner && kIsWeb)
              _buildWebPermissionOverlay(compass),
          ],
        );
      },
    );
  }

  Widget _buildWebPermissionOverlay(CompassProvider compass) {
    return GestureDetector(
      onTap: () async {
        final result = await requestIOSCompassPermission();
        if (result == 'granted' || result == 'not_supported') {
          setState(() => _dismissPermissionBanner = true);
          compass.stopListening();
          compass.startListening();
        }
      },
      child: Container(
        width: 280,
        height: 280,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          shape: BoxShape.circle,
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app, color: Colors.white, size: 40),
              SizedBox(height: 8),
              Text(
                "TAP TO START",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        // Arrival Button (Directive 1: Height 56, Radius 30)
        SizedBox(
          width: double.infinity,
          height: _buttonHeight,
          child: ElevatedButton(
            onPressed: () => _handleArrival(),
            style: ElevatedButton.styleFrom(
              backgroundColor: _orangeAccent, // Orange
              foregroundColor: Colors.white,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_borderRadius),
              ),
            ),
            child: const Text(
              "I HAVE ARRIVED",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Cancel / Manual Target
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: _buttonHeight,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _navyPrimary,
                    side: const BorderSide(color: _navyPrimary, width: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_borderRadius),
                    ),
                  ),
                  child: const Text(
                    "CANCEL",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SizedBox(
                height: _buttonHeight,
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Re-scan or Change Target
                    // For demo, just show snackbar
                    HapticService.selectionClick();
                    context.read<ShelterProvider>().loadShelters(); // Reload
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text("RESCAN"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navyPrimary, // Navy
                    foregroundColor: Colors.white,
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(_borderRadius),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _handleArrival() {
    HapticService.arrivedAtDestination();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("Confirm Arrival"),
        content: const Text("Have you reached the safe zone? Navigation will end."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("NO", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<ShelterProvider>().setSafeInShelter(true);
              Navigator.pushReplacement(
                context, 
                MaterialPageRoute(builder: (_) => const ShelterDashboardScreen())
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _orangeAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            ),
            child: const Text("YES, I'M SAFE", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}