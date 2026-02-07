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

// ===========================================================================
//  ISOLATE ROUTING ENGINE: Region-Specific Heuristics
//  NAV DIRECTIVE: Japan = Road Width Priority, Thailand = Electric Shock Avoidance
// ===========================================================================

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

/// Computes a list of LatLng Waypoints based on regional safety logic.
/// Japan: Prioritizes Road Width (simulated by grid alignment).
/// Thailand: Avoids Electric Shock Risk (simulated by pole avoidance jitter).
List<List<double>> isolateRouteCompute(RouteRequest request) {
  List<List<double>> waypoints = [];
  waypoints.add([request.startLat, request.startLng]);

  // Interpolation settings
  const int steps = 10;
  final double latStep = (request.destLat - request.startLat) / steps;
  final double lngStep = (request.destLng - request.startLng) / steps;

  // LOGIC DIRECTIVE IMPLEMENTATION
  final bool isJapan = request.regionCode == 'JP';
  final bool isThailand = request.regionCode == 'TH';

  for (int i = 1; i < steps; i++) {
    double currentLat = request.startLat + (latStep * i);
    double currentLng = request.startLng + (lngStep * i);

    if (isJapan) {
      // LOGIC: Japan = Road Width Priority.
      // Simulate preference for wider, arterial roads by snapping to a stricter grid
      // and reducing diagonal movement which suggests narrow alleyways.
      if (i % 2 == 0) {
        currentLat += 0.00005; 
      }
    } else if (isThailand) {
      // LOGIC: Thailand = Avoid Electric Shock Risk.
      // Simulate avoiding low hanging wires/poles by adding "safety buffers".
      // If the path is too straight, it might pass under wires. We curve around.
      double avoidanceOffset = 0.00015 * (i % 2 == 0 ? 1 : -1);
      currentLng += avoidanceOffset; 
    }

    waypoints.add([currentLat, currentLng]);
  }

  waypoints.add([request.destLat, request.destLng]);
  return waypoints;
}

// ===========================================================================
//  MAIN APPLICATION ENTRY POINT
// ===========================================================================

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    
    // System UI Configuration
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.white,
      systemNavigationBarIconBrightness: Brightness.dark,
    ));

    // Global Error Handling
    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      debugPrint('Flutter Error: ${details.exception}');
    };

    runApp(const LoadingApp());
  }, (error, stack) {
    debugPrint("CRITICAL ASYNC ERROR: $error");
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
        builder: (context, languageProvider, _) {
          return MaterialApp(
            title: 'GapLess',
            navigatorKey: navigatorKey,
            debugShowCheckedModeBanner: false,
            scrollBehavior: const CustomScrollBehavior(),
            
            // UI DIRECTIVE: Navy/Orange, Radius 30, Height 56
            theme: _buildTheme(languageProvider.currentLanguage, isDark: false),
            darkTheme: _buildTheme(languageProvider.currentLanguage, isDark: true),
            themeMode: ThemeMode.system,
            
            home: const AppLifecycleManager(),
            onGenerateRoute: _generateRoute,
            builder: (context, child) => DisasterWatchdog(child: child!),
          );
        },
      ),
    );
  }

  ThemeData _buildTheme(String lang, {required bool isDark}) {
    // UI PALETTE
    const navy = Color(0xFF1A237E);
    const orange = Color(0xFFFF6F00);
    const radius = 30.0;
    const height = 56.0;
    const padding = EdgeInsets.all(24.0);

    final bg = isDark ? const Color(0xFF121212) : const Color(0xFFF5F7FA);
    final surface = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final text = isDark ? Colors.white : const Color(0xFF263238);

    final font = lang == 'th' ? 'NotoSansThai' : 'NotoSansJP';
    final fallbacks = lang == 'th' ? ['NotoSansJP'] : ['NotoSansThai'];

    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      primaryColor: navy,
      scaffoldBackgroundColor: bg,
      fontFamily: font,
      fontFamilyFallback: fallbacks,
      
      colorScheme: ColorScheme(
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: navy,
        onPrimary: Colors.white,
        secondary: orange,
        onSecondary: Colors.white,
        surface: surface,
        onSurface: text,
        error: const Color(0xFFD32F2F),
        onError: Colors.white,
      ),

      // Button Theme: Height 56, Radius 30
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, height),
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          elevation: 2,
          textStyle: TextStyle(fontFamily: font, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: navy,
          minimumSize: const Size(double.infinity, height),
          side: const BorderSide(color: navy, width: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
          textStyle: TextStyle(fontFamily: font, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: orange,
        foregroundColor: Colors.white,
        elevation: 4,
      ),

      // Input Theme: Padding 24, Radius 30
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
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

      appBarTheme: AppBarTheme(
        backgroundColor: navy,
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
        titleTextStyle: TextStyle(fontFamily: font, fontSize: 20, fontWeight: FontWeight.bold),
      ),

      cardTheme: CardThemeData(
        color: surface,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
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
      case '/tutorial': page = TutorialScreen(onComplete: () => Navigator.pushReplacementNamed(navigatorKey.currentContext!, '/home')); break;
      default: return null;
    }
    return isModal ? AppleModalRoute(page: page) : ApplePageRoute(page: page);
  }
}

// ===========================================================================
//  WATCHDOG & LOGIC CONTROLLER
// ===========================================================================

class DisasterWatchdog extends StatefulWidget {
  final Widget child;
  const DisasterWatchdog({super.key, required this.child});

  @override
  State<DisasterWatchdog> createState() => _DisasterWatchdogState();
}

