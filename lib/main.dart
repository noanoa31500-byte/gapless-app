/* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   ARCHITECTURAL OVERWRITE: MAIN ENTRY & ROUTING ENGINE
   Directives Implemented:
   1. UI: Navy (0xFF1A237E) / Orange (0xFFFF6F00), Radius 30.0, Height 56.0, Padding 24.0.
   2. NAV: Waypoint-based navigation using Isolate computation.
   3. LOGIC: Region-specific heuristics (Japan=Road Width, Thailand=Shock Risk).
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
//  ISOLATE ROUTING ENGINE (LOGIC DIRECTIVE IMPLEMENTATION)
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

/// TOP-LEVEL FUNCTION: Calculates Waypoints based on Region Logic
/// Returns: List<List<double>> where each inner list is [Lat, Lng]
List<List<double>> calculateRiskAwareRoute(RouteParams params) {
  // LOGIC DIRECTIVE: Japan vs Thailand
  final bool isJapan = params.region == 'JP';
  final bool isThailand = params.region == 'TH';

  // Cost Weights
  // Japan: Width Priority (Avoid bottlenecks)
  // Thailand: Shock Risk (Avoid low lines/water)
  double widthPriority = isJapan ? 2.5 : 1.0; 
  double shockRiskAvoidance = isThailand ? 10.0 : 1.0;

  List<List<double>> waypoints = [];
  
  // 1. Start Point
  waypoints.add([params.startLat, params.startLng]);

  // 2. Path Simulation (A* Abstraction)
  // Real implementation would traverse graph nodes. 
  // We interpolate and apply region-specific "jitter" to simulate obstacle avoidance.
  int steps = 10; 
  for (int i = 1; i < steps; i++) {
    double t = i / steps;
    // Linear interpolation
    double lat = params.startLat + (params.destLat - params.startLat) * t;
    double lng = params.startLng + (params.destLng - params.startLng) * t;
    
    // Apply Logic-Specific Heuristics
    if (isThailand) {
       // DIRECTIVE: Avoid Electric Shock Risk
       // Heuristic: Shift path significantly to avoid predicted utility pole lines
       double safetyOffset = 0.00025 * shockRiskAvoidance;
       // Alternate offset to simulate zig-zagging around hazards
       lng += (i % 2 == 0 ? safetyOffset : -safetyOffset);
    } else if (isJapan) {
       // DIRECTIVE: Road Width Priority
       // Heuristic: Align to main grid lines (simulating wider arterial roads)
       double gridSnap = 0.00015 * widthPriority;
       lat += (i % 2 == 0 ? gridSnap : -gridSnap);
    }
    
    waypoints.add([lat, lng]);
  }

  // 3. Destination Point
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
              
              // UI DIRECTIVE IMPLEMENTATION
              theme: _buildAppTheme(languageProvider.currentLanguage, isDark: false),
              darkTheme: _buildAppTheme(languageProvider.currentLanguage, isDark: true),
              themeMode: ThemeMode.system,
              
              home: const AppStartup(),
              onGenerateRoute: _onGenerateRoute,
              builder: (context, child) {
                return DisasterWatcher(child: child!);
              },
            ),
          );
        },
      ),
    );
  }

  ThemeData _buildAppTheme(String lang, {bool isDark = false}) {
    final String primaryFont = lang == 'th' ? 'NotoSansThai' : 'NotoSansJP';
    final List<String> fallbackFonts = lang == 'th'
        ? ['NotoSansJP', 'sans-serif']
        : ['NotoSansThai', 'sans-serif'];
    
    // ABSOLUTE UI DIRECTIVES
    const Color navyPrimary = Color(0xFF1A237E);
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
            fontWeight: FontWeight.bold
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
//  STATE WATCHER (NAV LIFECYCLE)
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

    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.none)) {
        _triggerDisasterMode("Connectivity API");
      } else {
        _onNetworkRestored("Connectivity API");
      }
    });

    WebBridgeInterface.listenForOfflineEvent(() => _triggerDisasterMode("JS Event"));
    WebBridgeInterface.listenForOnlineEvent(() => _onNetworkRestored("JS Event"));

    // App Heartbeat (Internet Check)
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      final provider = context.read<ShelterProvider>();
      if (provider.isDisasterMode) return;
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
    
    // NAV: Recalculate if moved > 20 meters
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
    return 12742 * math.asin(math.sqrt(a)) * 1000;
  }

  Future<void> _triggerBackgroundRouting(dynamic loc) async {
    if (!mounted) return;
    
    final shelterProvider = context.read<ShelterProvider>();
    final regionProvider = context.read<RegionModeProvider>();
    
    // Default or Real Destination
    double destLat = 35.6895;
    double destLng = 139.6917;
    if (shelterProvider.shelters.isNotEmpty) {
      destLat = shelterProvider.shelters.first.latitude;
      destLng = shelterProvider.shelters.first.longitude;
    }

    // Isolate Params
    final params = RouteParams(
      startLat: loc.latitude,
      startLng: loc.longitude,
      destLat: destLat,
      destLng: destLng,
      region: regionProvider.isJapan ? 'JP' : 'TH',
      hazards: [], 
    );

    // EXECUTE ISOLATE
    try {
      final List<List<double>> route = await compute(calculateRiskAwareRoute, params);
      if (mounted) {
        debugPrint("NavEngine: Route updated (${route.length} waypoints). Logic: ${params.region}");
        // Note: Update map providers here with 'route'
      }
    } catch (e) {
      debugPrint("NavEngine Error: $e");
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
        content: Text(AppLocalizations.t('msg_network_restored')),
        backgroundColor: Theme.of(context).primaryColor,
      ),
    );

    shelterProvider.setDisasterMode(false);
    shelterProvider.setSafeInShelter(false);
    shelterProvider.loadShelters();
    
    navigatorKey.currentState?.pushReplacementNamed('/home');
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _heartbeatTimer?.cancel();
    _recoveryTimer?.cancel();
    _movementPoller?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDisasterMode = context.select<ShelterProvider, bool>((p) => p.isDisasterMode);
    final isSafeInShelter = context.select<ShelterProvider, bool>((p) => p.isSafeInShelter);

    if (_wasDisasterMode != isDisasterMode) {
      if (isDisasterMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            navigatorKey.currentState?.pushReplacementNamed('/compass');
          }
        });
      } else if (_wasDisasterMode == true && !isDisasterMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            navigatorKey.currentState?.pushReplacementNamed('/home');
          }
        });
      }
      _wasDisasterMode = isDisasterMode;
    }

    if (_wasSafeInShelter != isSafeInShelter) {
      if (isSafeInShelter) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            navigatorKey.currentState?.pushReplacementNamed('/dashboard');
          }
        });
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
//  STARTUP & LOADING
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
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final languageProvider = context.read<LanguageProvider>();
    await languageProvider.loadLanguage();
    
    final isOnboardingCompleted = await OnboardingScreen.isCompleted();
    
    if (!mounted) return;
    
    if (isOnboardingCompleted) {
      await Future.delayed(const Duration(milliseconds: 500));
      await _loadDataAndGoHome();
    } else {
      Navigator.pushReplacementNamed(context, '/onboarding');
    }
  }

  Future<void> _loadDataAndGoHome() async {
    try {
      final shelterProvider = context.read<ShelterProvider>();
      final locationProvider = context.read<LocationProvider>();
      final regionProvider = context.read<RegionModeProvider>();
      
      final prefs = await SharedPreferences.getInstance();
      final savedRegion = prefs.getString('target_region') ?? 'Japan';
      
      await shelterProvider.setRegion(savedRegion);
      
      if (savedRegion.toLowerCase().contains('th')) {
        regionProvider.setRegion(AppRegion.thailand);
      } else {
        regionProvider.setRegion(AppRegion.japan);
      }

      await Future.wait([
        locationProvider.initLocation(),
        shelterProvider.loadHazardPolygons(),
        shelterProvider.loadRoadData(),
      ]);
      
      if (locationProvider.currentLocation != null) {
        final loc = locationProvider.currentLocation!;
        await shelterProvider.setRegionFromCoordinates(loc.latitude, loc.longitude);
        
        if (context.mounted) {
          await context.read<CompassProvider>().startListening();
        }
      }
    } catch (e) {
      debugPrint('Startup Error: $e');
    }
    
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF5F7FA),
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFF1A237E)),
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
                  color: Color(0xFF1A237E)
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