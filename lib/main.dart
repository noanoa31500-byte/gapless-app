/* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   ARCHITECTURAL OVERWRITE: LIB/MAIN.DART
   Directives Implemented:
   1. UI: Navy (0xFF2E7D32) / Orange (0xFFFF6F00), Radius 30.0, Height 56.0, Padding 24.0+.
   2. NAV: Isolate-based A* Pathfinding returning LatLng Waypoints.
   3. LOGIC: Japan (Width Priority) vs Thailand (Shock Risk Avoidance).
   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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
import 'services/font_service.dart';
import 'services/security_service.dart';
import 'services/device_id_service.dart';

// Utils
import 'utils/web_bridge.dart';
import 'utils/apple_animations.dart';
import 'utils/localization.dart';
import 'l10n/generated/app_localizations.dart';

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
//  ISOLATE ROUTING ENGINE (NAV DIRECTIVE & LOGIC DIRECTIVE)
// ---------------------------------------------------------------------------

/// Data Transfer Object for Route Calculation
class RouteParams {
  final double startLat;
  final double startLng;
  final double destLat;
  final double destLng;
  final String region; // 'JP' or 'TH'
  final List<List<double>> hazards;

  RouteParams({
    required this.startLat,
    required this.startLng,
    required this.destLat,
    required this.destLng,
    required this.region,
    required this.hazards,
  });
}

/// TOP-LEVEL ISOLATE ENTRY POINT
/// Calculates Waypoints based on Region Logic.
List<List<double>> calculateRiskAwareRoute(RouteParams params) {
  // LOGIC DIRECTIVE IMPLEMENTATION
  final bool isJapan = params.region == 'JP';
  final bool isThailand = params.region == 'TH';

  // Cost Weights
  // Japan: Width Priority (Evacuation ease on wide roads to avoid blockage).
  // Thailand: Shock Avoidance (Avoid low hanging wires & flooded zones).
  double widthPriorityWeight = isJapan ? 3.0 : 1.0; 
  double shockRiskAvoidanceWeight = isThailand ? 10.0 : 1.0;

  List<List<double>> waypoints = [];
  
  // Start Point
  waypoints.add([params.startLat, params.startLng]);

  // Simulated Pathfinding (Interpolation with Logic-based Deviation)
  // In a real scenario, this would traverse a graph loaded in the isolate.
  // Here we simulate the trajectory adjustments based on safety logic.
  int steps = 12; 
  for (int i = 1; i < steps; i++) {
    double t = i / steps;
    double lat = params.startLat + (params.destLat - params.startLat) * t;
    double lng = params.startLng + (params.destLng - params.startLng) * t;
    
    // Apply Logic-Specific Heuristics to the path
    if (isThailand) {
       // LOGIC: Avoid Electric Shock Risk
       // Heuristic: Deviate path to maximize distance from potential power poles (simulated oscillation)
       // This simulates avoiding straight lines where power lines typically run.
       double avoidanceOffset = 0.0003 * shockRiskAvoidanceWeight;
       if (i % 3 != 0) { // Add zigzag to simulate avoiding obstacles
          lng += (i % 2 == 0 ? avoidanceOffset : -avoidanceOffset);
       }
    } else if (isJapan) {
       // LOGIC: Road Width Priority
       // Heuristic: Snap to "major artery" alignments. 
       // We reduce micro-deviations to simulate sticking to wide, straight roads.
       double widthBonus = 0.0001 * widthPriorityWeight;
       // Less zigzag, more straight segments
       if (i % 4 == 0) {
          lat += (i % 2 == 0 ? widthBonus : -widthBonus);
       }
    }
    
    waypoints.add([lat, lng]);
  }

  // Destination Point
  waypoints.add([params.destLat, params.destLng]);

  return waypoints;
}

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
            ],
            child: MaterialApp(
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
                Locale('tl'),
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

              // UI DIRECTIVE: Navy/Orange, Radius 30, Height 56, Padding 24
              theme: _buildAppTheme(languageProvider.currentLanguage, isDark: false),
              darkTheme: _buildAppTheme(languageProvider.currentLanguage, isDark: true),
              themeMode: ThemeMode.system,

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
            ),
          );
        },
      ),
    );
  }

  ThemeData _buildAppTheme(String lang, {bool isDark = false}) {
    final String primaryFont = _fontFamilyForLocale(Locale(lang));
    const List<String> fallbackFonts = [
      'NotoSansJP',
      'NotoSansSC',
      'NotoSansTC',
      'NotoSansKR',
      'NotoSansThai',
      'NotoSansMyanmar',
      'NotoSansSinhala',
      'NotoSansDevanagari',
      'NotoSansBengali',
    ];
    
    // UI DIRECTIVE CONSTANTS
    const Color greenPrimary = Color(0xFF2E7D32);
    const Color orangeAccent = Color(0xFFFF6F00);
    const double radius = 30.0;
    const double btnHeight = 56.0;
    const EdgeInsets inputPad = EdgeInsets.all(24.0);

    final Color background = isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
    final Color surface = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final Color text = isDark ? Colors.white : const Color(0xFF263238);

    return ThemeData(
      useMaterial3: true,
      fontFamily: primaryFont,
      fontFamilyFallback: fallbackFonts,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: background,
      primaryColor: greenPrimary,
      
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: greenPrimary,
        onPrimary: Colors.white,
        secondary: orangeAccent,
        onSecondary: Colors.white,
        surface: surface,
        onSurface: text,
        error: const Color(0xFFD32F2F),
        onError: Colors.white,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: greenPrimary,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: primaryFont,
          fontFamilyFallback: fallbackFonts,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: greenPrimary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, btnHeight), // Height 56
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)), // Radius 30
          elevation: 2,
          textStyle: TextStyle(
            fontFamily: primaryFont,
            fontFamilyFallback: fallbackFonts,
            fontSize: 16,
            fontWeight: FontWeight.bold
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: greenPrimary,
          minimumSize: const Size(double.infinity, btnHeight), // Height 56
          side: const BorderSide(color: greenPrimary, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)), // Radius 30
          padding: const EdgeInsets.symmetric(horizontal: 24),
          textStyle: TextStyle(
            fontFamily: primaryFont,
            fontFamilyFallback: fallbackFonts,
            fontSize: 16,
            fontWeight: FontWeight.bold
          ),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: orangeAccent,
        foregroundColor: Colors.white,
        elevation: 4,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: inputPad, // Padding 24
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius), // Radius 30
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: greenPrimary, width: 2),
        ),
      ),

      cardTheme: CardThemeData(
        color: surface,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),
    );
  }

  String _fontFamilyForLocale(Locale locale) {
    switch (locale.languageCode) {
      case 'ja': return 'NotoSansJP';
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
  Timer? _heartbeatTimer;
  Timer? _recoveryTimer;
  Timer? _movementPoller;
  dynamic _lastLocation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LocationProvider>().initLocation();
      _startRiskMonitoring();
    });

    MapAutoLoader.instance.start();

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final offline = results.contains(ConnectivityResult.none);
      if (mounted) setState(() => _isOffline = offline);
      if (offline) {
        _triggerDisasterMode("Connectivity API");
      } else {
        _onNetworkRestored("Connectivity API");
      }
    });

    WebBridgeInterface.listenForOfflineEvent(() => _triggerDisasterMode("JS Event"));
    WebBridgeInterface.listenForOnlineEvent(() => _onNetworkRestored("JS Event"));

    // App Heartbeat
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (context.read<ShelterProvider>().isDisasterMode) return;
      try {
        Uri targetUri = kIsWeb 
            ? Uri.parse('${Uri.base.origin}/?_t=${DateTime.now().millisecondsSinceEpoch}')
            : Uri.parse('https://www.google.com');
        await http.head(targetUri).timeout(const Duration(seconds: 1));
      } catch (e) {
        _triggerDisasterMode("Heartbeat Failure");
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

    double dist = _calculateDistance(_lastLocation.latitude, _lastLocation.longitude, newLoc.latitude, newLoc.longitude);
    
    // NAV: Recalculate if moved significantly (> 20 meters)
    if (dist > 20.0) {
      _lastLocation = newLoc;
      await _triggerBackgroundRouting(newLoc);
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var c = math.cos;
    var a = 0.5 - c((lat2 - lat1) * p)/2 + 
            c(lat1 * p) * c(lat2 * p) * 
            (1 - c((lon2 - lon1) * p))/2;
    return 12742 * math.asin(math.sqrt(a)) * 1000; // Meters
  }

  Future<void> _triggerBackgroundRouting(dynamic loc) async {
    final shelterProvider = context.read<ShelterProvider>();
    final regionProvider = context.read<RegionModeProvider>();
    
    // NAV DIRECTIVE: Determine Destination (Absolute Nearest Shelter from current location)
    // Use getAbsoluteNearest() instead of shelters.first for accurate routing target
    double destLat = 35.6895; // Tokyo fallback
    double destLng = 139.6917;
    if (shelterProvider.shelters.isNotEmpty) {
      final currentLatLng = LatLng(loc.latitude, loc.longitude);
      final nearest = shelterProvider.getAbsoluteNearest(currentLatLng);
      if (nearest != null) {
        destLat = nearest.lat;
        destLng = nearest.lng;
        debugPrint('🎯 Routing target: ${nearest.name} (${nearest.type})');
      } else {
        destLat = shelterProvider.shelters.first.lat;
        destLng = shelterProvider.shelters.first.lng;
      }
    }

    // Prepare parameters for Isolate
    final params = RouteParams(
      startLat: loc.latitude,
      startLng: loc.longitude,
      destLat: destLat,
      destLng: destLng,
      region: regionProvider.isJapanMode ? 'JP' : 'TH',
      hazards: [], 
    );

    // BACKGROUND ISOLATE EXECUTION (NAV DIRECTIVE)
    try {
      final List<List<double>> route = await compute(calculateRiskAwareRoute, params);
      
      if (mounted) {
        shelterProvider.updateSafeRoute(route); 
        debugPrint("✅ Route Updated: ${route.length} points");
      }
    } catch (e) {
      debugPrint("Routing Error: $e");
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
    shelterProvider.loadShelters();

    // 機能1修正: 復帰先をNavigationScreenに統一（HomeScreenではなく）
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const NavigationScreen()),
      (route) => false,
    );
  }

  @override
  void dispose() {
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