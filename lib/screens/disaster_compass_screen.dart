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
import '../utils/apple_design_system.dart';
import '../services/haptic_service.dart';
import '../widgets/smart_compass.dart';
import 'shelter_dashboard_screen.dart';
import '../models/shelter.dart';
import '../services/compass_permission_service.dart';

/// ============================================================================
/// DisasterCompassScreen - 防災コンパス
/// ============================================================================
/// 
/// DIRECTIVES IMPLEMENTATION:
/// 1. UI: Navy (#1A237E) / Orange (#FF6F00) Palette.
///    - BorderRadius: 30.0
///    - Button Height: 56.0
///    - Padding: 24.0+
/// 2. NAV: Waypoint-based navigation visualization.
/// 3. LOGIC: Display active logic mode (Japan=Width, Thai=Electric).
/// ============================================================================
class DisasterCompassScreen extends StatefulWidget {
  const DisasterCompassScreen({super.key});

  @override
  State<DisasterCompassScreen> createState() => _DisasterCompassScreenState();
}

class _DisasterCompassScreenState extends State<DisasterCompassScreen> {
  // Constants based on Directives
  static const Color _navyPrimary = Color(0xFF1A237E);
  static const Color _orangeAccent = Color(0xFFFF6F00);
  static const double _uiRadius = 30.0;
  static const double _btnHeight = 56.0;
  static const double _contentPadding = 24.0;

  Timer? _voiceTimer;
  double? _lastSpokenDistance;
  bool _dismissPermissionBanner = false;

