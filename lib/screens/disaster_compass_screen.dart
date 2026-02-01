import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'dart:async';

import '../providers/compass_provider.dart';
import '../providers/shelter_provider.dart';
import '../providers/location_provider.dart';
import '../providers/alert_provider.dart';
import '../utils/localization.dart';
import '../utils/apple_design_system.dart';
import '../services/haptic_service.dart';
import '../widgets/smart_compass.dart';
import 'shelter_dashboard_screen.dart';
import '../models/shelter.dart';
import '../services/compass_permission_service.dart';
import '../services/magnetic_declination_config.dart';

/// ============================================================================
/// DisasterCompassScreen - Apple HIG準拠の防災コンパス
/// ============================================================================
/// 
/// デザインコンセプト: "Safety & Clarity"
/// 災害時のパニック状態でも誤操作を防ぐ、Apple流の「コンテンツファースト」なデザイン
/// 
/// 特徴:
/// - ダークモードベースのミニマルなコンパスUI
/// - グラスモーフィズムを採用した情報パネル
/// - セマンティックカラーによる直感的な状態表示
/// - アクセシブルな大きなタップターゲット
class DisasterCompassScreen extends StatefulWidget {
  const DisasterCompassScreen({super.key});

  @override
  State<DisasterCompassScreen> createState() => _DisasterCompassScreenState();
}

class _DisasterCompassScreenState extends State<DisasterCompassScreen> {
  Timer? _voiceTimer;
  double? _lastSpokenDistance;
  bool _dismissPermissionBanner = false;

