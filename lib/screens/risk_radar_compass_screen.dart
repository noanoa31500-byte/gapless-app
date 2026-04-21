import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../providers/compass_provider.dart';
import '../providers/shelter_provider.dart';
import '../providers/location_provider.dart';
import '../providers/language_provider.dart';
import '../providers/region_mode_provider.dart';
import '../services/offline_risk_scanner.dart';
import '../services/risk_radar_scanner.dart';
import '../widgets/risk_radar_compass_widget.dart';
import '../utils/styles.dart';
import '../utils/localization.dart';
import '../widgets/safe_text.dart';
import 'shelter_dashboard_screen.dart';

/// ============================================================================
/// RiskRadarCompassScreen - リスクレーダー付き避難コンパス画面
/// ============================================================================
///
/// 【設計思想】
/// 「画面の赤い方向・雷の方向さえ避ければ生き残れる」
///
/// 泥水で視界が悪い洪水時でも、直感的に安全な方向を判断できる
/// 命を守るためのレーダー型コンパスを提供します。
///
/// 【なぜこの機能が洪水時に有効なのか】
///
/// 1. **激流は突然来る**
///    - 浸水時は流速が予測困難
///    - 浸水シミュレーションデータから流速の速い方向を警告
///
/// 2. **激流は突然来る**
///    - 膝上（0.5m以上）の水深では大人でも流される
///    - 浸水シミュレーションで「深くなる方向」を回避
///
/// 3. **パニック時の認知負荷軽減**
///    - 地図を読む余裕がない災害時
///    - 色だけで判断できるUI（青=浸水、紫=激流、緑=安全）
///
/// 4. **360度全方位の危険把握**
///    - 地図アプリでは前方しか見えない
///    - レーダーなら背後からの激流も把握可能
/// ============================================================================

class RiskRadarCompassScreen extends StatefulWidget {
  const RiskRadarCompassScreen({super.key});

  @override
  State<RiskRadarCompassScreen> createState() => _RiskRadarCompassScreenState();
}