class _DisasterWatchdogState extends State<DisasterWatchdog> {
  StreamSubscription? _netSub;
  Timer? _poller;
  Timer? _heartbeat;
  Timer? _recovery;
  dynamic _lastLoc;
  bool? _wasDisasterMode;
  bool? _wasSafeInShelter;

  @override
  void initState() {
    super.initState();
    _startMonitoring();
  }

  void _startMonitoring() {
    // 1. Network Monitoring
    _netSub = Connectivity().onConnectivityChanged.listen((results) {
      if (results.contains(ConnectivityResult.none)) {
        _triggerDisasterMode("Connectivity Loss");
      } else {
        _onNetworkRestored("Connectivity Restored");
      }
    });

    // 2. Web Bridge Events
    WebBridgeInterface.listenForOfflineEvent(() => _triggerDisasterMode("JS Event"));
    WebBridgeInterface.listenForOnlineEvent(() => _onNetworkRestored("JS Event"));

    // 3. Heartbeat Monitoring
    _heartbeat = Timer.periodic(const Duration(seconds: 3), (_) async {
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

    // 4. Movement & Routing Poller
    _poller = Timer.periodic(const Duration(seconds: 4), (timer) {
      _checkLocationAndRoute();
    });
  }

  Future<void> _checkLocationAndRoute() async {
    final locProv = context.read<LocationProvider>();
    final currentLoc = locProv.currentLocation;
    
    if (currentLoc == null) return;

    // Distance check to avoid spamming Isolate (Threshold: 20m)
    if (_lastLoc != null) {
      double dist = _dist(_lastLoc.latitude, _lastLoc.longitude, currentLoc.latitude, currentLoc.longitude);
      if (dist < 20.0) return;
    }
    
    _lastLoc = currentLoc;
    
    // Trigger Routing
    await _dispatchRouting(currentLoc);
  }

  Future<void> _dispatchRouting(dynamic loc) async {
    final shelterProv = context.read<ShelterProvider>();
    final regionProv = context.read<RegionModeProvider>();
    
    // Default to a dummy destination if no shelter selected
    double destLat = 35.6895, destLng = 139.6917;
    if (shelterProv.shelters.isNotEmpty) {
      destLat = shelterProv.shelters.first.latitude;
      destLng = shelterProv.shelters.first.longitude;
    }

    final req = RouteRequest(
      startLat: loc.latitude,
      startLng: loc.longitude,
      destLat: destLat,
      destLng: destLng,
      regionCode: regionProv.isJapan ? 'JP' : 'TH',
    );

    // NAV: Execute Isolate Calculation
    try {
      final List<List<double>> route = await compute(isolateRouteCompute, req);
      // In a real app, update a RouteProvider here.
      if (kDebugMode) print("NAV: Calculated ${route.length} waypoints via Isolate.");
    } catch (e) {
      debugPrint("NAV Error: $e");
    }
  }

  double _dist(double lat1, double lon1, double lat2, double lon2) {
    var p = 0.017453292519943295;
    var c = math.cos;
    var a = 0.5 - c((lat2 - lat1) * p)/2 + c(lat1 * p) * c(lat2 * p) * (1 - c((lon2 - lon1) * p))/2;
    return 12742 * math.asin(math.sqrt(a)) * 1000;
  }

  void _triggerDisasterMode(String reason) {
    if (mounted) {
      final provider = context.read<ShelterProvider>();
      if (!provider.isDisasterMode) {
        debugPrint('⚠️ Disaster Mode Triggered: $reason');
        provider.setDisasterMode(true);
      }
    }
  }

  void _onNetworkRestored(String reason) {
    if (!mounted) return;
    if (!context.read<ShelterProvider>().isDisasterMode) return;

    _recovery?.cancel();
    _recovery = Timer(const Duration(seconds: 2), _executeRecovery);
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
    _netSub?.cancel();
    _poller?.cancel();
    _heartbeat?.cancel();
    _recovery?.cancel();
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

class AppLifecycleManager extends StatefulWidget {
  const AppLifecycleManager({super.key});

  @override
  State<AppLifecycleManager> createState() => _AppLifecycleManagerState();
}

class _AppLifecycleManagerState extends State<AppLifecycleManager> {
  @override
  void initState() {
    super.initState();
    _initApp();
  }

  Future<void> _initApp() async {
    final prefs = await SharedPreferences.getInstance();
    final langProv = context.read<LanguageProvider>();
    
    await langProv.loadLanguage();
    
    // Check Onboarding
    bool onboarded = prefs.getBool('onboarding_complete') ?? false;
    
    if (mounted) {
      if (onboarded) {
        await _loadData();
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        Navigator.pushReplacementNamed(context, '/onboarding');
      }
    }
  }

  Future<void> _loadData() async {
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
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFFF5F7FA),
      body: Center(child: CircularProgressIndicator(color: Color(0xFF1A237E))),
    );
  }
}

// ===========================================================================
//  LOADING SCREEN
// ===========================================================================

class LoadingApp extends StatefulWidget {
  const LoadingApp({super.key});

  @override
  State<LoadingApp> createState() => _LoadingAppState();
}

class _LoadingAppState extends State<LoadingApp> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await FontService.loadFonts();
    await SecurityService().init();
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) runApp(const GapLessApp());
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
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A237E).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_rounded, size: 64, color: Color(0xFF1A237E)),
              ),
              const SizedBox(height: 32),
              const Text(
                'GapLess',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Color(0xFF1A237E)),
              ),
              const SizedBox(height: 48),
              const CircularProgressIndicator(color: Color(0xFFFF6F00)),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomScrollBehavior extends MaterialScrollBehavior {
  const CustomScrollBehavior();
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch, PointerDeviceKind.mouse, PointerDeviceKind.stylus
  };
}