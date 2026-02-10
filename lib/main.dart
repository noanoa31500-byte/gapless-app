/* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   ARCHITECTURAL OVERWRITE: LIB/MAIN.DART
   Directives Implemented:
   1. UI: Navy (0xFF1A237E) / Orange (0xFFFF6F00), Radius 30.0, Height 56.0, Padding 24.0+.
   2. NAV: Delegates Waypoint generation to real RoutingEngine (via ShelterProvider).
   3. LOGIC: Sets up RegionModeProvider to drive Japan/Thailand safety logic.
   !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! */

import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
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
//  MAIN APPLICATION
// ---------------------------------------------------------------------------

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    
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
              
              // UI DIRECTIVE: Navy/Orange, Radius 30, Height 56, Padding 24
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
    
    // UI DIRECTIVE CONSTANTS
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
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
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
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
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
      }
    });

    WebBridgeInterface.listenForOfflineEvent(() => _triggerDisasterMode("JS Event"));
  }

  void _startRiskMonitoring() {
    // Start background routing updates based on movement
    // This delegates to ShelterProvider which uses the REAL RoutingEngine (Directive 2 & 3)
    final locProvider = context.read<LocationProvider>();
    
    _movementPoller = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      final currentLoc = locProvider.currentLocation;
      if (currentLoc != null) {
        // Only update if moved significantly
        if (_lastLocation == null || _calculateDistance(_lastLocation, currentLoc) > 10.0) {
          _lastLocation = currentLoc;
          // Trigger the REAL routing engine logic in background
          context.read<ShelterProvider>().updateBackgroundRoutes(currentLoc);
        }
      }
    });
  }

  double _calculateDistance(dynamic loc1, dynamic loc2) {
    // Simple Euclidean approx is fast enough for change detection
    return (loc1.latitude - loc2.latitude).abs() + (loc1.longitude - loc2.longitude).abs() * 111000;
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

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _movementPoller?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDisasterMode = context.select<ShelterProvider, bool>((p) => p.isDisasterMode);
    final isSafeInShelter = context.select<ShelterProvider, bool>((p) => p.isSafeInShelter);

    // Auto-navigation based on mode changes
    if (_wasDisasterMode != isDisasterMode) {
      if (isDisasterMode) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          navigatorKey.currentState?.pushReplacementNamed('/compass');
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

  Future<void> _loadDataAndGoHome() async {
    try {
      final shelterProvider = context.read<ShelterProvider>();
      final locationProvider = context.read<LocationProvider>();
      final regionProvider = context.read<RegionModeProvider>();
      
      final prefs = await SharedPreferences.getInstance();
      final savedRegion = prefs.getString('target_region') ?? 'Japan';
      
      // Initialize Logic Mode (Directive 3)
      if (savedRegion.toLowerCase().contains('th')) {
        await regionProvider.setRegion(AppRegion.thailand);
        await shelterProvider.setRegion('th_satun');
      } else {
        await regionProvider.setRegion(AppRegion.japan);
        await shelterProvider.setRegion('jp_osaki');
      }

      await Future.wait([
        locationProvider.initLocation(),
        shelterProvider.loadHazardPolygons(),
        shelterProvider.loadRoadData(), // Loads binary graph for NAV
        shelterProvider.loadShelters(),
      ]);
      
      // Initialize Graph for RoutingEngine
      await shelterProvider.buildRoadGraph();
      
      if (context.mounted) {
        await context.read<CompassProvider>().startListening();
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