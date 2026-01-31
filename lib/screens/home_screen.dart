import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cancellable_tile_provider/flutter_map_cancellable_tile_provider.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/shelter.dart';
import '../providers/location_provider.dart';
import '../providers/shelter_provider.dart';
import '../providers/region_mode_provider.dart'; // For AppRegion enum
import '../providers/language_provider.dart';
import '../services/risk_visualization_service.dart'; // FloodCircleData, PowerRiskCircleData
import 'settings_screen.dart';
import 'chat_screen.dart';
import '../utils/styles.dart';
import '../utils/localization.dart';
import '../utils/apple_design_system.dart';
import 'emergency_card_screen.dart';
import '../widgets/safe_text.dart';
import '../services/haptic_service.dart';


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  
  // 現在地パルスアニメーション用
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  
  // 地域変更検知用
  String? _lastRegion;
  // 初期ズーム完了フラグ
  bool _initialZoomDone = false;

  @override
  void initState() {
    super.initState();
    // データのロード（初回のみ）
    Future.microtask(() {
      if (mounted) {
        final shelterProvider = context.read<ShelterProvider>();
        if (shelterProvider.shelters.isEmpty) {
          shelterProvider.loadShelters();
          shelterProvider.loadHazardPolygons();
          shelterProvider.loadRoadData(); // 道路データも初回ロードする
        }
      }
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    
    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // データ監視
    final locationProvider = context.watch<LocationProvider>();
    final shelterProvider = context.watch<ShelterProvider>();
    context.watch<LanguageProvider>(); // 言語変更を監視（再描画トリガー）
    
    // 地域変更検知とカメラ移動
    if (_lastRegion != shelterProvider.currentRegion) {
      _lastRegion = shelterProvider.currentRegion;
      
      // ビルド完了後にカメラ移動
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // 地域ごとの中心座標
        LatLng target;
        final center = shelterProvider.getCenter();
        target = LatLng(center['lat']!, center['lng']!);
        
        _mapController.move(target, 14.0);
      });
    }

    // 1. (Valid logic space)
    // 災害モード監視は main.dart の DisasterWatcher に移行したため削除


    // 2. Automatic Zoom Logic (Enhanced)
    // GPSがなくても、デフォルト拠点周辺を表示する
    if (!_initialZoomDone && !shelterProvider.isLoading) {
      // 優先順位: GPS -> Japan Base (Natori/Sendai Kosen)
      LatLng? effectiveLocation = locationProvider.currentLocation;
      
      // Webでの拒否時など (0,0) の場合もフォールバック
      if (effectiveLocation != null && effectiveLocation.latitude == 0 && effectiveLocation.longitude == 0) {
        effectiveLocation = null;
      }
      
      // フォールバック: Natori/Sendai Kosen
      const japanBase = LatLng(38.3591, 140.9405);
      effectiveLocation ??= japanBase;

      // データロード完了を待つために、shelterProvider.displayedSheltersを使う
      final targetList = shelterProvider.displayedShelters.isNotEmpty 
          ? shelterProvider.displayedShelters 
          : shelterProvider.shelters; // フォールバック

      Shelter? nearest;
      if (targetList.isNotEmpty) {
        // 現在地(または拠点)から一番近い場所を探す
        nearest = shelterProvider.getAbsoluteNearest(effectiveLocation);
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
        // シェルターがない場合でも、とりあえず拠点には移動
        if (!_initialZoomDone) {
             _initialZoomDone = true; // Loop回避
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

    // データ読み込み中はApple風ローディング表示
    if (shelterProvider.isLoading) {
      return Scaffold(
        backgroundColor: AppleColors.systemBackground,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Apple風のローディングインジケーター
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppleColors.secondaryBackground,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(AppleColors.actionBlue),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                AppLocalizations.t('bot_analyzing'),
                style: AppleTypography.subhead.copyWith(
                  color: AppleColors.secondaryLabel,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 初期位置（FlutterMap用、初回ビルド時のみ有効）
    // Japan Base (Natori/Sendai Kosen)
    const initialCenter = LatLng(38.3591, 140.9405);

    return Scaffold(
      body: Stack(
        children: [
          // 1. Map Layer
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: initialCenter,
              initialZoom: 14.0,
              minZoom: 10.0,
              maxZoom: 18.0,
              interactionOptions: InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              // 1.1 Tile Layer (CartoDB Positron - 軽量・高速 + エラー抑制)
              TileLayer(
                urlTemplate: 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.safejapan.app',
                maxZoom: 19,
                // タイル読み込みのキャンセルエラーを抑制
                tileProvider: CancellableNetworkTileProvider(silenceExceptions: true),
              ),

              // 1.2 Polygon Layer (Hazard Zones - 浸水・洪水エリア)
              // 青のグラデーションで水害エリアを直感的に可視化
              PolygonLayer(
                polygons: _buildFloodHazardPolygons(shelterProvider.hazardPolygons),
              ),

              // 1.25 Road Data Layer (Thailand/Japan Roads from GeoJSON)
              if (shelterProvider.roadPolylines.isNotEmpty)
                PolylineLayer(
                  polylines: _buildRoadPolylines(shelterProvider.roadPolylines),
                ),

              // 1.26 Safest Route Layer (最大安全ルート表示)
              if (shelterProvider.safestRoute != null && shelterProvider.safestRoute!.isNotEmpty)
                PolylineLayer(
                  polylines: [_buildSafestRoutePolyline(shelterProvider)],
                ),

              // 1.27 Flood Risk Layer (浸水リスク域 - 青色)
              // レイヤー順序: 最初に描画して下層に配置
              if (shelterProvider.floodRiskCircles.isNotEmpty)
                CircleLayer(
                  circles: _buildFloodRiskCircles(shelterProvider.floodRiskCircles),
                ),

              // 1.28 Power Risk Layer (感電危険域 - 黄色)
              // レイヤー順序: 浸水域の上に描画し、重なり部分を強調
              if (shelterProvider.powerRiskCircles.isNotEmpty)
                CircleLayer(
                  circles: _buildPowerRiskCircles(shelterProvider.powerRiskCircles),
                ),
              
              // 1.29 Thailand Flood Risk Points Layer - 非表示（ポリゴンに統合済み）
              // 青いポイントクラウドは hazard_thailand.json のポリゴンで置き換え
              // if (shelterProvider.floodRiskPoints.isNotEmpty && shelterProvider.currentAppRegion == AppRegion.thailand)
              //   CircleLayer(
              //     circles: _buildFloodRiskPointCircles(shelterProvider.floodRiskPoints),
              //   ),
              
              // 1.30 Thailand Power Lines Layer (送電線 - 半径20m危険エリアを太線で表現)
              // 電線から半径20mの危険範囲を可視化
              if (shelterProvider.powerLinePolylines.isNotEmpty && shelterProvider.currentAppRegion == AppRegion.thailand)
                PolylineLayer(
                  polylines: _buildPowerLineBufferPolylines(shelterProvider.powerLinePolylines),
                ),
              
              // 1.31 Thailand Power Points Layer (発電所・タワーの感電危険域)
              if (shelterProvider.powerRiskCircles.isNotEmpty && shelterProvider.currentAppRegion == AppRegion.thailand)
                CircleLayer(
                  circles: _buildPowerPointCircles(shelterProvider.powerRiskCircles),
                ),


              // 1.3 Hazard Points Layer (Thailand Vegetation - Point Cloud)
              if (shelterProvider.hazardPoints.isNotEmpty)
                CircleLayer(
                  circles: shelterProvider.hazardPoints.map((point) {
                    final isTree = point['type'] == 'tree';
                    return CircleMarker(
                      point: LatLng(point['lat'], point['lng']),
                      radius: isTree ? 12.0 : 8.0, // Trees are bigger visually on map
                      color: isTree 
                          ? Colors.red[900]!.withValues(alpha: 0.6) // Deep red for trees 
                          : Colors.redAccent.withValues(alpha: 0.4), // Lighter red for grass
                      useRadiusInMeter: true, // Scale with map
                    );
                  }).toList(),
                ),
              
              // 1.3 Clustered Shelter Markers (避難所 - 緑系クラスター)
              if (shelterProvider.currentAppRegion == AppRegion.japan && shelterProvider.osakiShelters.isNotEmpty)
                MarkerClusterLayerWidget(
                  options: MarkerClusterLayerOptions(
                    maxClusterRadius: 80,
                    size: const Size(50, 50),
                    disableClusteringAtZoom: 16,
                    markers: _buildShelterMarkers(shelterProvider),
                    builder: (context, markers) {
                      return Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF43A047),
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2)),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            '${markers.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // 1.35 Clustered Food Supply Markers (食料補給 - オレンジ系クラスター)
              if (shelterProvider.currentAppRegion == AppRegion.japan && shelterProvider.foodSupplyPoints.isNotEmpty)
                MarkerClusterLayerWidget(
                  options: MarkerClusterLayerOptions(
                    maxClusterRadius: 80,
                    size: const Size(50, 50),
                    disableClusteringAtZoom: 16,
                    markers: _buildFoodSupplyMarkers(shelterProvider),
                    builder: (context, markers) {
                      return Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFFF9800),
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2)),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            '${markers.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // 1.36 Satun Shelters (サトゥーン避難所 - タイ用 緑クラスター)
              if (shelterProvider.currentAppRegion == AppRegion.thailand && shelterProvider.satunShelters.isNotEmpty)
                MarkerClusterLayerWidget(
                  options: MarkerClusterLayerOptions(
                    maxClusterRadius: 80,
                    size: const Size(50, 50),
                    disableClusteringAtZoom: 16,
                    markers: _buildSatunShelterMarkers(shelterProvider),
                    builder: (context, markers) {
                      return Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF43A047), // 緑（日本の避難所と同じ）
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [
                            BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2)),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            '${markers.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // 1.4 Current Location Layer (Apple Maps風)
              if (locationProvider.currentLocation != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: locationProvider.currentLocation!,
                      width: 80,
                      height: 80,
                      child: AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Stack(
                            alignment: Alignment.center,
                            children: [
                              // 精度円（外側のパルス）
                              Transform.scale(
                                scale: 1.0 + (_pulseAnimation.value * 0.3),
                                child: Container(
                                  width: 70,
                                  height: 70,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: AppleColors.actionBlue.withValues(
                                      alpha: 0.15 * (1 - _pulseAnimation.value),
                                    ),
                                  ),
                                ),
                              ),
                              // 中間リング
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppleColors.actionBlue.withValues(alpha: 0.2),
                                ),
                              ),
                              // 中央ドット（Apple Maps風）
                              Container(
                                width: 18,
                                height: 18,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppleColors.actionBlue,
                                  border: Border.all(color: Colors.white, width: 3),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppleColors.actionBlue.withValues(alpha: 0.4),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
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
                  TextSourceAttribution(
                    'CartoDB',
                    onTap: () => launchUrl(Uri.parse('https://carto.com/attributions')),
                  ),
                ],
              ),
            ],
          ),

          // 2. UI Overlay - Apple HIG準拠のグラスモーフィズムUI
          SafeArea(
            child: Stack(
              children: [
                // Top Bar: Logo & Settings (グラスモーフィズム)
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Logo (グラスモーフィズム)
                        _buildGlassContainer(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Gap',
                                  style: AppleTypography.headline.copyWith(
                                    color: AppleColors.label,
                                  ),
                                ),
                                TextSpan(
                                  text: 'Less',
                                  style: AppleTypography.headline.copyWith(
                                    color: AppleColors.dangerRed,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Settings Button (グラスモーフィズム)
                        _buildGlassIconButton(
                          icon: Icons.settings_rounded,
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (context) => Container(
                                height: MediaQuery.of(context).size.height * 0.9,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                                ),
                                child: const SettingsScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                // Bottom Right: AI & Disaster Buttons
                Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Disaster Mode Button (重要なので不透明)
                        _buildPrimaryActionButton(
                          icon: Icons.warning_amber_rounded,
                          color: AppleColors.dangerRed,
                          onPressed: () {
                            HapticService.disasterModeActivated();
                            context.read<ShelterProvider>().setDisasterMode(true);
                          },
                        ),
                        const SizedBox(height: 12),
                        
                        // Online AI Button (グラスモーフィズム拡張ボタン)
                        _buildGlassExtendedButton(
                          icon: Icons.smart_toy_rounded,
                          label: AppLocalizations.t('online_ai_btn'),
                          color: AppleColors.actionBlue,
                          onPressed: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (context) => Container(
                                height: MediaQuery.of(context).size.height * 0.9,
                                decoration: const BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                                ),
                                child: const ChatScreen(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                // Center Bottom: Emergency Gear Button
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 100.0),
                    child: _buildGlassExtendedButton(
                      icon: Icons.contact_emergency_rounded,
                      label: AppLocalizations.t('btn_emergency_gear'),
                      color: AppleColors.dangerRed,
                      onPressed: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (context) => Container(
                            height: MediaQuery.of(context).size.height * 0.85,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                            ),
                            child: const EmergencyCardScreen(),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                
                // Bottom Left: Tool Buttons (グラスモーフィズム)
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Survival Guide
                        _buildGlassIconButton(
                          icon: Icons.healing_rounded,
                          color: AppleColors.warningOrange,
                          onPressed: () => Navigator.pushNamed(context, '/survival_guide'),
                        ),
                        const SizedBox(height: 10),
                        
                        // Triage
                        _buildGlassIconButton(
                          icon: Icons.medical_services_rounded,
                          color: const Color(0xFF9C27B0),
                          onPressed: () => Navigator.pushNamed(context, '/triage'),
                        ),
                        const SizedBox(height: 10),
                        
                        // Filter Toggle
                        _buildGlassIconButton(
                          icon: shelterProvider.isEmergencyMode 
                              ? Icons.verified_user_rounded 
                              : Icons.public_rounded,
                          color: shelterProvider.isEmergencyMode 
                              ? AppleColors.dangerRed 
                              : AppleColors.secondaryLabel,
                          onPressed: () => shelterProvider.toggleEmergencyMode(),
                        ),
                        const SizedBox(height: 10),
                        
                        // Current Location
                        _buildGlassIconButton(
                          icon: Icons.my_location_rounded,
                          color: AppleColors.actionBlue,
                          onPressed: () {
                            if (locationProvider.currentLocation != null) {
                              _mapController.move(locationProvider.currentLocation!, 15.0);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // Apple HIG準拠 グラスモーフィズムUIコンポーネント
  // ==========================================================================

  /// グラスモーフィズムコンテナ（汎用）
  Widget _buildGlassContainer({
    required Widget child,
    EdgeInsetsGeometry? padding,
    double borderRadius = 16.0,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: padding ?? const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
              width: 0.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  /// グラスモーフィズムアイコンボタン
  Widget _buildGlassIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 0.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: color ?? AppleColors.label,
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  /// プライマリアクションボタン（不透明、重要なアクション用）
  Widget _buildPrimaryActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 26,
        ),
      ),
    );
  }

  /// グラスモーフィズム拡張ボタン（ラベル付き）
  Widget _buildGlassExtendedButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.3),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: AppleTypography.subhead.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // マーカー・レイヤー関連メソッド
  // ==========================================================================

  /// 変換済みの道路データをPolylineに変換（軽量版）
  /// 
  /// データの読み込みとグラフ構築は既にcompute()でバックグラウンド処理済みなので、
  /// このメソッドは単純にPolylineオブジェクトを生成するだけです。
  List<Polyline> _buildRoadPolylines(List<List<LatLng>> roadData) {
    List<Polyline> polylines = [];
    
    for (var points in roadData) {
      if (points.isNotEmpty) {
        polylines.add(Polyline(
          points: points,
          strokeWidth: 2.5,
          color: Colors.grey.shade700.withValues(alpha: 0.4),
        ));
      }
    }
    
    return polylines;
  }

  /// 最大安全ルートをPolylineに変換
  /// 
  /// 計算されたノードIDリストから座標を取得し、緑色の太い線で表示
  Polyline _buildSafestRoutePolyline(ShelterProvider provider) {
    final routeNodeIds = provider.safestRoute!;
    final graph = provider.roadGraph!;
    
    List<LatLng> points = [];
    
    // ノードIDから座標を取得
    for (var nodeId in routeNodeIds) {
      final node = graph.nodes[nodeId];
      if (node != null) {
        points.add(node.position);
      }
    }
    
    return Polyline(
      points: points,
      strokeWidth: 5.0, // 太い線で強調
      color: Colors.green.withValues(alpha: 0.8), // 緑色で「安全」を示す
      borderColor: Colors.white,
      borderStrokeWidth: 1.0,
    );
  }

  /// 浸水リスク域のCircleを生成（青グラデーション版）
  /// 
  /// 防災エンジニアとしての視点:
  /// 水深に応じた青のグラデーションで直感的に危険度を伝える。
  /// - 浅い水深 → 薄い水色（透明度高め）
  /// - 深い水深 → 濃い紺色（透明度低め）
  List<CircleMarker> _buildFloodRiskCircles(List<FloodCircleData> circles) {
    return circles.map((data) {
      final predDepth = data.predDepth;
      final position = data.position;
      
      // 水深に基づく青のグラデーション
      // 0.0m → 薄い水色, 3.0m以上 → 濃い紺色
      final depthRatio = (predDepth / 3.0).clamp(0.0, 1.0);
      
      // 色の補間: 薄い水色 → 濃い紺色
      final color = Color.lerp(
        const Color(0xFF81D4FA), // Light Blue 200
        const Color(0xFF0D47A1), // Blue 900
        depthRatio,
      )!;
      
      // 透明度: 浅い = 0.3 (透明度高め), 深い = 0.7 (透明度低め)
      final opacity = 0.3 + (depthRatio * 0.4);
      
      // 半径: 水深が深いほど大きく表示
      final radius = 30.0 + (depthRatio * 30.0);
      
      return CircleMarker(
        point: position,
        radius: radius,
        useRadiusInMeter: true,
        color: color.withValues(alpha: opacity),
        borderColor: const Color(0xFF1565C0).withValues(alpha: 0.6), // Blue 800
        borderStrokeWidth: 0.5,
      );
    }).toList();
  }

  /// 電力設備リスク域のCircleを生成（感電危険域）
  /// 
  /// 防災エンジニアとしての視点:
  /// 洪水時の「見えない死」= 感電死は、最も防ぎたい事故です。
  /// 濁った水の中では電線が見えず、気づかずに近づいて命を落とす
  /// ケースが後を絶ちません。
  /// 
  /// 黄色/オレンジの警告色で「立入禁止エリア」を明示し、
  /// 半径20mは電気が水を通じて伝わる危険範囲を示します。
  List<CircleMarker> _buildPowerRiskCircles(List<PowerRiskCircleData> circles) {
    return circles.map((data) {
      final position = data.position;
      
      return CircleMarker(
        point: position,
        radius: 20.0, // 感電危険範囲 20m（水を通じた通電距離）
        useRadiusInMeter: true,
        color: const Color(0xFFFFC107).withValues(alpha: 0.55), // Amber (半透明)
        borderColor: const Color(0xFFFF9800).withValues(alpha: 0.85), // Orange
        borderStrokeWidth: 2.0, // 太めの縁取りで視認性を最大化
      );
    }).toList();
  }

  /// 洪水・浸水ハザードポリゴンを描画
  /// 
  /// Apple HIG準拠: 視認性の高い「Warning Orange」と「Danger Red」を使用
  /// 青色は「情報」を、オレンジ/赤は「警告/危険」を直感的に伝えます。
  List<Polygon> _buildFloodHazardPolygons(List<List<LatLng>> polygons) {
    if (polygons.isEmpty) return [];
    
    return polygons.asMap().entries.map((entry) {
      final index = entry.key;
      final points = entry.value;
      
      // ポリゴンの面積に基づいて危険度を推定
      // 小さいポリゴンは局所的な浸水、大きいポリゴンは広域浸水
      final area = _calculatePolygonArea(points);
      
      // 面積が大きいほど危険度が高い（閾値ベースで色分け）
      Color fillColor;
      Color borderColor;
      double fillOpacity;
      double borderWidth;
      
      if (area > 0.001) {
        // 大規模浸水エリア: 赤（Danger Red）
        fillColor = const Color(0xFFFF3B30); // Apple Danger Red
        borderColor = const Color(0xFFD32F2F);
        fillOpacity = 0.45;
        borderWidth = 3.0;
      } else if (area > 0.0003) {
        // 中規模浸水エリア: オレンジ（Warning Orange）
        fillColor = const Color(0xFFFF9500); // Apple Warning Orange
        borderColor = const Color(0xFFF57C00);
        fillOpacity = 0.40;
        borderWidth = 2.5;
      } else {
        // 小規模浸水エリア: 青（Info Blue）- 従来の色
        final ratio = polygons.length > 1 
            ? (index / (polygons.length - 1)).clamp(0.0, 1.0)
            : 0.5;
        fillColor = Color.lerp(
          const Color(0xFF81D4FA),
          const Color(0xFF1565C0),
          ratio,
        )!;
        borderColor = const Color(0xFF0D47A1);
        fillOpacity = 0.35;
        borderWidth = 2.0;
      }
      
      return Polygon(
        points: points,
        color: fillColor.withValues(alpha: fillOpacity),
        borderColor: borderColor.withValues(alpha: 0.85),
        borderStrokeWidth: borderWidth,
        isFilled: true,
      );
    }).toList();
  }
  
  /// ポリゴンの面積を計算（緯度経度から簡易計算）
  double _calculatePolygonArea(List<LatLng> points) {
    if (points.length < 3) return 0.0;
    
    double area = 0.0;
    final n = points.length;
    
    for (int i = 0; i < n; i++) {
      final j = (i + 1) % n;
      area += points[i].longitude * points[j].latitude;
      area -= points[j].longitude * points[i].latitude;
    }
    
    return (area / 2).abs();
  }

  /// 送電線の危険エリアを太いラインで描画（半径20m相当）
  /// 
  /// 防災エンジニアとしての視点:
  /// 洪水時の感電事故は見えない危険です。
  /// 黄色/オレンジの警告色で「立入禁止エリア」を明示し、
  /// 避難者が無意識に危険エリアを避けられるようにします。
  /// 
  /// 地図の縮尺に関わらず、ピクセル単位で一定の太さを維持することで
  /// どのズームレベルでも視認性を確保します。
  List<Polyline> _buildPowerLineBufferPolylines(List<List<LatLng>> powerLines) {
    List<Polyline> polylines = [];
    
    for (var line in powerLines) {
      if (line.length < 2) continue;
      
      // メインの電線ライン（太い黄色/オレンジのバッファ表現）
      // strokeWidth: 40.0 はピクセル単位で、ズームレベル15付近で約20m幅に相当
      polylines.add(Polyline(
        points: line,
        strokeWidth: 40.0, // 太いラインで半径20mのバッファを表現
        color: const Color(0xFFFFC107).withValues(alpha: 0.5), // Amber (半透明の黄色)
        borderColor: const Color(0xFFFF9800).withValues(alpha: 0.8), // Orange
        borderStrokeWidth: 2.0,
      ));
      
      // 中心線（電線本体を示す細い線）
      polylines.add(Polyline(
        points: line,
        strokeWidth: 3.0,
        color: const Color(0xFFE65100), // Orange 900 (電線本体)
      ));
    }
    
    return polylines;
  }

  /// 発電所・タワーのポイントを円で描画
  /// 
  /// 黄色/オレンジで半径20mの危険エリアを表示
  List<CircleMarker> _buildPowerPointCircles(List<PowerRiskCircleData> points) {
    return points.where((p) => p.powerType != 'power_line').map((data) {
      return CircleMarker(
        point: data.position,
        radius: 25.0, // 発電所/タワーは少し大きめ
        useRadiusInMeter: true,
        color: const Color(0xFFFFC107).withValues(alpha: 0.6), // Amber
        borderColor: const Color(0xFFFF6F00).withValues(alpha: 0.9), // Orange 800
        borderStrokeWidth: 2.5,
      );
    }).toList();
  }

  /// 大崎市公式避難所の詳細モーダルを表示
  void _showOsakiShelterDetails(BuildContext context, OsakiShelter shelter) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ハンドル
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              
              // タイトル行
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: shelter.isFloodShelter 
                          ? const Color(0xFF2E7D32).withValues(alpha: 0.1)
                          : const Color(0xFF43A047).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      shelter.isFloodShelter ? Icons.flood : Icons.night_shelter,
                      color: shelter.isFloodShelter 
                          ? const Color(0xFF2E7D32)
                          : const Color(0xFF43A047),
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SafeText(
                          shelter.name,
                          style: emergencyTextStyle(size: 18, isBold: true),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 4),
                        SafeText(
                          AppLocalizations.t(shelter.isFloodShelter 
                              ? 'marker_flood_shelter' 
                              : 'marker_official_shelter'),
                          style: emergencyTextStyle(
                            size: 12, 
                            color: shelter.isFloodShelter 
                                ? const Color(0xFF2E7D32) 
                                : const Color(0xFF43A047),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              
              // 詳細情報
              if (shelter.address.isNotEmpty)
                _buildDetailRow(Icons.location_on, AppLocalizations.t('address'), shelter.address),
              if (shelter.capacity > 0)
                _buildDetailRow(Icons.people, AppLocalizations.t('capacity'), '${shelter.capacity}${AppLocalizations.t('capacity_unit')}'),
              _buildDetailRow(
                Icons.water_drop,
                AppLocalizations.t('flood_support'),
                shelter.isFloodShelter ? AppLocalizations.t('supported') : AppLocalizations.t('not_supported'),
              ),
              
              const SizedBox(height: 20),
              
              // ナビゲーションボタン
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _launchExternalNavigation(
                      destLat: shelter.lat,
                      destLng: shelter.lng,
                      destName: shelter.name,
                    );
                  },
                  icon: const Icon(Icons.navigation),
                  label: Text(AppLocalizations.t('navigate_here')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF43A047),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 食料補給ポイントの詳細モーダルを表示
  void _showFoodSupplyDetails(BuildContext context, FoodSupplyPoint point) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ハンドル
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              
              // タイトル行
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF9800).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.local_grocery_store,
                      color: Color(0xFFFF9800),
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SafeText(
                          point.name,
                          style: emergencyTextStyle(size: 18, isBold: true),
                          maxLines: 2,
                        ),
                        const SizedBox(height: 4),
                        SafeText(
                          AppLocalizations.t('marker_food_supply'),
                          style: emergencyTextStyle(
                            size: 12, 
                            color: const Color(0xFFFF9800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              
              // 詳細情報
              _buildDetailRow(Icons.store, AppLocalizations.t('shop_type'), _getShopTypeName(point.shopType)),
              if (point.nameEn != point.name)
                _buildDetailRow(Icons.translate, 'English', point.nameEn),
              
              const SizedBox(height: 20),
              
              // ナビゲーションボタン
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _launchExternalNavigation(
                      destLat: point.lat,
                      destLng: point.lng,
                      destName: point.name,
                    );
                  },
                  icon: const Icon(Icons.navigation),
                  label: Text(AppLocalizations.t('navigate_here')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF9800),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 詳細行ウィジェット
  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          const SizedBox(width: 12),
          SafeText(
            '$label: ',
            style: emergencyTextStyle(size: 14, isBold: true, color: Colors.grey[700]!),
          ),
          Expanded(
            child: SafeText(
              value,
              style: emergencyTextStyle(size: 14),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 店舗タイプの表示名を取得
  String _getShopTypeName(String shopType) {
    return AppLocalizations.translateShelterType(shopType);
  }

  /// 避難所マーカーを構築（アイコンのみ、タップでポップアップ）
  List<Marker> _buildShelterMarkers(ShelterProvider provider) {
    return provider.osakiShelters.map((shelter) {
      final isFlood = shelter.isFloodShelter;
      final color = isFlood ? const Color(0xFF2E7D32) : const Color(0xFF43A047);
      
      return Marker(
        point: shelter.position,
        width: 50,
        height: 50,
        child: GestureDetector(
          onTap: () => _showOsakiShelterDetails(context, shelter),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: Icon(
              isFlood ? Icons.flood : Icons.night_shelter,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      );
    }).toList();
  }

  /// 食料補給マーカーを構築（アイコンのみ、タップでポップアップ）
  List<Marker> _buildFoodSupplyMarkers(ShelterProvider provider) {
    return provider.foodSupplyPoints.map((point) {
      return Marker(
        point: point.position,
        width: 50,
        height: 50,
        child: GestureDetector(
          onTap: () => _showFoodSupplyDetails(context, point),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: const Icon(
              Icons.local_grocery_store,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      );
    }).toList();
  }

  /// サトゥーン避難所マーカーを構築（タイ用、緑アイコン）
  List<Marker> _buildSatunShelterMarkers(ShelterProvider provider) {
    return provider.satunShelters.map((shelter) {
      final icon = _getSatunAmenityIcon(shelter.amenityType);
      
      return Marker(
        point: shelter.position,
        width: 50,
        height: 50,
        child: GestureDetector(
          onTap: () => _showSatunShelterDetails(context, shelter),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF43A047), // 緑（日本の避難所と同じ）
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 28,
            ),
          ),
        ),
      );
    }).toList();
  }

  /// サトゥーン避難所詳細ポップアップ
  void _showSatunShelterDetails(BuildContext context, RegionalShelter shelter) {
    final lang = AppLocalizations.lang;
    final displayName = shelter.getDisplayName(lang);
    final subName = lang == 'th' ? shelter.nameEn : shelter.nameTh;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ハンドル
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              
              // タイトル行
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF43A047).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _getSatunAmenityIcon(shelter.amenityType),
                      color: const Color(0xFF43A047),
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SafeText(
                          displayName,
                          style: emergencyTextStyle(size: 18, isBold: true),
                          maxLines: 2,
                        ),
                        if (subName.isNotEmpty && subName != displayName) ...[
                          const SizedBox(height: 4),
                          SafeText(
                            subName,
                            style: emergencyTextStyle(size: 12, color: Colors.grey[600]!),
                            maxLines: 1,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 12),
              
              // 詳細情報
              _buildDetailRow(Icons.category, AppLocalizations.t('type'), _getAmenityTypeName(shelter.amenityType)),
              _buildDetailRow(Icons.verified, AppLocalizations.t('status'), AppLocalizations.t('official_data')),
              
              const SizedBox(height: 20),
              
              // ナビゲーションボタン
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _launchExternalNavigation(
                      destLat: shelter.lat,
                      destLng: shelter.lng,
                      destName: displayName,
                    );
                  },
                  icon: const Icon(Icons.navigation),
                  label: Text(AppLocalizations.t('navigate_here')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF43A047),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// サトゥーン施設タイプに応じたアイコンを取得
  IconData _getSatunAmenityIcon(String amenityType) {
    switch (amenityType) {
      case 'hospital':
        return Icons.local_hospital;
      case 'school':
        return Icons.school;
      case 'place_of_worship':
      case 'temple':
        return Icons.temple_buddhist;
      case 'community_centre':
        return Icons.groups;
      case 'government':
      case 'townhall':
        return Icons.account_balance;
      default:
        return Icons.night_shelter;
    }
  }

  /// 施設タイプ名を多言語で取得
  String _getAmenityTypeName(String amenityType) {
    return AppLocalizations.translateShelterType(amenityType);
  }

  /// 外部地図アプリでルート案内を起動
  /// 
  /// - Web: Google Maps URLを新しいタブで開く
  /// - iOS: Apple Maps (maps://) を優先、失敗時はGoogle Maps URL
  /// - Android: Google Maps Intent (google.navigation://) を優先、失敗時はgeo://
  Future<void> _launchExternalNavigation({
    required double destLat,
    required double destLng,
    required String destName,
  }) async {
    final locationProvider = context.read<LocationProvider>();
    final currentLocation = locationProvider.currentLocation;
    
    // 現在地がない場合は目的地のみでGoogle Mapsを開く
    final String originParam = currentLocation != null 
        ? '${currentLocation.latitude},${currentLocation.longitude}'
        : '';
    
    final String destination = '$destLat,$destLng';
    
    
    try {
      if (kIsWeb) {
        // Web: Google Maps URLを開く
        final String googleMapsUrl = currentLocation != null
            ? 'https://www.google.com/maps/dir/$originParam/$destination'
            : 'https://www.google.com/maps/search/?api=1&query=$destLat,$destLng';
        
        final Uri uri = Uri.parse(googleMapsUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      } else {
        // Mobile: プラットフォーム別にスキームを試行
        await _launchMobileNavigation(
          destLat: destLat,
          destLng: destLng,
          destName: destName,
          originLat: currentLocation?.latitude,
          originLng: currentLocation?.longitude,
        );
      }
      
      // 成功通知
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SafeText('📍 $destName ${AppLocalizations.t("navigation_started")}'),
            backgroundColor: const Color(0xFF43A047),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      // エラー通知
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SafeText(AppLocalizations.t('map_launch_failed')),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// モバイル向けナビゲーション起動
  Future<void> _launchMobileNavigation({
    required double destLat,
    required double destLng,
    required String destName,
    double? originLat,
    double? originLng,
  }) async {
    final String destination = '$destLat,$destLng';
    
    // 1. Google Maps アプリ (Android/iOS)
    final googleMapsUri = Uri.parse(
      'google.navigation:q=$destination&mode=w' // mode=w は徒歩
    );
    
    if (await canLaunchUrl(googleMapsUri)) {
      await launchUrl(googleMapsUri);
      return;
    }
    
    // 2. Apple Maps (iOS)
    final appleMapsUri = Uri.parse(
      'maps://?daddr=$destination&dirflg=w' // dirflg=w は徒歩
    );
    
    if (await canLaunchUrl(appleMapsUri)) {
      await launchUrl(appleMapsUri);
      return;
    }
    
    // 3. geo:// スキーム (Android標準)
    final geoUri = Uri.parse(
      'geo:$destLat,$destLng?q=$destLat,$destLng(${Uri.encodeComponent(destName)})'
    );
    
    if (await canLaunchUrl(geoUri)) {
      await launchUrl(geoUri);
      return;
    }
    
    // 4. フォールバック: Google Maps Web
    final webFallbackUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$destination&travelmode=walking'
    );
    
    if (await canLaunchUrl(webFallbackUri)) {
      await launchUrl(webFallbackUri, mode: LaunchMode.externalApplication);
    }
  }
}