  @override
  void initState() {
    super.initState();
    
    // 音声ガイダンス (15秒間隔)
    _voiceTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _speakNavigationUpdate();
    });
    
    // 自動ナビゲーション開始試行
    WidgetsBinding.instance.addPostFrameCallback((_) {
       _tryStartAutoNavigation();
       _speakNavigationUpdate();
       
       // バックグラウンドルート更新
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
    super.dispose();
  }
  
  void _speakNavigationUpdate() {
    if (!mounted) return;
    final alertProvider = context.read<AlertProvider>();
    final compassProvider = context.read<CompassProvider>();
    
    if (compassProvider.isSafeNavigating) {
      final dist = compassProvider.remainingDistance;
      // 50m以上の変化で読み上げ
      if (_lastSpokenDistance == null || (dist - _lastSpokenDistance!).abs() > 50) {
        _lastSpokenDistance = dist;
        alertProvider.speakNavigation(dist, compassProvider.getDirectionName());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shelterProvider = context.watch<ShelterProvider>();
    final region = shelterProvider.currentAppRegion;

    return Scaffold(
      backgroundColor: _navyPrimary, // UI Directive: Navy Background
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(_contentPadding), // UI Directive: Padding 24+
          child: Stack(
            children: [
              Column(
                children: [
                  // 1. Header (Logic Mode Display)
                  _buildLogicHeader(region),
                  const SizedBox(height: 24),
                  
                  // 2. Destination Info
                  _buildDestinationCard(),
                  
                  // 3. Compass (Main Visual)
                  Expanded(
                    child: _buildCompassCenter(),
                  ),
                  
                  // 4. Action Buttons
                  _buildActionButtons(),
                ],
              ),
              
              // Web Permission Banner
              _buildPermissionBannerIfNeeded(),
            ],
          ),
        ),
      ),
    );
  }

  /// LOGIC Directive: Display Active Logic Mode
  Widget _buildLogicHeader(AppRegion region) {
    String logicText;
    IconData logicIcon;
    
    if (region == AppRegion.japan) {
      logicText = "Logic: Road Width Priority"; // Japan Logic
      logicIcon = Icons.add_road;
    } else {
      logicText = "Logic: Avoid Electric Risk"; // Thailand Logic
      logicIcon = Icons.bolt;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(_uiRadius), // UI Directive: Radius 30
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          Row(
            children: [
              Icon(logicIcon, color: _orangeAccent, size: 18),
              const SizedBox(width: 8),
              Text(
                logicText,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.volume_up, color: Colors.white, size: 20),
            onPressed: () => context.read<AlertProvider>().toggleVoiceGuidance(),
          ),
        ],
      ),
    );
  }

  /// NAV Directive: Waypoint/Target Info
  Widget _buildDestinationCard() {
    return Consumer3<LocationProvider, ShelterProvider, CompassProvider>(
      builder: (context, locProv, shelterProv, compassProv, _) {
        final target = shelterProv.navTarget;
        final dist = compassProv.remainingDistance;
        
        if (target == null) {
          return _buildInfoBox(
            title: AppLocalizations.t('loc_no_destination'),
            subtitle: AppLocalizations.t('loc_select_in_chat'),
            icon: Icons.flag,
            accent: Colors.grey,
          );
        }

        return _buildInfoBox(
          title: target.name,
          subtitle: "${dist.toStringAsFixed(0)}m - Waypoint Nav Active",
          icon: Icons.navigation,
          accent: _orangeAccent,
        );
      },
    );
  }

  Widget _buildInfoBox({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(_uiRadius),
        border: Border.all(color: accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: accent, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompassCenter() {
    return Consumer3<CompassProvider, LocationProvider, ShelterProvider>(
      builder: (context, compassProv, locProv, shelterProv, _) {
        final heading = compassProv.trueHeading ?? compassProv.heading ?? 0.0;
        final target = shelterProv.navTarget;
        final loc = locProv.currentLocation;
        
        // ウェイポイント方位 (Waypoints)
        double? targetBearing;
        if (compassProv.isSafeNavigating && compassProv.magnetResult != null) {
           targetBearing = compassProv.magnetResult!.bearingToTarget;
        } else if (target != null && loc != null) {
           targetBearing = Geolocator.bearingBetween(
             loc.latitude, loc.longitude, target.lat, target.lng
           );
        }

        return Center(
          child: SmartCompass(
            heading: heading,
            safeBearing: targetBearing,
            magneticDeclination: 0.0, // handled by provider
            size: 280,
            safeThreshold: 25.0,
          ),
        );
      }
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        // Arrival Button
        SizedBox(
          width: double.infinity,
          height: _btnHeight, // UI Directive: 56.0
          child: ElevatedButton(
            onPressed: () => _confirmArrival(),
            style: ElevatedButton.styleFrom(
              backgroundColor: _orangeAccent, // UI Directive: Orange Accent
              foregroundColor: _navyPrimary,
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(_uiRadius), // UI Directive: 30.0
              ),
            ),
            child: Text(
              AppLocalizations.t('btn_arrived_label'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionBannerIfNeeded() {
    final compassProv = context.watch<CompassProvider>();
    if (compassProv.hasSensorData || _dismissPermissionBanner) return const SizedBox.shrink();

    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.8),
        child: Center(
          child: GestureDetector(
            onTap: () async {
              final res = await requestIOSCompassPermission();
              if (res == 'granted' || res == 'not_supported') {
                setState(() => _dismissPermissionBanner = true);
                compassProv.stopListening();
                compassProv.startListening();
              }
            },
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: _orangeAccent,
                borderRadius: BorderRadius.circular(_uiRadius),
              ),
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.compass_calibration, color: Colors.white, size: 48),
                  SizedBox(height: 16),
                  Text(
                    "Tap to Enable Compass",
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _findAndStartNavigation(String type, {String? typeLabel}) async {
    final shelterProvider = context.read<ShelterProvider>();
    final loc = context.read<LocationProvider>().currentLocation;
    
    if (loc == null) return;

    if (shelterProvider.startCachedNavigation(type)) {
       final safeRoute = shelterProvider.getSafestRouteAsLatLng();
       if (safeRoute.isNotEmpty) {
           context.read<CompassProvider>().startRouteNavigation(safeRoute);
           HapticService.destinationSet();
       }
       return;
    }

    // Default search
    final nearest = shelterProvider.getNearestShelter(loc);
    if (nearest != null) {
       await shelterProvider.startNavigation(nearest, currentLocation: loc);
       final safeRoute = shelterProvider.getSafestRouteAsLatLng();
       if (safeRoute.isNotEmpty) {
           context.read<CompassProvider>().startRouteNavigation(safeRoute);
       }
    }
  }

  void _confirmArrival() {
    HapticService.arrivedAtDestination();
    context.read<ShelterProvider>().setSafeInShelter(true);
    Navigator.pushReplacement(
      context, 
      MaterialPageRoute(builder: (_) => const ShelterDashboardScreen())
    );
  }
}