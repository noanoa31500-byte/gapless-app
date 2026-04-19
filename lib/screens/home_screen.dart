/* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   ARCHITECTURAL OVERWRITE: LIB/SCREENS/HOME_SCREEN.DART
   Directives Implemented:
   1. UI: Navy (0xFF2E7D32) / Orange (0xFFFF6F00) Palette.
          BorderRadius 30.0 for buttons/cards.
          Height 56.0 for primary actions.
          Padding 24.0+ for layout breathing room.
   2. NAV: Visualizes Waypoint-based navigation (List<LatLng>) via Polyline.
   3. LOGIC: Explicitly displays the active safety logic based on region.
             Japan = Road Width Priority.
             Thailand = Avoid Electric Shock Risk.
   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

import 'dart:async';
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
import '../utils/accessibility.dart';
import '../utils/localization.dart';
import '../widgets/dead_reckoning_badge.dart';
import '../ble/ble_packet.dart';
import '../ble/ble_repository.dart';
import '../ble/ble_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  // --- DIRECTIVE 1: UI CONSTANTS ---
  static const Color _greenPrimary = Color(0xFF2E7D32);
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

  // ── ハザードオーバーレイ ON/OFF ─────────────────────────────────────────────
  bool _showFloodOverlay  = true;

  // ── 危険エリア在圏警告 ──────────────────────────────────────────────────────
  // 0=安全, 1=ハザードポリゴン内, 2=洪水リスク近傍
  int _dangerLevel = 0;
  Timer? _hazardCheckTimer;

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
      // 危険エリア在圏チェック — 5秒ごと
      _hazardCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        _checkDangerZone();
      });
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
    _hazardCheckTimer?.cancel();
    _pulseController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  /// 5秒ごとに現在地とハザードゾーンを照合して警告レベルを更新
  void _checkDangerZone() {
    if (!mounted) return;
    final loc = context.read<LocationProvider>().currentLocation;
    if (loc == null) return;
    final shelter = context.read<ShelterProvider>();

    int level = 0;
    if (shelter.isPointInHazardZone(loc)) {
      level = 1;
    } else if (shelter.isNearFloodRisk(loc)) {
      level = 2;
    }

    if (level != _dangerLevel) {
      setState(() => _dangerLevel = level);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Watch Providers
    // 高頻度通知の LocationProvider は必要フィールド (currentLocation) のみ購読し、
    // GPS が同一座標の間は再描画しない。LatLng が == を実装しているため動作する。
    final currentLocation =
        context.select<LocationProvider, LatLng?>((p) => p.currentLocation);
    final shelterProvider = context.watch<ShelterProvider>();
    // RegionModeProvider は isJapanMode のみ参照しているのでそれだけ購読。
    final isJapanMode =
        context.select<RegionModeProvider, bool>((p) => p.isJapanMode);
    final reduceMotion = AppleAccessibility.reduceMotion(context);
    if (reduceMotion && _pulseController.isAnimating) {
      _pulseController.stop();
    } else if (!reduceMotion && !_pulseController.isAnimating) {
      _pulseController.repeat(reverse: true);
    }
    // 言語フィールドのみ購読（単一文字列が変わったときだけ再描画）
    context.select<LanguageProvider, String>((p) => p.currentLanguage);
    
    // Region change detection for map centering
    if (_lastRegion != shelterProvider.currentRegion) {
      _lastRegion = shelterProvider.currentRegion;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final center = shelterProvider.getCenter();
        _mapController.move(LatLng(center['lat']!, center['lng']!), 14.0);
      });
    }

    // Auto Zoom Logic
    _handleAutoZoom(currentLocation, shelterProvider);

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
                  color: _greenPrimary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(_greenPrimary),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                GapLessL10n.t('bot_analyzing'),
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
          _buildMapLayer(currentLocation, shelterProvider),

          // ---------------------------------------------------------
          // LAYER 2: UI OVERLAY (Navy/Orange, Radius 30, Padding 24)
          // ---------------------------------------------------------
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(_uiPadding),
              child: Column(
                children: [
                  // Top Bar
                  _buildTopBar(),

                  const Spacer(),

                  // Logic Indicator (Directive 3)
                  _buildLogicIndicator(isJapanMode),
                  const SizedBox(height: 16),

                  // Bottom Action Bar
                  _buildBottomBar(context),
                ],
              ),
            ),
          ),
          
          // ---------------------------------------------------------
          // LAYER 3: DEAD RECKONING BADGE
          // ---------------------------------------------------------
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 0,
            right: 0,
            child: const Center(child: DeadReckoningBadge()),
          ),

          // ---------------------------------------------------------
          // LAYER 3b: 危険エリア在圏警告バナー
          // ---------------------------------------------------------
          if (_dangerLevel > 0)
            Positioned(
              top: MediaQuery.of(context).padding.top + 52,
              left: 16,
              right: 16,
              child: _buildDangerBanner(),
            ),

          // ---------------------------------------------------------
          // LAYER 3c: ハザードオーバーレイ ON/OFF トグル
          // ---------------------------------------------------------
          Positioned(
            left: _uiPadding,
            bottom: _uiPadding + 80 + 32,
            child: _buildOverlayToggles(),
          ),

          // ---------------------------------------------------------
          // LAYER 4: FLOATING ACTION BUTTONS
          // ---------------------------------------------------------
          Positioned(
            right: _uiPadding,
            bottom: _uiPadding + 80 + 32, // Above bottom bar
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildFab(
                  icon: Icons.my_location_rounded,
                  onPressed: () => _centerMap(context.read<LocationProvider>()),
                  color: Colors.white,
                  iconColor: _greenPrimary,
                ),
                const SizedBox(height: 16),
                _buildFab(
                  icon: Icons.warning_amber_rounded,
                  onPressed: () => _confirmDisasterMode(),
                  color: _orangeAccent,
                  iconColor: Colors.white,
                ),
                const SizedBox(height: 16),
                _buildFab(
                  icon: Icons.report_rounded,
                  onPressed: () =>
                      _showDangerReportDialog(context.read<LocationProvider>()),
                  color: const Color(0xFFE53935),
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
    LatLng? currentLocation,
    ShelterProvider shelterProv,
  ) {
    const initialCenter = LatLng(38.3591, 140.9405); // 大崎市中心

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
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

        // 4. Flood Risk Circles (Thailand) — トグルで表示/非表示
        if (_showFloodOverlay && shelterProv.floodRiskCircles.isNotEmpty)
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

        // 6. DIRECTIVE 2: WAYPOINT NAVIGATION ROUTE (List<LatLng>)
        if (shelterProv.getSafestRouteAsLatLng().isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: shelterProv.getSafestRouteAsLatLng(),
                strokeWidth: 6.0,
                color: _greenPrimary.withValues(alpha: 0.8),
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
                color: _greenPrimary,
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
        if (currentLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: currentLocation,
                width: 60,
                height: 60,
                child: AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, _) => Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _greenPrimary.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Center(
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: _greenPrimary,
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
          onTap: () async {
            await provider.startNavigation(shelter);
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Target Set: ${shelter.name}"),
                backgroundColor: _greenPrimary,
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
                  color: isSelected ? _orangeAccent : _greenPrimary,
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
                    color: _greenPrimary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    GapLessL10n.t('label_target'),
                    style: GapLessL10n.safeStyle(const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
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

  // ---------------------------------------------------------------------------
  // 危険エリア在圏警告バナー
  // ---------------------------------------------------------------------------

  Widget _buildDangerBanner() {
    final (Color bg, Color border, IconData icon, String titleKey, String subKey) =
        switch (_dangerLevel) {
      1 => (
          const Color(0xFFB71C1C),
          const Color(0xFFEF9A9A),
          Icons.dangerous_rounded,
          'danger_hazard_title',
          'danger_hazard_sub',
        ),
      2 => (
          const Color(0xFF1B5E20),
          const Color(0xFF90CAF9),
          Icons.water_rounded,
          'danger_flood_title',
          'danger_flood_sub',
        ),
      3 => (
          const Color(0xFFE65100),
          const Color(0xFFFFCC80),
          Icons.electric_bolt_rounded,
          'danger_power_title',
          'danger_power_sub',
        ),
      _ => (Colors.transparent, Colors.transparent, Icons.info, '', ''),
    };

    // GapLessL10n.safeStyle() で常に両フォントを保証
    final titleStyle = GapLessL10n.safeStyle(
      const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
    );
    final subStyle = GapLessL10n.safeStyle(
      const TextStyle(color: Colors.white70, fontSize: 11),
    );

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border, width: 1.5),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(GapLessL10n.t(titleKey), style: titleStyle),
                  Text(GapLessL10n.t(subKey),   style: subStyle),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _dangerLevel = 0),
              child: const Icon(Icons.close, color: Colors.white54, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ハザードオーバーレイ ON/OFF トグルボタン群
  // ---------------------------------------------------------------------------

  Widget _buildOverlayToggles() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildToggleChip(
          icon: Icons.water_rounded,
          label: GapLessL10n.t('overlay_flood'),
          active: _showFloodOverlay,
          activeColor: const Color(0xFF388E3C),
          onTap: () => setState(() => _showFloodOverlay = !_showFloodOverlay),
        ),
      ],
    );
  }

  Widget _buildToggleChip({
    required IconData icon,
    required String label,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? activeColor.withValues(alpha: 0.88) : Colors.white.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? activeColor : Colors.grey.shade400, width: 1.5),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: active ? Colors.white : Colors.grey.shade600),
            const SizedBox(width: 4),
            Text(
              label,
              style: GapLessL10n.safeStyle(TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: active ? Colors.white : Colors.grey.shade600,
              )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
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
                color: _greenPrimary.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Row(
            children: [
              const Icon(Icons.shield, color: _greenPrimary),
              const SizedBox(width: 8),
              RichText(
                text: TextSpan(
                  style: GapLessL10n.safeStyle(const TextStyle()),
                  children: const [
                    TextSpan(
                      text: 'Gap',
                      style: TextStyle(color: _greenPrimary, fontWeight: FontWeight.bold, fontSize: 18)
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
          iconColor: _greenPrimary,
        ),
      ],
    );
  }

  // --- DIRECTIVE 3: LOGIC INDICATOR ---
  Widget _buildLogicIndicator(bool isJapan) {
    // Display specific logic based on region
    final text = isJapan 
        ? "LOGIC: Road Width Priority (Blockage Avoidance)" 
        : "LOGIC: Avoid Electric Shock & Flood Risk";
    final icon = isJapan ? Icons.add_road : Icons.flash_off;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _greenPrimary.withValues(alpha: 0.9),
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
            color: _greenPrimary.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildBottomBtn(Icons.smart_toy, "AI Guide", () => _showChat(context)),
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
              color: isPrimary ? _greenPrimary : Colors.transparent,
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

  /// 災害モード起動前に確認ダイアログを表示（誤タップ防止）
  Future<void> _confirmDisasterMode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF6F00)),
            const SizedBox(width: 8),
            Text(
              GapLessL10n.t('disaster_mode_confirm_title'),
              style: GapLessL10n.safeStyle(const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Text(
          GapLessL10n.t('disaster_mode_confirm_body'),
          style: GapLessL10n.safeStyle(const TextStyle(fontSize: 14)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              GapLessL10n.t('btn_cancel'),
              style: GapLessL10n.safeStyle(const TextStyle(color: Color(0xFF6B7280))),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF6F00),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(GapLessL10n.t('disaster_mode_confirm_ok')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      HapticService.disasterModeActivated();
      context.read<ShelterProvider>().setDisasterMode(true);
    }
  }

  void _handleAutoZoom(LatLng? loc, ShelterProvider shelter) {
    if (_initialZoomDone || shelter.isLoading) return;

    LatLng? effectiveLocation = loc;

    if (effectiveLocation != null && effectiveLocation.latitude == 0 && effectiveLocation.longitude == 0) {
      effectiveLocation = null;
    }

    // GPSなし時は大崎市をデフォルト位置とする
    effectiveLocation ??= const LatLng(38.3591, 140.9405); // 大崎市

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

  Future<void> _showDangerReportDialog(LocationProvider locProv) async {
    final pos = locProv.currentLocation;
    if (pos == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(GapLessL10n.t('home_no_location'))),
        );
      }
      return;
    }

    final options = [
      (label: GapLessL10n.t('home_report_passable'), type: BleDataType.passable, icon: Icons.check_circle, color: const Color(0xFF43A047)),
      (label: GapLessL10n.t('home_report_blocked'),  type: BleDataType.blocked,  icon: Icons.block,         color: const Color(0xFFE53935)),
      (label: GapLessL10n.t('home_report_danger'),   type: BleDataType.danger,   icon: Icons.warning,       color: _orangeAccent),
    ];

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_uiRadius)),
        title: Row(
          children: [
            const Icon(Icons.report_rounded, color: Color(0xFFE53935)),
            const SizedBox(width: 8),
            Text(GapLessL10n.t('home_danger_title'), style: GapLessL10n.safeStyle(const TextStyle(fontWeight: FontWeight.bold))),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((opt) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: opt.color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: Icon(opt.icon),
                  label: Text(opt.label, style: GapLessL10n.safeStyle(const TextStyle(fontWeight: FontWeight.bold))),
                  onPressed: () async {
                    Navigator.of(ctx).pop();
                    await _submitDangerReport(pos, opt.type);
                  },
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _submitDangerReport(LatLng pos, BleDataType dataType) async {
    final deviceId = 'unknown'; // DeviceIdService で上書き可能
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final packet = BlePacket(
      senderDeviceId: deviceId,
      timestamp:      now,
      lat:            pos.latitude,
      lng:            pos.longitude,
      accuracyMeters: 10.0,
      dataType:       dataType,
    );
    await BleRepository.instance.insert(packet);
    BleService.instance.enqueue(packet);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(GapLessL10n.t('home_report_sent')),
          backgroundColor: _greenPrimary,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
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