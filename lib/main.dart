
import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart'; // for compute
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart';

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
      debugPrint('GapLess UI Error: ${details.exception}');
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
    debugPrint('GapLess Critical Error: $error');
    debugPrint(stack.toString());
  });
}

/// The Root Widget: Setup Providers and Theme
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
              
              // THEME: Navy & Orange, Radius 30.0
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

                return isModal 
                    ? AppleModalRoute(page: page) 
                    : ApplePageRoute(page: page);
              },
              builder: (context, child) {
                // Wraps the app in Navigation & Connectivity logic
                return NavigationOrchestrator(
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
    final String primaryFont = lang == 'th' ? 'NotoSansThai' : 'NotoSansJP';
    final List<String> fallbackFonts = lang == 'th'
        ? ['NotoSansJP', 'sans-serif']
        : ['NotoSansThai', 'sans-serif'];

    const Color navyPrimary = Color(0xFF1A237E); // Absolute Directive
    const Color orangeAccent = Color(0xFFFF6F00); // Absolute Directive
    const Color dangerRed = Color(0xFFD32F2F);
    
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
        error: dangerRed,
        onError: Colors.white,
        surface: surface,
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
          minimumSize: const Size(double.infinity, 56.0), // Directive: Height 56
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30.0), // Directive: Radius 30
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
          minimumSize: const Size(double.infinity, 56.0), // Directive: Height 56
          side: const BorderSide(color: navyPrimary, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30.0), // Directive: Radius 30
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
        contentPadding: const EdgeInsets.all(24.0), // Directive: Padding 24+
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30.0), // Directive: Radius 30
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30.0),
          borderSide: BorderSide(color: Colors.grey.withOpacity(0.2)),
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
          borderRadius: BorderRadius.circular(30.0), // Directive: Radius 30
        ),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),
      
      snackBarTheme: SnackBarThemeData(
        backgroundColor: navyPrimary,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30.0)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// REQUIREMENT 3: NAVIGATION ORCHESTRATOR
/// Handles background pathfinding triggers based on movement
class NavigationOrchestrator extends StatefulWidget {
  final Widget child;
  const NavigationOrchestrator({super.key, required this.child});

  @override
  State<NavigationOrchestrator> createState() => _NavigationOrchestratorState();
}

class _NavigationOrchestratorState extends State<NavigationOrchestrator> {
  // Movement threshold for recalculation (meters)
  static const double _recalcThresholdMeters = 20.0;
  LatLng? _lastCalcPos;
  
  @override
  void initState() {
    super.initState();
    // In a real implementation, we'd subscribe to the LocationProvider's stream here
    // For this architecture demo, we assume the LocationProvider notifies listeners
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LocationProvider>().addListener(_onLocationUpdate);
    });
  }

  @override
  void dispose() {
    // Ideally remove listener, but LocationProvider lifecycle is app-wide
    super.dispose();
  }

  void _onLocationUpdate() {
    final locProvider = context.read<LocationProvider>();
    final currentLocation = locProvider.currentLocation;
    
    if (currentLocation == null) return;
    
    // Convert to LatLng for calculation
    final currentLatLng = LatLng(currentLocation.latitude, currentLocation.longitude);

    // Initial Calculation
    if (_lastCalcPos == null) {
      _triggerBackgroundRouting(currentLatLng);
      return;
    }

    // Distance Check (> 20m)
    final Distance distance = const Distance();
    final double dist = distance(currentLatLng, _lastCalcPos!);

    if (dist > _recalcThresholdMeters) {
      _triggerBackgroundRouting(currentLatLng);
    }
  }

  void _triggerBackgroundRouting(LatLng pos) {
    _lastCalcPos = pos;
    // Execute logic in background isolate via Provider
    // This ensures UI (60fps) is not blocked
    context.read<ShelterProvider>().updateBackgroundRoutes(
      // We pass a simple object to avoid passing context or complex objects to isolate
      // Note: Implementation details are in ShelterProvider
      pos, 
    );
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

/// Handles Connectivity & Disaster Mode State
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
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.none)) {
        _triggerDisasterMode("Connectivity API");
      } else {
        _onNetworkRestored("Connectivity API");
      }
    });

    WebBridgeInterface.listenForOfflineEvent(() => _triggerDisasterMode("JS Event"));
    WebBridgeInterface.listenForOnlineEvent(() => _onNetworkRestored("JS Event"));

    // Heartbeat for "False Positive" Online status
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
    // Watch critical states for navigation overrides
    final isDisasterMode = context.select<ShelterProvider, bool>((p) => p.isDisasterMode);
    final isSafeInShelter = context.select<ShelterProvider, bool>((p) => p.isSafeInShelter);

    // Navigation triggers based on state changes
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

  /// CRITICAL: Load Hazards and Build Graph based on Region Logic
  Future<void> _loadDataAndGoHome() async {
    try {
      final shelterProvider = context.read<ShelterProvider>();
      final locationProvider = context.read<LocationProvider>();
      final regionProvider = context.read<RegionModeProvider>();
      
      final prefs = await SharedPreferences.getInstance();
      final savedRegion = prefs.getString('target_region') ?? 'Japan';
      
      // REQUIREMENT 1 & 3 LOGIC: Region Setup
      // Japan: Road width priority. Thailand: Avoid Electric Shock Risk.
      if (savedRegion.toLowerCase().contains('th')) {
        regionProvider.setRegion(AppRegion.thailand);
        // Implicitly configures provider for Electric Shock avoidance
        // Load Thailand Assets
        await shelterProvider.setRegion('Thailand'); 
      } else {
        regionProvider.setRegion(AppRegion.japan);
        // Implicitly configures provider for Road Width priority
        // Load Japan Assets
        await shelterProvider.setRegion('Japan'); 
      }

      await Future.wait([
        locationProvider.initLocation(),
        // Loads assets/hazard_[region].json and assets/roads_[region].bin
        shelterProvider.loadHazardPolygons(), 
        shelterProvider.loadRoadData(),
      ]);
      
      // Requirement 2: Construct Graph
      await shelterProvider.buildRoadGraph();
      
      if (locationProvider.currentLocation != null) {
        final loc = locationProvider.currentLocation!;
        await shelterProvider.setRegionFromCoordinates(loc.latitude, loc.longitude);
        
        if (context.mounted) {
          await context.read<CompassProvider>().startListening();
          // Initial Route Calculation triggers here, subsequent ones in NavigationOrchestrator
          await shelterProvider.updateBackgroundRoutes(
             LatLng(loc.latitude, loc.longitude)
          );
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
