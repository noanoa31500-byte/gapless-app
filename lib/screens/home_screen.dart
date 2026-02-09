/* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   ARCHITECTURAL OVERWRITE: LIB/SCREENS/HOME_SCREEN.DART
   Directives Implemented:
   1. UI: Navy (0xFF1A237E) / Orange (0xFFFF6F00) Palette.
          BorderRadius 30.0 for buttons/cards.
          Height 56.0 for primary actions.
          Padding 24.0+ for layout breathing room.
   2. NAV: Visualizes Waypoint-based navigation (List<LatLng>) via Polyline.
   3. LOGIC: Explicitly displays the active safety logic based on region.
             Japan = Road Width Priority.
             Thailand = Avoid Electric Shock Risk.
   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

// Providers & Services
import '../providers/location_provider.dart';
import '../providers/shelter_provider.dart';
import '../providers/region_mode_provider.dart';
import '../providers/language_provider.dart';
import '../services/haptic_service.dart';

// Models
import '../models/shelter.dart';

// Screens
import 'settings_screen.dart';
import 'chat_screen.dart';
import 'emergency_card_screen.dart';

// Utils
import '../utils/localization.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // --- DIRECTIVE 1: UI CONSTANTS ---
  static const Color _navyPrimary = Color(0xFF1A237E);
  static const Color _orangeAccent = Color(0xFFFF6F00);
  static const double _uiRadius = 30.0;
  static const double _uiHeight = 56.0;
  static const double _uiPadding = 24.0;

  final MapController _mapController = MapController();
  
  // Animation for "Current Location" Pulse
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  
  bool _initialZoomDone = false;
  String? _lastRegion;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Initial Data Load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  Future<void> _loadInitialData() async {
    final shelterProvider = context.read<ShelterProvider>();
    if (shelterProvider.shelters.isEmpty) {
      await shelterProvider.loadShelters();
      await shelterProvider.loadHazardPolygons();
      await shelterProvider.loadRoadData();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch Providers
    final locationProvider = context.watch<LocationProvider>();
    final shelterProvider = context.watch<ShelterProvider>();
    final regionProvider = context.watch<RegionModeProvider>();
    context.watch<LanguageProvider>();
    
    // Region change detection for map centering
    if (_lastRegion != shelterProvider.currentRegion) {
      _lastRegion = shelterProvider.currentRegion;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final center = shelterProvider.getCenter();
        _mapController.move(LatLng(center['lat']!, center['lng']!), 14.0);
      });
    }

    // Auto Zoom Logic
    _handleAutoZoom(locationProvider, shelterProvider);

    // Loading State
    if (shelterProvider.isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _navyPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(_navyPrimary),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                AppLocalizations.t('bot_analyzing'),
                style: const TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ---------------------------------------------------------
          // LAYER 1: MAP VIEW
          // ---------------------------------------------------------
          _buildMapLayer(locationProvider, shelterProvider, regionProvider),

          // ---------------------------------------------------------
          // LAYER 2: UI OVERLAY (Navy/Orange, Radius 30, Padding 24)
          // ---------------------------------------------------------
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(_uiPadding),
              child: Column(
                children: [
                  // Top Bar
                  _buildTopBar(regionProvider),
                  
                  const Spacer(),
                  
                  // Logic Indicator (Directive 3)
                  _buildLogicIndicator(regionProvider),
                  const SizedBox(height: 16),

                  // Bottom Action Bar
                  _buildBottomBar(context),
                ],
              ),
            ),
          ),
          
          // ---------------------------------------------------------
          // LAYER 3: FLOATING ACTION BUTTONS
          // ---------------------------------------------------------
          Positioned(
            right: _uiPadding,
            bottom: _uiPadding + 80 + 32, // Above bottom bar
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFab(
                  icon: Icons.my_location_rounded,
                  onPressed: () => _centerMap(locationProvider),
                  color: Colors.white,
                  iconColor: _navyPrimary,
                ),
                const SizedBox(height: 16),
                _buildFab(
                  icon: Icons.warning_amber_rounded,
                  onPressed: () {
                    HapticService.disasterModeActivated();
                    context.read<ShelterProvider>().setDisasterMode(true);
                  },
                  color: _orangeAccent,
                  iconColor: Colors.white,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MAP CONSTRUCTION
  // ---------------------------------------------------------------------------

  Widget _buildMapLayer(
    LocationProvider locProv, 
    ShelterProvider shelterProv,
    RegionModeProvider regionProv,
  ) {
    const initialCenter = LatLng(38.3591, 140.9405);

    return FlutterMap(
      mapController: _mapController,
      options: const MapOptions(
        initialCenter: initialCenter,
        initialZoom: 14.0,
        minZoom: 10.0,
        maxZoom: 18.0,
        interactionOptions: InteractionOptions(flags: InteractiveFlag.all),
      ),
      children: [
        // 1. Base Tiles
        TileLayer(
          urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
          subdomains: const ['a', 'b', 'c'],
          userAgentPackageName: 'com.gapless.app',
          tileProvider: CancellableNetworkTileProvider(silenceExceptions: true),
        ),

        // 2. Road Polylines (Background)
        if (shelterProv.roadPolylines.isNotEmpty)
          PolylineLayer(
            polylines: shelterProv.roadPolylines.map((points) => Polyline(
              points: points,
              strokeWidth: 2.0,
              color: Colors.grey.withValues(alpha: 0.3),
            )).toList(),
          ),

        // 3. Hazard Polygons
        if (shelterProv.hazardPolygons.isNotEmpty)
          PolygonLayer(
            polygons: shelterProv.hazardPolygons.map((points) => Polygon(
              points: points,
              color: Colors.red.withValues(alpha: 0.15),
              borderColor: Colors.red.withValues(alpha: 0.5),
              borderStrokeWidth: 2.0,
              isFilled: true,
            )).toList(),
          ),

        // 4. Flood Risk Circles (Thailand)
        if (shelterProv.floodRiskCircles.isNotEmpty)
          CircleLayer(
            circles: shelterProv.floodRiskCircles.map((data) => CircleMarker(
              point: data.position,
              radius: 40.0,
              useRadiusInMeter: true,
              color: Colors.blue.withValues(alpha: 0.2 + (data.riskScore / 10).clamp(0.0, 0.6)),
              borderColor: Colors.blue.withValues(alpha: 0.5),
              borderStrokeWidth: 1.0,
            )).toList(),
          ),

        // 5. Power Risk Circles (Thailand)
        if (shelterProv.powerRiskCircles.isNotEmpty)
          CircleLayer(
            circles: shelterProv.powerRiskCircles.map((data) => CircleMarker(
              point: data.position,
              radius: 20.0,
              useRadiusInMeter: true,
              color: Colors.amber.withValues(alpha: 0.4),
              borderColor: Colors.amber.withValues(alpha: 0.8),
              borderStrokeWidth: 2.0,
            )).toList(),
          ),

        // 6. DIRECTIVE 2: WAYPOINT NAVIGATION ROUTE (List<LatLng>)
        if (shelterProv.getSafestRouteAsLatLng().isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: shelterProv.getSafestRouteAsLatLng(),
                strokeWidth: 6.0,
                color: _navyPrimary.withValues(alpha: 0.8),
                borderColor: Colors.white,
                borderStrokeWidth: 2.0,
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
              ),
            ],
          ),

        // 7. Shelter Markers (Clustered)
        MarkerClusterLayerWidget(
          options: MarkerClusterLayerOptions(
            maxClusterRadius: 80,
            size: const Size(50, 50),
            disableClusteringAtZoom: 16,
            markers: _buildShelterMarkers(shelterProv),
            builder: (context, markers) => Container(
              decoration: BoxDecoration(
                color: _navyPrimary,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
                ],
              ),
              child: Center(
                child: Text(
                  '${markers.length}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ),

        // 8. Current Location (Pulsing)
        if (locProv.currentLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: locProv.currentLocation!,
                width: 60,
                height: 60,
                child: AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, _) => Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _navyPrimary.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Center(
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: _navyPrimary,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),

        // Attribution
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution(
              'OpenStreetMap contributors',
              onTap: () => launchUrl(Uri.parse('https://openstreetmap.org/copyright')),
            ),
          ],
        ),
      ],
    );
  }

  List<Marker> _buildShelterMarkers(ShelterProvider provider) {
    return provider.displayedShelters.map((shelter) {
      final isSelected = provider.navTarget?.id == shelter.id;
      return Marker(
        point: shelter.position,
        width: 60,
        height: 60,
        child: GestureDetector(
          onTap: () {
            // Start navigation to this shelter
            provider.startNavigation(shelter);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Target Set: ${shelter.name}"),
                backgroundColor: _navyPrimary,
                duration: const Duration(milliseconds: 1500),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelected ? _orangeAccent : _navyPrimary,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
                  ],
                ),
                child: Icon(
                  _getShelterIcon(shelter.type),
                  color: Colors.white,
                  size: 20,
                ),
              ),
              if (isSelected)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _navyPrimary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    "TARGET",
                    style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
        ),
      );
    }).toList();
  }

  IconData _getShelterIcon(String type) {
    if (type == 'hospital') return Icons.local_hospital;
    if (type == 'water') return Icons.water_drop;
    if (type == 'convenience' || type == 'store') return Icons.store;
    return Icons.night_shelter;
  }

  // ---------------------------------------------------------------------------
  // UI COMPONENTS (NAVY/ORANGE, RADIUS 30)
  // ---------------------------------------------------------------------------

  Widget _buildTopBar(RegionModeProvider regionProv) {
    return Row(
      children: [
        // App Title Card
        Container(
          height: _uiHeight,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_uiRadius),
            boxShadow: [
              BoxShadow(
                color: _navyPrimary.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Row(
            children: [
              const Icon(Icons.shield, color: _navyPrimary),
              const SizedBox(width: 8),
              RichText(
                text: const TextSpan(
                  children: [
                    TextSpan(
                      text: 'Gap', 
                      style: TextStyle(color: _navyPrimary, fontWeight: FontWeight.bold, fontSize: 18)
                    ),
                    TextSpan(
                      text: 'Less', 
                      style: TextStyle(color: _orangeAccent, fontWeight: FontWeight.bold, fontSize: 18)
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        // Settings Button
        _buildFab(
          icon: Icons.settings,
          onPressed: () => _showSettings(context),
          color: Colors.white,
          iconColor: _navyPrimary,
        ),
      ],
    );
  }

  // --- DIRECTIVE 3: LOGIC INDICATOR ---
  Widget _buildLogicIndicator(RegionModeProvider regionProv) {
    final isJapan = regionProv.isJapanMode;
    // Display specific logic based on region
    final text = isJapan 
        ? "LOGIC: Road Width Priority (Blockage Avoidance)" 
        : "LOGIC: Avoid Electric Shock & Flood Risk";
    final icon = isJapan ? Icons.add_road : Icons.flash_off;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _navyPrimary.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(_uiRadius),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: _orangeAccent, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_uiRadius),
        boxShadow: [
          BoxShadow(
            color: _navyPrimary.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildBottomBtn(Icons.smart_toy, "AI Guide", () => _showChat(context)),
          _buildBottomBtn(Icons.explore, "Compass", () {
             Navigator.pushNamed(context, '/compass');
          }, isPrimary: true),
          _buildBottomBtn(Icons.badge, "ID Card", () => _showEmergencyCard(context)),
        ],
      ),
    );
  }

  Widget _buildBottomBtn(IconData icon, String label, VoidCallback onTap, {bool isPrimary = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isPrimary ? _navyPrimary : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isPrimary ? Colors.white : Colors.grey,
              size: 24,
            ),
          ),
          if (!isPrimary) ...[
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFab({
    required IconData icon, 
    required VoidCallback onPressed,
    required Color color,
    required Color iconColor,
  }) {
    return Container(
      height: 56,
      width: 56,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon, color: iconColor),
        onPressed: onPressed,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // HELPERS & MODALS
  // ---------------------------------------------------------------------------

  void _handleAutoZoom(LocationProvider loc, ShelterProvider shelter) {
    if (_initialZoomDone || shelter.isLoading) return;
    
    LatLng? effectiveLocation = loc.currentLocation;
    
    if (effectiveLocation != null && effectiveLocation.latitude == 0 && effectiveLocation.longitude == 0) {
      effectiveLocation = null;
    }
    
    // Default fallback to Osaki if no GPS
    const japanBase = LatLng(38.3591, 140.9405);
    effectiveLocation ??= japanBase;

    final targetList = shelter.displayedShelters.isNotEmpty 
        ? shelter.displayedShelters 
        : shelter.shelters;

    Shelter? nearest;
    if (targetList.isNotEmpty) {
      nearest = shelter.getAbsoluteNearest(effectiveLocation);
    }

    if (nearest != null) {
      _initialZoomDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            _mapController.fitCamera(
              CameraFit.bounds(
                bounds: LatLngBounds.fromPoints([
                  effectiveLocation!,
                  LatLng(nearest!.lat, nearest.lng),
                ]),
                padding: const EdgeInsets.all(80),
                maxZoom: 16.0,
              ),
            );
          }
        });
      });
    } else {
      if (!_initialZoomDone) {
        _initialZoomDone = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              _mapController.move(effectiveLocation!, 14.0);
            }
          });
        });
      }
    }
  }

  void _centerMap(LocationProvider loc) {
    if (loc.currentLocation != null) {
      _mapController.move(loc.currentLocation!, 16.0);
    }
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(_uiRadius)),
        ),
        child: const SettingsScreen(),
      ),
    );
  }

  void _showChat(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(_uiRadius)),
        ),
        child: const ChatScreen(),
      ),
    );
  }

  void _showEmergencyCard(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(_uiRadius)),
        ),
        child: const EmergencyCardScreen(),
      ),
    );
  }
}