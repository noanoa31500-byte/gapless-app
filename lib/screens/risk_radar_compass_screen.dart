import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../providers/compass_provider.dart';
import '../providers/shelter_provider.dart';
import '../providers/location_provider.dart';
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
/// 1. **感電死は「見えない死」**
///    - タイの洪水では、水没した電線からの感電死が深刻
///    - 濁った水中では電線が見えない
///    - 電力インフラの位置から危険方向を事前警告
/// 
/// 2. **激流は突然来る**
///    - 膝上（0.5m以上）の水深では大人でも流される
///    - 浸水シミュレーションで「深くなる方向」を回避
/// 
/// 3. **パニック時の認知負荷軽減**
///    - 地図を読む余裕がない災害時
///    - 色だけで判断できるUI（黄色=感電、青=浸水、緑=安全）
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
  // リスクスキャナー
  late OfflineRiskScanner _baseScanner;
  late RiskRadarScanner _radarScanner;
  
  // スキャン結果
  RadarScanResult? _scanResult;
  
  // 状態
  bool _isScanning = false;
  bool _isInitialized = false;
  
  // スキャン設定
  static const double _scanRadius = 100.0; // メートル
  
  @override
  void initState() {
    super.initState();
    _initializeScanner();
  }

  Future<void> _initializeScanner() async {
    _baseScanner = OfflineRiskScanner();
    _radarScanner = RiskRadarScanner(_baseScanner);
    
    try {
      await _radarScanner.loadData();
      setState(() {
        _isInitialized = true;
      });
      // 初回スキャン実行
      _performScan();
    } catch (e) {
      if (kDebugMode) {
        print('❌ Risk Radar initialization error: $e');
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
    _radarScanner.debugPrint(result);
    
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
    final shelterProvider = context.watch<ShelterProvider>();
    final region = shelterProvider.currentRegion;
    final themeColor = _getThemeColor();

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
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
    );
  }

  Widget _buildHeader(String region) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.radar, color: Colors.green, size: 24),
                const SizedBox(width: 8),
                Text(
                  _getScreenTitle(),
                  style: emergencyTextStyle(
                    color: Colors.white,
                    size: 18,
                    isBold: true,
                  ),
                ),
              ],
            ),
          ),
          // スキャンボタン
          IconButton(
            icon: _isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.green,
                    ),
                  )
                : const Icon(Icons.refresh, color: Colors.green),
            onPressed: _isScanning ? null : _performScan,
          ),
        ],
      ),
    );
  }

  String _getScreenTitle() {
    return AppLocalizations.t('risk_radar_title');
  }

  Widget _buildRiskSummaryBanner() {
    if (_scanResult == null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade800,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              _getLoadingText(),
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ),
      );
    }

    final riskLevel = _scanResult!.overallRiskLevel;
    Color bgColor;
    String riskText;
    IconData icon;

    if (riskLevel > 0.6) {
      bgColor = Colors.red.shade800;
      riskText = _getHighRiskText();
      icon = Icons.warning_rounded;
    } else if (riskLevel > 0.3) {
      bgColor = Colors.orange.shade800;
      riskText = _getMediumRiskText();
      icon = Icons.error_outline;
    } else {
      bgColor = Colors.green.shade800;
      riskText = _getLowRiskText();
      icon = Icons.check_circle_outline;
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
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
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${(riskLevel * 100).toInt()}%',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getLoadingText() {
    return AppLocalizations.t('risk_loading');
  }

  String _getHighRiskText() {
    return AppLocalizations.t('risk_high');
  }

  String _getMediumRiskText() {
    return AppLocalizations.t('risk_medium');
  }

  String _getLowRiskText() {
    return AppLocalizations.t('risk_low');
  }

  String _getDangerSummary() {
    final electro = _scanResult!.dangerZones
        .where((z) => z.type == RiskType.electrocution).length;
    final flood = _scanResult!.dangerZones
        .where((z) => z.type == RiskType.deepWater).length;
    final rapid = _scanResult!.dangerZones
        .where((z) => z.type == RiskType.rapidFlow).length;
    
    final parts = <String>[];
    if (electro > 0) parts.add('⚡$electro');
    if (flood > 0) parts.add('🌊$flood');
    if (rapid > 0) parts.add('💨$rapid');
    
    return parts.join(' ');
  }

  Widget _buildDestinationInfo() {
    return Consumer2<LocationProvider, ShelterProvider>(
      builder: (context, locationProvider, shelterProvider, _) {
        final target = shelterProvider.navTarget;
        final currentLocation = locationProvider.currentLocation;

        if (target == null || currentLocation == null) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.flag_outlined, color: Colors.grey, size: 20),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.t('loc_no_destination'),
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        final distance = Geolocator.distanceBetween(
          currentLocation.latitude,
          currentLocation.longitude,
          target.lat,
          target.lng,
        );
        
        final distanceText = distance < 1000
            ? '${distance.toStringAsFixed(0)}m'
            : '${(distance / 1000).toStringAsFixed(1)}km';

        // ルート補正が必要かチェック
        final needsCorrection = _scanResult?.safetyGuidance?.needsCorrection ?? false;

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: needsCorrection 
                ? Colors.orange.shade900.withValues(alpha: 0.5)
                : Colors.green.shade900.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: needsCorrection ? Colors.orange : Colors.green,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                needsCorrection ? Icons.alt_route : Icons.flag,
                color: needsCorrection ? Colors.orange : Colors.green,
                size: 24,
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
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (needsCorrection && _scanResult?.safetyGuidance?.reason != null)
                      Text(
                        _scanResult!.safetyGuidance!.reason,
                        style: TextStyle(
                          color: Colors.orange.shade200,
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  distanceText,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
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

        double? targetBearing;
        if (target != null && currentLocation != null) {
          targetBearing = Geolocator.bearingBetween(
            currentLocation.latitude,
            currentLocation.longitude,
            target.lat,
            target.lng,
          );
          // -180〜180 を 0〜360 に変換
          if (targetBearing < 0) targetBearing += 360;
        }

        // 補正された方位があればそれを使用
        if (_scanResult?.safetyGuidance?.needsCorrection == true) {
          targetBearing = _scanResult!.safetyGuidance!.recommendedBearing;
        }

        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // レーダーコンパス
            RiskRadarCompassWidget(
              scanResult: _scanResult,
              deviceHeading: heading,
              targetBearing: targetBearing,
              size: MediaQuery.of(context).size.width * 0.8,
              lang: AppLocalizations.lang,
              isScanning: _isScanning,
              onTap: _performScan,
            ),
            const SizedBox(height: 16),
            // 凡例
            _buildLegend(),
          ],
        );
      },
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLegendItem('⚡', Colors.yellow, _getLegendText('shock')),
          const SizedBox(width: 16),
          _buildLegendItem('🌊', Colors.blue, _getLegendText('flood')),
          const SizedBox(width: 16),
          _buildLegendItem('💨', Colors.purple, _getLegendText('rapid')),
          const SizedBox(width: 16),
          _buildLegendItem('✅', Colors.green, _getLegendText('safe')),
        ],
      ),
    );
  }

  Widget _buildLegendItem(String icon, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(icon, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 11)),
      ],
    );
  }

  String _getLegendText(String key) {
    const texts = {
      'shock': {'ja': '感電', 'en': 'Shock', 'th': 'ไฟฟ้า'},
      'flood': {'ja': '浸水', 'en': 'Flood', 'th': 'น้ำท่วม'},
      'rapid': {'ja': '激流', 'en': 'Rapid', 'th': 'น้ำไหลเชี่ยว'},
      'safe': {'ja': '安全', 'en': 'Safe', 'th': 'ปลอดภัย'},
    };
    return texts[key]?[AppLocalizations.lang] ?? texts[key]?['en'] ?? key;
  }

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
    final text = AppLocalizations.lang == 'ja'
        ? jpLabel
        : AppLocalizations.lang == 'th'
            ? thLabel
            : label;

    return ActionChip(
      avatar: Icon(icon, size: 16, color: Colors.green),
      label: SafeText(
        text,
        style: safeStyle(size: 12, isBold: true),
      ),
      backgroundColor: Colors.grey.shade900,
      surfaceTintColor: Colors.grey.shade900,
      elevation: 2,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Colors.green, width: 1),
      ),
      onPressed: () => _findAndStartNavigation(type),
    );
  }

  void _findAndStartNavigation(String type) {
    final shelterProvider = context.read<ShelterProvider>();
    final locationProvider = context.read<LocationProvider>();
    final userLoc = locationProvider.currentLocation;

    if (userLoc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Location not available')),
      );
      return;
    }

    final region = shelterProvider.currentRegion;
    final countryCode = region.startsWith('th') ? 'TH' : 'JP';

    List<String> targetTypes = [type];
    if (type == 'shelter') {
      targetTypes = ['shelter', 'school', 'gov', 'community_centre', 'temple'];
    } else if (type == 'hospital') {
      targetTypes = ['hospital'];
    } else if (type == 'convenience') {
      targetTypes = ['convenience', 'store'];
    } else if (type == 'water') {
      if (countryCode == 'TH') {
        targetTypes = ['water', 'convenience', 'store'];
      } else {
        targetTypes = ['water'];
      }
    }

    final nearest = shelterProvider.getNearestShelter(
      LatLng(userLoc.latitude, userLoc.longitude),
      includeTypes: targetTypes,
    );

    if (nearest != null) {
      shelterProvider.startNavigation(nearest);
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: SafeText(
            AppLocalizations.t('bot_dest_set').replaceAll('@name', nearest.name),
            style: safeStyle(color: Colors.white),
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
      // スキャンを再実行
      _performScan();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.t('msg_no_facility_nearby'),
            style: safeStyle(color: Colors.white),
          ),
          backgroundColor: Colors.grey,
        ),
      );
    }
  }

  Widget _buildArrivedButton(Color themeColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: () => _confirmArrival(context),
          icon: const Icon(Icons.check_circle, size: 24),
          label: Text(
            AppLocalizations.t('btn_arrived_label'),
            style: emergencyTextStyle(size: 16, isBold: true),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(25),
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
        title: Text(AppLocalizations.t('dialog_safety_title')),
        content: Text(AppLocalizations.t('dialog_safety_desc')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(AppLocalizations.t('btn_cancel')),
          ),
          ElevatedButton(
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
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text(AppLocalizations.t('btn_yes_arrived')),
          ),
        ],
      ),
    );
  }
}
