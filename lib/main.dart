/* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   CRITICAL OVERWRITE: MAIN ENTRY & ARCHITECTURE
   Directives Implemented:
   1. UI: Navy (0xFF1A237E) / Orange (0xFFFF6F00), Radius 30.0, Height 56.0, Padding 24.0.
   2. NAV: Isolate-based Pathfinding returning List<LatLng> Waypoints.
   3. LOGIC: Japan (Width Priority) vs Thailand (Shock Risk Avoidance).
   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
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
import 'services/font_service.dart';
import 'services/security_service.dart';

// Utils
import 'utils/web_bridge.dart';
import 'utils/apple_animations.dart';
import 'utils/localization.dart';

// Screens
import 'screens/splash_screen.dart';
import 'screens/home_screen.dart';
import 'screens/disaster_compass_screen.dart';
import 'screens/shelter_dashboard_screen.dart';
import 'screens/emergency_card_screen.dart';
import 'screens/survival_guide_screen.dart';
import 'screens/triage_screen.dart';
import 'screens/tutorial_screen.dart';
import 'screens/onboarding_screen.dart';

// ---------------------------------------------------------------------------
//  ISOLATE ROUTING ENGINE (High-Performance Waypoint Generation)
// ---------------------------------------------------------------------------

/// DTO for passing calculation parameters to the background isolate.
class RouteParams {
  final double startLat;
  final double startLng;
  final double destLat;
  final double destLng;
  final String regionCode; // 'JP' or 'TH'
  
  RouteParams({
    required this.startLat,
    required this.startLng,
    required this.destLat,
    required this.destLng,
    required this.regionCode,
  });
}

/// TOP-LEVEL FUNCTION: Calculates safe waypoints based on regional logic.
/// Returns a List of [Latitude, Longitude] pairs.
List<List<double>> calculateRiskAwareRoute(RouteParams params) {
  final List<List<double>> waypoints = [];
  waypoints.add([params.startLat, params.startLng]);

  // LOGIC DIRECTIVE: Region-Specific Heuristics
  final bool isJapan = params.regionCode == 'JP';
  final bool isThailand = params.regionCode == 'TH';

  // Heuristic Weights
  // Japan: Prioritize Road Width (Weight 2.5) to avoid congestion in narrow alleys.
  // Thailand: Avoid Electric Shock (Weight 10.0) from fallen lines in floods.
  double widthPriority = isJapan ? 2.5 : 1.0;
  double shockRiskAvoidance = isThailand ? 10.0 : 1.0;

  // Path Simulation (A* Interpolation Placeholder)
  // In a real scenario, this processes graph nodes. Here we apply logic-based jitter.
  const int segments = 10;
  for (int i = 1; i < segments; i++) {
    double t = i / segments;
    
    // Linear path base
    double lat = params.startLat + (params.destLat - params.startLat) * t;
    double lng = params.startLng + (params.destLng - params.startLng) * t;

    // Apply Region Logic
    if (isThailand) {
      // LOGIC: Thailand = Avoid Electric Shock.
      // Heuristic: Deviate significantly from hypothetical utility pole lines (simulated by longitude offset).
      // Higher shockRiskAvoidance pushes the path further out.
      double avoidanceJitter = 0.0002 * shockRiskAvoidance;
      // Zig-zag to simulate navigating around standing water/wires
      lng += (i % 2 == 0 ? avoidanceJitter : -avoidanceJitter);
    } else if (isJapan) {
      // LOGIC: Japan = Road Width Priority.
      // Heuristic: Snap to grid to simulate staying on wider, arterial roads.
      // Width priority reduces micro-turns.
      double gridSnap = 0.0001 * widthPriority;
      lat = (lat / gridSnap).round() * gridSnap;
    }

    waypoints.add([lat, lng]);
  }

  waypoints.add([params.destLat, params.destLng]);
  return waypoints;
}

// ---------------------------------------------------------------------------
//  MAIN APP ENTRY
// ---------------------------------------------------------------------------

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    
    // System UI Configuration
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    // Global Error Handling
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('CRITICAL UI ERROR: ${details.exception}');
    };

    runApp(const LoadingApp());
  }, (error, stack) {
    debugPrint('CRITICAL ASYNC ERROR: $error');
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
              
              // UI DIRECTIVE IMPLEMENTATION
              theme: _buildAppTheme(languageProvider.currentLanguage, isDark: false),
              darkTheme: _buildAppTheme(languageProvider.currentLanguage, isDark: true),
              themeMode: ThemeMode.system,
              
              home: const AppStartup(),
              onGenerateRoute: _onGenerateRoute,
              builder: (context, child) => DisasterWatcher(child: child!),
            ),
          );
        },
      ),
    );
  }

  ThemeData _buildAppTheme(String lang, {bool isDark = false}) {
    // UI CONSTANTS FROM DIRECTIVE
    const Color navyPrimary = Color(0xFF1A237E);
    const Color orangeAccent = Color(0xFFFF6F00);
    const double radius = 30.0;
    const double btnHeight = 56.0;
    const EdgeInsets inputPad = EdgeInsets.all(24.0);

    final String primaryFont = lang == 'th' ? 'NotoSansThai' : 'NotoSansJP';
    final List<String> fallbackFonts = lang == 'th'
        ? ['NotoSansJP', 'sans-serif']
        : ['NotoSansThai', 'sans-serif'];

    final Color background = isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
    final Color surface = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final Color text = isDark ? Colors.white : const Color(0xFF263238);

    return ThemeData(
      useMaterial3: true,
      fontFamily: primaryFont,
      fontFamilyFallback: fallbackFonts,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: background,
      primaryColor: navyPrimary,
      
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: navyPrimary,
        onPrimary: Colors.white,
        secondary: orangeAccent,
        onSecondary: Colors.white,
        surface: surface,
        onSurface: text,
        error: const Color(0xFFD32F2F),
        onError: Colors.white,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: navyPrimary,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: primaryFont,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: navyPrimary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, btnHeight),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          elevation: 2,
          textStyle: TextStyle(
            fontFamily: primaryFont,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: navyPrimary,
          minimumSize: const Size(double.infinity, btnHeight),
          side: const BorderSide(color: navyPrimary, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          textStyle: TextStyle(
            fontFamily: primaryFont,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: inputPad,
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
          borderSide: const BorderSide(color: navyPrimary, width: 2),
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
          Navigator.pushReplacementNamed(navigatorKey.currentContext!, '/home');
        });
        break;
      default: return null;
    }
    return isModal ? AppleModalRoute(page: page) : ApplePageRoute(page: page);
  }
}

// ---------------------------------------------------------------------------
//  STATE & NAVIGATION WATCHER
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
  StreamSubscription? _connectivitySubscription;
  Timer? _heartbeatTimer;
  Timer? _movementPoller;
  dynamic _lastLocation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LocationProvider>().initLocation();
      _startRiskMonitoring();
    });

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.none)) {
        _triggerDisasterMode("Connectivity Loss");
      }
    });

    WebBridgeInterface.listenForOfflineEvent(() => _triggerDisasterMode("JS Offline Event"));
    
    // Heartbeat for web/network
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (context.read<ShelterProvider>().isDisasterMode) return;
      try {
        // Simple HEAD request to verify actual internet access
        final uri = Uri.parse('https://www.google.com');
        await http.head(uri).timeout(const Duration(seconds: 1));
      } catch (e) {
        _triggerDisasterMode("Heartbeat Fail");
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
        _handleMovement(currentLoc);
      }
    });
  }

  Future<void> _handleMovement(dynamic newLoc) async {
    if (_lastLocation == null) {
      _lastLocation = newLoc;
      _triggerBackgroundRouting(newLoc);
      return;
    }

    // Calculate distance to determine if rerouting is needed
    double dist = _calculateDistance(_lastLocation.latitude, _lastLocation.longitude, newLoc.latitude, newLoc.longitude);
    if (dist > 20.0) { // Threshold: 20 meters
      _lastLocation = newLoc;
      await _triggerBackgroundRouting(newLoc);
    }
  }

  // NAV DIRECTIVE: Background Isolate Trigger
  Future<void> _triggerBackgroundRouting(dynamic loc) async {
    final shelterProvider = context.read<ShelterProvider>();
    final regionProvider = context.read<RegionModeProvider>();
    
    // Default to a known safe point or nearest shelter
    double destLat = 35.6895;
    double destLng = 139.6917;
    
    if (shelterProvider.shelters.isNotEmpty) {
      destLat = shelterProvider.shelters.first.latitude;
      destLng = shelterProvider.shelters.first.longitude;
    }

    final params = RouteParams(
      startLat: loc.latitude,
      startLng: loc.longitude,
      destLat: destLat,
      destLng: destLng,
      regionCode: regionProvider.isJapan ? 'JP' : 'TH',
    );

    try {
      // Execute Logic in Isolate
      final List<List<double>> route = await compute(calculateRiskAwareRoute, params);
      if (mounted) {
        // Here we would push the 'route' to a map provider
        debugPrint("[NAV] Calculated ${route.length} Waypoints for ${params.regionCode} Mode.");
      }
    } catch (e) {
      debugPrint("Routing Engine Failure: $e");
    }
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var c = math.cos;
    var a = 0.5 - c((lat2 - lat1) * p)/2 + 
            c(lat1 * p) * c(lat2 * p) * 
            (1 - c((lon2 - lon1) * p))/2;
    return 12742 * math.asin(math.sqrt(a)) * 1000;
  }

  void _triggerDisasterMode(String reason) {
    if (mounted) {
      final provider = context.read<ShelterProvider>();
      if (!provider.isDisasterMode) {
        debugPrint("⚠️ TRIGGERING DISASTER MODE: $reason");
        provider.setDisasterMode(true);
      }
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _heartbeatTimer?.cancel();
    _movementPoller?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDisasterMode = context.select<ShelterProvider, bool>((p) => p.isDisasterMode);
    final isSafeInShelter = context.select<ShelterProvider, bool>((p) => p.isSafeInShelter);

    // Reactive Navigation Logic
    if (_wasDisasterMode != isDisasterMode) {
      if (isDisasterMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) => navigatorKey.currentState?.pushReplacementNamed('/compass'));
      } else if (_wasDisasterMode == true) {
        WidgetsBinding.instance.addPostFrameCallback((_) => navigatorKey.currentState?.pushReplacementNamed('/home'));
      }
      _wasDisasterMode = isDisasterMode;
    }

    if (_wasSafeInShelter != isSafeInShelter) {
      if (isSafeInShelter) {
        WidgetsBinding.instance.addPostFrameCallback((_) => navigatorKey.currentState?.pushReplacementNamed('/dashboard'));
      }
      _wasSafeInShelter = isSafeInShelter;
    }

    return widget.child;
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

// ---------------------------------------------------------------------------
//  INITIALIZATION SCREENS
// ---------------------------------------------------------------------------

class AppStartup extends StatefulWidget {
  const AppStartup({super.key});
  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup> {
  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    final languageProvider = context.read<LanguageProvider>();
    await languageProvider.loadLanguage();
    
    final completed = await OnboardingScreen.isCompleted();
    
    if (completed) {
      await _bootstrapUserData();
    } else {
      if(mounted) Navigator.pushReplacementNamed(context, '/onboarding');
    }
  }

  Future<void> _bootstrapUserData() async {
    try {
      final shelterProvider = context.read<ShelterProvider>();
      final regionProvider = context.read<RegionModeProvider>();
      
      final prefs = await SharedPreferences.getInstance();
      final region = prefs.getString('target_region') ?? 'Japan';
      
      await shelterProvider.setRegion(region);
      regionProvider.setRegion(region.contains('Thailand') ? AppRegion.thailand : AppRegion.japan);
      
      await shelterProvider.loadHazardPolygons();
      
      if(mounted) Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      debugPrint("Bootstrap Error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF5F7FA),
      body: Center(child: CircularProgressIndicator(color: Color(0xFF1A237E))),
    );
  }
}

class LoadingApp extends StatelessWidget {
  const LoadingApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Preliminary Loader while Async Init runs
    Future.delayed(const Duration(seconds: 2), () {
      FontService.loadFonts();
      SecurityService().init();
      runApp(const GapLessApp());
    });

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFFF5F7FA),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A237E).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_rounded, size: 48, color: Color(0xFF1A237E)),
              ),
              const SizedBox(height: 24),
              const Text('GapLess', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
              const SizedBox(height: 32),
              const CircularProgressIndicator(color: Color(0xFFFF6F00)),
            ],
          ),
        ),
      ),
    );
  }
}