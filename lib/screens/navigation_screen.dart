import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/road_feature.dart';
import '../models/shelter.dart';
import '../models/user_profile.dart' as nav;
import '../providers/user_profile_provider.dart';
import '../providers/language_provider.dart';
import '../providers/location_provider.dart';
import '../providers/shelter_provider.dart';
import '../screens/emergency_card_screen.dart';
import '../screens/shelter_dashboard_screen.dart';
import '../screens/survival_guide_screen.dart';
import '../screens/settings_screen.dart';
import '../services/ble_road_report_service.dart';
import '../services/fallback_mode_controller.dart';
import '../data/map_repository.dart';
import '../data/road_parser.dart';
import '../services/gps_logger.dart';
import '../services/navigation_announcer.dart';
import '../services/power_manager.dart';
import '../utils/localization.dart';
import '../services/road_report_scorer.dart';
import '../services/safety_route_engine.dart';
import '../services/sensor_fusion_bearing_controller.dart';
import '../widgets/calibration_overlay.dart';
import '../widgets/quick_report_sheet.dart';
import '../widgets/return_home_compass.dart';
import '../widgets/turn_by_turn_panel.dart';

// ============================================================================
// NavigationScreen — 全サービス統合ナビゲーション画面
// ============================================================================

// ── アクセシビリティプロファイル ────────────────────────────────────────────

enum _AccessProfile { standard, elderly, wheelchair }

// ── Isolate ルート計算 ──────────────────────────────────────────────────────

class _RouteComputeParams {
  final List<RoadFeature> features;
  final double startLat;
  final double startLng;
  final double goalLat;
  final double goalLng;
  final bool requiresFlatRoute;
  final bool isElderly;
  final double walkSpeedMps;

  const _RouteComputeParams({
    required this.features,
    required this.startLat,
    required this.startLng,
    required this.goalLat,
    required this.goalLng,
    required this.requiresFlatRoute,
    required this.isElderly,
    required this.walkSpeedMps,
  });
}

RouteResult _computeRouteInIsolate(_RouteComputeParams p) {
  final engine = SafetyRouteEngine();
  final profile = nav.UserProfile(
    requiresFlatRoute: p.requiresFlatRoute,
    isElderly: p.isElderly,
    walkSpeedMps: p.walkSpeedMps,
  );
  engine.buildGraph(p.features, profile: profile);
  return engine.findRoute(
    LatLng(p.startLat, p.startLng),
    LatLng(p.goalLat, p.goalLng),
    profile: profile,
  );
}

