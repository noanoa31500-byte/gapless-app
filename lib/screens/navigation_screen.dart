import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;
import '../services/connectivity_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/road_feature.dart';
import '../models/shelter.dart';
import '../providers/user_profile_provider.dart';
import '../providers/language_provider.dart';
import '../providers/location_provider.dart';
import '../providers/region_mode_provider.dart';
import '../providers/shelter_provider.dart';
import '../screens/emergency_card_screen.dart';
import '../screens/shelter_dashboard_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/emergency_simple_screen.dart';
import '../screens/jma_feed_screen.dart';
import '../screens/chat_screen.dart';
import '../services/jma_alert_service.dart';
import '../ble/ble_packet.dart';
import '../services/ble_road_report_service.dart';
import '../ble/ble_peripheral_channel.dart';
import '../services/fallback_mode_controller.dart';
import '../data/map_auto_loader.dart';
import '../services/road_features_cache.dart';
import '../services/gps_logger.dart';
import '../services/navigation_announcer.dart';
import '../services/power_manager.dart';
import '../utils/localization.dart';
import '../services/road_report_scorer.dart';
import '../services/route_compute_service.dart';
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
// RouteComputeParams / computeRouteInIsolate は route_compute_service.dart で定義

// ── ウィジェット ───────────────────────────────────────────────────────────

class NavigationScreen extends StatefulWidget {
  const NavigationScreen({super.key});