  @override
  void initState() {
    super.initState();
    
    // 音声ガイダンスタイマー開始（15秒ごと）
    _voiceTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _speakNavigationUpdate();
    });
    
    // Auto-Start Navigation Check
    // 画面が開かれた直後に、既に目的地があれば自動的にナビを開始しようと試みる
    WidgetsBinding.instance.addPostFrameCallback((_) {
       _tryStartAutoNavigation();
       _speakNavigationUpdate(); // Initial speak
       
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
  
  /// 自動ナビゲーション開始を試みる
  void _tryStartAutoNavigation() {
    final shelterProvider = context.read<ShelterProvider>();
    final compassProvider = context.read<CompassProvider>();
    final locationProvider = context.read<LocationProvider>();
    
    // 既にナビ中なら何もしない
    if (compassProvider.isNavigating) return;
    
    final target = shelterProvider.navTarget;
    final userLoc = locationProvider.currentLocation;
    
    // ターゲットと現在地があり、かつコンパスの方位が取得できていれば開始
    // (iOS Webの場合、headingがnullならユーザー許可待ちなのでここには入らない -> ボタンを押した後に再トライが必要)
    if (target != null && userLoc != null && compassProvider.heading != null) {
        // ターゲットタイプを推論して開始
        // ここでは単純に "shelter" として開始するが、実際にはナビロジックが重要
         _findAndStartNavigation(target.type, typeLabel: target.name); 
    }
  }
  
  @override
  void dispose() {
    _voiceTimer?.cancel();

    super.dispose();
  }
  
  /// 現在の距離と方向を音声で読み上げ
  void _speakNavigationUpdate() {
    if (!mounted) return;
    
    final shelterProvider = context.read<ShelterProvider>();
    final locationProvider = context.read<LocationProvider>();
    final alertProvider = context.read<AlertProvider>();
    final compassProvider = context.read<CompassProvider>(); // Add CompassProvider
    
    final target = shelterProvider.navTarget;
    final currentLocation = locationProvider.currentLocation;
    
    if (target == null || currentLocation == null) return;
    
    double distance;
    // ナビゲーション中は「ルート残距離」を使用
    if (compassProvider.isSafeNavigating) {
        distance = compassProvider.remainingDistance;
    } else {
        // Use cached route distance if available
        final cachedDist = shelterProvider.getDistanceToTargetIfCached(target);
        if (cachedDist != null) {
            distance = cachedDist;
        } else {
            // Trigger background calculation if missing
            if (!shelterProvider.isRoutingLoading) {
                 Future.microtask(() {
                     shelterProvider.calculateSafestRoute(
                         LatLng(currentLocation.latitude, currentLocation.longitude),
                         LatLng(target.lat, target.lng),
                         target: target
                     );
                 });
            }
            return; // Don't speak if distance is unknown
        }
    }
    
    // 距離が大きく変わった時だけ読み上げ（50m以上の変化）
    if (_lastSpokenDistance != null && (distance - _lastSpokenDistance!).abs() < 50) {
      return;
    }
    _lastSpokenDistance = distance;
    
    // 方向を計算
    final bearing = Geolocator.bearingBetween(
      currentLocation.latitude,
      currentLocation.longitude,
      target.lat,
      target.lng,
    );
    
    final direction = _getDirectionText(bearing);
    alertProvider.speakNavigation(distance, direction);
  }
  
  /// 方位角から方向テキストを取得
  String _getDirectionText(double bearing) {
    final normalizedBearing = (bearing + 360) % 360;
    
    // 8方位
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

  /// 地域に応じたテーマカラー（アクセント用）
  Color _getRegionAccentColor(String region) {
    if (region.startsWith('th')) {
      return AppleColors.actionBlue; // 洪水 = Blue
    }
    return AppleColors.dangerRed; // 地震 = Red
  }

  IconData _getRegionHazardIcon(String region) {
    if (region.startsWith('th')) {
      return Icons.water_drop_rounded; // Flood
    }
    return Icons.warning_amber_rounded; // Earthquake
  }

  String _getRegionHazardName(String region) {
    if (region.startsWith('th')) {
      return AppLocalizations.t('hazard_flood');
    }
    return AppLocalizations.t('hazard_earthquake');
  }

  @override
  Widget build(BuildContext context) {
    final shelterProvider = context.watch<ShelterProvider>();
    final region = shelterProvider.currentRegion;
    final accentColor = _getRegionAccentColor(region);

    return Scaffold(
      backgroundColor: const Color(0xFF000000), // Apple Compass風の黒背景
      body: SafeArea(
        child: Stack(
          children: [
            // メインコンテンツ
            Column(
              children: [
                // ヘッダー（グラスモーフィズム）
                _buildHeader(region, accentColor),
                
                // 目的地情報パネル
                _buildDestinationPanel(),
                
                // コンパス本体
                Expanded(
                  child: _buildCompassArea(),
                ),
                
                // 目的地選択ボタン
                _buildDestinationButtons(),
                
                // 到着ボタン
                _buildArrivalButton(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// ヘッダー（グラスモーフィズム）
  Widget _buildHeader(String region, Color accentColor) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withValues(alpha: 0.1),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              // 閉じるボタン
              _buildIconButton(
                icon: Icons.close_rounded,
                onPressed: () => Navigator.pop(context),
              ),
              
              const Spacer(),
              
              // ハザード表示
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _getRegionHazardIcon(region),
                    color: accentColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _getRegionHazardName(region),
                    style: AppleTypography.headline.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              
              const Spacer(),
              
              // 音声ガイダンストグル
              Consumer<AlertProvider>(
                builder: (context, alertProvider, _) {
                  return _buildIconButton(
                    icon: alertProvider.isVoiceGuidanceEnabled
                        ? Icons.volume_up_rounded
                        : Icons.volume_off_rounded,
                    onPressed: () {
                      alertProvider.toggleVoiceGuidance();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            alertProvider.isVoiceGuidanceEnabled
                                ? AppLocalizations.t('voice_on')
                                : AppLocalizations.t('voice_off'),
                            style: AppleTypography.subhead.copyWith(color: Colors.white),
                          ),
                          backgroundColor: AppleColors.darkTertiaryBackground,
                          duration: const Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// アイコンボタン（共通スタイル）
  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Icon(
          icon,
          color: Colors.white.withValues(alpha: 0.9),
          size: 20,
        ),
      ),
    );
  }

  /// 目的地情報パネル（グラスモーフィズム）
  Widget _buildDestinationPanel() {
    return Consumer3<LocationProvider, ShelterProvider, CompassProvider>(
      builder: (context, locationProvider, shelterProvider, compassProvider, _) {
        final target = shelterProvider.navTarget;
        final currentLocation = locationProvider.currentLocation;
        final perm = locationProvider.lastPermissionStatus;

        // 権限エラー
        if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
          return _buildInfoPanel(
            icon: Icons.location_disabled_rounded,
            iconColor: AppleColors.warningOrange,
            title: AppLocalizations.t('loc_permission_denied'),
            subtitle: null,
            action: TextButton(
              onPressed: () => Geolocator.openAppSettings(),
              child: Text(
                AppLocalizations.t('loc_open_settings'),
                style: AppleTypography.subhead.copyWith(
                  color: AppleColors.actionBlue,
                ),
              ),
            ),
          );
        }

        // 位置情報取得中
        if (currentLocation == null) {
          return _buildInfoPanel(
            icon: Icons.my_location_rounded,
            iconColor: AppleColors.actionBlue,
            title: AppLocalizations.t('loc_acquiring'),
            subtitle: null,
            showProgress: true,
          );
        }

        // 目的地未設定
        if (target == null) {
          return _buildInfoPanel(
            icon: Icons.flag_rounded,
            iconColor: Colors.white.withValues(alpha: 0.5),
            title: AppLocalizations.t('loc_no_destination'),
            subtitle: AppLocalizations.t('loc_select_in_chat'),
          );
        }

        // 正常表示 (Distance Display Logic)
        double distance;
        
        // ナビゲーション中は「ルート残距離」を表示
        if (compassProvider.isSafeNavigating) {
            distance = compassProvider.remainingDistance;
        } else {
        // Check if we have a background cached route to this target
            final cachedDist = shelterProvider.getDistanceToTargetIfCached(target);
            if (cachedDist != null) {
                distance = cachedDist;
            } else {
                // FORCE CALCULATION (No Straight Line)
                // Trigger calculation if not already working
                if (!shelterProvider.isRoutingLoading) {
                     Future.microtask(() {
                         shelterProvider.calculateSafestRoute(
                             LatLng(currentLocation.latitude, currentLocation.longitude),
                             LatLng(target.lat, target.lng),
                             target: target
                         );
                     });
                }
                // Return dummy -1 to indicate loading in display logic
                distance = -1.0; 
            }
        }
        
        final isLastKnown = locationProvider.isUsingLastKnownLocation;
        final distanceText = distance < 0 
            ? '計算中...' 
            : distance < 1000
                ? '${distance.toStringAsFixed(0)}m'
                : '${(distance / 1000).toStringAsFixed(1)}km';

        return _buildInfoPanel(
          icon: distance < 0 ? Icons.sync : (isLastKnown ? Icons.history_rounded : Icons.directions_walk_rounded),
          iconColor: distance < 0 ? Colors.white.withValues(alpha: 0.5) : (isLastKnown ? AppleColors.warningOrange : AppleColors.safetyGreen),
          title: target.name,
          subtitle: distance < 0 ? distanceText : '🚶 $distanceText ${isLastKnown ? "[前回位置]" : "[最新]"}',
          isLargeSubtitle: distance >= 0,
        );
      },
    );
  }

  /// 情報パネル（汎用）
  Widget _buildInfoPanel({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    bool showProgress = false,
    bool isLargeSubtitle = false,
    Widget? action,
  }) {
    return Container(
      margin: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.15),
                width: 0.5,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: iconColor, size: 32),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: AppleTypography.headline.copyWith(
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: isLargeSubtitle
                        ? AppleTypography.title1.copyWith(
                            color: AppleColors.safetyGreen,
                            fontWeight: FontWeight.w700,
                          )
                        : AppleTypography.subhead.copyWith(
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                    textAlign: TextAlign.center,
                  ),
                ],
                if (showProgress) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 100,
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(AppleColors.actionBlue),
                    ),
                  ),
                ],
                if (action != null) ...[
                  const SizedBox(height: 8),
                  action,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// コンパス本体（SmartCompass統合）
  Widget _buildCompassArea() {
    return Consumer3<CompassProvider, LocationProvider, ShelterProvider>(
      builder: (context, compassProvider, locationProvider, shelterProvider, _) {
        final target = shelterProvider.navTarget;
        final currentLocation = locationProvider.currentLocation;
        final heading = compassProvider.trueHeading ?? compassProvider.heading ?? 0.0;
        final region = shelterProvider.currentRegion;
        
        // 地域同期チェック (CompassProviderの偏角を現在の地域に合わせる)
        if (compassProvider.currentGeoRegion.code != region) {
          // 非同期で実行
          Future.microtask(() {
            if (region.startsWith('th')) {
              compassProvider.setGeoRegion(GeoRegion.thSatun);
            } else {
              compassProvider.setGeoRegion(GeoRegion.jpOsaki);
            }
          });
        }

        // 避難所への方位を計算
        double? safeBearing;
        
        // ナビゲーション中は「次のウェイポイント」への方位を優先
        if (compassProvider.isNavigating && compassProvider.magnetResult != null) {
          safeBearing = compassProvider.magnetResult!.bearingToTarget;
        } else if (target != null && currentLocation != null) {
          // ターゲットはあるがナビ開始前、またはフォールバック
          safeBearing = Geolocator.bearingBetween(
            currentLocation.latitude,
            currentLocation.longitude,
            target.lat,
            target.lng,
          );
        }
        
        // 危険箇所への方位リストを取得
        List<double> dangerBearings = [];
        if (currentLocation != null) {
          // ハザードポイント（タイ版）
          for (final point in shelterProvider.hazardPoints) {
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
          
          // ハザードポリゴン（日本版）
          for (final polygon in shelterProvider.hazardPolygons) {
            if (polygon.isNotEmpty) {
              double avgLat = 0, avgLng = 0;
              for (final point in polygon) {
                avgLat += point.latitude;
                avgLng += point.longitude;
              }
              avgLat /= polygon.length;
              avgLng /= polygon.length;
              
              // 距離チェック: 1000m以内のハザードのみ警告対象にする
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

        // リアルタイム道路リスク分析 & 安全ナビゲーションリスク
        Color? overlayColor;
        // String? riskMessage; // Removed unused variable
        
        if (currentLocation != null) {
          final latLng = LatLng(currentLocation.latitude, currentLocation.longitude);
          
          // 1. Safe Compass Hazard Check (Priority)
          // Unified Risk Check using ShelterProvider
          final headingForRisk = compassProvider.trueHeading ?? compassProvider.heading ?? 0.0;
          final riskInfo = shelterProvider.getRoadRiskInDirection(latLng, headingForRisk);
          
          if (riskInfo != null && riskInfo['isSafe'] == false) {
            overlayColor = AppleColors.dangerRed.withValues(alpha: 0.3); // Stronger Red
            // riskMessage = riskInfo['message'];
            // Haptic Feedback for Danger
             if (compassProvider.hapticEnabled) {
               // HapticService.heavyImpact(); // Add debounce logic in production
             }
          } 
          // 2. Safe Navigation Active (Check Alignment)
          else if (compassProvider.isSafeNavigating && safeBearing != null) {
             // Calculate alignment with the route bearing
             double diff = (safeBearing - heading).abs();
             if (diff > 180) diff = 360 - diff;
             
             // Only show Green if facing the target (within 30 degrees)
             if (diff < 30) {
               overlayColor = AppleColors.safetyGreen.withValues(alpha: 0.15);
               // riskMessage = 'On Route';
             } else {
               // Off alignment -> No Green Overlay (Neutral)
               overlayColor = null; 
               // riskMessage = null; // Or show turn instruction?
             }
          }
          // 3. Existing Road Risk Check (Fallback)
          else {
            final roadInfo = shelterProvider.getRoadRiskInDirection(latLng, heading);
            if (roadInfo != null) {
               final isSafe = roadInfo['isSafe'] as bool;
               // final message = roadInfo['message'] as String;
               
               if (!isSafe) {
                 overlayColor = AppleColors.dangerRed.withValues(alpha: 0.15);
                 // riskMessage = message;
               } else {
                  overlayColor = AppleColors.safetyGreen.withValues(alpha: 0.15); // Blue -> Green
                  // riskMessage = message;
                }
             }
             // No fallback color -> default to neutral/transparent
          }
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            // 背景アラートオーバーレイ
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
              
            // Risk Message Component removed as per user request
            // if (riskMessage != null) ...

              SmartCompass(
                // trueHeadingを使用（CompassProviderで偏角補正済み）
                heading: compassProvider.trueHeading ?? compassProvider.heading ?? 0.0,
                safeBearing: safeBearing,
                dangerBearings: dangerBearings,
                magneticDeclination: 0.0, // 偏角はCompassProviderで適用済み
                size: 280,
                safeThreshold: 25.0,
                dangerThreshold: 20.0,
              ),
            
             // iOS Web Permission / Compass Not Ready Fallback
             if (!compassProvider.hasSensorData && !_dismissPermissionBanner)
               Positioned.fill(
                 child: Container(
                   color: Colors.black.withValues(alpha: 0.6), // Semitransparent overlay
                   child: Center(
                     child: GestureDetector(
                       onTap: () async {
                          // explicit user action
                          final result = await requestIOSCompassPermission();
                          
                          if (!mounted) return;
                          
                          if (result == 'granted' || result == 'not_supported') {
                             // Dismiss immediately on success
                             setState(() => _dismissPermissionBanner = true);
                             
                             // Success or non-iOS platform
                             compassProvider.stopListening();
                             compassProvider.startListening();
                             
                             // Permission Granted -> Try Auto Start Immediately
                             // 少し待ってから開始（ストリームが安定するのを待つ）
                             Future.delayed(const Duration(milliseconds: 500), () {
                               if (mounted) _tryStartAutoNavigation();
                             });
                             
                          } else {
                             // Denied or Error
                             ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                 content: Text('Compass permission $result. Please enable in settings.'),
                                 backgroundColor: AppleColors.dangerRed,
                               ),
                             );
                          }
                       },
                       child: Container(
                         padding: const EdgeInsets.all(24),
                         decoration: BoxDecoration(
                           color: AppleColors.actionBlue,
                           borderRadius: BorderRadius.circular(16),
                           boxShadow: [
                             BoxShadow(
                               color: AppleColors.actionBlue.withValues(alpha: 0.4),
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
                                 color: Colors.white.withValues(alpha: 0.7), 
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



  /// 目的地選択ボタン
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

  /// 目的地チップ（Apple HIG準拠）
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
                  style: AppleTypography.subhead.copyWith(
                    color: Colors.white,
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

  /// 到着ボタン
  Widget _buildArrivalButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: () => _confirmArrival(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppleColors.safetyGreen,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_rounded, size: 24),
              const SizedBox(width: 10),
              Text(
                AppLocalizations.t('btn_arrived_label'),
                style: AppleTypography.headline.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
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
      _showSnackBar(AppLocalizations.t('bot_loc_error'), AppleColors.warningOrange);
      return;
    }

    // 0. Flash Cache Check (Offline Support)
    // キャッシュがあれば即座にナビを開始し、計算待ち時間をゼロにする
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
             AppleColors.safetyGreen,
           );
           return;
       }
    }

    // Type Mapping Logic
    List<String> targetTypes = [type];
    if (type == 'shelter') {
      targetTypes = ['shelter', 'school', 'gov', 'community_centre', 'temple'];
    } else if (type == 'hospital') {
      targetTypes = ['hospital'];
    } else if (type == 'convenience') {
      targetTypes = ['convenience', 'store'];
    } else if (type == 'water') {
      // 日本・タイ両方でコンビニを給水ポイントとして扱う
      targetTypes = ['water', 'convenience', 'store'];
    }

    Shelter? nearest;

    // タイの給水所（Water Station）特別ロジック
    if (type == 'water' && (shelterProvider.currentRegion.toLowerCase().contains('th') || shelterProvider.currentRegion.toLowerCase().contains('satun'))) {
      final waterStation = shelterProvider.getNearestSafeWaterStation(LatLng(userLoc.latitude, userLoc.longitude));
      if (waterStation != null) {
        // RegionalShelter -> Shelter 変換
        nearest = Shelter(
          id: 'water_${waterStation.lat}_${waterStation.lng}',
          name: waterStation.getDisplayName(AppLocalizations.lang),
          lat: waterStation.lat,
          lng: waterStation.lng,
          type: 'water_station', // Custom type
          verified: true,
          region: 'Thailand',
        );
      }
    }

    // 見つからなかった場合（または日本の場合）は通常検索
    if (nearest == null) {
      nearest = shelterProvider.getNearestShelter(
        LatLng(userLoc.latitude, userLoc.longitude),
        includeTypes: targetTypes,
      );
    }

    if (nearest != null) {
      if (nearest.name.toLowerCase() == 'unknown' || nearest.name == '不明') {
        _showSnackBar(AppLocalizations.t('msg_unknown_location'), AppleColors.warningOrange);
        return;
      }
      
      // ハザードゾーン内の避難所かチェック
      final isInHazard = shelterProvider.isShelterInHazardZone(nearest);
      if (isInHazard) {
        // ハザードゾーン外の安全な避難所を探す
        final safeShelter = shelterProvider.getNearestSafeShelter(
          LatLng(userLoc.latitude, userLoc.longitude),
        );
        if (safeShelter != null) {
          nearest = safeShelter;
          _showSnackBar(
            AppLocalizations.t('msg_safer_location').replaceAll('@name', nearest.name),
            AppleColors.warningOrange,
          );
        }
      }

      // 現在地を渡して安全ルートを計算
      final currentLatLng = LatLng(userLoc.latitude, userLoc.longitude);
      await shelterProvider.startNavigation(nearest, currentLocation: currentLatLng);
      
      // 安全ルートが計算されていればコンパスナビゲーションを開始
      final compassProvider = context.read<CompassProvider>();
      
      // Regions Unified Logic
      // 日本(Osaki)もタイ(Satun)も、共通の RoutingEngine で計算された「最大安全ルート」を使用する
      final safeRoute = shelterProvider.getSafestRouteAsLatLng();
      
      if (safeRoute.isNotEmpty) {
          compassProvider.startRouteNavigation(safeRoute);
          if (kDebugMode) {
            print('🧭 安全ルートでコンパスナビゲーション開始 (Unified): ${safeRoute.length}ポイント');
          }
      } else {
          // ルートが見つからない場合（または計算失敗時）は、直線距離ナビにフォールバックする場合などが考えられるが、
          // 今回は「安全ルートが見つからない」ことを通知するフローも検討すべき。
          // ただし、CompassProvider内で startNavigation(route) が空なら何もしないので安全。
          if (kDebugMode) {
             print('⚠️ 安全ルートが見つかりませんでした。コンパスは直線モード（または待機）になります。');
          }
          // 必要に応じて直線ナビを開始するならここ
          // compassProvider.startRouteNavigation([currentLatLng, LatLng(nearest.lat, nearest.lng)]);
      }
      
      // ハプティックフィードバック - 目的地設定
      HapticService.destinationSet();
      
      // 音声で目的地設定を通知（タグラベルのみ）
      final alertProvider = context.read<AlertProvider>();
      final tagLabel = typeLabel ?? AppLocalizations.translateShelterType(type);
      alertProvider.speakDestinationSet(tagLabel);
      
      _lastSpokenDistance = null;
      
      _showSnackBar(
        AppLocalizations.t('bot_dest_set').replaceAll('@name', nearest.name),
        AppleColors.safetyGreen,
      );
    } else {
      _showSnackBar(AppLocalizations.t('msg_no_facility_nearby'), AppleColors.quaternaryLabel);
    }
  }

  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppleTypography.subhead.copyWith(color: Colors.white),
        ),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _confirmArrival(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppleColors.darkSecondaryBackground,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          AppLocalizations.t('dialog_safety_title'),
          style: AppleTypography.title3.copyWith(color: Colors.white),
        ),
        content: Text(
          AppLocalizations.t('dialog_safety_desc'),
          style: AppleTypography.body.copyWith(
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              AppLocalizations.t('btn_cancel'),
              style: AppleTypography.headline.copyWith(
                color: AppleColors.actionBlue,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              // ハプティックフィードバック - 到着確認
              HapticService.arrivedAtDestination();
              
              Navigator.pop(ctx);
              context.read<ShelterProvider>().setSafeInShelter(true);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => const ShelterDashboardScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppleColors.safetyGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              AppLocalizations.t('btn_yes_arrived'),
              style: AppleTypography.headline.copyWith(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}


