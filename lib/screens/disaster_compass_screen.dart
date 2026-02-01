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
/// 1. UI: Navy/Orange palette, BorderRadius 30.0, Height 56.0, Padding 24.0+.
/// 2. NAV: Waypoint-based navigation visualization.
/// 3. LOGIC: Japan=Road width priority display, Thailand=Electric Shock Risk display.
class DisasterCompassScreen extends StatefulWidget {
  const DisasterCompassScreen({super.key});

  @override
  State<DisasterCompassScreen> createState() => _DisasterCompassScreenState();
}

class _DisasterCompassScreenState extends State<DisasterCompassScreen> {
  // UI Constants based on directives
  static const Color _navyPrimary = Color(0xFF1A237E);
  static const Color _orangeAccent = Color(0xFFFF6F00);
  static const double _buttonHeight = 56.0;
  static const double _borderRadius = 30.0;
  static const double _defaultPadding = 24.0;

  Timer? _voiceTimer;
  double? _lastSpokenDistance;
  bool _dismissPermissionBanner = false;

  @override
  void initState() {
    super.initState();

    // 音声ガイダンスタイマー
    _voiceTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _speakNavigationUpdate();
    });

    // 自動ナビゲーション開始チェック
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryStartAutoNavigation();
      _speakNavigationUpdate();

      // バックグラウンドルート更新
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
                Padding(
                  padding: const EdgeInsets.all(_defaultPadding),
                  child: _buildHeader(region),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _defaultPadding),
                  child: _buildDestinationPanel(),
                ),
                Expanded(
                  child: _buildCompassArea(),
                ),
                _buildLogicStatusIndicator(region),
                _buildDestinationButtons(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(_defaultPadding, 8, _defaultPadding, _defaultPadding),
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
            Text(
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

  Widget _buildLogicStatusIndicator(AppRegion region) {
    final bool isJapan = region == AppRegion.japan;
    final String text = isJapan
        ? "Priority: Wide Roads (Avoid Blockage)"
        : "Priority: Avoid Electric Shock Risk";
    final IconData icon = isJapan ? Icons.add_road : Icons.flash_off;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: _defaultPadding, vertical: 8),
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
          Text(
            text,
            style: const TextStyle(
              color: _navyPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
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
        if (compassProvider.isSafeNavigating) {
          distance = compassProvider.remainingDistance;
        } else {
          distance = shelterProvider.getDistanceToTargetIfCached(target) ?? -1.0;
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
                  _buildStat("MODE", "WAYPOINT"),
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
              dangerBearings: [],
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
      padding: const EdgeInsets.symmetric(horizontal: _defaultPadding),
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

  Widget _buildArrivalButton() {
    return SizedBox(
      width: double.infinity,
      height: _buttonHeight,
      child: ElevatedButton(
        onPressed: () => _confirmArrival(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: _navyPrimary,
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_borderRadius),
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

    if (shelterProvider.startCachedNavigation(type)) {
      final nearest = shelterProvider.navTarget!;
      final safeRoute = shelterProvider.getSafestRouteAsLatLng();
      if (safeRoute.isNotEmpty) {
        context.read<CompassProvider>().startRouteNavigation(safeRoute);
        HapticService.destinationSet();
        _showSnackBar("Navigating to ${nearest.name}", _navyPrimary);
        return;
      }
    }

    List<String> types = [type];
    if (type == 'water') types = ['water', 'convenience', 'store'];
    
    final nearest = shelterProvider.getNearestShelter(userLoc, includeTypes: types);
    
    if (nearest != null) {
      await shelterProvider.startNavigation(nearest, currentLocation: userLoc);
      final safeRoute = shelterProvider.getSafestRouteAsLatLng();
      if (safeRoute.isNotEmpty) {
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
        title: Text(AppLocalizations.t('dialog_safety_title'), style: TextStyle(color: _navyPrimary, fontWeight: FontWeight.bold)),
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