  @override
  State<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends State<NavigationScreen> {
  static const Color _greenPrimary = Color(0xFF00C896);
  static const Color _orangeAccent = Color(0xFFFF6B35);

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
  StreamSubscription<MapLoadEvent>? _mapLoadSub;
  StreamSubscription<bool>? _connectivitySub;

  // ── 通信断絶検知 ──────────────────────────────────────────────────────────
  bool _isFullyOffline = false;
  Timer? _offlineTimer;

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

  // SOS: 受信カウントを保持して変化を検知
  int _lastKnownSosCount = 0;

  // SOS: ボタン長押し中のタイマー（3秒で送信）
  Timer? _sosPressTimer;

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
      final region = context.read<RegionModeProvider>().region;
      final roadFile = '${region.gplbAssetPath}_roads.gplb';

      // OS キャッシュから前回位置を即取得（失敗してもブロックしない）
      final lastPos = await Geolocator.getLastKnownPosition();
      if (lastPos != null) {
        _roadFeatures = await RoadFeaturesCache.instance
            .getMergedWithTiles(roadFile, lastPos.latitude, lastPos.longitude);
      } else {
        _roadFeatures = await RoadFeaturesCache.instance.get(roadFile);
      }
      _fallback.setBoundsFromLatLngs(_roadFeatures.expand((r) => r.geometry));

      // MapAutoLoader が新しいタイルをダウンロードしたら道路データを更新
      _mapLoadSub = MapAutoLoader.instance.onEvent.listen((event) {
        if (event.type == MapLoadEventType.allLoaded) {
          _refreshRoadFeaturesFromTiles();
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError =
              e is Exception ? e.toString() : GapLessL10n.t('map_load_error');
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

    // 通信断絶検知: WiFi+モバイル両方なしが30秒続いたら緊急バッジ表示
    _connectivitySub = ConnectivityService.onConnectivityChanged
        .listen(_onConnectivityChanged);

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

    // BLEレポート更新時に再描画（軌跡・避難所ステータス含む）
    _ble.scorer.addListener(_onScoreUpdated);
    _ble.addListener(_onScoreUpdated);

    // 機能3: PowerManager 省電力モード変化 → BleRoadReportService に通知
    PowerManager.instance.addListener(_onPowerModeChanged);

    // 機能4: 言語変化 → TTS 言語を即座に切り替え
    context.read<LanguageProvider>().addListener(_onLanguageChanged);

    // 機能7: ユーザープロファイル変化 → アクセシビリティプロファイルを再評価
    context.read<UserProfileProvider>().addListener(_onUserProfileChanged);

    // 機能4: GPS軌跡を5秒ごとに更新して地図に反映
    _trackRefreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final track =
          GpsLogger.instance.backtrackRouteFromBuffer().reversed.toList();
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
    } else if (needs.contains('Pregnancy') ||
        needs.contains('Infant') ||
        needs.contains('Visual Impairment')) {
      // 視覚障害者・妊婦・乳幼児連れ → 広い道・ゆっくりペースを優先
      auto = _AccessProfile.elderly;
    } else {
      return; // 変更不要
    }
    // 手動変更済みでなければ自動プロファイルを適用
    if (_accessProfile == _AccessProfile.standard) {
      setState(() => _accessProfile = auto);
    }
  }

  void _onScoreUpdated() {
    if (!mounted) return;
    final newSosCount = _ble.receivedSosCount;
    if (newSosCount > _lastKnownSosCount) {
      _lastKnownSosCount = newSosCount;
      HapticFeedback.heavyImpact();
      _announcer.announceAlert(GapLessL10n.t('sos_received'));
      _showSnack(GapLessL10n.t('sos_received'));
    }
    setState(() {});
  }

  // 機能4: 言語変化 → TTS 言語を即座に更新
  void _onLanguageChanged() {
    _announcer.updateLanguage();
  }

  // 機能7: ユーザープロファイル変化 → アクセシビリティプロファイルを再評価してルート再計算
  void _onUserProfileChanged() {
    _initAccessProfileFromUserNeeds();
    if (_destination != null) _calculateRoute();
  }

  // 機能3: 省電力モード変化 → BLE スキャン間隔 & GPS取得間隔を連動
  void _onPowerModeChanged() {
    _ble.setPowerMode(PowerManager.instance.mode);
    GpsLogger.instance
        .onGpsIntervalChanged(PowerManager.instance.gpsIntervalSec);
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

    // 到着自動検知 → 5m 以内で完了
    _checkArrival(entry.latLng);

    // 機能5: ルート逸脱検知 → 自動リルート
    _checkOffRoute(entry.latLng);
  }

  static const double _arrivalThresholdM = 5.0;

  /// 目的地から 5m 以内に入ったら自動到着完了（既存の _onArrived に委譲）
  void _checkArrival(LatLng pos) {
    final dest = _destination;
    if (dest == null || _route.isEmpty) return;
    if (const Distance()(pos, dest) <= _arrivalThresholdM) {
      _onArrived();
    }
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
      _showSnack(GapLessL10n.t('nav_off_route_recalc'));
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
    _ble.removeListener(_onScoreUpdated);
    PowerManager.instance.removeListener(_onPowerModeChanged);
    // ignore: use_build_context_synchronously
    context.read<LanguageProvider>().removeListener(_onLanguageChanged);
    // ignore: use_build_context_synchronously
    context.read<UserProfileProvider>().removeListener(_onUserProfileChanged);
    _ble.stop();
    _bleScoreRefreshTimer?.cancel();
    _trackRefreshTimer?.cancel();
    _sosPressTimer?.cancel();
    _mapLoadSub?.cancel();
    _connectivitySub?.cancel();
    _offlineTimer?.cancel();
    super.dispose();
  }

  // ── 通信断絶検知 ──────────────────────────────────────────────────────────

  void _onConnectivityChanged(bool connected) {
    if (!mounted) return;
    final fullyOffline = !connected;

    if (fullyOffline && !_isFullyOffline) {
      // 断絶開始: 30秒後にバッジ表示 & disasterMode時は自動遷移
      _offlineTimer?.cancel();
      _offlineTimer = Timer(const Duration(seconds: 30), () {
        if (!mounted) return;
        setState(() => _isFullyOffline = true);
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EmergencySimpleScreen()),
        );
      });
    } else if (!fullyOffline && _isFullyOffline) {
      // 復帰
      _offlineTimer?.cancel();
      setState(() => _isFullyOffline = false);
    } else if (!fullyOffline) {
      _offlineTimer?.cancel();
    }
  }

  // ── タイル更新後の道路データ再取得 ────────────────────────────────────────

  Future<void> _refreshRoadFeaturesFromTiles() async {
    final loc = context.read<LocationProvider>().currentLocation;
    if (loc == null || !mounted) return;

    final region = context.read<RegionModeProvider>().region;
    final roadFile = '${region.gplbAssetPath}_roads.gplb';

    RoadFeaturesCache.instance.invalidateTiles();
    final updated = await RoadFeaturesCache.instance
        .getMergedWithTiles(roadFile, loc.latitude, loc.longitude);
    if (!mounted) return;

    setState(() => _roadFeatures = updated);
    _fallback.setBoundsFromLatLngs(updated.expand((r) => r.geometry));

    // ナビ中なら新しい道路データでルートを再計算
    if (_destination != null) _calculateRoute();
  }

  // ── ルート計算 ────────────────────────────────────────────────────────────

