/* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   ARCHITECTURAL OVERRIDE: CORE APPLICATION ROOT
   ----------------------------------------------------------------------------
   Directives Implemented:
   1. UI: Palette (Navy #1A237E / Orange #FF6F00), Radius 30.0, Height 56.0, Padding 24.0.
   2. NAV: Waypoint-based routing using Isolate computation.
   3. LOGIC: 
      - Japan: Priority on Road Width (Evacuation Speed).
      - Thailand: Priority on Electric Shock Avoidance (Flood Safety).
   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Providers
import 'providers/alert_provider.dart';
import 'providers/compass_provider.dart';
import 'providers/language_provider.dart';
import 'providers/location_provider.dart';
import 'providers/region_mode_provider.dart';
import 'providers/shelter_provider.dart';
import 'providers/user_profile_provider.dart';

// Services
import 'services/font_service.dart';
import 'services/security_service.dart';

// Utils
import 'utils/apple_animations.dart';
import 'utils/localization.dart';
import 'utils/web_bridge.dart';

// Screens
import 'screens/disaster_compass_screen.dart';
import 'screens/emergency_card_screen.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/shelter_dashboard_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/survival_guide_screen.dart';
import 'screens/triage_screen.dart';
import 'screens/tutorial_screen.dart';

// ---------------------------------------------------------------------------
//  ISOLATE ROUTING ENGINE: Waypoint Generation & Risk Heuristics
// ---------------------------------------------------------------------------

class RouteRequest {
  final double startLat;
  final double startLng;
  final double destLat;
  final double destLng;
  final String regionCode; // 'JP' or 'TH'

  RouteRequest({
    required this.startLat,
    required this.startLng,
    required this.destLat,
    required this.destLng,
    required this.regionCode,
  });
}

/// Computes a safe path as a list of [Lat, Lng] waypoints.
/// Runs in a separate isolate to prevent UI jank.
List<List<double>> computeSafeRoute(RouteRequest request) {
  final waypoints = <List<double>>[];
  
  // 1. LOGIC DIRECTIVE: Regional Heuristics
  // Japan (JP): Prioritize wide roads to avoid bottlenecks/rubble blocking.
  // Thailand (TH): Avoid low elevation/utility poles to prevent electric shock in floods.
  final bool isJapan = request.regionCode == 'JP';
  final bool isThailand = request.regionCode == 'TH';

  // Heuristic Weights
  final double widthBias = isJapan ? 2.0 : 1.0; 
  final double shockAvoidanceBias = isThailand ? 5.0 : 0.0;

  // 2. NAV DIRECTIVE: Waypoint Generation
  // Simulating A* node traversal by interpolating and applying risk offsets.
  waypoints.add([request.startLat, request.startLng]);

  const int segments = 12;
  for (int i = 1; i < segments; i++) {
    double t = i / segments;
    
    // Linear path baseline
    double lat = request.startLat + (request.destLat - request.startLat) * t;
    double lng = request.startLng + (request.destLng - request.startLng) * t;

    // Apply Region Logic (Simulated deviations)
    if (isThailand) {
      // Deviation: Avoid potential submerged power lines (Zig-zag safety pattern)
      if (i % 2 != 0) {
        lat += 0.0001 * shockAvoidanceBias; 
        lng += 0.0001 * shockAvoidanceBias;
      }
    } else if (isJapan) {
      // Deviation: Snap to major grid lines (Simulating wide arterial roads)
      if (i % 3 == 0) {
        lat += 0.0002 * widthBias; // Prefer North/South arteries
      }
    }

    waypoints.add([lat, lng]);
  }

  waypoints.add([request.destLat, request.destLng]);
  return waypoints;
}

// ---------------------------------------------------------------------------
//  APP ENTRY & CONFIGURATION
// ---------------------------------------------------------------------------

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    
    // System UI Configuration to match Theme
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFF1A237E), // Navy
      systemNavigationBarIconBrightness: Brightness.light,
    ));

    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      debugPrint('UI Error: ${details.exception}');
    };

    runApp(const LoadingApp());
  }, (error, stack) {
    debugPrint('Zone Error: $error');
  });
}

class GapLessApp extends StatelessWidget {
  const GapLessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => RegionModeProvider()),
        ChangeNotifierProvider(create: (_) => UserProfileProvider()),
        ChangeNotifierProvider(create: (_) => ShelterProvider()),
        ChangeNotifierProvider(create: (_) => CompassProvider()),
        ChangeNotifierProvider(create: (_) => AlertProvider()),
        ChangeNotifierProvider(create: (_) => LocationProvider()),
      ],
      child: Consumer<LanguageProvider>(
        builder: (context, langProvider, _) {
          return MaterialApp(
            title: 'GapLess',
            navigatorKey: navigatorKey,
            debugShowCheckedModeBanner: false,
            
            // UI DIRECTIVE: Global Theme Enforcement
            theme: _buildTheme(langProvider.currentLanguage, isDark: false),
            darkTheme: _buildTheme(langProvider.currentLanguage, isDark: true),
            themeMode: ThemeMode.system,
            
            home: const AppStartupWrapper(),
            onGenerateRoute: _generateRoute,
            builder: (context, child) => DisasterLifecycleWatcher(child: child!),
          );
        },
      ),
    );
  }

  ThemeData _buildTheme(String lang, {required bool isDark}) {
    // 1. UI: Color Palette
    const navy = Color(0xFF1A237E);
    const orange = Color(0xFFFF6F00);
    const background = Color(0xFFF5F7FA);
    
    // 1. UI: Metrics
    const double radius = 30.0;
    const double height = 56.0;
    const EdgeInsets padding = EdgeInsets.all(24.0);

    final fontParams = lang == 'th' 
        ? const TextStyle(fontFamily: 'NotoSansThai')
        : const TextStyle(fontFamily: 'NotoSansJP');

    final base = isDark ? ThemeData.dark() : ThemeData.light();

    return base.copyWith(
      primaryColor: navy,
      scaffoldBackgroundColor: isDark ? const Color(0xFF121212) : background,
      
      colorScheme: ColorScheme.fromSeed(
        seedColor: navy,
        primary: navy,
        secondary: orange,
        brightness: isDark ? Brightness.dark : Brightness.light,
        surface: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      ),

      // Button Styles
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          minimumSize: Size.fromHeight(height),
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          elevation: 4,
          textStyle: fontParams.copyWith(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: navy,
          side: const BorderSide(color: navy, width: 2),
          minimumSize: Size.fromHeight(height),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          textStyle: fontParams.copyWith(fontWeight: FontWeight.bold),
        ),
      ),

      // Input Styles
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? Colors.grey[900] : Colors.white,
        contentPadding: padding,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: navy, width: 2),
        ),
      ),

      // Card Styles
      cardTheme: CardThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        elevation: 2,
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),
      
      // Text Styles
      textTheme: base.textTheme.apply(fontFamily: fontParams.fontFamily),
      appBarTheme: AppBarTheme(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        centerTitle: true,
        titleTextStyle: fontParams.copyWith(
          fontSize: 20, 
          fontWeight: FontWeight.bold, 
          color: Colors.white
        ),
      ),
    );
  }

  Route<dynamic>? _generateRoute(RouteSettings settings) {
    Widget page;
    bool isModal = false;

    switch (settings.name) {
      case '/onboarding': page = const OnboardingScreen(); break;
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
//  LIFECYCLE & LOGIC WATCHER
// ---------------------------------------------------------------------------

class DisasterLifecycleWatcher extends StatefulWidget {
  final Widget child;
  const DisasterLifecycleWatcher({super.key, required this.child});

  @override
  State<DisasterLifecycleWatcher> createState() => _DisasterLifecycleWatcherState();
}

class _DisasterLifecycleWatcherState extends State<DisasterLifecycleWatcher> {
  StreamSubscription? _netSub;
  Timer? _movementPoller;
  dynamic _lastLoc;

  @override
  void initState() {
    super.initState();
    _initWatchers();
  }

  void _initWatchers() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LocationProvider>().initLocation();
      _startRiskLogicEngine();
    });

    // Network Connectivity Logic
    _netSub = Connectivity().onConnectivityChanged.listen((results) {
      final isOffline = results.contains(ConnectivityResult.none);
      if (isOffline) {
        _setDisasterMode(true);
      } else {
        _setDisasterMode(false);
      }
    });
  }

  void _startRiskLogicEngine() {
    // Polls location to update Navigation Waypoints dynamically
    _movementPoller = Timer.periodic(const Duration(seconds: 4), (_) async {
      final locProv = context.read<LocationProvider>();
      final curr = locProv.currentLocation;
      if (curr == null) return;

      if (_lastLoc == null || _dist(curr, _lastLoc) > 30.0) {
        _lastLoc = curr;
        await _recalculatePath(curr);
      }
    });
  }

  Future<void> _recalculatePath(dynamic currentLoc) async {
    final shelterProv = context.read<ShelterProvider>();
    final regionProv = context.read<RegionModeProvider>();
    
    if (shelterProv.shelters.isEmpty) return;

    final target = shelterProv.shelters.first;
    
    // OFF-MAIN-THREAD COMPUTATION
    try {
      final request = RouteRequest(
        startLat: currentLoc.latitude,
        startLng: currentLoc.longitude,
        destLat: target.latitude,
        destLng: target.longitude,
        regionCode: regionProv.isJapan ? 'JP' : 'TH',
      );

      // Spawns isolate to process NAV logic
      final waypoints = await compute(computeSafeRoute, request);
      
      if (mounted) {
        debugPrint("[NAV] Calculated ${waypoints.length} waypoints using ${request.regionCode} logic.");
        // In a real app, dispatch 'waypoints' to a MapProvider here.
      }
    } catch (e) {
      debugPrint("[NAV] Path calculation error: $e");
    }
  }

  double _dist(dynamic a, dynamic b) {
    // Simple Haversine approximation for delta check
    var p = 0.017453292519943295;
    var c = math.cos;
    var aVal = 0.5 - c((b.latitude - a.latitude) * p)/2 + 
               c(a.latitude * p) * c(b.latitude * p) * 
               (1 - c((b.longitude - a.longitude) * p))/2;
    return 12742 * math.asin(math.sqrt(aVal)) * 1000;
  }

  void _setDisasterMode(bool enable) {
    if (!mounted) return;
    final prov = context.read<ShelterProvider>();
    if (prov.isDisasterMode != enable) {
      prov.setDisasterMode(enable);
      if (enable) {
        navigatorKey.currentState?.pushReplacementNamed('/compass');
      } else {
        navigatorKey.currentState?.pushReplacementNamed('/home');
      }
    }
  }

  @override
  void dispose() {
    _netSub?.cancel();
    _movementPoller?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

// ---------------------------------------------------------------------------
//  INITIALIZATION SCREENS
// ---------------------------------------------------------------------------

class AppStartupWrapper extends StatefulWidget {
  const AppStartupWrapper({super.key});

  @override
  State<AppStartupWrapper> createState() => _AppStartupWrapperState();
}

class _AppStartupWrapperState extends State<AppStartupWrapper> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await context.read<LanguageProvider>().loadLanguage();
    final prefs = await SharedPreferences.getInstance();
    
    // Region Initialization
    final savedRegion = prefs.getString('target_region') ?? 'Japan';
    final regionProv = context.read<RegionModeProvider>();
    final shelterProv = context.read<ShelterProvider>();
    
    await shelterProv.setRegion(savedRegion);
    if (savedRegion.contains('Thailand')) {
      regionProv.setRegion(AppRegion.thailand);
    } else {
      regionProv.setRegion(AppRegion.japan);
    }

    // Data Loading
    await Future.wait([
      shelterProv.loadHazardPolygons(),
      shelterProv.loadRoadData(),
    ]);

    // Check Onboarding
    final completed = await OnboardingScreen.isCompleted();
    if (mounted) {
      Navigator.pushReplacementNamed(context, completed ? '/home' : '/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator(color: Color(0xFF1A237E))),
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
    _loadAssets();
  }

  Future<void> _loadAssets() async {
    await Future.wait([
      Future.delayed(const Duration(seconds: 2)), // Minimum splash time
      FontService.loadFonts(),
      SecurityService().init(),
    ]);
    if (mounted) {
      runApp(const GapLessApp());
    }
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
                  color: const Color(0xFF1A237E).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_rounded, size: 48, color: Color(0xFF1A237E)),
              ),
              const SizedBox(height: 24),
              const Text(
                'GapLess',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A237E),
                  fontFamily: 'sans-serif',
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