class _RiskRadarCompassScreenState extends State<RiskRadarCompassScreen>
    with SingleTickerProviderStateMixin {
  // --- DESIGN SYSTEM ---
  static const Color _emerald = Color(0xFF00C896);
  static const Color _amber = Color(0xFFFF6B35);
  static const Color _darkBg = Color(0xFF0A0A1A);

  // リスクスキャナー
  late OfflineRiskScanner _baseScanner;
  late RiskRadarScanner _radarScanner;

  // スキャン結果
  RadarScanResult? _scanResult;

  // 状態
  bool _isScanning = false;
  bool _isInitialized = false;

  // ウェイポイント追跡（A*計算済みルートを使用、なければ直線）
  int _waypointIdx = 0;

  // スキャン設定
  static const double _scanRadius = 100.0; // メートル

  @override
  void initState() {
    super.initState();
    _initializeScanner();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final compass = context.read<CompassProvider>();
      if (!compass.hasSensorData) {
        compass.startListening();
      }
    });
  }

  Future<void> _initializeScanner() async {
    _baseScanner = OfflineRiskScanner();
    _radarScanner = RiskRadarScanner(_baseScanner);

    // 現在地域に対応する hazard ファイルをロードする。
    final region = context.read<RegionModeProvider>().region;
    try {
      await _radarScanner.loadData(region: region);
      if (!mounted) return;
      setState(() {
        _isInitialized = true;
      });
      // 初回スキャン実行
      _performScan();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Risk Radar initialization error: $e');
      }
    }
  }

  Future<void> _performScan() async {
    if (!_isInitialized || _isScanning) return;

    final locationProvider = context.read<LocationProvider>();
    final shelterProvider = context.read<ShelterProvider>();

    final currentLocation = locationProvider.currentLocation;
    if (currentLocation == null) return;

    setState(() {
      _isScanning = true;
    });

    // スキャン実行
    final result = _radarScanner.scanRadar(
      currentLocation: LatLng(
        currentLocation.latitude,
        currentLocation.longitude,
      ),
      targetLocation: shelterProvider.navTarget != null
          ? LatLng(
              shelterProvider.navTarget!.lat,
              shelterProvider.navTarget!.lng,
            )
          : null,
      scanRadius: _scanRadius,
    );

    // デバッグ出力
    _radarScanner.printDebugInfo(result);

    setState(() {
      _scanResult = result;
      _isScanning = false;
    });
  }

  Color _getThemeColor() {
    final riskLevel = _scanResult?.overallRiskLevel ?? 0.0;
    if (riskLevel > 0.6) return const Color(0xFFB71C1C); // Dark red
    if (riskLevel > 0.3) return const Color(0xFFE65100); // Dark orange
    return const Color(0xFF1B5E20); // Dark green (safe)
  }

  @override
  Widget build(BuildContext context) {
    // Selector化: 言語と currentRegion のみ購読し、ShelterProvider 全体の変更で再描画されないようにする
    context.select<LanguageProvider, String>((p) => p.currentLanguage);
    final region = context.select<ShelterProvider, String>((p) => p.currentRegion);
    final themeColor = _getThemeColor();

    return Scaffold(
      backgroundColor: _darkBg,
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.4),
            radius: 1.3,
            colors: [
              Color(0xFF0D0D2B),
              Color(0xFF0A0A1A),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ヘッダー
              _buildHeader(region),

              // リスクサマリーバナー
              _buildRiskSummaryBanner(),

              // 目的地情報
              _buildDestinationInfo(),

              // レーダーコンパス（メイン）
              Expanded(
                child: Center(
                  child: _buildRadarCompass(),
                ),
              ),

              // 目的地選択ボタン
              _buildNavigationButtons(),

              // 到着ボタン
              _buildArrivedButton(themeColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(String region) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 1,
                  ),
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.close, color: Colors.white, size: 20),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.radar, color: _emerald, size: 22),
                const SizedBox(width: 8),
                Text(
                  _getScreenTitle(),
                  style: emergencyTextStyle(
                    color: Colors.white,
                    size: 17,
                    isBold: true,
                  ),
                ),
              ],
            ),
          ),
          // スキャンボタン
          ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _emerald.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _emerald.withValues(alpha: 0.35),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _emerald.withValues(alpha: 0.2),
                      blurRadius: 10,
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: _isScanning
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _emerald,
                          ),
                        )
                      : Icon(Icons.refresh, color: _emerald, size: 20),
                  onPressed: _isScanning ? null : _performScan,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getScreenTitle() {
    return GapLessL10n.t('risk_radar_title');
  }

  Widget _buildRiskSummaryBanner() {
    if (_scanResult == null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.12),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: _emerald,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  _getLoadingText(),
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final riskLevel = _scanResult!.overallRiskLevel;
    Color bgColor;
    Color glowColor;
    String riskText;
    IconData icon;

    if (riskLevel > 0.6) {
      bgColor = const Color(0xFFB71C1C);
      glowColor = const Color(0xFFFF1744);
      riskText = _getHighRiskText();
      icon = Icons.warning_rounded;
    } else if (riskLevel > 0.3) {
      bgColor = _amber.withValues(alpha: 0.85);
      glowColor = _amber;
      riskText = _getMediumRiskText();
      icon = Icons.error_outline;
    } else {
      bgColor = _emerald.withValues(alpha: 0.8);
      glowColor = _emerald;
      riskText = _getLowRiskText();
      icon = Icons.check_circle_outline;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.35),
            blurRadius: 16,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        riskText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          letterSpacing: 0.3,
                        ),
                      ),
                      if (_scanResult!.dangerZones.isNotEmpty)
                        Text(
                          _getDangerSummary(),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${(riskLevel * 100).toInt()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getLoadingText() {
    return GapLessL10n.t('risk_loading');
  }

  String _getHighRiskText() {
    return GapLessL10n.t('risk_high');
  }

  String _getMediumRiskText() {
    return GapLessL10n.t('risk_medium');
  }

  String _getLowRiskText() {
    return GapLessL10n.t('risk_low');
  }

  String _getDangerSummary() {
    final flood = _scanResult!.dangerZones
        .where((z) => z.type == RiskType.deepWater).length;
    final rapid = _scanResult!.dangerZones
        .where((z) => z.type == RiskType.rapidFlow).length;

    final parts = <String>[];
    if (flood > 0) parts.add('🌊$flood');
    if (rapid > 0) parts.add('🌀$rapid');

    return parts.join(' ');
  }

  Widget _buildDestinationInfo() {
    return Consumer2<LocationProvider, ShelterProvider>(
      builder: (context, locationProvider, shelterProvider, _) {
        final target = shelterProvider.navTarget;
        final currentLocation = locationProvider.currentLocation;

        if (target == null || currentLocation == null) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.10),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.flag_outlined,
                        color: Colors.white.withValues(alpha: 0.35), size: 20),
                    const SizedBox(width: 8),
                    Text(
                      GapLessL10n.t('loc_no_destination'),
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.45)),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final routeM = shelterProvider.navRouteDistanceM;
        final isComputing = shelterProvider.isComputingRoute;
        final distance = routeM > 0
            ? routeM
            : Geolocator.distanceBetween(
                currentLocation.latitude,
                currentLocation.longitude,
                target.lat,
                target.lng,
              );

        final distanceText = isComputing && routeM <= 0
            ? '計算中…'
            : distance < 1000
                ? '${distance.toStringAsFixed(0)}m'
                : '${(distance / 1000).toStringAsFixed(1)}km';

        // ルート補正が必要かチェック
        final needsCorrection = _scanResult?.safetyGuidance?.needsCorrection ?? false;
        final accentColor = needsCorrection ? _amber : _emerald;

        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.35),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.12),
                    blurRadius: 12,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    needsCorrection ? Icons.alt_route : Icons.flag,
                    color: accentColor,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SafeText(
                          target.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            letterSpacing: 0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (needsCorrection &&
                            _scanResult?.safetyGuidance?.reason != null)
                          Text(
                            _scanResult!.safetyGuidance!.reason,
                            style: TextStyle(
                              color: _amber.withValues(alpha: 0.85),
                              fontSize: 11,
                            ),
                          ),
                      ],
                    ),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.3),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          distanceText,
                          style: TextStyle(
                            color: accentColor,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRadarCompass() {
    return Consumer3<CompassProvider, LocationProvider, ShelterProvider>(
      builder: (context, compassProvider, locationProvider, shelterProvider, _) {
        final target = shelterProvider.navTarget;
        final currentLocation = locationProvider.currentLocation;
        final heading = compassProvider.heading ?? 0.0;
        final route = shelterProvider.computedRoute;

        // ウェイポイント追跡: 現在地から30m以内なら次のウェイポイントへ進める
        if (currentLocation != null && route.length > 2) {
          final clampedIdx = _waypointIdx.clamp(0, route.length - 1);
          final wp = route[clampedIdx];
          final d = Geolocator.distanceBetween(
            currentLocation.latitude, currentLocation.longitude,
            wp.latitude, wp.longitude,
          );
          if (d < 30 && clampedIdx < route.length - 1) {
            // 次フレームで setState
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _waypointIdx = clampedIdx + 1);
            });
          }
        }

        // 向かう先: ルートがあれば次ウェイポイント、なければ目的地直線
        LatLng? aimPoint;
        if (route.length > 2 && currentLocation != null) {
          final idx = _waypointIdx.clamp(0, route.length - 1);
          aimPoint = route[idx];
        } else if (target != null) {
          aimPoint = LatLng(target.lat, target.lng);
        }

        double? targetBearing;
        if (aimPoint != null && currentLocation != null) {
          targetBearing = Geolocator.bearingBetween(
            currentLocation.latitude, currentLocation.longitude,
            aimPoint.latitude, aimPoint.longitude,
          );
          if (targetBearing < 0) targetBearing += 360;
        }

        // 危険回避補正があればそれを優先
        if (_scanResult?.safetyGuidance?.needsCorrection == true) {
          targetBearing = _scanResult!.safetyGuidance!.recommendedBearing;
        }

        // 次の曲がり角指示
        String? turnHint;
        if (route.length > 2 && currentLocation != null) {
          final idx = _waypointIdx.clamp(0, route.length - 2);
          if (idx + 1 < route.length) {
            final bearingToNext = Geolocator.bearingBetween(
              currentLocation.latitude, currentLocation.longitude,
              route[idx].latitude, route[idx].longitude,
            );
            final bearingAfter = Geolocator.bearingBetween(
              route[idx].latitude, route[idx].longitude,
              route[idx + 1].latitude, route[idx + 1].longitude,
            );
            final diff = ((bearingAfter - bearingToNext + 540) % 360) - 180;
            final distToNext = Geolocator.distanceBetween(
              currentLocation.latitude, currentLocation.longitude,
              route[idx].latitude, route[idx].longitude,
            );
            final label = diff > 30 ? GapLessL10n.t('nav_turn_right') : diff < -30 ? GapLessL10n.t('nav_turn_left') : GapLessL10n.t('nav_straight');
            final ahead = GapLessL10n.t('nav_dist_ahead').replaceAll('@dist', '${distToNext.toStringAsFixed(0)}m');
            turnHint = '$ahead $label';
          }
        }

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (turnHint != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _emerald.withValues(alpha: 0.4),
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _emerald.withValues(alpha: 0.15),
                          blurRadius: 12,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: Text(
                      turnHint,
                      style: GapLessL10n.safeStyle(const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        letterSpacing: 0.3,
                      )),
                    ),
                  ),
                ),
              ),
            RiskRadarCompassWidget(
              scanResult: _scanResult,
              deviceHeading: heading,
              targetBearing: targetBearing,
              size: MediaQuery.of(context).size.width * 0.8,
              lang: GapLessL10n.lang,
              isScanning: _isScanning,
              onTap: _performScan,
            ),
            const SizedBox(height: 14),
            _buildLegend(),
          ],
        );
      },
    );
  }

  Widget _buildLegend() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLegendItem('🌊', Colors.blue.shade300, _getLegendText('flood')),
              const SizedBox(width: 16),
              _buildLegendItem('🌀', Colors.purple.shade300, _getLegendText('rapid')),
              const SizedBox(width: 16),
              _buildLegendItem('✅', _emerald, _getLegendText('safe')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(String icon, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _getLegendText(String key) => GapLessL10n.t('risk_legend_$key');

  Widget _buildNavigationButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildNavButton(
              icon: Icons.opacity,
              label: 'Water',
              jpLabel: '給水所',
              thLabel: 'น้ำดื่ม',
              type: 'water',
            ),
            const SizedBox(width: 8),
            _buildNavButton(
              icon: Icons.local_hospital,
              label: 'Hospital',
              jpLabel: '病院',
              thLabel: 'โรงพยาบาล',
              type: 'hospital',
            ),
            const SizedBox(width: 8),
            _buildNavButton(
              icon: Icons.store,
              label: 'Store',
              jpLabel: 'コンビニ',
              thLabel: 'ร้านค้า',
              type: 'convenience',
            ),
            const SizedBox(width: 8),
            _buildNavButton(
              icon: Icons.home,
              label: 'Shelter',
              jpLabel: '避難所',
              thLabel: 'ที่พักพิง',
              type: 'shelter',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavButton({
    required IconData icon,
    required String label,
    required String jpLabel,
    required String thLabel,
    required String type,
  }) {
    final text = GapLessL10n.lang == 'ja'
        ? jpLabel
        : GapLessL10n.lang == 'th'
            ? thLabel
            : label;

    return ActionChip(
      avatar: Icon(icon, size: 16, color: _emerald),
      label: SafeText(
        text,
        style: safeStyle(size: 12, isBold: true),
      ),
      backgroundColor: Colors.white.withValues(alpha: 0.07),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: _emerald.withValues(alpha: 0.4), width: 1),
      ),
      onPressed: () => _findAndStartNavigation(type),
    );
  }

  Future<void> _findAndStartNavigation(String type) async {
    final shelterProvider = context.read<ShelterProvider>();
    final locationProvider = context.read<LocationProvider>();
    final userLoc = locationProvider.currentLocation;

    if (userLoc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: SafeText(GapLessL10n.t('nav_no_location'), style: safeStyle(color: Colors.white))),
      );
      return;
    }

    List<String> targetTypes = [type];
    if (type == 'shelter') {
      targetTypes = ['shelter', 'school', 'gov', 'community_centre', 'temple'];
    } else if (type == 'hospital') {
      targetTypes = ['hospital'];
    } else if (type == 'convenience') {
      targetTypes = ['convenience', 'store'];
    } else if (type == 'water') {
      targetTypes = ['water'];
    }

    final nearest = shelterProvider.getNearestShelter(
      LatLng(userLoc.latitude, userLoc.longitude),
      includeTypes: targetTypes,
    );

    if (nearest != null) {
      await shelterProvider.startNavigation(
        nearest,
        currentLocation: LatLng(userLoc.latitude, userLoc.longitude),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: SafeText(
            GapLessL10n.t('bot_dest_set').replaceAll('@name', nearest.name),
            style: safeStyle(color: Colors.white),
          ),
          backgroundColor: _emerald,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
        ),
      );
      // スキャンを再実行
      _performScan();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            GapLessL10n.t('msg_no_facility_nearby'),
            style: safeStyle(color: Colors.white),
          ),
          backgroundColor: Colors.grey.shade800,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  Widget _buildArrivedButton(Color themeColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: _emerald.withValues(alpha: 0.35),
              blurRadius: 20,
              spreadRadius: 0,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: () => _confirmArrival(context),
            icon: const Icon(Icons.check_circle, size: 22),
            label: Text(
              GapLessL10n.t('btn_arrived_label'),
              style: emergencyTextStyle(size: 16, isBold: true),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _emerald,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmArrival(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A38),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: SafeText(
          GapLessL10n.t('dialog_safety_title'),
          style: TextStyle(
            color: _emerald,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: SafeText(
          GapLessL10n.t('dialog_safety_desc'),
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: SafeText(
              GapLessL10n.t('btn_cancel'),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: _emerald.withValues(alpha: 0.3),
                  blurRadius: 12,
                  spreadRadius: 0,
                ),
              ],
            ),
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                context.read<ShelterProvider>().setSafeInShelter(true);
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ShelterDashboardScreen(),
                  ),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _emerald,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: SafeText(
                GapLessL10n.t('btn_yes_arrived'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
