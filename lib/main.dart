import 'dart:async';
import 'dart:ui';
import 'dart:math' as math;
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

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runZonedGuarded(() {
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('Flutter Error: ${details.exception}');
    };

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    runApp(const LoadingApp());
  }, (error, stack) {
    debugPrint('Async Error: $error');
    debugPrint('Stack: $stack');
  });
}

/// Root Widget setting up Providers and Theme
/// ABSOLUTE DIRECTIVE: Navy/Orange UI with Radius 30, Padding 24
class GapLessApp extends StatelessWidget {
  const GapLessApp({super.key});

  // ABSOLUTE DIRECTIVE: Navy/Orange Palette
  static const Color kNavyPrimary = Color(0xFF1A237E);
  static const Color kOrangeAccent = Color(0xFFFF6F00);
  
  // ABSOLUTE DIRECTIVE: UI Metrics
  static const double kBorderRadius = 30.0;
  static const double kButtonHeight = 56.0;
  static const EdgeInsets kContentPadding = EdgeInsets.all(24.0);

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
              
              theme: _buildTheme(languageProvider.currentLanguage, isDark: false),
              darkTheme: _buildTheme(languageProvider.currentLanguage, isDark: true),
              themeMode: ThemeMode.system,
              
              home: const AppStartup(),
              