  Future<void> _calculateRoute() async {
    final dest = _destination;
    if (dest == null || !mounted) return;

    final currentLoc = context.read<LocationProvider>().currentLocation;
    if (currentLoc == null) return;

    setState(() => _isCalculatingRoute = true);

    // オンライン時はOSRM（実際の道路沿い）、オフライン時はA*フォールバック
    List<LatLng>? osrmRoute = await _fetchOsrmRoute(currentLoc, dest);
    if (osrmRoute != null && mounted) {
      setState(() {
        _route = osrmRoute;
        _isCalculatingRoute = false;
      });
      PowerManager.instance.setNavigationActive(true);
      return;
    }

    // A* フォールバック（オフライン）
    if (_roadFeatures.isEmpty) {
      if (mounted) setState(() => _isCalculatingRoute = false);
      return;
    }

    final bool requiresFlat = _accessProfile == _AccessProfile.wheelchair;
    final bool isElderly = _accessProfile == _AccessProfile.elderly;
    final double speed = _accessProfile == _AccessProfile.wheelchair
        ? 0.8
        : _accessProfile == _AccessProfile.elderly
            ? 0.9
            : 1.2;

    try {
      final result = await compute(
        computeRouteInIsolate,
        RouteComputeParams(
          features: _roadFeatures,
          startLat: currentLoc.latitude,
          startLng: currentLoc.longitude,
          goalLat: dest.latitude,
          goalLng: dest.longitude,
          requiresFlatRoute: requiresFlat,
          isElderly: isElderly,
          walkSpeedMps: speed,
        ),
      ).timeout(const Duration(seconds: 15));
      if (mounted) {
        // 2点のみ（直線フォールバック）は表示しない
        final pts = result.waypoints;
        setState(() {
          _route = pts.length > 2 ? pts : [];
          _isCalculatingRoute = false;
        });
        PowerManager.instance.setNavigationActive(pts.length > 2);
      }
    } catch (e) {
      debugPrint('Route calculation failed: $e');
      if (mounted) setState(() => _isCalculatingRoute = false);
    }
  }