// ── ウィジェット ───────────────────────────────────────────────────────────

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  static const Color _greenPrimary = Color(0xFF2E7D32);
  static const Color _orangeAccent = Color(0xFFFF6F00);

  // ── サービス ──────────────────────────────────────────────────────────────
  final _fallback = FallbackModeController();
  final _sensorFusion = SensorFusionBearingController();
  final _announcer = NavigationAnnouncer();
  final _mapController = MapController();
  final _ble = BleRoadReportService.instance;

  // ── ストリーム購読 ────────────────────────────────────────────────────────
  StreamSubscription<BearingState>? _bearingSub;
  StreamSubscription<bool>? _calibrationSub;
  StreamSubscription<DivergenceWarning>? _divergenceSub;

  // ── 状態 ─────────────────────────────────────────────────────────────────
  List<RoadFeature> _roadFeatures = [];
  List<LatLng> _route = [];
  LatLng? _destination;
  String? _destinationName;
  bool _isLoadingMap = true;
  String? _loadError;
  bool _showCalibration = false;
  double _headingDeg = 0;
  double _divergenceDeg = 0;
  bool _showDivergence = false;
  bool _isCalculatingRoute = false;
  double _loadProgress = 0;
  bool _outOfBoundsAnnounced = false;

  // 前回のアクセシビリティプロファイル（前セクションで実装済み）
  _AccessProfile _accessProfile = _AccessProfile.standard;

  // BLEピアレポートの期限切れパージタイマー
  Timer? _bleScoreRefreshTimer;

  // 機能4: GPS軌跡バッファ（表示用）
  List<LatLng> _gpsTrack = [];
  Timer? _trackRefreshTimer;

  // ── ライフサイクル ────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootServices());
  }

  Future<void> _bootServices() async {
    try {
      final bytes = await MapRepository.instance.readBytes('tokyo_center_roads.gplb');
      _roadFeatures = RoadParser.parse(bytes);
      _fallback.setBoundsFromLatLngs(_roadFeatures.expand((r) => r.geometry));
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e is Exception ? e.toString() : GapLessL10n.t('map_load_error');
          _isLoadingMap = false;
        });
      }
      return;
    }

    await GpsLogger.instance.startLogging();
    await PowerManager.instance.start();
    await _announcer.init();
    _sensorFusion.start();

    _bearingSub = _sensorFusion.bearingStream.listen((state) {
      if (mounted) setState(() => _headingDeg = state.bearing);
    });
    _calibrationSub = _sensorFusion.calibrationNeededStream.listen((needed) {
      if (mounted) setState(() => _showCalibration = needed);
    });
    _divergenceSub = _sensorFusion.divergenceWarningStream.listen((w) {
      if (!mounted) return;
      setState(() {
        _divergenceDeg = w.divergenceDeg;
        _showDivergence = true;
      });
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted) setState(() => _showDivergence = false);
      });
    });

    GpsLogger.instance.addListener(_onGpsUpdate);
    _fallback.addListener(_onFallbackChanged);

    if (mounted) context.read<LocationProvider>().startLocationTracking();

    // 機能2: BLEサービス起動 & スコア更新タイマー
    _ble.start();
    _bleScoreRefreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) {
        if (mounted) {
          _ble.scorer.purgeExpired();
          setState(() {});
        }
      },
    );

    // BLEレポート更新時に再描画
    _ble.scorer.addListener(_onScoreUpdated);

    // 機能3: PowerManager 省電力モード変化 → BleRoadReportService に通知
    PowerManager.instance.addListener(_onPowerModeChanged);

    // 機能4: 言語変化 → TTS 言語を即座に切り替え
    context.read<LanguageProvider>().addListener(_onLanguageChanged);

    // 機能4: GPS軌跡を5秒ごとに更新して地図に反映
    _trackRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final track = GpsLogger.instance.backtrackRouteFromBuffer().reversed.toList();
      setState(() => _gpsTrack = track);
    });

    // 避難所データをロード（ShelterProviderが空ならロード）
    final shelterProv = context.read<ShelterProvider>();
    if (shelterProv.shelters.isEmpty) {
      shelterProv.loadShelters();
    }

    // 機能3: UserProfileProvider.needs に基づいて _accessProfile を自動初期化
    _initAccessProfileFromUserNeeds();

    if (mounted) setState(() => _isLoadingMap = false);
  }

  /// 緊急カードに登録されたニーズからアクセシビリティプロファイルを自動設定
  void _initAccessProfileFromUserNeeds() {
    if (!mounted) return;
    final needs = context.read<UserProfileProvider>().profile.needs;
    _AccessProfile auto;
    if (needs.contains('Wheelchair')) {
      auto = _AccessProfile.wheelchair;
    } else if (needs.contains('Pregnancy') || needs.contains('Infant')) {
      auto = _AccessProfile.elderly; // ゆっくりペースを推奨
    } else {
      return; // 変更不要
    }
    // 手動変更済みでなければ自動プロファイルを適用
    if (_accessProfile == _AccessProfile.standard) {
      setState(() => _accessProfile = auto);
    }
  }

  void _onScoreUpdated() {
    if (mounted) setState(() {});
  }

  // 機能4: 言語変化 → TTS 言語を即座に更新
  void _onLanguageChanged() {
    _announcer.updateLanguage();
  }

  // 機能3: 省電力モード変化 → BLE スキャン間隔 & GPS取得間隔を連動
  void _onPowerModeChanged() {
    _ble.setSavingMode(PowerManager.instance.isPowerSaving);
    // 機能1: GpsLogger の取得間隔も PowerManager に追随させる
    GpsLogger.instance.onGpsIntervalChanged(PowerManager.instance.gpsIntervalSec);
  }

  // 機能5: 最後に警告した狭道セグメントの中点（連続発話防止）
  LatLng? _lastNarrowRoadWarned;

  // 機能5: 自動リルート制御（連続再計算を防ぐ）
  DateTime? _lastRerouteTime;

  void _onGpsUpdate() {
    final entry = GpsLogger.instance.latestEntry;
    if (entry == null) return;
    _fallback.updatePosition(entry.latLng);

    // 機能5: 現在地 30m 以内の狭道（幅 ≤ 2m）を検索して TTS 警告
    _checkNarrowRoadAhead(entry.latLng);

    // 機能5: ルート逸脱検知 → 自動リルート
    _checkOffRoute(entry.latLng);
  }

  /// ルートから 50m 以上離れたら自動再計算（30秒デバウンス）
  void _checkOffRoute(LatLng pos) {
    if (_route.isEmpty || _destination == null || _isCalculatingRoute) return;

    // 30秒以内に再計算済みの場合はスキップ
    if (_lastRerouteTime != null &&
        DateTime.now().difference(_lastRerouteTime!) <
            const Duration(seconds: 30)) return;

    const dist = Distance();
    double minDist = double.infinity;
    for (final pt in _route) {
      final d = dist(pos, pt);
      if (d < minDist) minDist = d;
    }

    if (minDist > 50.0) {
      _lastRerouteTime = DateTime.now();
      _showSnack('ルートを外れました。再計算します…');
      _calculateRoute();
    }
  }

  void _checkNarrowRoadAhead(LatLng pos) {
    if (_roadFeatures.isEmpty) return;
    const dist = Distance();
    const double warningRadiusM = 30.0;

    for (final road in _roadFeatures) {
      final w = road.widthMeters;
      if (w == null || w > 2.0) continue;

      // セグメントの各点との距離をチェック
      bool nearThisRoad = false;
      for (final pt in road.geometry) {
        if (dist(pos, pt) <= warningRadiusM) {
          nearThisRoad = true;
          break;
        }
      }
      if (!nearThisRoad) continue;

      // 同じ地点への連続警告を防止（50m 以上離れたら再警告可）
      final mid = road.midpoint;
      if (_lastNarrowRoadWarned != null &&
          dist(_lastNarrowRoadWarned!, mid) < 50.0) {
        continue;
      }

      _lastNarrowRoadWarned = mid;
      _announcer.announceNarrowRoad(w);
      break; // 1回の更新で1件のみ警告
    }
  }

  void _onFallbackChanged() {
    if (_fallback.mode == FallbackMode.returnHome && !_outOfBoundsAnnounced) {
      _outOfBoundsAnnounced = true;
      _announcer.announceOutOfBounds();
    }
    if (_fallback.mode == FallbackMode.normal) {
      _outOfBoundsAnnounced = false;
    }
  }

  @override
  void dispose() {
    GpsLogger.instance.removeListener(_onGpsUpdate);
    GpsLogger.instance.stopLogging();
    _fallback.removeListener(_onFallbackChanged);
    _fallback.dispose();
    _sensorFusion.dispose();
    _bearingSub?.cancel();
    _calibrationSub?.cancel();
    _divergenceSub?.cancel();
    _announcer.dispose();
    _ble.scorer.removeListener(_onScoreUpdated);
    PowerManager.instance.removeListener(_onPowerModeChanged);
    // ignore: use_build_context_synchronously
    context.read<LanguageProvider>().removeListener(_onLanguageChanged);
    _ble.stop();
    _bleScoreRefreshTimer?.cancel();
    _trackRefreshTimer?.cancel();
    super.dispose();
  }

  // ── ルート計算 ────────────────────────────────────────────────────────────

  Future<void> _calculateRoute() async {
    final dest = _destination;
    if (dest == null || _roadFeatures.isEmpty || !mounted) return;

    final currentLoc = context.read<LocationProvider>().currentLocation;
    if (currentLoc == null) return;

    setState(() => _isCalculatingRoute = true);

    // 機能4: プロファイルに基づいてパラメータを設定
    final bool requiresFlat = _accessProfile == _AccessProfile.wheelchair;
    final bool isElderly = _accessProfile == _AccessProfile.elderly;
    final double speed = _accessProfile == _AccessProfile.wheelchair
        ? 0.8
        : _accessProfile == _AccessProfile.elderly
            ? 0.9
            : 1.2;

    try {
      final result = await compute(
        _computeRouteInIsolate,
        _RouteComputeParams(
          features: _roadFeatures,
          startLat: currentLoc.latitude,
          startLng: currentLoc.longitude,
          goalLat: dest.latitude,
          goalLng: dest.longitude,
          requiresFlatRoute: requiresFlat,
          isElderly: isElderly,
          walkSpeedMps: speed,
        ),
      );
      if (mounted) {
        setState(() {
          _route = result.waypoints;
          _isCalculatingRoute = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isCalculatingRoute = false);
    }
  }

  // 機能1: 最寄り避難所への自動ルーティング
  Future<void> _navigateToNearestShelter() async {
    final currentLoc = context.read<LocationProvider>().currentLocation;
    if (currentLoc == null) {
      _showSnack(GapLessL10n.t('nav_no_location'));
      return;
    }

    final shelterProvider = context.read<ShelterProvider>();
    final nearest = shelterProvider.getAbsoluteNearest(currentLoc);
    if (nearest == null) {
      _showSnack(GapLessL10n.t('nav_no_shelter'));
      return;
    }

    setState(() {
      _destination = LatLng(nearest.lat, nearest.lng);
      _destinationName = nearest.name;
    });
    _mapController.move(LatLng(nearest.lat, nearest.lng), 15.0);
    await _calculateRoute();

    if (mounted) {
      _showSnack(GapLessL10n.t('nav_route_calculated').replaceAll('@name', nearest.name));
    }
  }

  // ── ユーザー操作 ──────────────────────────────────────────────────────────

  void _onMapTap(TapPosition _, LatLng latlng) {
    setState(() {
      _destination = latlng;
      _destinationName = null;
    });
    _calculateRoute();
  }

  void _moveToCurrentLocation() {
    final loc = context.read<LocationProvider>().currentLocation;
    if (loc != null) _mapController.move(loc, 15.0);
  }

  // 機能5: 到着 → 安全確認ダイアログ → ShelterDashboard遷移
  void _onArrived() {
    _announcer.announceWaypointPassed(0, 1, 0);
    setState(() {
      _route = [];
      _destination = null;
      _destinationName = null;
    });

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            const Icon(Icons.flag_rounded, color: Color(0xFFFF6F00), size: 28),
            const SizedBox(width: 12),
            Text(GapLessL10n.t('nav_arrive_title'),
                style: GapLessL10n.safeStyle(const TextStyle(fontSize: 18))),
          ],
        ),
        content: Text(GapLessL10n.t('nav_arrive_body'), style: GapLessL10n.safeStyle(const TextStyle())),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(GapLessL10n.t('nav_still_moving'), style: GapLessL10n.safeStyle(const TextStyle())),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ShelterDashboardScreen()),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF388E3C),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(GapLessL10n.t('nav_safe_confirm'), style: GapLessL10n.safeStyle(const TextStyle())),
          ),
        ],
      ),
    );
  }

  Future<void> _startBacktrack() async {
    final waypoints = await GpsLogger.instance.backtrackRoute();
    if (waypoints.isEmpty) return;
    _fallback.startBacktrack(waypoints);
    await _announcer.announceBacktrackStart();
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: _greenPrimary,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  // 機能3: 道路状況報告BottomSheet
  void _showRoadReportSheet() {
    final loc = context.read<LocationProvider>().currentLocation;
    if (loc == null) {
      _showSnack(GapLessL10n.t('nav_no_location'));
      return;
    }
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _RoadReportSheet(
        currentLat: loc.latitude,
        currentLng: loc.longitude,
        onReport: (passable) {
          _ble.enqueueReport(
            lat: loc.latitude,
            lng: loc.longitude,
            accuracyM: 10.0,
            passable: passable,
          );
          _showSnack(passable ? GapLessL10n.t('nav_reported_passable') : GapLessL10n.t('nav_reported_blocked'));
        },
      ),
    );
  }

  // 機能4: アクセシビリティプロファイル選択ダイアログ
  void _showAccessProfileDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(GapLessL10n.t('nav_profile_title')),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ProfileOption(
              icon: Icons.directions_walk,
              label: GapLessL10n.t('nav_profile_standard'),
              subtitle: GapLessL10n.t('nav_profile_standard_sub'),
              selected: _accessProfile == _AccessProfile.standard,
              onTap: () {
                setState(() => _accessProfile = _AccessProfile.standard);
                Navigator.pop(context);
                if (_destination != null) _calculateRoute();
              },
            ),
            _ProfileOption(
              icon: Icons.elderly,
              label: GapLessL10n.t('nav_profile_elderly'),
              subtitle: GapLessL10n.t('nav_profile_elderly_sub'),
              selected: _accessProfile == _AccessProfile.elderly,
              onTap: () {
                setState(() => _accessProfile = _AccessProfile.elderly);
                Navigator.pop(context);
                if (_destination != null) _calculateRoute();
              },
            ),
            _ProfileOption(
              icon: Icons.accessible,
              label: GapLessL10n.t('nav_profile_wheelchair'),
              subtitle: GapLessL10n.t('nav_profile_wheelchair_sub'),
              selected: _accessProfile == _AccessProfile.wheelchair,
              onTap: () {
                setState(() => _accessProfile = _AccessProfile.wheelchair);
                Navigator.pop(context);
                if (_destination != null) _calculateRoute();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>(); // 言語変更時に再描画
    return ListenableBuilder(
      listenable: Listenable.merge([_fallback, PowerManager.instance]),
      builder: (_, __) {
        final bgValue = PowerManager.instance.backgroundColorValue;
        return Scaffold(
          backgroundColor: bgValue != null ? Color(bgValue) : null,
          appBar: _buildAppBar(),
          // 機能3: BottomNavigationBar（タップでNavigator.push）
          bottomNavigationBar: _buildBottomNav(),
          body: Consumer<LocationProvider>(
            builder: (_, locationProv, __) {
              final inFallback = _fallback.isInFallback;
              return Column(
                children: [
                  _NavStatusBar(ble: _ble, locationProv: locationProv),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: inFallback
                          ? _buildFallbackCompass()
                          : _buildMapStack(locationProv.currentLocation),
                    ),
                  ),
                ],
              );
            },
          ),
          floatingActionButton: _buildFabGroup(),
        );
      },
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: _greenPrimary,
      foregroundColor: Colors.white,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(GapLessL10n.t('nav_screen_title'),
              style: GapLessL10n.safeStyle(const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          if (_destinationName != null)
            Text(
              _destinationName!,
              style: GapLessL10n.safeStyle(const TextStyle(fontSize: 11, color: Colors.white70)),
            ),
        ],
      ),
      actions: [
        // 機能4: アクセシビリティアイコン
        IconButton(
          onPressed: _showAccessProfileDialog,
          tooltip: GapLessL10n.t('nav_profile_title'),
          icon: Icon(
            _accessProfile == _AccessProfile.wheelchair
                ? Icons.accessible
                : _accessProfile == _AccessProfile.elderly
                    ? Icons.elderly
                    : Icons.directions_walk,
            color: _accessProfile != _AccessProfile.standard
                ? _orangeAccent
                : Colors.white,
          ),
        ),
        // 電池表示
        ListenableBuilder(
          listenable: PowerManager.instance,
          builder: (_, __) {
            final level = PowerManager.instance.batteryLevel;
            final saving = PowerManager.instance.isPowerSaving;
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    saving ? Icons.battery_alert : Icons.battery_full,
                    color: saving ? _orangeAccent : Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$level%',
                    style: TextStyle(
                        color: saving ? _orangeAccent : Colors.white,
                        fontSize: 13),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ── 地図スタック ──────────────────────────────────────────────────────────

  Widget _buildMapStack(LatLng? currentLoc) {
    if (_loadError != null) return _buildError();
    if (_isLoadingMap) return _buildLoading();

    final scores = _ble.scorer.scores;
    final reportMarkers = _buildReportMarkers(scores);

    // 機能2: 避難所マーカー
    final shelterProv = context.read<ShelterProvider>();
    final shelterMarkers = _buildShelterMarkers(shelterProv.displayedShelters);

    return Stack(
      key: const ValueKey('map'),
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: currentLoc ?? const LatLng(35.6895, 139.6917),
            initialZoom: 15.0,
            onTap: _onMapTap,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.gapless',
            ),
            // 機能4: GPS軌跡（薄い紫ライン）
            if (_gpsTrack.length >= 2)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _gpsTrack,
                    color: const Color(0x556A1B9A),
                    strokeWidth: 3,
                    isDotted: true,
                  ),
                ],
              ),
            if (_route.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _route,
                    color: _greenPrimary,
                    strokeWidth: 4,
                  ),
                ],
              ),
            // BLEピアレポートマーカー
            if (reportMarkers.isNotEmpty)
              MarkerLayer(markers: reportMarkers),
            // 機能2: 避難所マーカー
            if (shelterMarkers.isNotEmpty)
              MarkerLayer(markers: shelterMarkers),
            MarkerLayer(
              markers: [
                if (currentLoc != null)
                  Marker(
                    point: currentLoc,
                    width: 40,
                    height: 40,
                    child: Transform.rotate(
                      angle: _headingDeg * 3.14159265 / 180,
                      child: const Icon(Icons.navigation,
                          color: _orangeAccent, size: 36),
                    ),
                  ),
                if (_destination != null)
                  Marker(
                    point: _destination!,
                    width: 36,
                    height: 36,
                    child: const Icon(Icons.location_pin,
                        color: Color(0xFFB71C1C), size: 36),
                  ),
              ],
            ),
          ],
        ),
        DivergenceWarningBanner(
          visible: _showDivergence,
          divergenceDeg: _divergenceDeg,
        ),
        CalibrationOverlay(
          visible: _showCalibration,
          onDismiss: () => setState(() => _showCalibration = false),
        ),
        if (_isCalculatingRoute)
          Positioned(
            bottom: 116,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: _greenPrimary,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Text(GapLessL10n.t('nav_calculating'),
                        style: GapLessL10n.safeStyle(const TextStyle(color: Colors.white, fontSize: 14))),
                  ],
                ),
              ),
            ),
          ),
        if (currentLoc != null)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: TurnByTurnPanel(
              route: _route,
              currentPosition: currentLoc,
              headingDeg: _headingDeg,
              onArrived: _onArrived,
            ),
          ),
      ],
    );
  }

  // 機能2: スコアデータからマーカーリストを生成
  List<Marker> _buildReportMarkers(Map<String, SegmentScore> scores) {
    final markers = <Marker>[];
    for (final entry in scores.entries) {
      final segId = entry.key;
      final score = entry.value;
      // セグメントIDから緯度経度を復元（"lat,lng"形式）
      final parts = segId.split(',');
      if (parts.length != 2) continue;
      final lat = double.tryParse(parts[0]);
      final lng = double.tryParse(parts[1]);
      if (lat == null || lng == null) continue;

      final opacity = score.displayOpacity.clamp(0.3, 1.0);
      final isDangerous = score.isConfirmedDangerous;
      final isSafe = score.isConfirmedSafe;

      // 未確定レポートは薄く表示
      if (!isDangerous && !isSafe && score.passableWeight + score.impassableWeight < 0.5) {
        continue;
      }

      markers.add(Marker(
        point: LatLng(lat, lng),
        width: 32,
        height: 32,
        child: Opacity(
          opacity: opacity,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDangerous
                  ? const Color(0xFFD32F2F)
                  : isSafe
                      ? const Color(0xFF388E3C)
                      : const Color(0xFFFFA000),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Icon(
              isDangerous
                  ? Icons.block
                  : isSafe
                      ? Icons.check_circle
                      : Icons.warning_amber,
              color: Colors.white,
              size: 16,
            ),
          ),
        ),
      ));
    }
    return markers;
  }

  // 機能2: 避難所マーカー生成（タップで目的地設定）
  List<Marker> _buildShelterMarkers(List<Shelter> shelters) {
    return shelters.map((s) {
      final isTarget = _destination != null &&
          (_destination!.latitude - s.lat).abs() < 0.0001 &&
          (_destination!.longitude - s.lng).abs() < 0.0001;
      return Marker(
        point: LatLng(s.lat, s.lng),
        width: 44,
        height: 44,
        child: GestureDetector(
          onTap: () {
            setState(() {
              _destination = LatLng(s.lat, s.lng);
              _destinationName = s.name;
            });
            _calculateRoute();
            _showSnack(GapLessL10n.t('nav_route_to').replaceAll('@name', s.name));
          },
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isTarget ? _orangeAccent : _greenPrimary,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
              ],
            ),
            child: Icon(
              s.type == 'hospital' ? Icons.local_hospital : Icons.night_shelter,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      );
    }).toList();
  }

  // 機能3: BottomNavigationBar（タブ1〜3はNavigator.pushで独立画面として開く）
  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: 0, // 地図タブが常にアクティブ（他タブはpushで開く）
      onTap: (i) {
        if (i == 0) return;
        final destinations = [
          null, // 0: 地図（何もしない）
          const EmergencyCardScreen(),
          const SurvivalGuideScreen(),
          const SettingsScreen(),
        ];
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => destinations[i]!),
        );
      },
      type: BottomNavigationBarType.fixed,
      selectedItemColor: _greenPrimary,
      unselectedItemColor: Colors.grey,
      backgroundColor: Colors.white,
      elevation: 8,
      items: [
        BottomNavigationBarItem(icon: const Icon(Icons.map), label: GapLessL10n.t('nav_tab_map')),
        BottomNavigationBarItem(icon: const Icon(Icons.badge), label: GapLessL10n.t('nav_tab_card')),
        BottomNavigationBarItem(icon: const Icon(Icons.menu_book), label: GapLessL10n.t('nav_tab_guide')),
        BottomNavigationBarItem(icon: const Icon(Icons.settings), label: GapLessL10n.t('nav_tab_settings')),
      ],
    );
  }

  // ── 帰還支援コンパス ──────────────────────────────────────────────────────

  Widget _buildFallbackCompass() {
    final state = _fallback.state;
    return ReturnHomeCompass(
      key: const ValueKey('fallback'),
      returnBearingDeg: state.returnBearingDeg,
      returnDistanceM: state.returnDistanceM,
      headingDeg: _headingDeg,
      onBacktrackPressed: () => _startBacktrack(),
    );
  }

  // ── ローディング ──────────────────────────────────────────────────────────

  Widget _buildLoading() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(_greenPrimary)),
          const SizedBox(height: 24),
          Text(GapLessL10n.t('nav_loading_map'),
              style: GapLessL10n.safeStyle(const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          const SizedBox(height: 16),
          if (_loadProgress > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Column(
                children: [
                  LinearProgressIndicator(
                    value: _loadProgress,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(_greenPrimary),
                    backgroundColor: const Color(0xFFCFD8DC),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(_loadProgress * 100).toInt()}%',
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFF607D8B)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── エラー ────────────────────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      key: const ValueKey('error'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: Color(0xFF90A4AE)),
            const SizedBox(height: 16),
            Text(_loadError ?? GapLessL10n.t('unknown_error'),
                textAlign: TextAlign.center,
                style: GapLessL10n.safeStyle(const TextStyle(fontSize: 16))),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _loadError = null;
                  _isLoadingMap = true;
                  _loadProgress = 0;
                });
                _bootServices();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _greenPrimary,
                foregroundColor: Colors.white,
                minimumSize: const Size(180, 56),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              child: Text(GapLessL10n.t('map_download_retry'),
                  style: GapLessL10n.safeStyle(const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
            ),
          ],
        ),
      ),
    );
  }

  // ── FABグループ ───────────────────────────────────────────────────────────

  Widget _buildFabGroup() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // クイック報告（カメラ1枚で即時BLE送信）
        FloatingActionButton.small(
          heroTag: 'quickReport',
          onPressed: () => showQuickReport(context),
          backgroundColor: const Color(0xFFE53935),
          foregroundColor: Colors.white,
          tooltip: GapLessL10n.t('nav_tooltip_photo'),
          child: const Icon(Icons.camera_alt),
        ),
        const SizedBox(height: 8),
        // 機能3: 道路状況報告ボタン
        FloatingActionButton.small(
          heroTag: 'report',
          onPressed: _showRoadReportSheet,
          backgroundColor: const Color(0xFF6A1B9A),
          foregroundColor: Colors.white,
          tooltip: GapLessL10n.t('nav_tooltip_report'),
          child: const Icon(Icons.campaign),
        ),
        const SizedBox(height: 8),
        // 機能1: 最寄り避難所ルーティングボタン
        FloatingActionButton.extended(
          heroTag: 'shelter',
          onPressed: _navigateToNearestShelter,
          backgroundColor: _orangeAccent,
          foregroundColor: Colors.white,
          icon: const Icon(Icons.emergency_share),
          label: Text(GapLessL10n.t('nav_nearest_shelter'),
              style: GapLessL10n.safeStyle(const TextStyle(fontWeight: FontWeight.bold))),
        ),
        const SizedBox(height: 8),
        // 現在地ボタン
        FloatingActionButton(
          heroTag: 'location',
          onPressed: _moveToCurrentLocation,
          backgroundColor: _greenPrimary,
          foregroundColor: Colors.white,
          child: const Icon(Icons.my_location),
        ),
      ],
    );
  }
}

