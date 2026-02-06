/* !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
   FIXME: CRITICAL UPDATE - ASYNC SAFE ROUTING ENGINE
   PRIORITY: P0 (HIGHEST) - BLOCKER

   IMPLEMENTATION OF HIGH-PERFORMANCE RISK-AWARE NAVIGATION SYSTEM
   
   [x] THEME: Navy/Orange, Radius 30.0, Padding 24.0+
   [x] NAV: Waypoint-based (List<LatLng>)
   [x] LOGIC: Japan (Width Priority) vs Thailand (Shock/Risk Priority)
   [x] PERF: A* runs in 'compute' Isolate
   [x] VISUALIZATION: Blue Hazard Polygons with Navy Border
   [x] DATA: Binary Road Graph + GeoJSON/Custom Hazard Files
   [x] TRIGGERS: Startup + Movement (>20m threshold)
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
// ISOLATE ROUTING ENGINE - A* PATHFINDING
// ---------------------------------------------------------------------------

class RoutingRequest {
  final Map<String, double> start;
  final Map<String, double> end;
  final String region;
  final List<List<Map<String, double>>> hazardPolygons;
  final List<Map<String, dynamic>> roadNodes;

  RoutingRequest({
    required this.start,
    required this.end,
    required this.region,
    required this.hazardPolygons,
    required this.roadNodes,
  });
}

/// Isolate worker function for A* pathfinding
Future<List<Map<String, double>>> routeWorker(RoutingRequest req) async {
  final isJapan = req.region == 'JP';
  
  // Priority Queue simulation for A*
  final openSet = <_AStarNode>[];
  final closedSet = <String>{};
  final cameFrom = <String, _AStarNode>{};
  
  final startNode = _AStarNode(
    position: req.start,
    gScore: 0.0,
    fScore: _calcDistance(req.start, req.end),
  );
  
  openSet.add(startNode);
  
  while (openSet.isNotEmpty) {
    openSet.sort((a, b) => a.fScore.compareTo(b.fScore));
    final current = openSet.removeAt(0);
    
    final currentKey = '${current.position['lat']},${current.position['lng']}';
    
    if (_calcDistance(current.position, req.end) < 10.0) {
      return _reconstructPath(cameFrom, current, req.start);
    }
    
    closedSet.add(currentKey);
    
    final neighbors = _getNeighbors(current.position, req.roadNodes, isJapan);
    
    for (final neighbor in neighbors) {
      final neighborKey = '${neighbor['lat']},${neighbor['lng']}';
      
      if (closedSet.contains(neighborKey)) continue;
      
      if (_intersectsAnyHazard(current.position, neighbor, req.hazardPolygons)) {
        continue;
      }
      
      final roadWidth = neighbor['width'] ?? 5.0;
      double moveCost = _calcDistance(current.position, neighbor);
      
      if (isJapan && roadWidth < 4.0) {
        moveCost *= 5.0;
      }
      
      if (!isJapan) {
        final riskLevel = neighbor['risk'] ?? 1.0;
        moveCost *= riskLevel;
      }
      
      final tentativeGScore = current.gScore + moveCost;
      
      final existingIdx = openSet.indexWhere((n) => 
        n.position['lat'] == neighbor['lat'] && 
        n.position['lng'] == neighbor['lng']
      );
      
      if (existingIdx == -1 || tentativeGScore < openSet[existingIdx].gScore) {
        final neighborNode = _AStarNode(
          position: neighbor,
          gScore: tentativeGScore,
          fScore: tentativeGScore + _calcDistance(neighbor, req.end),
        );
        
        cameFrom[neighborKey] = current;
        
        if (existingIdx != -1) {
          openSet[existingIdx] = neighborNode;
        } else {
          openSet.add(neighborNode);
        }
      }
    }
  }
  
  return [req.start, req.end];
}

class _AStarNode {
  final Map<String, double> position;
  final double gScore;
  final double fScore;
  
  _AStarNode({
    required this.position,
    required this.gScore,
    required this.fScore,
  });
}

List<Map<String, double>> _reconstructPath(
  Map<String, _AStarNode> cameFrom,
  _AStarNode current,
  Map<String, double> start,
) {
  final path = <Map<String, double>>[current.position];
  var node = current;
  
  while (true) {
    final key = '${node.position['lat']},${node.position['lng']}';
    if (!cameFrom.containsKey(key)) break;
    node = cameFrom[key]!;
    path.insert(0, node.position);
    if (_calcDistance(node.position, start) < 1.0) break;
  }
  
  return path;
}

List<Map<String, double>> _getNeighbors(
  Map<String, double> position,
  List<Map<String, dynamic>> roadNodes,
  bool isJapan,
) {
  final neighbors = <Map<String, double>>[];
  
  for (final node in roadNodes) {
    final dist = _calcDistance(position, {
      'lat': node['lat'] as double,
      'lng': node['lng'] as double,
    });
    
    if (dist > 0.1 && dist < 100.0) {
      neighbors.add({
        'lat': node['lat'] as double,
        'lng': node['lng'] as double,
        'width': node['width'] as double? ?? 5.0,
        'risk': node['risk'] as double? ?? 1.0,
      });
    }
  }
  
  return neighbors;
}

double _calcDistance(Map<String, double> p1, Map<String, double> p2) {
  const R = 6371000;
  final dLat = (p2['lat']! - p1['lat']!) * (math.pi / 180.0);
  final dLon = (p2['lng']! - p1['lng']!) * (math.pi / 180.0);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(p1['lat']! * (math.pi / 180.0)) *
          math.cos(p2['lat']! * (math.pi / 180.0)) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return R * c;
}

bool _intersectsAnyHazard(
  Map<String, double> start,
  Map<String, double> end,
  List<List<Map<String, double>>> hazardPolygons,
) {
  for (final poly in hazardPolygons) {
    if (_lineIntersectsPolygon(start, end, poly)) {
      return true;
    }
  }
  return false;
}

bool _lineIntersectsPolygon(
  Map<String, double> p1,
  Map<String, double> p2,
  List<Map<String, double>> polygon,
) {
  for (int i = 0; i < polygon.length; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % polygon.length];
    
    if (_segmentsIntersect(p1, p2, a, b)) {
      return true;
    }
  }
  
  if (_pointInPolygon(p1, polygon) || _pointInPolygon(p2, polygon)) {
    return true;
  }
  
  return false;
}

bool _segmentsIntersect(
  Map<String, double> p1,
  Map<String, double> p2,
  Map<String, double> p3,
  Map<String, double> p4,
) {
  final d1 = _direction(p3, p4, p1);
  final d2 = _direction(p3, p4, p2);
  final d3 = _direction(p1, p2, p3);
  final d4 = _direction(p1, p2, p4);
  
  if (((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
      ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))) {
    return true;
  }
  
  return false;
}

double _direction(
  Map<String, double> p1,
  Map<String, double> p2,
  Map<String, double> p3,
) {
  return (p3['lat']! - p1['lat']!) * (p2['lng']! - p1['lng']!) -
      (p2['lat']! - p1['lat']!) * (p3['lng']! - p1['lng']!);
}

bool _pointInPolygon(Map<String, double> point, List<Map<String, double>> polygon) {
  bool inside = false;
  for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final xi = polygon[i]['lng']!;
    final yi = polygon[i]['lat']!;
    final xj = polygon[j]['lng']!;
    final yj = polygon[j]['lat']!;
    
    final intersect = ((yi > point['lat']!) != (yj > point['lat']!)) &&
        (point['lng']! < (xj - xi) * (point['lat']! - yi) / (yj - yi) + xi);
    
    if (intersect) inside = !inside;
  }
  return inside;
}

// ---------------------------------------------------------------------------
// APP WIDGET
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
        ? ['NotoSansJP', 'sans-serif', 'Arial']
        : ['NotoSansThai', 'sans-serif', 'Arial'];

    const Color navyPrimary = Color(0xFF1A237E);
    const Color orangeAccent = Color(0xFFFF6F00);
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
          minimumSize: const Size(double.infinity, 56.0),
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(30.0),
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
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
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
        contentPadding: const EdgeInsets.all(24.0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30.0),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30.0),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(30.0),
          borderSide: const BorderSide(color: navyPrimary, width: 2),
        ),
      ),

      cardTheme: CardThemeData(
        color: surface,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30.0),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
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

// ---------------------------------------------------------------------------
// DISASTER WATCHER
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
  
  Map<String, double>? _lastCalcLocation;
  bool _isCalculating = false;

  @override
  void initState() {
    super.initState();
    
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final locProvider = context.read<LocationProvider>();
      locProvider.initLocation();
      locProvider.addListener(_onLocationChanged);
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

  void _onLocationChanged() {
    final locProvider = context.read<LocationProvider>();
    final currentLoc = locProvider.currentLocation;
    
    if (currentLoc == null || _isCalculating) return;

    final lat = currentLoc.latitude;
    final lng = currentLoc.longitude;

    if (_lastCalcLocation == null) {
      _triggerPathfinding(lat, lng);
    } else {
      final dist = _calcDistance(
        {'lat': _lastCalcLocation!['lat']!, 'lng': _lastCalcLocation!['lng']!}, 
        {'lat': lat, 'lng': lng}
      );
      
      if (dist > 20.0) {
        _triggerPathfinding(lat, lng);
      }
    }
  }

  Future<void> _triggerPathfinding(double lat, double lng) async {
    _isCalculating = true;
    _lastCalcLocation = {'lat': lat, 'lng': lng};

    final shelterProvider = context.read<ShelterProvider>();
    final regionProvider = context.read<RegionModeProvider>();
    
    final targetShelter = shelterProvider.nearestShelter; 
    
    if (targetShelter != null) {
      final req = RoutingRequest(
        start: {'lat': lat, 'lng': lng},
        end: {'lat': targetShelter.latitude, 'lng': targetShelter.longitude},
        region: regionProvider.currentRegion == AppRegion.japan ? 'JP' : 'TH',
        hazardPolygons: shelterProvider.hazardPolygons,
        roadNodes: shelterProvider.roadNodes,
      );

      try {
        final List<Map<String, double>> path = await compute(routeWorker, req);
        
        if (mounted) {
          shelterProvider.setCalculatedRoute(path);
          debugPrint("✓ Path calculated: ${path.length} waypoints");
        }
      } catch (e) {
        debugPrint("✗ Pathfinding error: $e");
      }
    }
    
    _isCalculating = false;
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
    context.read<LocationProvider>().removeListener(_onLocationChanged);
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

// ---------------------------------------------------------------------------
// APP STARTUP
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
        shelterProvider.buildRoadGraph(),
      ]);
      
      if (locationProvider.currentLocation != null) {
        final loc = locationProvider.currentLocation!;
        await shelterProvider.setRegionFromCoordinates(loc.latitude, loc.longitude);
        
        if (context.mounted) {
          await context.read<CompassProvider>().startListening();
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

// ---------------------------------------------------------------------------
// LOADING APP
// ---------------------------------------------------------------------------

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
            mainAxisAlignment: