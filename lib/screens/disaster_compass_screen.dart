import 'dart:async';
import 'dart:math' as math;
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
import '../services/magnetic_declination_config.dart';
import '../services/compass_permission_service.dart';

/// ============================================================================
/// DisasterCompassScreen (Overwritten)
/// ============================================================================
/// 
/// Directives Implemented:
/// 1. UI: Navy (#1A237E) / Orange (#FF6F00) palette. 
///    BorderRadius 30.0, Height 56.0, Padding 24.0+.
/// 2. NAV: Waypoint-based navigation integration.
/// 3. LOGIC: Visualizes "Road width priority" (JP) vs "Avoid Electric Shock" (TH).
class DisasterCompassScreen extends StatefulWidget {
  const DisasterCompassScreen({super.key});

  @override
  State<DisasterCompassScreen> createState() => _DisasterCompassScreenState();
}

class _DisasterCompassScreenState extends State<DisasterCompassScreen> {
  // Constants for UI Directives
  static const Color _colNavy = Color(0xFF1A237E);
  static const Color _colOrange = Color(0xFFFF6F00);
  static const Color _colSurface = Color(0xFF283593); // Lighter Navy
  static const double _uiRadius = 30.0;
  static const double _btnHeight = 56.0;
  static const double _padStd = 24.0;

  Timer? _voiceTimer;
  bool _dismissPermissionBanner = false;

  @override
  void initState() {
    super.initState();
    
    // Voice guidance loop (15s)
    _voiceTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _speakNavigationUpdate();
    });
    
    // Auto-navigation check on build
    WidgetsBinding.instance.addPostFrameCallback((_) {
       _tryStartAutoNavigation();
       
       // Background calculation trigger
       final locProvider = context.read<LocationProvider>();
       if (locProvider.currentLocation != null) {
         context.read<ShelterProvider>().updateBackgroundRoutes(locProvider.currentLocation!);
       }
    });
  }
  
  @override
  void dispose() {
    _voiceTimer?.cancel();
    super.dispose();
  }

  // --- Logic Helpers ---

  void _speakNavigationUpdate() {
    if (!mounted) return;
    final alertProvider = context.read<AlertProvider>();
    final compassProvider = context.read<CompassProvider>();
    
    if (compassProvider.isSafeNavigating && compassProvider.magnetResult != null) {
      final dist = compassProvider.magnetResult!.distanceToTarget;
      // Simple direction logic based on bearing could be added here
      alertProvider.speakNavigation(dist, "waypoint");
    }
  }

  void _tryStartAutoNavigation() {
    final shelterProvider = context.read<ShelterProvider>();
    final compassProvider = context.read<CompassProvider>();
    
    if (compassProvider.isNavigating) return;
    
    if (shelterProvider.navTarget != null) {
         _findAndStartNavigation(
           shelterProvider.navTarget!.type, 
           typeLabel: shelterProvider.navTarget!.name
         ); 
    }
  }

  // --- UI Builders ---

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _colNavy,
      body: SafeArea(
        child: Column(
          children: [
            // 1. Header Area (Status & Logic Display)
            _buildHeader(),
            
            // 2. Main Compass Area
            Expanded(
              child: _buildCompassContent(),
            ),
            
            // 3. Info Panel (Waypoint/Distance)
            _buildInfoPanel(),
            
            // 4. Action Buttons (Destinations)
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final shelterProvider = context.watch<ShelterProvider>();
    final region = shelterProvider.currentRegion;
    final isThai = region.startsWith('th');

    // LOGIC Visualization: Show active strategy
    final String strategyText = isThai 
        ? "⚡ STRATEGY: AVOID ELECTRIC SHOCK" 
        : "🛣️ STRATEGY: ROAD WIDTH PRIORITY";

    return Padding(
      padding: const EdgeInsets.all(_padStd),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              const Text(
                "DISASTER COMPASS",
                style: TextStyle(
                  color: Colors.white, 
                  fontWeight: FontWeight.bold, 
                  fontSize: 18,
                  letterSpacing: 1.5,
                ),
              ),
              // Voice Toggle
              Consumer<AlertProvider>(
                builder: (context, alert, _) => IconButton(
                  icon: Icon(
                    alert.isVoiceGuidanceEnabled ? Icons.volume_up : Icons.volume_off,
                    color: _colOrange,
                  ),
                  onPressed: () => alert.toggleVoiceGuidance(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Strategy Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: isThai ? Colors.orange.withValues(alpha: 0.2) : Colors.blue.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20), // Not 30, strictly pill shape here
              border: Border.all(
                color: isThai ? _colOrange : Colors.cyanAccent,
                width: 1.5
              ),
            ),
            child: Text(
              strategyText,
              style: TextStyle(
                color: isThai ? _colOrange : Colors.cyanAccent,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompassContent() {
    return Consumer3<CompassProvider, LocationProvider, ShelterProvider>(
      builder: (context, compass, loc, shelter, _) {
        // Sync Region Logic
        if (shelter.currentRegion.startsWith('th')) {
           if (compass.currentGeoRegion != GeoRegion.thSatun) {
             Future.microtask(() => compass.setGeoRegion(GeoRegion.thSatun));
           }
        } else {
           if (compass.currentGeoRegion != GeoRegion.jpOsaki) {
             Future.microtask(() => compass.setGeoRegion(GeoRegion.jpOsaki));
           }
        }

        // Determine Bearing
        double? targetBearing;
        
        // NAV: Waypoint Logic
        if (compass.isNavigating && compass.magnetResult != null) {
          // Priority 1: Active Waypoint Navigation
          targetBearing = compass.magnetResult!.bearingToTarget;
        } else if (shelter.navTarget != null && loc.currentLocation != null) {
          // Priority 2: Straight Line Fallback
          targetBearing = Geolocator.bearingBetween(
            loc.currentLocation!.latitude,
            loc.currentLocation!.longitude,
            shelter.navTarget!.lat,
            shelter.navTarget!.lng,
          );
        }

        final heading = compass.trueHeading ?? compass.heading ?? 0.0;

        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer Ring
            Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _colSurface, width: 2),
              ),
            ),
            
            // Smart Compass Widget
            SmartCompass(
              heading: heading,
              safeBearing: targetBearing,
              // Logic: Pass hazard bearings if available
              dangerBearings: _calculateDangerBearings(loc.currentLocation, shelter),
              size: 280,
              safeThreshold: 30.0,
            ),

            // Permission Banner (iOS Web)
            if (!compass.hasSensorData && !_dismissPermissionBanner)
              _buildPermissionOverlay(compass),
          ],
        );
      },
    );
  }

  List<double> _calculateDangerBearings(LatLng? current, ShelterProvider provider) {
    if (current == null) return [];
    List<double> dangers = [];
    
    // Thailand Point Hazards
    for (final p in provider.hazardPoints) {
      if (p['lat'] != null && p['lng'] != null) {
        dangers.add(Geolocator.bearingBetween(
          current.latitude, current.longitude, p['lat'], p['lng']
        ));
      }
    }
    return dangers;
  }

  Widget _buildPermissionOverlay(CompassProvider provider) {
    return Center(
      child: GestureDetector(
        onTap: () async {
          final res = await requestIOSCompassPermission();
          if (res == 'granted' || res == 'not_supported') {
            setState(() => _dismissPermissionBanner = true);
            provider.stopListening();
            provider.startListening();
          }
        },
        child: Container(
          width: 200,
          height: 200,
          decoration: BoxDecoration(
            color: _colNavy.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(_uiRadius),
            border: Border.all(color: _colOrange, width: 2),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.compass_calibration, color: _colOrange, size: 40),
              SizedBox(height: 10),
              Text("TAP TO START", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoPanel() {
    return Consumer<CompassProvider>(
      builder: (context, compass, _) {
        final dist = compass.magnetResult?.distanceToTarget ?? 0.0;
        final index = compass.magnetResult?.currentWaypointIndex ?? 0;
        final total = compass.magnetResult?.totalWaypoints ?? 0;
        
        String infoText = "NO DESTINATION";
        String subText = "Select a target below";
        
        if (compass.isNavigating) {
          infoText = dist < 1000 
              ? "${dist.toStringAsFixed(0)} m" 
              : "${(dist/1000).toStringAsFixed(1)} km";
          // NAV: Display Waypoint Progress
          subText = "WAYPOINT ${index + 1} / $total";
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: _padStd),
          padding: const EdgeInsets.all(20),
          width: double.infinity,
          decoration: BoxDecoration(
            color: _colSurface,
            borderRadius: BorderRadius.circular(_uiRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 5),
              )
            ]
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subText,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    infoText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _colOrange,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.directions_run, color: Colors.white, size: 28),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButtons() {
    return Container(
      padding: const EdgeInsets.all(_padStd),
      child: Column(
        children: [
          // Destination Grid
          Row(
            children: [
              _buildTargetBtn(Icons.home_filled, "SHELTER", "shelter"),
              const SizedBox(width: 12),
              _buildTargetBtn(Icons.local_hospital, "HOSPITAL", "hospital"),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildTargetBtn(Icons.water_drop, "WATER", "water"),
              const SizedBox(width: 12),
              _buildTargetBtn(Icons.store, "SUPPLY", "convenience"),
            ],
          ),
          const SizedBox(height: 24),
          
          // Arrived Button (Full Width)
          SizedBox(
            width: double.infinity,
            height: _btnHeight,
            child: ElevatedButton(
              onPressed: () => _confirmArrival(),
              style: ElevatedButton.styleFrom(
                backgroundColor: _colOrange,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(_uiRadius),
                ),
                elevation: 4,
              ),
              child: const Text(
                "ARRIVED AT SAFETY",
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetBtn(IconData icon, String label, String type) {
    return Expanded(
      child: SizedBox(
        height: _btnHeight,
        child: ElevatedButton(
          onPressed: () => _findAndStartNavigation(type, typeLabel: label),
          style: ElevatedButton.styleFrom(
            backgroundColor: _colSurface,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_uiRadius),
              side: const BorderSide(color: Colors.white24),
            ),
            elevation: 0,
            padding: EdgeInsets.zero,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- Logic Implementation ---

  Future<void> _findAndStartNavigation(String type, {String? typeLabel}) async {
    final shelterProvider = context.read<ShelterProvider>();
    final locProvider = context.read<LocationProvider>();
    
    if (locProvider.currentLocation == null) {
      _showSnackBar(AppLocalizations.t('bot_loc_error'));
      return;
    }

    // 1. Instant Cache Check
    if (shelterProvider.startCachedNavigation(type)) {
       _startCompassRoute();
       HapticService.destinationSet();
       _showSnackBar("Started cached route: $typeLabel");
       return;
    }

    // 2. Find Nearest
    List<String> targetTypes = [type];
    if (type == 'shelter') targetTypes = ['shelter', 'school', 'gov', 'temple'];
    if (type == 'water') targetTypes = ['water', 'convenience', 'store']; // TH Logic adaptation

    final nearest = shelterProvider.getNearestShelter(
      locProvider.currentLocation!,
      includeTypes: targetTypes
    );

    if (nearest != null) {
      // 3. Calc Safe Route
      await shelterProvider.startNavigation(nearest, currentLocation: locProvider.currentLocation!);
      _startCompassRoute();
      
      HapticService.destinationSet();
      _showSnackBar("Calculated safe route to: ${nearest.name}");
    } else {
      _showSnackBar(AppLocalizations.t('msg_no_facility_nearby'));
    }
  }

  void _startCompassRoute() {
    final shelter = context.read<ShelterProvider>();
    final compass = context.read<CompassProvider>();
    
    // NAV: Pass Waypoints (List<LatLng>)
    final route = shelter.getSafestRouteAsLatLng();
    if (route.isNotEmpty) {
      compass.startRouteNavigation(route);
    }
  }

  void _confirmArrival() {
    HapticService.arrivedAtDestination();
    context.read<ShelterProvider>().setSafeInShelter(true);
    Navigator.pushReplacementNamed(context, '/dashboard');
  }

  void _showSnackBar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: _colOrange,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
}