              onGenerateRoute: _generateRoute,
              builder: (context, child) {
                // Wrap every page with DisasterWatcher for global background navigation logic
                return DisasterWatcher(child: child!);
              },
            ),
          );
        },
      ),
    );
  }

  Route<dynamic>? _generateRoute(RouteSettings settings) {
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

    if (isModal) return AppleModalRoute(page: page);
    return ApplePageRoute(page: page);
  }

  ThemeData _buildTheme(String lang, {bool isDark = false}) {
    final String primaryFont = lang == 'th' ? 'NotoSansThai' : 'NotoSansJP';
    final List<String> fallbackFonts = ['sans-serif', 'Arial'];

    final Color background = isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
    final Color surface = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final Color text = isDark ? Colors.white : const Color(0xFF263238);

    return ThemeData(
      useMaterial3: true,
      fontFamily: primaryFont,
      fontFamilyFallback: fallbackFonts,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: background,
      
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: kNavyPrimary,
        onPrimary: Colors.white,
        secondary: kOrangeAccent,
        onSecondary: Colors.white,
        error: const Color(0xFFD32F2F),
        onError: Colors.white,
        surface: surface,
        onSurface: text,
      ),

      appBarTheme: AppBarTheme(
        backgroundColor: kNavyPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: primaryFont,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: kNavyPrimary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, kButtonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kBorderRadius),
          ),
          textStyle: TextStyle(
            fontFamily: primaryFont,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
          elevation: 2,
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: kNavyPrimary,
          minimumSize: const Size(double.infinity, kButtonHeight),
          side: const BorderSide(color: kNavyPrimary, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kBorderRadius),
          ),
          textStyle: TextStyle(
            fontFamily: primaryFont,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: kOrangeAccent,
        foregroundColor: Colors.white,
        elevation: 4,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: kContentPadding,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kBorderRadius),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kBorderRadius),
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kBorderRadius),
          borderSide: const BorderSide(color: kNavyPrimary, width: 2),
        ),
      ),

      cardTheme: CardThemeData(
        color: surface,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kBorderRadius),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),
      
      snackBarTheme: SnackBarThemeData(
        backgroundColor: kNavyPrimary,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Global State Watcher & Background Navigation Orchestrator
/// Handles Requirement 3: Background Pathfinding with Waypoint Triggers
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
  StreamSubscription? _locationSubscription;
  Timer? _heartbeatTimer;
  Timer? _recoveryTimer;

  // For Distance Threshold Logic (Req 3: > 20 meters triggers recalc)
  dynamic _lastCalcLocation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initGlobalWatchers();
    });
  }

  void _initGlobalWatchers() {
    final locationProvider = context.read<LocationProvider>();
    locationProvider.initLocation();

    // 1. Connectivity Watcher
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.none)) {
        _triggerDisasterMode("Connectivity API");
      } else {
        _onNetworkRestored("Connectivity API");
      }
    });

    WebBridgeInterface.listenForOfflineEvent(() => _triggerDisasterMode("JS Event"));
    WebBridgeInterface.listenForOnlineEvent(() => _onNetworkRestored("JS Event"));

    // 2. Heartbeat (Offline Detection)
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

    // 3. BACKGROUND PATHFINDING TRIGGER (CRITICAL REQUIREMENT)
    // "ON MOVE: Listen to LocationStream. When user moves > 20 meters, trigger a SILENT background recalculation."
    _locationSubscription = locationProvider.locationStream.listen((currentLoc) {
      if (currentLoc == null) return;
      
      bool shouldRecalculate = false;
      if (_lastCalcLocation == null) {
        shouldRecalculate = true;
      } else {
        // Simple Haversine approximation
        final double dist = _calculateDistanceInMeters(
          _lastCalcLocation.latitude, _lastCalcLocation.longitude,
          currentLoc.latitude, currentLoc.longitude
        );
        if (dist > 20.0) {
          shouldRecalculate = true;
        }
      }

      if (shouldRecalculate) {
        _lastCalcLocation = currentLoc;
        // Run pathfinding in background isolate (via compute)
        context.read<ShelterProvider>().updateBackgroundRoutes(currentLoc);
      }
    });
  }

  double _calculateDistanceInMeters(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295;
    final a = 0.5 - math.cos((lat2 - lat1) * p) / 2 + 
              math.cos(lat1 * p) * math.cos(lat2 * p) * 
              (1 - math.cos((lon2 - lon1) * p)) / 2;
    return 12742 * math.asin(math.sqrt(a)) * 1000; // Meters
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
    
    // Rebuild graph upon reconnection
    shelterProvider.buildRoadGraph();
    
    navigatorKey.currentState?.pushReplacementNamed('/home');
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _locationSubscription?.cancel();
    _heartbeatTimer?.cancel();
    _recoveryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch for mode changes to redirect navigation
    final isDisasterMode = context.select<ShelterProvider, bool>((p) => p.isDisasterMode);
    final isSafeInShelter = context.select<ShelterProvider, bool>((p) => p.isSafeInShelter);

    if (_wasDisasterMode != isDisasterMode) {
      if (isDisasterMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          navigatorKey.currentState?.pushReplacementNamed('/compass');
        });
      } else if (_wasDisasterMode == true && !isDisasterMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          navigatorKey.currentState?.pushReplacementNamed('/home');
        });
      }
      _wasDisasterMode = isDisasterMode;
    }

    if (_wasSafeInShelter != isSafeInShelter) {
      if (isSafeInShelter) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          navigatorKey.currentState?.pushReplacementNamed('/dashboard');
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

/// Initialization Logic with Region-Specific Setup
/// Handles Requirements 1 & 2:
///   - Load Hazard Polygons (Japan/Thailand)
///   - Load Binary Road Data
///   - Build Road Graph
///   - Initialize region-specific logic (Japan: Road Width, Thailand: Electric Shock Hazards)
class AppStartup extends StatefulWidget {
  const AppStartup({super.key});

  @override
  State<AppStartup> createState() => _AppStartupState();
}

class _AppStartupState extends State<AppStartup> {
  @override
  void initState() {
    super.initState();
    _initializeSystem();
  }

  Future<void> _initializeSystem() async {
    // 1. Load Language & Basic Settings
    final languageProvider = context.read<LanguageProvider>();
    await languageProvider.loadLanguage();
    
    final isOnboardingCompleted = await OnboardingScreen.isCompleted();
    
    if (!mounted) return;
    
    if (isOnboardingCompleted) {
      // 2. Load Critical Navigation Assets
      await _loadNavigationAssets();
    } else {
      Navigator.pushReplacementNamed(context, '/onboarding');
    }
  }

  Future<void> _loadNavigationAssets() async {
    try {
      final shelterProvider = context.read<ShelterProvider>();
      final locationProvider = context.read<LocationProvider>();
      final regionProvider = context.read<RegionModeProvider>();
      
      // Determine Region Logic
      // LOGIC DIRECTIVE:
      //   - Japan = Road Width Priority
      //   - Thailand = Electric Shock (Hazards)
      final prefs = await SharedPreferences.getInstance();
      final savedRegion = prefs.getString('target_region') ?? 'Japan';
      
      await shelterProvider.setRegion(savedRegion);
      
      if (savedRegion.toLowerCase().contains('th')) {
        regionProvider.setRegion(AppRegion.thailand); // Implies Shock Risk logic
      } else {
        regionProvider.setRegion(AppRegion.japan); // Implies Width priority logic
      }

      // Parallel Data Loading (Req 1 & 2)
      // REQUIREMENT 1: Load Hazard Polygons (Blue Zones)
      // REQUIREMENT 2: Load Binary Road Data
      await Future.wait([
        locationProvider.initLocation(),
        shelterProvider.loadHazardPolygons(), // Loads hazard_japan.json / hazard_thailand.json
        shelterProvider.loadRoadData(),       // Loads roads_jp.bin / roads_th.bin
      ]);

      // Build Road Graph (Req 2)
      await shelterProvider.buildRoadGraph();
      
      // Initial Computation (Req 3: "ON STARTUP: Immediately calculate route")
      if (locationProvider.currentLocation != null) {
        final loc = locationProvider.currentLocation!;
        await shelterProvider.setRegionFromCoordinates(loc.latitude, loc.longitude);
        
        if (context.mounted) {
          // Initialize Compass
          await context.read<CompassProvider>().startListening();
          // Trigger first pathfinding (via compute isolate)
          await shelterProvider.updateBackgroundRoutes(loc);
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
        child: CircularProgressIndicator(
          color: GapLessApp.kNavyPrimary,
        ),
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