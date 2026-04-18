/* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   ARCHITECTURAL OVERWRITE: LIB/MAIN.DART
   Directives Implemented:
   1. UI: Navy (0xFF2E7D32) / Orange (0xFFFF6F00), Radius 30.0, Height 56.0, Padding 24.0+.
   2. NAV: Isolate-based A* Pathfinding returning LatLng Waypoints.
   3. LOGIC: Japan (Width Priority) vs Thailand (Shock Risk Avoidance).
   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Providers
import 'providers/shelter_provider.dart';
import 'providers/user_profile_provider.dart';
import 'providers/compass_provider.dart';
import 'providers/alert_provider.dart';
import 'providers/location_provider.dart';
import 'providers/language_provider.dart';
import 'providers/region_mode_provider.dart';

// Services
import 'data/map_repository.dart';
import 'data/map_auto_loader.dart';
import 'models/road_feature.dart';
import 'services/font_service.dart';
import 'services/security_service.dart';
import 'services/device_id_service.dart';
import 'services/route_compute_service.dart';
import 'services/road_features_cache.dart';

// Utils
import 'utils/web_bridge.dart';
import 'utils/apple_animations.dart';
import 'utils/localization.dart';
import 'l10n/generated/app_localizations.dart';

// Theme (Apple Design System)
import 'theme/app_theme.dart';
import 'theme/emergency_theme_notifier.dart';

// Screens
import 'screens/splash_screen.dart';
import 'screens/map_data_loading_screen.dart';
import 'screens/home_screen.dart';
import 'screens/disaster_compass_screen.dart';
import 'screens/shelter_dashboard_screen.dart';
import 'screens/emergency_card_screen.dart';
import 'screens/survival_guide_screen.dart';
import 'screens/triage_screen.dart';
import 'screens/tutorial_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/permission_gate_screen.dart';
import 'screens/navigation_screen.dart';

// ---------------------------------------------------------------------------
//  MAIN APPLICATION
// ---------------------------------------------------------------------------

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    // 🆔 デバイスUUID初期化（重複評価防止・プライバシー設計）
    // アプリ起動直後にlocalStorageからUUIDを取得 or 生成して保存
    await DeviceIdService.instance.init();
    
    // System UI Config
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('Flutter Error: ${details.exception}');
    };

    runApp(const LoadingApp());
  }, (error, stack) {
    debugPrint('Async Error: $error');
  });
}

class GapLessApp extends StatelessWidget {
  const GapLessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => LanguageProvider(),
      child: Consumer<LanguageProvider>(
        builder: (context, languageProvider, _) {
          return MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => RegionModeProvider()),
              ChangeNotifierProvider(create: (_) => UserProfileProvider()),
              ChangeNotifierProvider(create: (_) => ShelterProvider()),
              ChangeNotifierProvider(create: (_) => CompassProvider()),
              ChangeNotifierProvider(create: (_) => AlertProvider()),
              ChangeNotifierProvider(create: (_) => LocationProvider()),
              ChangeNotifierProvider(create: (_) => EmergencyThemeNotifier()),
            ],
            child: Consumer<EmergencyThemeNotifier>(
              builder: (context, emergencyTheme, _) {
                final String primaryFont =
                    _fontFamilyForLocale(Locale(languageProvider.currentLanguage));
                final ThemeData themeData = emergencyTheme.isEmergency
                    ? AppTheme.buildEmergency(
                        fontFamily: primaryFont,
                        fontFamilyFallback: GapLessL10n.fallbackFonts,
                      )
                    : AppTheme.buildNormal(
                        fontFamily: primaryFont,
                        fontFamilyFallback: GapLessL10n.fallbackFonts,
                      );

                return MaterialApp(
                  title: 'GapLess',
                  navigatorKey: navigatorKey,
                  debugShowCheckedModeBanner: false,
                  scrollBehavior: const CustomScrollBehavior(),

                  // 多言語テキスト整形（タイ語・ミャンマー語等の文字結合・豆腐防止に必須）
                  localizationsDelegates: const [
                    AppLocalizations.delegate,
                    GlobalMaterialLocalizations.delegate,
                    GlobalWidgetsLocalizations.delegate,
                    GlobalCupertinoLocalizations.delegate,
                  ],
                  supportedLocales: const [
                    Locale('ja'),
                    Locale('en'),
                    Locale('zh'),
                    Locale('vi'),
                    Locale('ko'),
                    Locale('th'),
                    Locale('fil'), // ISO 639-2 (内部コード)
                    Locale('tl'),  // ISO 639-1 (Tagalog, システムロケール tl-PH 対応)
                    Locale('ne'),
                    Locale('pt'),
                    Locale('id'),
                    Locale('my'),
                    Locale('si'),
                    Locale('zh', 'TW'),
                    Locale('hi'),
                    Locale('es'),
                    Locale('mn'),
                    Locale('uz'),
                    Locale('bn'),
                  ],
                  localeResolutionCallback: (locale, supportedLocales) {
                    if (locale == null) return const Locale('en');
                    for (final s in supportedLocales) {
                      if (s.languageCode == locale.languageCode &&
                          s.countryCode == locale.countryCode) return s;
                    }
                    for (final s in supportedLocales) {
                      if (s.languageCode == locale.languageCode) return s;
                    }
                    return const Locale('en');
                  },

                  // Apple Design System theme — 通常時 緑、緊急時 赤に切替
                  theme: themeData,
                  darkTheme: themeData,
                  themeMode: ThemeMode.dark,

                  home: const AppStartup(),

                  onGenerateRoute: _onGenerateRoute,
                  builder: (context, child) {
                    final locale = Localizations.localeOf(context);
                    final fontFamily = _fontFamilyForLocale(locale);
                    return DefaultTextStyle(
                      style: TextStyle(
                        fontFamily: fontFamily,
                        fontFamilyFallback: GapLessL10n.fallbackFonts,
                      ),
                      child: DisasterWatcher(child: child!),
                    );
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }

  String _fontFamilyForLocale(Locale locale) {
    switch (locale.languageCode) {
      case 'ja': return 'NotoSansJP';
      // zh_TW is stored as a single language code string, handle both forms
      case 'zh_TW': return 'NotoSansTC';
      case 'zh': return locale.countryCode == 'TW' ? 'NotoSansTC' : 'NotoSansSC';
      case 'ko': return 'NotoSansKR';
      case 'th': return 'NotoSansThai';
      case 'my': return 'NotoSansMyanmar';
      case 'si': return 'NotoSansSinhala';
      case 'hi':
      case 'ne': return 'NotoSansDevanagari';
      case 'bn': return 'NotoSansBengali';
      default:   return 'NotoSans';
    }
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    Widget page;
    bool isModal = false;

    switch (settings.name) {
      case '/onboarding': page = const OnboardingScreen(); break;
      case '/splash': page = const SplashScreen(); break;
      case '/home': page = const HomeScreen(); break;
      case '/compass': page = const DisasterCompassScreen(); break;
      case '/dashboard': page = const ShelterDashboardScreen(); break;
      case '/emergency_card': page = const EmergencyCardScreen(); isModal = true; break;
      case '/survival_guide': page = const SurvivalGuideScreen(); break;
      case '/triage': page = const TriageScreen(); break;
      case '/tutorial':
        page = TutorialScreen(onComplete: () {
          navigatorKey.currentState?.pushReplacementNamed('/home');
        });
        break;
      default: return null;
    }
    return isModal ? AppleModalRoute(page: page) : ApplePageRoute(page: page);
  }
}

// ---------------------------------------------------------------------------
//  STATE MANAGERS & WATCHERS
// ---------------------------------------------------------------------------

class DisasterWatcher extends StatefulWidget {
  final Widget child;
  const DisasterWatcher({super.key, required this.child});

  @override
  State<DisasterWatcher> createState() => _DisasterWatcherState();
}

class _DisasterWatcherState extends State<DisasterWatcher> {
  bool? _wasDisasterMode;
  bool? _wasSafeInShelter;
  bool _isOffline = false; // オフライン状態フラグ（バナー表示制御）
  Timer? _disasterModeDebounce; // 頻繁なモード切替を防ぐデバウンスタイマー
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<MapLoadEvent>? _mapLoaderSubscription;
  Timer? _heartbeatTimer;
  Timer? _recoveryTimer;
  Timer? _movementPoller;
  dynamic _lastLocation;
  List<RoadFeature> _roadFeatures = [];
  String _roadFeaturesRegion = ''; // どの地域の道路データを保持しているか
  bool _routeComputeInProgress = false; // 並列 compute() を防ぐフラグ
  // ハートビート連続失敗カウンター（ヒステリシス用）
  // 3回連続失敗→災害モード、1回成功→カウンターリセット
  int _heartbeatFailCount = 0;
  static const int _heartbeatFailThreshold = 3;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LocationProvider>().initLocation();
      _startRiskMonitoring();
    });

    // DeadReckoningService をバインド（GPS消失時のフォールバック）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final dr = context.read<LocationProvider>().deadReckoningService;
      MapAutoLoader.instance.bindDeadReckoning(dr);
    });
    MapAutoLoader.instance.start();
    _mapLoaderSubscription = MapAutoLoader.instance.onEvent.listen((event) {
      if (event.type == MapLoadEventType.allLoaded && mounted) {
        setState(() {});
      }
    });

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.contains(ConnectivityResult.none);
      if (mounted) setState(() => _isOffline = offline);
      // カウンター管理はハートビートタイマーに一元化。
      // ここでは UI バナーのみ更新し、復帰時にのみ通知する。
      if (!offline) {
        _heartbeatFailCount = 0;
        _onNetworkRestored('Connectivity API');
      }
    });

    WebBridgeInterface.listenForOfflineEvent(() => _triggerDisasterMode("JS Event"));
    WebBridgeInterface.listenForOnlineEvent(() => _onNetworkRestored("JS Event"));

    // App Heartbeat（ヒステリシス付き・複数エンドポイント）
    // 単一サーバー障害では disaster mode に入らないよう、
    // 独立した3エンドポイントを並列チェックし全て失敗した場合のみカウントアップ。
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      if (context.read<ShelterProvider>().isDisasterMode) return;

      final endpoints = kIsWeb
          ? [Uri.parse('${Uri.base.origin}/?_t=${DateTime.now().millisecondsSinceEpoch}')]
          : [
              Uri.parse('https://www.google.com'),
              Uri.parse('https://www.apple.com'),
              Uri.parse('https://raw.githubusercontent.com'),
            ];

      // いずれか1つでも応答すれば即座に「ネット生存」と判断（全完了を待たない）
      final anyAlive = await Future.any(
        endpoints.map((uri) => http
            .head(uri)
            .timeout(const Duration(seconds: 2))
            .then((_) => true)
            .catchError((_) => false)),
      ).catchError((_) => false);

      if (anyAlive) {
        _heartbeatFailCount = 0;
      } else {
        _heartbeatFailCount++;
        if (_heartbeatFailCount >= _heartbeatFailThreshold) {
          _triggerDisasterMode('Heartbeat Failure ($_heartbeatFailCount 回連続・全エンドポイント)');
        }
      }
    });
  }

  void _startRiskMonitoring() {
    final locProvider = context.read<LocationProvider>();
    _movementPoller = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final currentLoc = locProvider.currentLocation;
      if (currentLoc != null) {
        _checkMovementAndRecalculate(currentLoc);
      }
    });
  }

  Future<void> _checkMovementAndRecalculate(dynamic newLoc) async {
    if (_lastLocation == null) {
      _lastLocation = newLoc;
      _triggerBackgroundRouting(newLoc);
      return;
    }

    double dist = Geolocator.distanceBetween(_lastLocation.latitude, _lastLocation.longitude, newLoc.latitude, newLoc.longitude);

    // GPS 精度が悪いときは閾値を自動引き上げ（精度2σ超えたときだけ再ルート）
    double accuracy = 10.0;
    try { accuracy = (newLoc.accuracy as num).toDouble(); } catch (_) {}
    final threshold = (accuracy * 2.0).clamp(20.0, 80.0);
    if (dist > threshold) {
      _lastLocation = newLoc;
      await _triggerBackgroundRouting(newLoc);
    }
  }

  Future<void> _triggerBackgroundRouting(dynamic loc) async {
    if (_routeComputeInProgress) return; // 前回の計算が完了するまで待機
    _routeComputeInProgress = true;

    try {
      final shelterProvider = context.read<ShelterProvider>();

      double destLat = 35.6895;
      double destLng = 139.6917;
      if (shelterProvider.shelters.isNotEmpty) {
        final nearest = shelterProvider.getAbsoluteNearest(LatLng(loc.latitude, loc.longitude));
        if (nearest != null) {
          destLat = nearest.lat;
          destLng = nearest.lng;
          debugPrint('🎯 Routing target: ${nearest.name}');
        } else {
          destLat = shelterProvider.shelters.first.lat;
          destLng = shelterProvider.shelters.first.lng;
        }
      }

      // 道路データをキャッシュ経由で取得（NavigationScreen と共有、二重ロードなし）
      // 地域が変わったらキャッシュを破棄して再ロード
      final isJapan = context.read<RegionModeProvider>().isJapanMode;
      final roadFile = isJapan ? 'tokyo_center_roads.gplb' : 'thailand_roads.gplb';
      if (_roadFeaturesRegion != roadFile) {
        _roadFeatures = [];
        _roadFeaturesRegion = roadFile;
      }
      if (_roadFeatures.isEmpty) {
        try {
          _roadFeatures = await RoadFeaturesCache.instance.get(roadFile);
        } catch (e) {
          debugPrint('Background routing: road data unavailable — $e');
          return;
        }
      }

      final result = await compute(
        computeRouteInIsolate,
        RouteComputeParams(
          features: _roadFeatures,
          startLat: loc.latitude,
          startLng: loc.longitude,
          goalLat: destLat,
          goalLng: destLng,
        ),
      );
      if (mounted && result.found) {
        final route = result.waypoints
            .map((p) => [p.latitude, p.longitude])
            .toList();
        shelterProvider.updateSafeRoute(route);
        debugPrint('✅ Route updated: ${route.length} waypoints');
      }
    } catch (e) {
      debugPrint('Routing error: $e');
    } finally {
      _routeComputeInProgress = false;
    }
  }

  void _triggerDisasterMode(String reason) {
    if (mounted) {
      final provider = context.read<ShelterProvider>();
      if (!provider.isDisasterMode) {
        debugPrint('⚠️ Offline detected ($reason). Triggering Disaster Mode.');
        provider.setDisasterMode(true);
      }
    }
  }

  void _onNetworkRestored(String reason) {
    if (!mounted) return;
    if (!context.read<ShelterProvider>().isDisasterMode) return;

    _recoveryTimer?.cancel();
    _recoveryTimer = Timer(const Duration(seconds: 2), _executeRecovery);
  }

  void _executeRecovery() {
    if (!mounted) return;
    final shelterProvider = context.read<ShelterProvider>();
    if (!shelterProvider.isDisasterMode) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(GapLessL10n.t('msg_network_restored')),
        backgroundColor: Theme.of(context).primaryColor,
      ),
    );

    shelterProvider.setDisasterMode(false);
    shelterProvider.setSafeInShelter(false);
    unawaited(shelterProvider.loadShelters());

    // 機能1修正: 復帰先をNavigationScreenに統一（HomeScreenではなく）
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const NavigationScreen()),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _mapLoaderSubscription?.cancel();
    MapAutoLoader.instance.stop();
    _connectivitySubscription?.cancel();
    _heartbeatTimer?.cancel();
    _recoveryTimer?.cancel();
    _movementPoller?.cancel();
    _disasterModeDebounce?.cancel();
    super.dispose();
  }

  /// 災害モード切替を 1.5 秒デバウンスしてナビゲーションを実行する。
  /// 短時間の連続切替（ネット断続など）によるループを防ぐ。
  void _scheduleDisasterModeNav(bool toDisaster) {
    _disasterModeDebounce?.cancel();
    _disasterModeDebounce = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (toDisaster) {
          navigatorKey.currentState?.pushReplacementNamed('/compass');
        } else {
          navigatorKey.currentState?.pushReplacementNamed('/home');
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDisasterMode = context.select<ShelterProvider, bool>((p) => p.isDisasterMode);
    final isSafeInShelter = context.select<ShelterProvider, bool>((p) => p.isSafeInShelter);

    if (_wasDisasterMode != isDisasterMode) {
      // 災害モード = 緊急テーマ。Consumer 側を再ビルドさせるため
      // build フェーズ後に notifyListeners を発火させる。
      final emergencyTheme = context.read<EmergencyThemeNotifier>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (isDisasterMode) {
          emergencyTheme.activateEmergency();
        } else {
          emergencyTheme.deactivateEmergency();
        }
      });

      if (isDisasterMode) {
        _scheduleDisasterModeNav(true);
      } else if (_wasDisasterMode == true && !isDisasterMode) {
        _scheduleDisasterModeNav(false);
      }
      _wasDisasterMode = isDisasterMode;
    }

    if (_wasSafeInShelter != isSafeInShelter) {
      if (isSafeInShelter) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          navigatorKey.currentState?.push(
            MaterialPageRoute(builder: (_) => const ShelterDashboardScreen()),
          );
        });
      }
      _wasSafeInShelter = isSafeInShelter;
    }

    // オフラインバナーを最前面に重ねる
    if (!_isOffline) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              color: const Color(0xFFB71C1C),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.wifi_off, color: Colors.white, size: 14),
                  const SizedBox(width: 6),
                  Text(
                    GapLessL10n.t('offline_banner'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class CustomScrollBehavior extends MaterialScrollBehavior {
  const CustomScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
      };
}

class AppStartup extends StatefulWidget {
  const AppStartup({super.key});

  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup> {
  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final languageProvider = context.read<LanguageProvider>();
    await languageProvider.loadLanguage();

    // マップデータが未キャッシュならダウンロード画面へ
    final allCached = await MapRepository.instance.isAllDataReady();
    if (!mounted) return;

    if (!allCached) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MapDataLoadingScreen()),
      );
      return;
    }

    final isOnboardingCompleted = await OnboardingScreen.isCompleted();
    if (!mounted) return;

    if (!isOnboardingCompleted) {
      Navigator.pushReplacementNamed(context, '/onboarding');
      return;
    }

    // パーミッション取得済みなら NavigationScreen へ直行
    final prefs = await SharedPreferences.getInstance();
    final permissionsGranted = prefs.getBool('permissions_granted') ?? false;
    if (!mounted) return;

    if (permissionsGranted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const NavigationScreen()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const PermissionGateScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF5F7FA),
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF2E7D32)),
      ),
    );
  }
}

class LoadingApp extends StatefulWidget {
  const LoadingApp({super.key});

  @override
  State<LoadingApp> createState() => _LoadingAppState();
}

class _LoadingAppState extends State<LoadingApp> {
  @override
  void initState() {
    super.initState();
    _preload();
  }

  Future<void> _preload() async {
    await Future.wait([
      Future.delayed(const Duration(seconds: 2)),
      FontService.loadFonts(),
      SecurityService().init(),
      _preloadFonts(),
    ]);
    if (mounted) {
      runApp(const GapLessApp());
    }
  }

  Future<void> _preloadFonts() async {
    // 複雑な文字結合ルールを持つスクリプトは pubspec.yaml の遅延ロードでは
    // 最初のフレームに間に合わないため FontLoader で明示的にプリロードする
    final loaders = [
      FontLoader('NotoSansThai')
        ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/NotoSansThai-Bold.ttf')),
      FontLoader('NotoSansMyanmar')
        ..addFont(rootBundle.load('assets/fonts/NotoSansMyanmar-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/NotoSansMyanmar-Bold.ttf')),
      FontLoader('NotoSansSinhala')
        ..addFont(rootBundle.load('assets/fonts/NotoSansSinhala-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/NotoSansSinhala-Bold.ttf')),
      FontLoader('NotoSansDevanagari')
        ..addFont(rootBundle.load('assets/fonts/NotoSansDevanagari-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/NotoSansDevanagari-Bold.ttf')),
      FontLoader('NotoSansBengali')
        ..addFont(rootBundle.load('assets/fonts/NotoSansBengali-Regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/NotoSansBengali-Bold.ttf')),
    ];
    await Future.wait(loaders.map((l) => l.load()));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: const Color(0xFF2E7D32).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_rounded, size: 48, color: Color(0xFF2E7D32)),
              ),
              const SizedBox(height: 24),
              const Text(
                'GapLess',
                style: TextStyle(
                  fontSize: 32, 
                  fontWeight: FontWeight.bold, 
                  color: Color(0xFF2E7D32)
                ),
              ),
              const SizedBox(height: 32),
              const CircularProgressIndicator(color: Color(0xFFFF6F00)),
            ],
          ),
        ),
      ),
    );
  }
}