// ============================================================================
// 機能5: ナビステータスバー
// ============================================================================

class _NavStatusBar extends StatelessWidget {
  final BleRoadReportService ble;
  final LocationProvider locationProv;

  const _NavStatusBar({required this.ble, required this.locationProv});

  @override
  Widget build(BuildContext context) {
    final bleRunning = ble.isRunning;
    final bleCount = ble.receivedCount;
    final hasLocation = locationProv.currentLocation != null;
    final isTracking = locationProv.isTracking;

    return ListenableBuilder(
      listenable: PowerManager.instance,
      builder: (_, __) {
        final saving = PowerManager.instance.isPowerSaving;
        return Container(
          color: saving
              ? const Color(0xFF4A0000)
              : const Color(0xFF2E7D32).withValues(alpha: 0.9),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          child: Row(
            children: [
              _StatusChip(
                icon: hasLocation
                    ? (isTracking ? Icons.gps_fixed : Icons.gps_not_fixed)
                    : Icons.gps_off,
                label: hasLocation ? 'GPS' : GapLessL10n.t('gps_none'),
                color: hasLocation ? Colors.greenAccent : Colors.redAccent,
              ),
              const SizedBox(width: 12),
              _StatusChip(
                icon: bleRunning ? Icons.bluetooth_connected : Icons.bluetooth_disabled,
                label: bleRunning ? 'BLE($bleCount)' : GapLessL10n.t('ble_off'),
                color: bleRunning ? Colors.lightBlueAccent : Colors.grey,
              ),
              const Spacer(),
              if (saving)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.power_settings_new,
                        color: Color(0xFFFF6F00), size: 14),
                    const SizedBox(width: 4),
                    Text(GapLessL10n.t('power_saving'),
                        style: GapLessL10n.safeStyle(const TextStyle(
                            color: Color(0xFFFF6F00),
                            fontSize: 11,
                            fontWeight: FontWeight.bold))),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatusChip(
      {required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 4),
        Text(label,
            style: GapLessL10n.safeStyle(TextStyle(
                color: color, fontSize: 11, fontWeight: FontWeight.w600))),
      ],
    );
  }
}

// ============================================================================
// 機能3: 道路状況報告BottomSheet
// ============================================================================

class _RoadReportSheet extends StatelessWidget {
  final double currentLat;
  final double currentLng;
  final void Function(bool passable) onReport;

  const _RoadReportSheet({
    required this.currentLat,
    required this.currentLng,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            GapLessL10n.t('road_report_title'),
            style: GapLessL10n.safeStyle(const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 4),
          Text(
            '${currentLat.toStringAsFixed(4)}, ${currentLng.toStringAsFixed(4)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          Text(
            GapLessL10n.t('road_report_hint'),
            style: GapLessL10n.safeStyle(const TextStyle(fontSize: 13, color: Colors.black54)),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onReport(true);
                  },
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(GapLessL10n.t('report_passable')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF388E3C),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 56),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onReport(false);
                  },
                  icon: const Icon(Icons.block),
                  label: Text(GapLessL10n.t('report_blocked')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD32F2F),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 56),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ============================================================================
// 機能4: プロファイル選択オプション行
// ============================================================================

class _ProfileOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ProfileOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon,
          color: selected ? const Color(0xFF2E7D32) : Colors.grey),
      title: Text(label,
          style: GapLessL10n.safeStyle(TextStyle(
              fontWeight:
                  selected ? FontWeight.bold : FontWeight.normal,
              color: selected ? const Color(0xFF2E7D32) : null))),
      subtitle: Text(subtitle, style: GapLessL10n.safeStyle(const TextStyle(fontSize: 12))),
      trailing: selected
          ? const Icon(Icons.check_circle, color: Color(0xFF2E7D32))
          : null,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      tileColor:
          selected ? const Color(0xFF2E7D32).withValues(alpha: 0.08) : null,
      onTap: onTap,
    );
  }
}
