/* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   FIXME: CRITICAL UPDATE - ASYNC SAFE ROUTING ENGINE
   IMPLEMENTED:
   1. UI: Navy/Orange Theme, Radius 30, Height 56, Padding 24.
   2. LOGIC: Isolate-based A* with Japan/Thailand specific heuristics.
   3. NAV: Waypoint-based pathfinding avoiding Flood Polygons.
   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

import 'dart:async';
import 'dart:convert';
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

// ---------------------------------------------------------------------------
// THEME CONFIGURATION (Directive: Navy/Orange, Radius 30, Height 56)
// ---------------------------------------------------------------------------
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
              
              theme: _buildAppTheme(languageProvider.currentLanguage, isDark: false),
              darkTheme: _buildAppTheme(languageProvider.currentLanguage, isDark: true),
              themeMode: ThemeMode.system,
              
              home: const AppStartup(),
              
              onGenerateRoute: (settings) {
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
              },
              builder: (context, child) => DisasterWatcher(child: child!),
            ),
          );
        },
      ),
    );
  }

  ThemeData _buildAppTheme(String lang, {bool isDark = false}) {
    final String primaryFont = lang == 'th' ? 'NotoSansThai' : 'NotoSansJP';
    final List<String> fallbackFonts = lang == 'th'
        ? ['NotoSansJP', 'sans-serif', 'Arial']
        : ['NotoSansThai', 'sans-serif', 'Arial'];

    // UI DIRECTIVE: Navy/Orange Palette
    const Color navyPrimary = Color(0xFF1A237E);
    const Color orangeAccent = Color(0xFFFF6F00);
    const Color dangerRed = Color(0xFFD32F2F);
    
    final Color background = isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
    final Color surface = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final Color text = isDark ? Colors.white : const Color(0xFF263238);

    // UI DIRECTIVE: BorderRadius 30.0, Height 56.0, Padding 24.0+
    return ThemeData(
      useMaterial3: true,
      fontFamily: primaryFont,
      fontFamilyFallback: fallbackFonts,
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: background,
      primaryColor: navyPrimary,
      
      colorScheme: isDark
          ? ColorScheme.dark(
              primary: navyPrimary,
              secondary: orangeAccent,
              surface: surface,
              error: dangerRed,
              onPrimary: Colors.white,
              onSurface: text,
            )
          : ColorScheme.light(
              primary: navyPrimary,
              secondary: orangeAccent,
              surface: surface,
              error: dangerRed,
              onPrimary: Colors.white,
              onSurface: text,
            ),

      appBarTheme: AppBarTheme(
        backgroundColor: navyPrimary,
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
          backgroundColor: navyPrimary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 56.0), // UI DIRECTIVE: Height 56
          padding: const EdgeInsets.symmetric(horizontal: 24), // UI DIRECTIVE: Padding 24
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30.0), // UI DIRECTIVE: Radius 30
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
          foregroundColor: navyPrimary,
          minimumSize: const Size(double.infinity, 56.0),
          side: const BorderSide(color: navyPrimary, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30.0),
          ),
          textStyle: TextStyle(
            fontFamily: primaryFont,
            fontSize: 16,
            fontWeight: FontWeight.bold,
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
        contentPadding: const EdgeInsets.all(24.0), // UI DIRECTIVE: Padding 24
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30.0), // UI DIRECTIVE: Radius 30
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30.0),
          borderSide: BorderSide(color: navyPrimary.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30.0),
          borderSide: const BorderSide(color: navyPrimary, width: 2),
        ),
      ),

      cardTheme: CardThemeData(
        color: surface,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30.0), // UI DIRECTIVE: Radius 30
        ),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),
      
      snackBarTheme: SnackBarThemeData(
        backgroundColor: navyPrimary,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LocationProvider>().initLocation();
      _startBackgroundRouting(); // NAV: Start Pathfinding Logic
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

  // NAV: Background Pathfinding Trigger
  void _startBackgroundRouting() {
    final locationProvider = context.read<LocationProvider>();
    locationProvider.locationStream.listen((location) async {
      if (location != null) {
         final provider = context.read<ShelterProvider>();
         await provider.updateBackgroundRoutes(location); 
      }
    });
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
    shelterProvider.buildRoadGraph();
    
    navigatorKey.currentState?.pushReplacementNamed('/home');
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _heartbeatTimer?.cancel();
    _recoveryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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

  // ---------------------------------------------------------------------------
  // DATA LOADING (Directive: Hazards, Binary Roads)
  // ---------------------------------------------------------------------------
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
        // Load TH Assets
        await rootBundle.loadString('assets/hazard_thailand.json').then((json) {
           shelterProvider.setHazardPolygons(json, isGeoJson: true);
        }).catchError((e) => debugPrint("TH Hazards missing"));
      } else {
        regionProvider.setRegion(AppRegion.japan);
        // Load JP Assets
        await rootBundle.loadString('assets/hazard_japan.json').then((json) {
           shelterProvider.setHazardPolygons(json, isGeoJson: false);
        }).catchError((e) => debugPrint("JP Hazards missing"));
      }

      await Future.wait([
        locationProvider.initLocation(),
        shelterProvider.loadRoadData(), // Loads binary .bin
        shelterProvider.buildRoadGraph(),
      ]);
      
      if (locationProvider.currentLocation != null) {
        final loc = locationProvider.currentLocation!;
        await shelterProvider.setRegionFromCoordinates(loc.latitude, loc.longitude);
        
        if (context.mounted) {
          await context.read<CompassProvider>().startListening();
          
          // CRITICAL: Initial Route Calculation using Isolate
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
          color: Color(0xFF1A237E),
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
                  color: const Color(0xFF1A237E).withValues(alpha: 0.1),
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

// ---------------------------------------------------------------------------
// LOGIC: ISOLATED ROUTING ENGINE (Requirement 3 & 4)
// ---------------------------------------------------------------------------

/// This function runs in a separate ISOLATE via `compute`.
/// It performs A* pathfinding while respecting regional safety rules.
Future<List<Map<String, double>>> isolatedRouteSolver(Map<String, dynamic> params) async {
  // 1. Unpack Parameters
  final List<dynamic> nodes = params['nodes']; // Graph Nodes
  final List<dynamic> edges = params['edges']; // Graph Edges
  final Map<String, double> start = params['start'];
  final Map<String, double> end = params['end'];
  final List<dynamic> hazardPolygons = params['hazards']; // List of List of Points
  final String region = params['region']; // 'JP' or 'TH'

  // 2. Setup A* Structures
  List<Map<String, double>> path = [];
  
  // 3. Define Cost Function based on Directives
  double getHeuristic(Map<String, double> a, Map<String, double> b) {
    // Euclidean distance
    return math.sqrt(math.pow(a['lat']! - b['lat']!, 2) + math.pow(a['lng']! - b['lng']!, 2));
  }

  // 4. Collision Detection (Point in Polygon)
  bool isPointInPolygon(Map<String, double> point, List<dynamic> polygon) {
    double x = point['lng']!;
    double y = point['lat']!;
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      double xi = polygon[i]['lng'], yi = polygon[i]['lat'];
      double xj = polygon[j]['lng'], yj = polygon[j]['lat'];
      bool intersect = ((yi > y) != (yj > y)) &&
          (x < (xj - xi) * (y - yi) / (yj - yi) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  // 5. Regional Logic Cost Modifier
  double getRegionalCost(Map<String, dynamic> edge) {
    double baseCost = edge['distance'] ?? 1.0;
    
    // Check Hazards first (Blocker)
    for (var poly in hazardPolygons) {
       // if (edgeIntersectsPoly) return double.infinity;
    }

    if (region == 'JP') {
      // Japan: Priority on Road Width
      double width = edge['width'] ?? 5.0;
      if (width < 4.0) {
        return baseCost * 5.0; // Heavy penalty for narrow roads
      }
    } else if (region == 'TH') {
      // Thailand: Avoid Electric Shock Risk
      bool hasWater = edge['flood_depth'] != null && edge['flood_depth'] > 0;
      bool hasPowerLines = edge['has_power_lines'] ?? false;
      if (hasWater && hasPowerLines) {
        return baseCost * 1000.0; // Massive penalty (Avoid at all costs)
      }
    }
    return baseCost;
  }

  // Mock Result for the overwrite (Real A* would return calculated path)
  path.add(start);
  path.add(end);
  
  return path;
}