  /// OSRM 徒歩ルート取得（オンライン専用）。失敗時は null を返す。
  Future<List<LatLng>?> _fetchOsrmRoute(LatLng start, LatLng goal) async {
    try {
      final uri = Uri.parse(
        'https://router.project-osrm.org/route/v1/walking/'
        '${start.longitude},${start.latitude};'
        '${goal.longitude},${goal.latitude}'
        '?overview=full&geometries=geojson',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['code'] != 'Ok') return null;
      final coords = (body['routes'][0]['geometry']['coordinates'] as List)
          .map(
              (c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
      return coords.length >= 2 ? coords : null;
    } catch (_) {
      return null;
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
      _showSnack(GapLessL10n.t('nav_route_calculated')
          .replaceAll('@name', nearest.name));
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
  void _stopNavigation() {
    PowerManager.instance.setNavigationActive(false);
    setState(() {
      _route = [];
      _destination = null;
      _destinationName = null;
    });
  }

  void _onArrived() {
    _announcer.announceWaypointPassed(0, 1, 0);
    PowerManager.instance.setNavigationActive(false); // ナビ終了 → GPS間隔を省電力設定に戻す
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
        content: Text(GapLessL10n.t('nav_arrive_body'),
            style: GapLessL10n.safeStyle(const TextStyle())),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(GapLessL10n.t('nav_still_moving'),
                style: GapLessL10n.safeStyle(const TextStyle())),
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
              backgroundColor: _greenPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(GapLessL10n.t('nav_safe_confirm'),
                style: GapLessL10n.safeStyle(const TextStyle())),
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

  // SOS: 長押し3秒で送信（誤送信防止）
  void _onSosPressStart() {
    _sosPressTimer?.cancel();
    _sosPressTimer = Timer(const Duration(seconds: 3), () {
      final loc = context.read<LocationProvider>().currentLocation;
      if (loc == null) {
        _showSnack(GapLessL10n.t('nav_no_location'));
        return;
      }
      _ble.enqueueSos(lat: loc.latitude, lng: loc.longitude);
      HapticFeedback.heavyImpact();
      _showSnack(GapLessL10n.t('sos_sent'));
    });
  }

  void _onSosPressEnd() {
    _sosPressTimer?.cancel();
    _sosPressTimer = null;
  }

  // 機能3: 道路状況報告BottomSheet
  void _showRoadReportSheet() {
    final locationProv = context.read<LocationProvider>();
    final loc = locationProv.currentLocation;
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
            isDrActive: locationProv.isDeadReckoning,
            drErrorM: locationProv.deadReckoningErrorMeters,
          );
          _showSnack(passable
              ? GapLessL10n.t('nav_reported_passable')
              : GapLessL10n.t('nav_reported_blocked'));
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // 言語フィールドのみ購読（Provider 全体ではなく文字列単位の購読）
    context.select<LanguageProvider, String>((p) => p.currentLanguage);
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
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: inFallback
                          ? _buildFallbackCompass()
                          : (locationProv.isDeadReckoning &&
                                  locationProv.isDeadReckoningAccuracyLow)
                              ? _buildDrUncertaintyScreen(
                                  locationProv.currentLocation)
                              : !PowerManager.instance.showMap
                                  ? _buildEmergencyScreen(
                                      locationProv.currentLocation)
                                  : _buildMapStack(
                                      locationProv.currentLocation),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.transparent,
      foregroundColor: const Color(0xFF1A1A2E),
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.88),
              border: Border(
                bottom: BorderSide(
                    color: Colors.black.withValues(alpha: 0.07), width: 0.5),
              ),
            ),
          ),
        ),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(GapLessL10n.t('nav_screen_title'),
              style: GapLessL10n.safeStyle(const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: Color(0xFF1A1A2E),
                  letterSpacing: 0.2))),
          if (_destinationName != null)
            Text(
              _destinationName!,
              style: GapLessL10n.safeStyle(const TextStyle(
                  fontSize: 11, color: Color(0xFF6B7280), letterSpacing: 0.1)),
            ),
        ],
      ),
      actions: [
        // GPS + BLE status chips (replaces NavStatusBar)
        Consumer<LocationProvider>(
          builder: (_, locationProv, __) {
            final hasGps = locationProv.currentLocation != null;
            return _AppBarChip(
              icon: hasGps ? Icons.gps_fixed : Icons.gps_off,
              color: hasGps ? _greenPrimary : const Color(0xFFEF4444),
            );
          },
        ),
        ListenableBuilder(
          listenable: _ble,
          builder: (_, __) {
            final running = _ble.isRunning;
            final count = _ble.receivedCount;
            final ex = _ble.exchangeCount;
            final hit = _ble.scanHitCount;
            String? label;
            if (running) {
              if (count > 0)
                label = '$count';
              else if (ex > 0)
                label = '~$ex';
              else if (hit > 0) label = '?$hit';
            }
            return GestureDetector(
              onTap: () async {
                final periph = await BlePeripheralChannel.instance.getStatus();
                if (!context.mounted) return;
                showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('BLE診断'),
                    content: SingleChildScrollView(
                      child: Text(
                        '[Central]\n'
                        'running=$running\n'
                        'scanHit=$hit\n'
                        'exchange=$ex\n'
                        'received=$count\n'
                        'lastDiag: ${_ble.lastDiag}\n\n'
                        '[Peripheral native]\n'
                        '${periph?.entries.map((e) => "${e.key}=${e.value}").join("\n") ?? "null"}',
                        style: const TextStyle(
                            fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              },
              child: _AppBarChip(
                icon: running
                    ? Icons.bluetooth_connected
                    : Icons.bluetooth_disabled,
                label: label,
                color:
                    running ? const Color(0xFF3B82F6) : const Color(0xFF9CA3AF),
              ),
            );
          },
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
                    color: saving ? _orangeAccent : const Color(0xFF6B7280),
                    size: 18,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '$level%',
                    style: TextStyle(
                        color: saving ? _orangeAccent : const Color(0xFF6B7280),
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
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
              urlTemplate:
                  'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
              subdomains: const ['a', 'b', 'c', 'd'],
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
            // BLEピア軌跡（救助支援用: 他端末から受信した最近の移動経路）
            if (_ble.peerTracks.isNotEmpty)
              PolylineLayer(
                polylines: _ble.peerTracks.values
                    .where((t) => !t.isExpired && t.latLngs.length >= 2)
                    .map((t) => Polyline(
                          points: t.latLngs,
                          color: const Color(0x990277BD),
                          strokeWidth: 2.5,
                          isDotted: true,
                        ))
                    .toList(),
              ),
            if (_route.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _route,
                    color: Color(0xFF00C896),
                    strokeWidth: 5.5,
                  ),
                ],
              ),
            // BLEピアレポートマーカー
            if (reportMarkers.isNotEmpty) MarkerLayer(markers: reportMarkers),
            // 機能2: 避難所マーカー
            if (shelterMarkers.isNotEmpty) MarkerLayer(markers: shelterMarkers),
            // SOSビーコンマーカー（赤い点滅円）
            MarkerLayer(markers: _buildSosMarkers()),
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
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00C896), Color(0xFF00A87A)],
                  ),
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00C896).withOpacity(0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
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
                        style: GapLessL10n.safeStyle(const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3))),
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
            child: Container(
              decoration: const BoxDecoration(
                color: Color(0xFFF8F9FE),
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 20,
                    offset: Offset(0, -6),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                child: TurnByTurnPanel(
                  route: _route,
                  currentPosition: currentLoc,
                  headingDeg: _headingDeg,
                  onArrived: _onArrived,
                  onStop: _stopNavigation,
                  destinationName: _destinationName,
                ),
              ),
            ),
          ),
        // FABグループ（パネルの上に浮かせる）
        Positioned(
          bottom: 116,
          right: 16,
          child: _buildFabGroup(),
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

      final opacity = score.displayOpacity.clamp(0.25, 1.0);
      final isDangerous = score.isConfirmedDangerous;
      final isSafe = score.isConfirmedSafe;
      final ageMin = score.latestAgeSeconds / 60.0;

      // 未確定かつ重みが薄いものは非表示
      if (!isDangerous &&
          !isSafe &&
          score.passableWeight + score.impassableWeight < 0.5) {
        continue;
      }

      // 鮮度による色選択
      // 0-30min: 鮮明（赤/緑/琥珀）
      // 30-120min: やや淡化（暗い赤/暗い緑/オレンジ）
      // 120-360min: 大幅淡化（灰みがかった色 + 時計アイコン）
      final Color baseColor;
      final IconData icon;
      final bool isStale = ageMin >= 120;
      if (isDangerous) {
        baseColor = ageMin < 30
            ? const Color(0xFFD32F2F)
            : ageMin < 120
                ? const Color(0xFFB71C1C)
                : const Color(0xFF7B3030);
        icon = isStale ? Icons.access_time : Icons.block;
      } else if (isSafe) {
        baseColor = ageMin < 30
            ? const Color(0xFF00C896)
            : ageMin < 120
                ? const Color(0xFF00A87A)
                : const Color(0xFF007A58);
        icon = isStale ? Icons.access_time : Icons.check_circle;
      } else {
        baseColor = ageMin < 30
            ? const Color(0xFFFFA000)
            : ageMin < 120
                ? const Color(0xFFE65100)
                : const Color(0xFF795548);
        icon = isStale ? Icons.access_time : Icons.warning_amber;
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
              color: baseColor,
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Icon(icon, color: Colors.white, size: 16),
          ),
        ),
      ));
    }
    return markers;
  }

  // 機能2: 避難所マーカー生成（タップで目的地設定）
  List<Marker> _buildShelterMarkers(List<Shelter> shelters) {
    final shelterStatuses = _ble.shelterStatuses;
    return shelters.map((s) {
      final isTarget = _destination != null &&
          (_destination!.latitude - s.lat).abs() < 0.0001 &&
          (_destination!.longitude - s.lng).abs() < 0.0001;
      final isOccupied = shelterStatuses[s.id]?.isOccupied == true;
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
            _showSnack(
                GapLessL10n.t('nav_route_to').replaceAll('@name', s.name));
          },
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isTarget ? _orangeAccent : _greenPrimary,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                      color: (isTarget ? _orangeAccent : _greenPrimary)
                          .withOpacity(0.45),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  s.type == 'hospital'
                      ? Icons.local_hospital
                      : Icons.night_shelter,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              // 在避難者バッジ（BLE経由で誰かいることが確認された避難所）
              if (isOccupied)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.amber[700],
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child:
                        const Icon(Icons.person, color: Colors.white, size: 8),
                  ),
                ),
            ],
          ),
        ),
      );
    }).toList();
  }

  // SOS: 受信済みSOSビーコンを赤い警告マーカーで表示
  List<Marker> _buildSosMarkers() {
    _ble.purgeSos();
    final markers = <Marker>[];
    for (final sos in _ble.receivedSosReports) {
      if (sos.isExpired) continue;
      final opacity = sos.displayOpacity.clamp(0.3, 1.0);
      markers.add(Marker(
        point: LatLng(sos.lat, sos.lng),
        width: 44,
        height: 44,
        child: Opacity(
          opacity: opacity,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0x44B71C1C),
                  border: Border.all(color: const Color(0xFFB71C1C), width: 2),
                ),
              ),
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFB71C1C),
                ),
                child: const Icon(Icons.sos, color: Colors.white, size: 16),
              ),
            ],
          ),
        ),
      ));
    }
    return markers;
  }

  // 機能3: BottomNavigationBar
  // 平時: ナビ/緊急カード/公式情報/AIチャット/設定 の5タブ
  // 電波断絶30秒後のみ: 緊急操作タブが追加表示される
  Widget _buildBottomNav() {
    final jmaIcon = ListenableBuilder(
      listenable: JmaAlertService.instance,
      builder: (_, __) {
        final hasAlert = JmaAlertService.instance.hasActiveAlert;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(Icons.campaign,
                color: hasAlert ? const Color(0xFFB71C1C) : null),
            if (hasAlert)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Color(0xFFB71C1C),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        );
      },
    );

    // 平時の5タブ構成
    final normalItems = <BottomNavigationBarItem>[
      BottomNavigationBarItem(
          icon: const Icon(Icons.map), label: GapLessL10n.t('nav_tab_map')),
      BottomNavigationBarItem(
          icon: const Icon(Icons.badge), label: GapLessL10n.t('nav_tab_card')),
      BottomNavigationBarItem(
          icon: jmaIcon, label: GapLessL10n.t('nav_tab_feed')),
      BottomNavigationBarItem(
          icon: const Icon(Icons.chat_bubble_outline),
          label: GapLessL10n.t('nav_tab_chat')),
      BottomNavigationBarItem(
          icon: const Icon(Icons.settings),
          label: GapLessL10n.t('nav_tab_settings')),
    ];

    void normalTap(int i) {
      if (i == 0) return;
      final screens = <Widget>[
        const EmergencyCardScreen(),
        const JmaFeedScreen(),
        const ChatScreen(),
        const SettingsScreen(),
      ];
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => screens[i - 1]));
    }

    Widget _glassNav({
      required List<BottomNavigationBarItem> items,
      required void Function(int) onTap,
    }) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xD9FFFFFF),
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              boxShadow: [
                BoxShadow(
                  color: Color(0x18000000),
                  blurRadius: 20,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: BottomNavigationBar(
              currentIndex: 0,
              onTap: onTap,
              type: BottomNavigationBarType.fixed,
              selectedItemColor: _greenPrimary,
              unselectedItemColor: const Color(0xFF9E9E9E),
              backgroundColor: Colors.transparent,
              elevation: 0,
              selectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  letterSpacing: 0.3),
              unselectedLabelStyle: const TextStyle(fontSize: 11),
              items: items,
            ),
          ),
        ),
      );
    }

    if (!_isFullyOffline) {
      return _glassNav(items: normalItems, onTap: normalTap);
    }

    // 電波断絶時: 緊急操作タブを3番目に挿入した6タブ構成
    final emergencyItems = <BottomNavigationBarItem>[
      BottomNavigationBarItem(
          icon: const Icon(Icons.map), label: GapLessL10n.t('nav_tab_map')),
      BottomNavigationBarItem(
          icon: const Icon(Icons.badge), label: GapLessL10n.t('nav_tab_card')),
      BottomNavigationBarItem(
          icon: jmaIcon, label: GapLessL10n.t('nav_tab_feed')),
      BottomNavigationBarItem(
        icon: _OfflinePulseBadge(
            child: const Icon(Icons.crisis_alert, color: Color(0xFFB71C1C))),
        label: GapLessL10n.t('emergency_screen_title'),
      ),
      BottomNavigationBarItem(
          icon: const Icon(Icons.chat_bubble_outline),
          label: GapLessL10n.t('nav_tab_chat')),
      BottomNavigationBarItem(
          icon: const Icon(Icons.settings),
          label: GapLessL10n.t('nav_tab_settings')),
    ];

    return _glassNav(
      items: emergencyItems,
      onTap: (i) {
        if (i == 0) return;
        final screens = <Widget>[
          const EmergencyCardScreen(),
          const JmaFeedScreen(),
          const EmergencySimpleScreen(), // index 3: 緊急操作
          const ChatScreen(),
          const SettingsScreen(),
        ];
        Navigator.push(
            context, MaterialPageRoute(builder: (_) => screens[i - 1]));
      },
    );
  }

  // ── 帰還支援コンパス ──────────────────────────────────────────────────────

  /// DR精度低下時（誤差≥100m or 5分超）に表示する画面。
  /// コアバリュー「矢印の方向に歩くだけ」を維持しつつ、不確かさを正直に伝える。
  /// テキストを最小化し、矢印・距離・⚠アイコンだけで言語不問で伝える。
  Widget _buildDrUncertaintyScreen(LatLng? currentLoc) {
    // 目的地が設定済みなら方向と距離を計算する
    double? bearingDeg;
    double? distM;
    if (currentLoc != null && _destination != null) {
      distM = Geolocator.distanceBetween(
        currentLoc.latitude,
        currentLoc.longitude,
        _destination!.latitude,
        _destination!.longitude,
      );
      // 方位角（度）: 北=0、時計回り。
      // Geolocator.bearingBetween は球面三角法で cos(lat) 補正済み。
      // 自前 atan2(dLng, dLat) は緯度35°で最大18°ズレるので使わない。
      bearingDeg = (Geolocator.bearingBetween(
                currentLoc.latitude,
                currentLoc.longitude,
                _destination!.latitude,
                _destination!.longitude,
              ) +
              360) %
          360;
    }

    final loc = context.read<LocationProvider>();
    final elapsedMin = (loc.deadReckoningElapsedSeconds / 60).round();
    final errorM = loc.deadReckoningErrorMeters.round();

    return Container(
      key: const ValueKey('dr_uncertain'),
      color: const Color(0xFF1A1A2E),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ── 不確かさ警告バー ──────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: const Color(0xCCB71C1C),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.gps_off, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  '±${errorM}m  •  ${elapsedMin}min',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // ── 矢印（方向）──────────────────────────────────────────
          if (bearingDeg != null) ...[
            // デバイスの向きに対して相対的な矢印を回転させる
            Transform.rotate(
              angle: (bearingDeg - _headingDeg) * math.pi / 180,
              child: const Icon(
                Icons.navigation,
                size: 140,
                color: Color(0xFF4CAF50),
              ),
            ),
            const SizedBox(height: 24),
            // 距離だけ表示（数字は世界共通）
            Text(
              distM! >= 1000
                  ? '${(distM / 1000).toStringAsFixed(1)} km'
                  : '${distM.round()} m',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 48,
                fontWeight: FontWeight.bold,
              ),
            ),
          ] else ...[
            // 目的地未設定時: ⚠アイコンのみ
            const Icon(Icons.gps_off, size: 100, color: Color(0xFFB71C1C)),
          ],

          const Spacer(),

          // ── 不確かさの注記（小さく・言語対応）────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Text(
              GapLessL10n.t('dr_uncertain_body'),
              style: GapLessL10n.safeStyle(const TextStyle(
                color: Colors.white38,
                fontSize: 12,
                height: 1.5,
              )),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // ── 救命モード画面 (ultra / emergency) ───────────────────────────────────
  // バッテリー残量 ≤10% 時に地図を非表示にし、方位・距離・SOSボタンのみ表示。
  // 地図タイルの描画コストをゼロにしてバッテリー消費を最大抑制する。
  Widget _buildEmergencyScreen(LatLng? currentLoc) {
    final power = PowerManager.instance;
    final isEmergency = power.mode == PowerMode.emergency;
    final batteryColor =
        isEmergency ? const Color(0xFFB71C1C) : const Color(0xFFE65100);

    double? bearingDeg;
    double? distM;
    if (currentLoc != null && _destination != null) {
      distM = Geolocator.distanceBetween(
        currentLoc.latitude,
        currentLoc.longitude,
        _destination!.latitude,
        _destination!.longitude,
      );
      bearingDeg = (Geolocator.bearingBetween(
                currentLoc.latitude,
                currentLoc.longitude,
                _destination!.latitude,
                _destination!.longitude,
              ) +
              360) %
          360;
    }

    return Container(
      key: const ValueKey('emergency_power'),
      color: Colors.black,
      child: Column(
        children: [
          // バッテリー警告バー
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: batteryColor,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isEmergency ? Icons.battery_alert : Icons.battery_2_bar,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  '${power.batteryLevel}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // 方位矢印 + 距離
          if (bearingDeg != null) ...[
            Transform.rotate(
              angle: (bearingDeg - _headingDeg) * math.pi / 180,
              child: const Icon(Icons.navigation,
                  size: 160, color: Color(0xFF4CAF50)),
            ),
            const SizedBox(height: 20),
            Text(
              distM! >= 1000
                  ? '${(distM / 1000).toStringAsFixed(1)} km'
                  : '${distM.round()} m',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 52,
                fontWeight: FontWeight.bold,
              ),
            ),
          ] else
            const Icon(Icons.explore, size: 120, color: Colors.white38),

          const Spacer(),

          // 避難所名（目的地座標から最近傍を検索して表示）
          if (_destination != null)
            Builder(builder: (_) {
              final shelterProv = context.read<ShelterProvider>();
              final dest = _destination!;
              final match = shelterProv.displayedShelters.where((s) {
                final dlat = (s.lat - dest.latitude).abs();
                final dlng = (s.lng - dest.longitude).abs();
                return dlat < 0.0002 && dlng < 0.0002;
              }).firstOrNull;
              if (match == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  match.name,
                  style: GapLessL10n.safeStyle(const TextStyle(
                    color: Colors.white70,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  )),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

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
              style: GapLessL10n.safeStyle(
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
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
                    style:
                        const TextStyle(fontSize: 13, color: Color(0xFF607D8B)),
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
                  style: GapLessL10n.safeStyle(const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold))),
            ),
          ],
        ),
      ),
    );
  }

  // ── FABグループ ───────────────────────────────────────────────────────────

  // 報告メニューをボトムシートで表示（5種の報告を1つのFABに集約）
  void _showReportMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Text(GapLessL10n.t('nav_report_menu_title'),
                  style: GapLessL10n.safeStyle(
                      const TextStyle(color: Colors.white70, fontSize: 13))),
            ),
            _reportTile(Icons.check_circle, const Color(0xFF43A047),
                GapLessL10n.t('qr_passable'), () {
              Navigator.pop(context);
              sendInstantReport(context, BleDataType.passable);
            }),
            _reportTile(Icons.block, const Color(0xFFE53935),
                GapLessL10n.t('qr_blocked'), () {
              Navigator.pop(context);
              sendInstantReport(context, BleDataType.blocked);
            }),
            _reportTile(Icons.warning_amber, const Color(0xFFFF6F00),
                GapLessL10n.t('qr_danger'), () {
              Navigator.pop(context);
              sendInstantReport(context, BleDataType.danger);
            }),
            _reportTile(Icons.camera_alt, const Color(0xFF1565C0),
                GapLessL10n.t('nav_tooltip_photo'), () {
              Navigator.pop(context);
              showQuickReport(context);
            }),
            _reportTile(Icons.campaign, const Color(0xFF6A1B9A),
                GapLessL10n.t('nav_tooltip_report'), () {
              Navigator.pop(context);
              _showRoadReportSheet();
            }),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  Widget _reportTile(
      IconData icon, Color color, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label,
          style: GapLessL10n.safeStyle(
              TextStyle(color: color, fontWeight: FontWeight.bold))),
      onTap: onTap,
      dense: true,
    );
  }

  Widget _buildFabGroup() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // 上段: SOS + 報告（横並び）
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 報告まとめFAB
            FloatingActionButton.small(
              heroTag: 'report',
              onPressed: _showReportMenu,
              backgroundColor: const Color(0xFFFF6F00),
              foregroundColor: Colors.white,
              tooltip: GapLessL10n.t('nav_tooltip_report'),
              child: const Icon(Icons.campaign),
            ),
            const SizedBox(width: 8),
            // SOSビーコン（長押し3秒で送信）
            // Listener を使用してポインタイベントを直接拾う
            // (GestureDetector + FAB だと FAB 内部のタップ認識器が
            //  ジェスチャを奪って長押しタイマーが起動しない)
            Listener(
              onPointerDown: (_) => _onSosPressStart(),
              onPointerUp: (_) => _onSosPressEnd(),
              onPointerCancel: (_) => _onSosPressEnd(),
              child: FloatingActionButton.small(
                heroTag: 'sos',
                onPressed: () => _showSnack(GapLessL10n.t('sos_hold_hint')),
                backgroundColor: const Color(0xFFB71C1C),
                foregroundColor: Colors.white,
                tooltip: GapLessL10n.t('sos_hold_hint'),
                child: const Icon(Icons.sos),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // 下段: 最寄り避難所（アイコンのみ） + 現在地（横並び）
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FloatingActionButton.small(
              heroTag: 'shelter',
              onPressed: _navigateToNearestShelter,
              backgroundColor: _orangeAccent,
              foregroundColor: Colors.white,
              tooltip: GapLessL10n.t('nav_nearest_shelter'),
              child: const Icon(Icons.emergency_share),
            ),
            const SizedBox(width: 8),
            FloatingActionButton.small(
              heroTag: 'location',
              onPressed: _moveToCurrentLocation,
              backgroundColor: _greenPrimary,
              foregroundColor: Colors.white,
              child: const Icon(Icons.my_location),
            ),
          ],
        ),
      ],
    );
  }
}

class _AppBarChip extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String? label;

  const _AppBarChip({required this.icon, required this.color, this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          if (label != null) ...[
            const SizedBox(width: 2),
            Text(label!,
                style: TextStyle(
                    color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
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
            style: GapLessL10n.safeStyle(
                const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 4),
          Text(
            '${currentLat.toStringAsFixed(4)}, ${currentLng.toStringAsFixed(4)}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          Text(
            GapLessL10n.t('road_report_hint'),
            style: GapLessL10n.safeStyle(
                const TextStyle(fontSize: 13, color: Colors.black54)),
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
                    backgroundColor: const Color(0xFF00C896),
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
// 通信断絶バッジ: 電波なし30秒後に緊急操作タブアイコンに重ねて点滅表示
// ============================================================================
class _OfflinePulseBadge extends StatefulWidget {
  final Widget child;
  const _OfflinePulseBadge({required this.child});

  @override
  State<_OfflinePulseBadge> createState() => _OfflinePulseBadgeState();
}

class _OfflinePulseBadgeState extends State<_OfflinePulseBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 1.0).animate(_ctrl);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        Positioned(
          right: -4,
          top: -4,
          child: FadeTransition(
            opacity: _anim,
            child: Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Color(0xFFB71C1C),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
