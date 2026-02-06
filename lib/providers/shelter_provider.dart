import 'dart:convert';
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:csv/csv.dart';
import '../models/shelter.dart';
import '../services/security_service.dart';
import '../services/binary_road_loader.dart';
import '../services/binary_graph_loader.dart';
import '../services/routing_engine.dart';
import '../services/safest_route_engine.dart';
import 'region_mode_provider.dart'; // Used for AppRegion enum
import '../services/risk_visualization_service.dart';
import '../models/road_graph.dart';
import '../services/navigation/gapless_navigation_engine.dart'; // New Navigation Engine

/// 避難所データを管理するProvider
class ShelterProvider with ChangeNotifier {
  // State
  // 初期値は jp_osaki (大崎市) -> AppRegion.japan
  final _securityService = SecurityService();
  String _currentRegion = 'jp_osaki'; // Legacy String Identifier
  AppRegion _currentAppRegion = AppRegion.japan; // New Enum Identifier

  List<Shelter> _shelters = [];
  List<List<LatLng>> _hazardPolygons = [];
  List<Map<String, dynamic>> _hazardPoints = [];
  List<List<LatLng>> _roadPolylines = [];
  RoadGraph? _roadGraph;
  RoutingEngine? _routingEngine;
  List<String>? _safestRoute;
  List<FloodCircleData> _floodRiskCircles = [];
  List<PowerRiskCircleData> _powerRiskCircles = [];
  
  // タイ専用データ
  List<Map<String, dynamic>> _floodRiskPoints = []; // satun_flood_prediction.json
  List<List<LatLng>> _powerLinePolylines = []; // power_risk_th.geojson
  
  // 大崎市公式避難所データ (CSV)
  List<OsakiShelter> _osakiShelters = [];
  
  // 食料補給ポイント (store.json)
  List<FoodSupplyPoint> _foodSupplyPoints = [];
  
  // サトゥーン避難所データ (GeoJSON) - タイ
  List<RegionalShelter> _satunShelters = [];
  
  bool _isLoading = false;
  bool _isRoutingLoading = false;
  bool _isEmergencyMode = true;

  // Navigation State
  Shelter? _navTarget;
  bool _isNavigating = false;

  // Disaster Mode & Language
  bool _isDisasterMode = false;

  String _currentLanguage = 'ja';
  
  // Background Route Cache
  Map<String, CachedRouteData> _cachedRoutes = {}; // Key: type (shelter, hospital)
  final Map<String, CachedRouteData> _targetSpecificCache = {}; // Key: Shelter ID
  
  // Internal State
  bool _isCaching = false;
  
  // Safe State
  bool _isSafeInShelter = false;

  // 民間施設などを除外するためのブラックリスト
  static const List<String> _blackListKeywords = [
    'そろばん', '珠算', '塾', 
    '英会話', '公文', 'スイミング', 'ピアノ', 'バレエ', 'ダンス',
    '自動車', 'driving', 'kumon', 'ballet', 'dance', 'piano', 'swimming'
  ];

  // Getters
  String get currentRegion => _currentRegion;
  AppRegion get currentAppRegion => _currentAppRegion; // New Getter
  List<Shelter> get shelters => _shelters;
  List<List<LatLng>> get hazardPolygons => _hazardPolygons;
  List<Map<String, dynamic>> get hazardPoints => _hazardPoints;
  List<List<LatLng>> get roadPolylines => _roadPolylines; // Updated Type
  
  // タイ専用データのゲッター
  List<Map<String, dynamic>> get floodRiskPoints => _floodRiskPoints;
  List<List<LatLng>> get powerLinePolylines => _powerLinePolylines;
  RoadGraph? get roadGraph => _roadGraph;
  List<String>? get safestRoute => _safestRoute;
  List<FloodCircleData> get floodRiskCircles => _floodRiskCircles;
  List<PowerRiskCircleData> get powerRiskCircles => _powerRiskCircles;
  List<OsakiShelter> get osakiShelters => _osakiShelters;
  List<FoodSupplyPoint> get foodSupplyPoints => _foodSupplyPoints;
  List<RegionalShelter> get satunShelters => _satunShelters;
  bool get isLoading => _isLoading;
  bool get isRoutingLoading => _isRoutingLoading;
  bool get isEmergencyMode => _isEmergencyMode;
  Shelter? get navTarget => _navTarget;
  bool get isNavigating => _isNavigating;
  bool get isDisasterMode => _isDisasterMode;
  String get currentLanguage => _currentLanguage;
  bool get isSafeInShelter => _isSafeInShelter;

  /// 表示用Shelterリスト (モードに応じてフィルタリング)
  List<Shelter> get displayedShelters {
    if (!_isEmergencyMode && !_isDisasterMode) {
      // 全表示モード（平時）
      return _shelters;
    }
    // 緊急モード: 公認避難所のみ (コンビニ等は除外)
    final officialTypes = ['shelter', 'hospital', 'school', 'temple', 'gov', 'community_centre'];
    return _shelters.where((s) => officialTypes.contains(s.type)).toList();
  }

  /// 座標から地域を自動設定 (GPS連動)
  Future<void> setRegionFromCoordinates(double lat, double lng) async {
    // 簡易的な判定: 緯度が20度未満ならタイ、それ以上なら日本
    // Satun, Thailand is approx 6.6 N
    // Osaki, Japan is approx 38.5 N
    String newRegion = 'jp_osaki'; // Default
    
    if (lat < 20.0) {
      newRegion = 'th_satun';
    } else {
      newRegion = 'jp_osaki';
    }
    
    // 変更があれば適用
    if (_currentRegion != newRegion) {
      print('🌏 GPS Detected Region Change: $_currentRegion -> $newRegion (Lat: $lat)');
      await setRegion(newRegion);
    }
  }

  LatLng? _lastRouteUpdateLoc;
  /// 避難所データを読み込む
  Future<void> loadShelters() async {
    final bool isFirstLoad = _shelters.isEmpty;
    
    if (isFirstLoad) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      List<Shelter> newShelters = [];

      if (kDebugMode) {
        print('🔍 ShelterProvider: Loading shelters for region: $_currentAppRegion (${_currentAppRegion == AppRegion.japan ? "Japan" : "Thailand"})');
      }
      
      List<String> filesToLoad = [];
      String assetPrefix = 'assets/data/';
      
      if (_currentAppRegion == AppRegion.japan) {
        filesToLoad = [
          '${assetPrefix}shelter.json',
          '${assetPrefix}hospital.json',
          '${assetPrefix}store.json',
          '${assetPrefix}water.geojson',
        ];
      } else {
        filesToLoad = [
          '${assetPrefix}shelter_th.geojson',
          '${assetPrefix}hospital_th.geojson',
          '${assetPrefix}store_th.geojson',
        ];
      }
      
      if (filesToLoad.isNotEmpty) {
        for (final path in filesToLoad) {
          try {
             final loaded = await _loadGeoJson(path, _currentRegion);
             print('📥 Loaded $path: ${loaded.length} items');
             newShelters.addAll(loaded);
          } catch (e) {
             print('❌ Failed to load $path: $e');
          }
        }
      }
      
      newShelters = newShelters.where((shelter) {
        final region = shelter.region ?? '';
        if (_currentRegion.startsWith('th')) return region.startsWith('th_');
        if (_currentRegion.startsWith('jp')) return region.startsWith('jp_');
        return region == _currentRegion || region.isEmpty;
      }).toList();

      _shelters = newShelters.where((shelter) {
        final name = shelter.name;
        if (name.isEmpty || 
            name == 'Unknown' || 
            name == 'Unknown Spot' || 
            name == 'Unnamed' ||
            name.toLowerCase() == 'unknown' ||
            name == '不明') return false;
        
        for (final keyword in _blackListKeywords) {
          if (name.contains(keyword)) return false;
        }
        return true;
      }).toList();

      print('✅ Loaded ${_shelters.length} shelters/locations (filtered)');
    } catch (e) {
      debugPrint('Error loading shelters: $e');
      _shelters = [];
    } finally {
      if (isFirstLoad) {
        _isLoading = false;
      }
      
      if (_currentAppRegion == AppRegion.japan) {
        await loadOsakiData();
      }
      
      if (_currentAppRegion == AppRegion.thailand) {
        await _loadFloodRiskData();
        await _loadPowerLineData();
        await loadThailandData();
      }
      
      notifyListeners();
    }
  }

  Future<void> _executeBackgroundUpdate(LatLng currentLoc) async {
    if (_roadGraph == null || _routingEngine == null) return;
    if (_isCaching) return;
    if (_isRoutingLoading) return;

    _isCaching = true;
    try {
      if (kDebugMode) print('🔄 ShelterProvider: バックグラウンド候補検索中... (${currentLoc.latitude.toStringAsFixed(4)}, ${currentLoc.longitude.toStringAsFixed(4)})');

      // ターゲットの種類ごとに計算
      final targets = ['shelter', 'hospital', 'water', 'convenience'];
      
      for (var type in targets) {
        // 直線距離で上位3件を取得（計算負荷軽減）
        final candidates = _getTopNCandidates(type, currentLoc, 3);
        
        CachedRouteData? bestRoadRoute;
        double minRoadDist = double.infinity;

        for (var target in candidates) {
          final startNode = _findNearestNode(currentLoc);
          final goalNode = _findNearestNode(LatLng(target.lat, target.lng));
          
          if (startNode != null && goalNode != null) {
            final route = _routingEngine!.findSafestPath(startNode, goalNode);
            if (route.isNotEmpty) {
              final dist = _calculateRouteDistance(route);
              // より短いルートが見つかれば更新
              if (dist < minRoadDist) {
                minRoadDist = dist;
                bestRoadRoute = CachedRouteData(
                  route: route,
                  target: target,
                  distance: dist,
                );
              }
            }
          }
        }

        if (bestRoadRoute != null) {
          _cachedRoutes[type] = bestRoadRoute;
          if (kDebugMode) print('📦 Type [$type]: 最短の実道路ルートをキャッシュ (${bestRoadRoute.distance.toStringAsFixed(0)}m)');
        }
      }
      
      _lastRouteUpdateLoc = currentLoc;
      notifyListeners();
      
    } catch (e) {
      if (kDebugMode) print('❌ Background Cache Error: $e');
    } finally {
      _isCaching = false;
    }
  }

  LatLng? _lastRecalcCheckLoc;
  Timer? _recalcTimer;
  static const double _moveThreshold = 5.0; // 5m移動
  static const Duration _recalcDelay = Duration(milliseconds: 2500); // 2.5s停止で発火

  /// バックグラウンドで避難経路を更新（移動・停止検知付き）
  Future<void> updateBackgroundRoutes(LatLng currentLoc) async {
    // 1. 初回または一定距離(5m)の移動をチェック
    if (_lastRouteUpdateLoc == null || _lastRecalcCheckLoc == null) {
      _lastRouteUpdateLoc = currentLoc;
      _lastRecalcCheckLoc = currentLoc;
      await _executeBackgroundUpdate(currentLoc);
      return;
    }

    final distFromLastCheck = const Distance().as(LengthUnit.Meter, _lastRecalcCheckLoc!, currentLoc);
    
    // 5m以上移動していなければタイマーをリセットせず無視
    if (distFromLastCheck < _moveThreshold) return;

    // 2. 移動を検知したらタイマーを（再）セット (Debounce)
    _lastRecalcCheckLoc = currentLoc;
    _recalcTimer?.cancel();
    _recalcTimer = Timer(_recalcDelay, () async {
      // 2.5秒間移動（5m以上の変化）がなければ「停止した」とみなし再計算
      if (kDebugMode) print('🛑 Stop Detected: 自動再計算を実行します');
      _lastRouteUpdateLoc = currentLoc;
      await _executeBackgroundUpdate(currentLoc);
    });
  }



  /// 道路データを読み込む (バイナリ版 - v4.0高速化対応)
  Future<void> _loadRoadData() async {
    try {
      final assetPath = _currentAppRegion == AppRegion.japan
          ? 'assets/data/roads_jp.bin' 
          : 'assets/data/roads_th.bin';
      
      if (kDebugMode) {
        print('🛣️ Loading road data for ${_currentAppRegion == AppRegion.japan ? "Japan" : "Thailand"}: $assetPath');
      }
      
      // BinaryRoadLoaderを使用してメインスレッドへの負荷を最小限にロード
      final roads = await BinaryRoadLoader.load(assetPath);
      
      // BinaryRoadLoader returns List<List<LatLng>>
      // _roadPolylinesの型と一致させる必要がある
      // もし_roadPolylinesがList<Map>等だった場合はモデル側も修正が必要だが
      // 今回はList<List<LatLng>>として扱う
      _roadPolylines = roads;
      notifyListeners();
      
      if (kDebugMode) {
        print('✅ Loaded ${roads.length} road segments from $assetPath');
      }
      
    } catch (e) {
      debugPrint('Error loading binary road data: $e');
      // GeoJSONがまだ必要な場合のフォールバックなどを検討
     _roadPolylines = [];
    }
  }

  /// タイの洪水リスクデータを読み込む (satun_flood_prediction.json)
  /// リスクスコアごとに大きな透過サークルとして表示
  Future<void> _loadFloodRiskData() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/data/satun_flood_prediction.json');
      final List<dynamic> data = json.decode(jsonString) as List<dynamic>;
      
      // リスクスコア1以上のポイントのみを抽出（0は森林・山岳地帯なので除外）
      _floodRiskPoints = data
          .where((item) => (item['risk_score'] as int? ?? 0) > 0)
          .map((item) => item as Map<String, dynamic>)
          .toList();
      
      if (kDebugMode) {
        print('🌊 Loaded ${_floodRiskPoints.length} flood risk points (filtered: risk_score > 0)');
      }
    } catch (e) {
      debugPrint('Error loading flood risk data: $e');
      _floodRiskPoints = [];
    }
  }

  /// タイの送電線データを読み込む (power_risk_th.geojson)
  /// 送電線と発電所（タワー）の周辺に半径20mの黄色いサークルを配置
  Future<void> _loadPowerLineData() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/data/power_risk_th.geojson');
      final Map<String, dynamic> geoJsonData = json.decode(jsonString);
      final List<dynamic> features = geoJsonData['features'] as List<dynamic>;
      
      List<List<LatLng>> powerLines = [];
      List<Map<String, dynamic>> powerPoints = []; // 送電線上のポイントと発電所のリスト
      
      for (var feature in features) {
        final geometry = feature['geometry'];
        final properties = feature['properties'];
        
        if (geometry == null) continue;
        
        final type = geometry['type'];
        
        if (type == 'LineString') {
          // 送電線
          final List<dynamic> coordinates = geometry['coordinates'] as List<dynamic>;
          List<LatLng> line = coordinates.map((coord) {
            final lat = coord[1] as double;
            final lng = coord[0] as double;
            
            // 送電線上の各ポイントをリスク範囲として追加
            powerPoints.add({
              'lat': lat,
              'lng': lng,
              'type': 'power_line',
              'voltage': properties?['voltage'] ?? 'unknown',
            });
            
            return LatLng(lat, lng);
          }).toList();
          
          if (line.isNotEmpty) {
            powerLines.add(line);
          }
        } else if (type == 'Point') {
          // 発電所・タワー
          final List<dynamic> coordinates = geometry['coordinates'] as List<dynamic>;
          powerPoints.add({
            'lat': coordinates[1] as double,
            'lng': coordinates[0] as double,
            'type': properties?['power'] ?? 'tower',
          });
        }
      }
      
      _powerLinePolylines = powerLines;
      
      // 送電線周辺リスクポイントを_powerRiskCirclesに保存
      _powerRiskCircles.clear();
      for (var point in powerPoints) {
        final lat = point['lat'] as double;
        final lng = point['lng'] as double;
        _powerRiskCircles.add(PowerRiskCircleData(
          position: LatLng(lat, lng),
          powerType: point['type'] as String,
          lat: lat,
          lng: lng,
        ));
      }
      
      if (kDebugMode) {
        print('⚡ Loaded ${_powerLinePolylines.length} power line segments and ${powerPoints.length} risk points');
      }
    } catch (e) {
      debugPrint('Error loading power line data: $e');
      _powerLinePolylines = [];
      _powerRiskCircles = [];
    }
  }

  /// GeoJSONファイルをパースしてShelterリストを返す
  Future<List<Shelter>> _loadGeoJson(String assetPath, String region) async {
    try {
      final String jsonString = await _securityService.loadEncryptedAsset(assetPath);
      final Map<String, dynamic> data = json.decode(jsonString);
      final List<dynamic> features = data['features'] as List<dynamic>;
      
      List<Shelter> result = [];
      
      for (var feature in features) {
        try {
          final props = feature['properties'] as Map<String, dynamic>;
          final geometry = feature['geometry'] as Map<String, dynamic>?;
          
          if (geometry == null) continue;

          // 1. Extract Name (Safe Fallback)
          String name = props['name'] ?? props['name:th'] ?? props['name:en'] ?? props['name:ja'] ?? 'Unknown';
          if (name.trim().isEmpty) name = 'Unknown'; // Ensure non-empty
          
          // 2. Extract Type
          // まずpropsに直接typeがあればそれを使う（日本版データ対応）
          String type = props['type'] as String? ?? 'other';
          
          // 既存のtypeがない、またはotherの場合はOSMフィールドから判定
          if (type == 'other') {
            final amenity = props['amenity'] as String?;
            final building = props['building'] as String?;
            final shop = props['shop'] as String?;
            final healthcare = props['healthcare'] as String?;
            
            // 不要な店舗タイプをスキップ (工具店、一般店舗など)
            final List<String> excludedShopTypes = [
              'general', 'hardware', 'doityourself', 'tools', 'trade',
              'car', 'car_repair', 'car_parts', 'tyres', 'motorcycle',
              'furniture', 'electronics', 'mobile_phone', 'computer',
              'clothes', 'shoes', 'jewelry', 'beauty', 'hairdresser',
              'florist', 'gift', 'books', 'stationery', 'toys',
            ];
            if (shop != null && excludedShopTypes.contains(shop)) {
              continue; // スキップ
            }
            
            if (amenity == 'school' || building == 'school') type = 'school';
            else if (amenity == 'university' || building == 'university') type = 'school'; 
            else if (amenity == 'hospital' || amenity == 'clinic' || amenity == 'doctors' || amenity == 'dentist' || healthcare == 'hospital' || healthcare == 'clinic') type = 'hospital';
            else if (amenity == 'townhall' || amenity == 'public_building') type = 'gov';
            else if (amenity == 'place_of_worship') type = 'temple';
            else if (amenity == 'shelter') type = 'shelter';
            else if (shop == 'convenience' || amenity == 'convenience_store') type = 'convenience';
            else if (shop == 'supermarket') type = 'convenience'; // スーパーもコンビニカテゴリに
            else if (amenity == 'fuel') type = 'fuel'; // ガソリンスタンド
            else if (amenity == 'drinking_water' || amenity == 'water_point') type = 'water';
          }
          
          // 3. Extract Coordinates (Centroid for Polygons)
          double lat = 0;
          double lng = 0;
          
          final geoType = geometry['type'];
          final dynamic coords = geometry['coordinates'];
          
          if (coords == null) continue; // Safety check

          if (geoType == 'Point') {
            final cList = coords as List;
            if (cList.length >= 2) {
              lng = (cList[0] as num).toDouble();
              lat = (cList[1] as num).toDouble();
            }
          } else if (geoType == 'Polygon') {
             // Polygon [[[x,y], [x,y]...]]
             final rings = coords as List;
             if (rings.isNotEmpty) {
               final points = rings[0] as List; // Outer ring
               if (points.isNotEmpty) {
                 double sumLat = 0;
                 double sumLng = 0;
                 int count = 0;
                 for (var p in points) {
                   final pList = p as List;
                   if (pList.length >= 2) {
                     sumLng += (pList[0] as num).toDouble();
                     sumLat += (pList[1] as num).toDouble();
                     count++;
                   }
                 }
                 if (count > 0) {
                   lat = sumLat / count;
                   lng = sumLng / count;
                 }
               }
             }
          } else if (geoType == 'MultiPolygon') {
             // Take first polygon
             final polys = coords as List;
             if (polys.isNotEmpty) {
               final rings = polys[0] as List;
               if (rings.isNotEmpty) {
                 final points = rings[0] as List;
                 double sumLat = 0;
                 double sumLng = 0;
                 int count = 0;
                 for (var p in points) {
                   final pList = p as List;
                   if (pList.length >= 2) {
                     sumLng += (pList[0] as num).toDouble();
                     sumLat += (pList[1] as num).toDouble();
                     count++;
                   }
                 }
                 if (count > 0) {
                   lat = sumLat / count;
                   lng = sumLng / count;
                 }
               }
             }
          }
          
          // Validation: invalid lat/lng or (0,0)
          if (lat == 0 && lng == 0) continue; 
          if (lat < -90 || lat > 90 || lng < -180 || lng > 180) continue;
          
          result.add(Shelter(
            id: props['@id']?.toString() ?? UniqueKey().toString(),
            name: name,
            lat: lat,
            lng: lng,
            type: type,
            verified: true, 
            region: region,
          ));
        } catch (e) {
          if (kDebugMode) print('Error parsing feature in $assetPath: $e');
          // Skip bad feature, continue to next
          continue;
        }
      }
      return result;
    } catch (e) {
      if (kDebugMode) print('GeoJSON Parse Error ($assetPath): $e');
      return [];
    }
  }

  /// 緊急モード（公式フィルタ）を切り替える
  void toggleEmergencyMode() {
    _isEmergencyMode = !_isEmergencyMode;
    notifyListeners();
  }

  /// 災害モードを切り替える
  void toggleDisasterMode() {
    _isDisasterMode = !_isDisasterMode;
    notifyListeners();
  }

  /// 災害モードを明示的に設定する
  void setDisasterMode(bool value) {
    if (_isDisasterMode != value) {
      _isDisasterMode = value;
      notifyListeners();
    }
  }

  /// 言語を設定する
  void setLanguage(String lang) {
    _currentLanguage = lang;
    notifyListeners();
  }

  /// 地域を切り替える (Demo用: Japan/Thailand toggle)
  void toggleRegion() {
    // jp... -> th_pathum, th... -> jp_osaki
    if (_currentRegion.startsWith('jp')) {
      _currentRegion = 'th_pathum';
    } else {
      _currentRegion = 'jp_osaki';
    }
    notifyListeners();
    
    // データ再読み込み
    loadShelters();
    loadHazardPolygons(); // This will load points for Thailand, polygons for Japan
    _loadRoadData(); // 道路データも読み込む
  }

  /// 特定の地域を設定する
  Future<void> setRegion(String region) async {
    // 文字列を正規化（大文字入力も対応）
    final normalizedRegion = region.toLowerCase();

    // 地域が変わる場合はナビゲーションターゲットをクリア
    if (_currentRegion != normalizedRegion && _currentRegion != 'jp_osaki' && _currentRegion != 'th_satun') {
       // 初期値や正規化後の値との比較が複雑なので、常にクリアするか検討
       // ここではシンプルに、現在の地域と入力が異なる場合にクリア
    }
    
    // 安全のため、地域設定時は常にナビゲーション状態をリセット
    _navTarget = null;
    _isNavigating = false;

    // AppRegionを判定し、内部用の地域コードを設定
    if (normalizedRegion == 'japan' || normalizedRegion.startsWith('jp')) {
      _currentAppRegion = AppRegion.japan;
      _currentRegion = 'jp_osaki'; // 内部コードを正規化
    } else if (normalizedRegion == 'thailand' || normalizedRegion.startsWith('th')) {
      _currentAppRegion = AppRegion.thailand;
      _currentRegion = 'th_satun'; // 内部コードを正規化
    } else {
      // フォールバック: そのまま使用
      _currentRegion = normalizedRegion;
      _currentAppRegion = AppRegion.japan;
    }
    
    print('🌏 Region set to: $_currentRegion (AppRegion: $_currentAppRegion)');

    notifyListeners();
    // 全データリロード
    await loadShelters();
    // loadShelters内部で _loadHazardPolygons と _loadRoadData が呼ばれるのでここでは不要
  }

  /// 現在の地域の中心座標を取得
  Map<String, double> getCenter() {
    if (_currentAppRegion == AppRegion.thailand) {
      return {'lat': 6.7371225, 'lng': 100.0798828}; // PCSHS Satun
    } else {
      // Japan (Osaki)
      return {'lat': 38.5772, 'lng': 140.9559};
    }
  }

  /// ハザードデータを読み込む (ポリゴンまたはポイント)
  Future<void> loadHazardPolygons() async {
    // Clear old data first
    _hazardPolygons = [];
    _hazardPoints = [];
    
    try {
      final String fileName = _currentRegion.startsWith('th')
          ? 'assets/data/hazard_thailand.json'
          : 'assets/data/hazard_japan.json';

      final String jsonString = await _securityService.loadEncryptedAsset(fileName);
      final Map<String, dynamic> jsonData = json.decode(jsonString) as Map<String, dynamic>;

      final String? dataType = jsonData['type'] as String?;

      // Check format type
      if (dataType == 'point_hazard') {
        // --- Point Based ---
        final List<dynamic> pointsData = jsonData['points'] as List<dynamic>;
        _hazardPoints = pointsData.map((p) => p as Map<String, dynamic>).toList();
        if (kDebugMode) print('Loaded ${_hazardPoints.length} hazard points');
        
      } else if (dataType == 'polygon_hazard') {
        // --- New Polygon Format (with metadata) ---
        final List<dynamic> polygonsData = jsonData['polygons'] as List<dynamic>;
        _hazardPolygons = polygonsData.map((polygon) {
          // 新形式: { "name": "...", "coordinates": [[lng, lat], ...] }
          if (polygon is Map<String, dynamic> && polygon.containsKey('coordinates')) {
            final List<dynamic> coords = polygon['coordinates'] as List<dynamic>;
            return coords.map((coord) {
              final List<dynamic> point = coord as List<dynamic>;
              final double lng = (point[0] as num).toDouble();
              final double lat = (point[1] as num).toDouble();
              return LatLng(lat, lng);
            }).toList();
          }
          // 旧形式: [[lng, lat], [lng, lat], ...]
          final List<dynamic> coords = polygon as List<dynamic>;
          return coords.map((coord) {
            final List<dynamic> point = coord as List<dynamic>;
            final double lng = (point[0] as num).toDouble();
            final double lat = (point[1] as num).toDouble();
            return LatLng(lat, lng);
          }).toList();
        }).toList();
        if (kDebugMode) print('Loaded ${_hazardPolygons.length} hazard polygons (new format)');
        
      } else {
        // --- Legacy Polygon Format (Japan) ---
        final List<dynamic> polygonsData = jsonData['polygons'] as List<dynamic>;
        _hazardPolygons = polygonsData.map((polygon) {
          final List<dynamic> coords = polygon as List<dynamic>;
          return coords.map((coord) {
            final List<dynamic> point = coord as List<dynamic>;
            final double lng = (point[0] as num).toDouble();
            final double lat = (point[1] as num).toDouble();
            return LatLng(lat, lng);
          }).toList();
        }).toList();
        if (kDebugMode) print('Loaded ${_hazardPolygons.length} hazard polygons (legacy format)');
      }

    } catch (e) {
      if (kDebugMode) print('Hazard load error: $e');
      _hazardPolygons = [];
      _hazardPoints = [];
    }
    notifyListeners();
  }

  /// 道路データを読み込む Publc API (実際は内部メソッドをこれにするか、ラッパーとして残す)
  Future<void> loadRoadData() async {
    await _loadRoadData();
  }

  /// リスクデータを読み込む（浸水＋電力設備）
  /// 
  /// タイ地域での災害リスク可視化のため
  Future<void> loadRiskData() async {
    // このメソッドは非推奨：loadShelters内で_loadFloodRiskDataと_loadPowerLineDataが呼ばれます
    if (kDebugMode) {
      print('⚠️ loadRiskData() is deprecated');
    }
    /*
    try {
      if (_currentRegion.startsWith('th')) {
        // タイのリスクデータを読み込む
        if (kDebugMode) print('🌊 浸水・電力リスクデータを読み込み中（バックグラウンド処理）...');
        
        // 並列で読み込み
        final results = await Future.wait([
          RiskVisualizationService.loadFloodRiskData('assets/data/satun_flood_prediction.json'),
          RiskVisualizationService.loadPowerRiskData('assets/data/power_risk_th.geojson'),
        ]);
        
        _floodRiskCircles = results[0] as List<FloodCircleData>;
        _powerRiskCircles = results[1] as List<PowerRiskCircleData>;
        
        if (kDebugMode) {
          print('✅ 浸水データ: ${_floodRiskCircles.length}地点');
          print('✅ 電力設備データ: ${_powerRiskCircles.length}箇所');
        }
      }
    } catch (e) {
      if (kDebugMode) print('❌ リスクデータの読み込みエラー: $e');
      _floodRiskCircles = [];
      _powerRiskCircles = [];
    }
    */
  }

  /// 道路グラフを構築（ルーティング用）
  /// 
  /// compute()でバックグラウンド処理するため、UIをブロックしません
  /// バイナリファイル（roads_jp.bin / roads_th.bin）を使用
  Future<void> buildRoadGraph() async {
    try {
      String binPath;
      String mode;
      
      if (_currentRegion.startsWith('th')) {
        binPath = 'assets/data/roads_th.bin';
        mode = 'thailand';
        
        if (kDebugMode) print('🗺️ タイの道路グラフを構築中...');
      } else if (_currentRegion.startsWith('jp')) {
        binPath = 'assets/data/roads_jp.bin';
        mode = 'japan';
        
        if (kDebugMode) print('🗺️ 日本の道路グラフを構築中...');
      } else {
        return; // 未対応地域
      }
      
      // バイナリファイルからグラフを構築
      _roadGraph = await BinaryGraphLoader.loadGraph(binPath, mode: mode);
      
      if (_roadGraph == null || _roadGraph!.nodes.isEmpty) {
        if (kDebugMode) print('⚠️ バイナリファイルからグラフを構築できませんでした: $binPath');
      }
      
      // RoutingEngineを初期化
      if (_roadGraph != null) {
        _reinitializeRoutingEngine();
        
        if (kDebugMode) {
          print('✅ グラフ構築完了: ${_roadGraph!.getStats()}');
        }
      }
      
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('❌ グラフ構築エラー: $e');
    }
  }

  /// RoutingEngineを現在の設定（ハザード等）で再初期化
  void _reinitializeRoutingEngine() {
    if (_roadGraph == null) return;

    // ハザードポリゴンを math.Point 形式に変換
    List<List<math.Point<double>>>? mathPolygons;
    if (_hazardPolygons.isNotEmpty) {
      mathPolygons = _hazardPolygons.map((poly) => 
        poly.map((p) => math.Point(p.latitude, p.longitude)).toList()
      ).toList();
    }

    _routingEngine = RoutingEngine(
      graph: _roadGraph!,
      mode: _currentAppRegion == AppRegion.japan ? 'japan' : 'thailand',
      hazardPolygons: mathPolygons,
      hazardPoints: _hazardPoints,
    );
    
    // Configure shared Navigation Engine
    if (_roadGraph != null) {
      GapLessNavigationEngine().configure(_routingEngine!, _roadGraph!);
    }
  }

  /// 最大安全ルートを計算
  /// 
  /// @param start 出発地点の座標
  /// @param goal 目的地の座標
  /// @param target (Optional) ターゲット避難所オブジェクト（キャッシュ用）
  Future<void> calculateSafestRoute(LatLng start, LatLng goal, {Shelter? target}) async {
    if (_roadGraph == null || _routingEngine == null) {
      if (kDebugMode) print('⚠️ グラフが未構築です。先にbuildRoadGraph()を呼び出してください。');
      return;
    }
    
    _isRoutingLoading = true;
    _safestRoute = null;
    notifyListeners();
    
    try {
      // 出発地点と目的地の最寄りノードを検索
      final startNodeId = _findNearestNode(start);
      final goalNodeId = _findNearestNode(goal);
      
      if (startNodeId == null || goalNodeId == null) {
        if (kDebugMode) print('⚠️ ルート計算: 最寄りノードが見つかりません');
        _isRoutingLoading = false;
        notifyListeners();
        return;
      }
      
      if (kDebugMode) print('🚀 最大安全ルート計算中...');
      
      // Dijkstraで最大安全ルート探索
      _safestRoute = _routingEngine!.findSafestPath(startNodeId, goalNodeId);
      
      if (_safestRoute != null && _safestRoute!.isNotEmpty) {
        if (kDebugMode) {
          print('✅ 安全ルート発見: ${_safestRoute!.length}ノード');
        }
        
        // Cache the result if target is provided
        if (target != null) {
            final dist = _calculateRouteDistance(_safestRoute!);
            _targetSpecificCache[target.id] = CachedRouteData(
                route: _safestRoute!, 
                target: target, 
                distance: dist
            );
        }
      } else {
        if (kDebugMode) print('⚠️ ルートが見つかりませんでした');
      }
    } catch (e) {
      if (kDebugMode) print('❌ ルート計算エラー: $e');
    } finally {
      _isRoutingLoading = false;
      notifyListeners();
    }
  }

  /// 最寄りのノードIDを検索
  String? _findNearestNode(LatLng point) {
    if (_roadGraph == null) return null;
    
    double minDist = double.infinity;
    String? nearestNodeId;
    
    for (var node in _roadGraph!.nodes.values) {
      const distance = Distance();
      final dist = distance.as(LengthUnit.Meter, point, node.position);
      
      if (dist < minDist) {
        minDist = dist;
        nearestNodeId = node.id;
      }
    }
    
   // 500m以上離れていたらnull
    if (minDist > 500) return null;
    return nearestNodeId;
  }


     /// Get top N candidates by straight-line distance
    List<Shelter> _getTopNCandidates(String type, LatLng loc, int n) {
      final List<MapEntry<Shelter, double>> candidates = [];
      const distanceCalc = Distance();
      
      for (var s in _shelters) {
          bool match = s.type == type;
          if (type == 'water' && (s.type == 'convenience' || s.type == 'store')) match = true;
          if (type == 'convenience' && s.type == 'store') match = true;
          if (type == 'hospital' && (s.type == 'hospital' || s.type == 'clinic')) match = true;
          if (type == 'shelter' && (s.type == 'shelter' || s.type == 'school' || s.type == 'community_centre')) match = true;

          if (match) {
              final d = distanceCalc.as(LengthUnit.Meter, loc, LatLng(s.lat, s.lng));
              candidates.add(MapEntry(s, d));
          }
      }
        // Return top N
      return candidates.take(n).map((e) => e.key).toList();
    }
  
  /// キャッシュされたルートでナビゲーションを開始
  /// 成功すればtrueを返す
  bool startCachedNavigation(String type) {
      if (_cachedRoutes.containsKey(type)) {
        if (kDebugMode) print('⚡ Using cached route for $type');
        final data = _cachedRoutes[type]!;
        _safestRoute = data.route;
        _navTarget = data.target;
        _isNavigating = true;
        _isRoutingLoading = false;
        notifyListeners();
        return true;
      }
      return false;
  }

  /// キャッシュされたルートを取得（なければnull）
  List<String>? getCachedRoute(String type) {
      return _cachedRoutes[type]?.route;
  }
  
  /// キャッシュされたルートの距離を取得（なければnull）
  double? getCachedDistance(String type) {
      return _cachedRoutes[type]?.distance;
  }

  /// ルート（ノードIDリスト）の総距離を計算
  double _calculateRouteDistance(List<String> route) {
    if (route.length < 2 || _roadGraph == null) return 0.0;
    
    double total = 0.0;
    const distanceCalc = Distance();
    
    for (int i = 0; i < route.length - 1; i++) {
        final n1 = _roadGraph!.nodes[route[i]];
        final n2 = _roadGraph!.nodes[route[i+1]];
        if (n1 != null && n2 != null) {
            total += distanceCalc.as(LengthUnit.Meter, n1.position, n2.position);
        }
    }
    return total;
  }

  /// 特定のターゲットへのキャッシュ済みルート距離を取得（ID一致確認）
  double? getDistanceToTargetIfCached(Shelter target) {
      // 1. Check specific cache first
      if (_targetSpecificCache.containsKey(target.id)) {
          return _targetSpecificCache[target.id]?.distance;
      }
      
      // 2. Check general cache
      for (final data in _cachedRoutes.values) {
          // ID check (assumes unique IDs)
          if (data.target.id == target.id) {
              return data.distance;
          }
      }
      return null;
  }

  /// 計算された安全ルートをクリア
  void clearSafestRoute() {
    _safestRoute = null;
    notifyListeners();
  }

  /// 指定したタイプの最寄り施設を検索
  /// [includeTypes]: 特定のタイプのみ検索したい場合に指定
  /// [officialOnly]: includeTypesがnullの場合に有効。trueなら公認避難所のみ(コンビニ除外)
  Shelter? getNearestShelter(LatLng userLocation, {
    List<String>? includeTypes, 
    bool officialOnly = true
  }) {
    // リリースビルドでもログを出力
    print('🔍 getNearestShelter called:');
    print('   Total shelters: ${_shelters.length}');
    print('   includeTypes: $includeTypes');
    print('   userLocation: ${userLocation.latitude}, ${userLocation.longitude}');
    
    if (_shelters.isEmpty) {
      print('   ⚠️ _shelters is EMPTY!');
      return null;
    }

    Shelter? nearest;
    double minDistance = double.infinity;
    const distance = Distance();
    int matchCount = 0;

    // 除外対象（officialOnly=trueの場合）
    final excludeTypes = ['convenience', 'fuel', 'water', 'store'];

    for (final shelter in _shelters) {
      bool isMatch = true;
      
      // 「Unknown」系の名前をスキップ
      final name = shelter.name.toLowerCase();
      if (name == 'unknown' || name.isEmpty || shelter.name == '不明') {
        continue;
      }

      if (includeTypes != null && includeTypes.isNotEmpty) {
        // 特定タイプ指定モード: 指定されたタイプ以外は除外
        if (!includeTypes.contains(shelter.type)) {
          isMatch = false;
        }
      } else if (officialOnly) {
        // 公認避難所モード: コンビニなどを除外
        if (excludeTypes.contains(shelter.type)) {
          isMatch = false;
        }
      }

      if (!isMatch) continue;

      // 危険区域（ハザードポリゴン）内の避難所は除外
      // ただし「洪水対応（isFloodShelter）」が明示されている場合は許可する
      if (_isInHazardZone(LatLng(shelter.lat, shelter.lng)) && !shelter.isFloodShelter) {
        // コンビニ等は除外、公式避難所でも洪水非対応なら除外
        if (kDebugMode) {
          // print('⚠️ Excluding high-risk shelter: ${shelter.name}');
        }
        continue;
      }

      matchCount++;

      final d = distance.as(LengthUnit.Meter, userLocation, LatLng(shelter.lat, shelter.lng));
      if (d < minDistance) {
        minDistance = d;
        nearest = shelter;
      }
    }

    // リリースビルドでもログを出力
    print('   Matched: $matchCount items');
    if (nearest != null) {
      print('   ✅ Found: ${nearest.name} (${nearest.type}) at ${minDistance.toStringAsFixed(0)}m');
    } else {
      print('   ❌ No match found');
    }

    return nearest;
  }

  /// 指定した地点が危険区域（ハザードポリゴン）内か判定
  bool _isInHazardZone(LatLng point) {
    return isPointInHazardZone(point);
  }

  /// 指定した地点がハザードゾーン内にあるかチェック
  bool isPointInHazardZone(LatLng point) {
    for (final polygon in _hazardPolygons) {
      if (_isPointInPolygon(point, polygon)) {
        return true;
      }
    }
    return false;
  }

  /// 点がポリゴン内にあるか判定 (Ray-casting Algorithm)
  bool _isPointInPolygon(LatLng point, List<LatLng> polygon) {
    if (polygon.length < 3) return false;
    
    bool inside = false;
    int j = polygon.length - 1;
    
    for (int i = 0; i < polygon.length; i++) {
      if (((polygon[i].latitude > point.latitude) != (polygon[j].latitude > point.latitude)) &&
          (point.longitude < (polygon[j].longitude - polygon[i].longitude) * (point.latitude - polygon[i].latitude) / (polygon[j].latitude - polygon[i].latitude) + polygon[i].longitude)) {
        inside = !inside;
      }
      j = i;
    }
    return inside;
  }

  // --- Navigation Logic ---

  /// ナビゲーションを開始（目的地ロック + 安全ルート計算）
  /// 
  /// ハザードゾーンを避けた最大安全ルートを計算し、
  /// コンパスナビゲーションで使用できるウェイポイントを生成します。
  Future<void> startNavigation(Shelter shelter, {LatLng? currentLocation}) async {
    _navTarget = shelter;
    _isNavigating = true;
    notifyListeners();
    
    // 現在地がある場合は安全ルートを計算
    if (currentLocation != null && _roadGraph != null && _routingEngine != null) {
      final goalLatLng = LatLng(shelter.lat, shelter.lng);
      
      if (kDebugMode) {
        print('🛡️ ハザード回避ルート計算開始...');
        print('   出発: ${currentLocation.latitude}, ${currentLocation.longitude}');
        print('   目的: ${shelter.name}');
      }
      
      await calculateSafestRoute(currentLocation, goalLatLng);
      
      if (_safestRoute != null && _safestRoute!.isNotEmpty) {
        if (kDebugMode) {
          print('✅ 安全ルート計算完了: ${_safestRoute!.length}ポイント');
        }
      }
    }
  }
  
  /// 安全ルートをLatLngリストとして取得（コンパスナビゲーション用）
  List<LatLng> getSafestRouteAsLatLng() {
    if (_safestRoute == null || _safestRoute!.isEmpty || _roadGraph == null) {
      return [];
    }
    
    return _safestRoute!
        .map((nodeId) => _roadGraph!.nodes[nodeId]?.position)
        .whereType<LatLng>()
        .toList();
  }
  
  /// 避難所がハザードゾーン内にあるかチェック
  bool isShelterInHazardZone(Shelter shelter) {
    return isPointInHazardZone(LatLng(shelter.lat, shelter.lng));
  }
  
  /// ハザードゾーン外の安全な避難所のみを取得
  List<Shelter> getSafeShelters() {
    return _shelters.where((shelter) => !isShelterInHazardZone(shelter)).toList();
  }
  
  /// 現在地から最も近い安全な避難所を取得
  Shelter? getNearestSafeShelter(LatLng currentPos) {
    final safeShelters = getSafeShelters();
    if (safeShelters.isEmpty) return null;
    
    Shelter? nearest;
    double minDistance = double.infinity;
    
    for (final shelter in safeShelters) {
      final d = Geolocator.distanceBetween(
        currentPos.latitude,
        currentPos.longitude,
        shelter.lat,
        shelter.lng,
      );
      if (d < minDistance) {
        minDistance = d;
        nearest = shelter;
      }
    }
    
    return nearest;
  }

  /// ナビゲーションを終了
  void endNavigation() {
    _navTarget = null;
    _isNavigating = false;
    notifyListeners();
  }

  /// 到着判定（現在地更新時に呼び出す）
  /// 目的地から30m以内に入ったらtrueを返し、ナビを終了する
  bool checkArrival(LatLng currentPos) {
    if (!_isNavigating || _navTarget == null) return false;

    final distanceInMeters = Geolocator.distanceBetween(
      currentPos.latitude,
      currentPos.longitude,
      _navTarget!.lat,
      _navTarget!.lng,
    );

    if (distanceInMeters <= 30.0) {
      // 到着！ -> 生活支援モードへ移行
      setSafeInShelter(true);
      return true;
    }
    return false;
  }

  /// 現在地から絶対的な最寄りの避難所を取得（ズーム用）
  Shelter? getAbsoluteNearest(LatLng currentPos) {
    // フィルタリング後の displayedShelters ではなく、
    // 現在のリスト全体(_shelters - すでにUnknownSpot除外済み)から探すのが一般的だが
    // 「現在の_sheltersリスト」という指示なので _shelters を使う。
    // ただし、もしEmergencyModeがOnなら、公式避難所から探すべきかもしれない。
    // ここでは安全のため displayedShelters を使うのがUX的に正しい（見えてないものにズームしない）。
    // 指示には "_shelters リスト" とあるが、文脈的に displayedShelters が適切。
    // しかし指示に忠実に _shelters を使う。
    
    if (_shelters.isEmpty) return null;

    Shelter? nearest;
    double minDistance = double.infinity;

    for (final shelter in _shelters) {
      final d = Geolocator.distanceBetween(
        currentPos.latitude,
        currentPos.longitude,
        shelter.lat,
        shelter.lng,
      );
      if (d < minDistance) {
        minDistance = d;
        nearest = shelter;
      }
    }
    return nearest;
  }

  // --- Offline Chat Utilities ---

  /// 2点間の方位を「北 (12時の方向)」形式で返す
  String getBlindDirectionText(LatLng from, LatLng to) {
    // 方位角を取得 (-180 ~ 180)
    final bearing = Geolocator.bearingBetween(
      from.latitude,
      from.longitude,
      to.latitude,
      to.longitude,
    );

    // 0~360に正規化
    final normalized = (bearing + 360) % 360;

    // 1. 8方位
    // 0°(360°):北, 45°:北東, ...
    // 22.5°ずらして45°で割るとインデックスが出る
    const directions = ['北', '北東', '東', '南東', '南', '南西', '西', '北西'];
    final index = ((normalized + 22.5) / 45).floor() % 8;
    final cardinal = directions[index];

    // 2. 時計の針
    // 1時間 = 30°
    int clock = (normalized / 30).round();
    if (clock == 0) clock = 12;

    return '$cardinal ($clock時の方向)';
  }

  /// オフラインチャット用の誘導メッセージを生成
  String generateOfflineResponse(Shelter target, LatLng currentPos) {
    const distanceCalc = Distance();
    final dist = distanceCalc.as(LengthUnit.Meter, currentPos, LatLng(target.lat, target.lng));
    final directionText = getBlindDirectionText(currentPos, LatLng(target.lat, target.lng));

    return '''
【誘導開始】
目的地: ${target.name}
距離: あと ${dist}m
進む方向: $directionText

⚠️ 足元に注意して、スマホのコンパスまたは太陽の位置を頼りに進んでください。''';
  }
  /// 避難完了状態を切り替える
  void setSafeInShelter(bool value) {
    _isSafeInShelter = value;
    if (value) {
      _isNavigating = false;
    }
    notifyListeners();
  }

  /// 大崎市公式避難所データをCSVから読み込む
  Future<void> loadOsakiSheltersFromCsv() async {
    try {
      final String csvString = await rootBundle.loadString('assets/data/osaki_shelters.csv');
      
      // CSVをパース（ヘッダー行をスキップ）
      final List<List<dynamic>> rows = const CsvToListConverter().convert(csvString);
      
      if (rows.isEmpty) return;
      
      // ヘッダー行をスキップ
      final dataRows = rows.skip(1);
      
      _osakiShelters = dataRows.map((row) {
        try {
          // index 1: 名称, index 5: 緯度, index 6: 経度, index 13: 洪水対応フラグ
          final name = row.length > 1 ? row[1].toString() : 'Unknown';
          final lat = row.length > 5 ? double.tryParse(row[5].toString()) ?? 0.0 : 0.0;
          final lng = row.length > 6 ? double.tryParse(row[6].toString()) ?? 0.0 : 0.0;
          final isFloodShelter = row.length > 13 && row[13].toString() == '1';
          final address = row.length > 3 ? row[3].toString() : '';
          final capacity = row.length > 22 ? int.tryParse(row[22].toString()) ?? 0 : 0;
          
          return OsakiShelter(
            name: name,
            lat: lat,
            lng: lng,
            isFloodShelter: isFloodShelter,
            address: address,
            capacity: capacity,
          );
        } catch (e) {
          return null;
        }
      }).whereType<OsakiShelter>().where((s) => s.lat != 0 && s.lng != 0).toList();
      
      if (kDebugMode) {
        print('📋 Loaded ${_osakiShelters.length} Osaki shelters from CSV');
      }
      
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('❌ Error loading Osaki shelters CSV: $e');
      _osakiShelters = [];
    }
  }

  /// 食料補給ポイントをstore.jsonから読み込む
  Future<void> loadFoodSupplyPoints() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/data/store.json');
      final Map<String, dynamic> geoJson = json.decode(jsonString);
      final List<dynamic> features = geoJson['features'] as List<dynamic>? ?? [];
      
      _foodSupplyPoints = features.map((feature) {
        try {
          final properties = feature['properties'] as Map<String, dynamic>? ?? {};
          final geometry = feature['geometry'] as Map<String, dynamic>? ?? {};
          final coordinates = geometry['coordinates'] as List<dynamic>? ?? [];
          
          if (coordinates.length < 2) return null;
          
          // GeoJSON: [経度, 緯度] の順
          final lng = (coordinates[0] as num).toDouble();
          final lat = (coordinates[1] as num).toDouble();
          
          // 店舗名を取得（日本語名優先）
          final name = properties['name:ja'] as String? 
              ?? properties['name'] as String? 
              ?? properties['brand:ja'] as String?
              ?? properties['brand'] as String?
              ?? 'Store';
          
          final nameEn = properties['name:en'] as String? 
              ?? properties['brand:en'] as String?
              ?? name;
          
          return FoodSupplyPoint(
            name: name,
            nameEn: nameEn,
            lat: lat,
            lng: lng,
            shopType: properties['shop'] as String? ?? 'convenience',
          );
        } catch (e) {
          return null;
        }
      }).whereType<FoodSupplyPoint>().toList();
      
      if (kDebugMode) {
        print('🍙 Loaded ${_foodSupplyPoints.length} food supply points from store.json');
      }
      
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('❌ Error loading food supply points: $e');
      _foodSupplyPoints = [];
    }
  }

  /// 大崎市データを一括読み込み
  /// CSVと店舗データを_sheltersに統合してコンパスナビゲーションで使えるようにする
  Future<void> loadOsakiData() async {
    await Future.wait([
      loadOsakiSheltersFromCsv(),
      loadFoodSupplyPoints(),
    ]);
    
    // === CSV避難所データを_sheltersに統合 ===
    int addedShelters = 0;
    for (final osakiShelter in _osakiShelters) {
      // 重複チェック（位置が近いものをスキップ）
      final exists = _shelters.any((s) => 
        (s.lat - osakiShelter.lat).abs() < 0.0005 && 
        (s.lng - osakiShelter.lng).abs() < 0.0005
      );
      if (!exists) {
        _shelters.add(Shelter(
          id: 'osaki_csv_${osakiShelter.name.hashCode}',
          name: osakiShelter.name,
          lat: osakiShelter.lat,
          lng: osakiShelter.lng,
          type: 'shelter', // 公式避難所
          verified: true,
          region: 'jp_osaki',
        ));
        addedShelters++;
      }
    }
    
    // === 食料補給ポイント（コンビニ等）を_sheltersに統合 ===
    // 給水所タグで検索できるように
    int addedStores = 0;
    for (final point in _foodSupplyPoints) {
      // 重複チェック
      final exists = _shelters.any((s) => 
        (s.lat - point.lat).abs() < 0.0005 && 
        (s.lng - point.lng).abs() < 0.0005
      );
      if (!exists) {
        _shelters.add(Shelter(
          id: 'store_jp_${point.name.hashCode}',
          name: point.name,
          lat: point.lat,
          lng: point.lng,
          type: 'convenience', // コンビニ/給水所
          verified: true,
          region: 'jp_osaki',
        ));
        addedStores++;
      }
    }
    
    // リリースビルドでもログを出力
    print('🏠 統合完了: CSV避難所 +$addedShelters件, 店舗 +$addedStores件');
    print('📊 _shelters総数: ${_shelters.length}件');
    
    notifyListeners();
  }

  /// サトゥーン避難所データを読み込み (GeoJSON)
  Future<void> loadSatunShelters() async {
    try {
      final String jsonString = await rootBundle.loadString('assets/data/satun_shelters.geojson');
      final Map<String, dynamic> geoJson = json.decode(jsonString);
      final List<dynamic> features = geoJson['features'] as List<dynamic>? ?? [];
      
      _satunShelters = features.map((feature) {
        try {
          final properties = feature['properties'] as Map<String, dynamic>? ?? {};
          final geometry = feature['geometry'] as Map<String, dynamic>? ?? {};
          final geometryType = geometry['type'] as String? ?? '';
          
          double lat = 0.0;
          double lng = 0.0;
          
          if (geometryType == 'Point') {
            // Point: [lng, lat]
            final coordinates = geometry['coordinates'] as List<dynamic>? ?? [];
            if (coordinates.length >= 2) {
              lng = (coordinates[0] as num).toDouble();
              lat = (coordinates[1] as num).toDouble();
            }
          } else if (geometryType == 'Polygon') {
            // Polygon: 座標の中心点を計算
            final coordinates = geometry['coordinates'] as List<dynamic>? ?? [];
            if (coordinates.isNotEmpty) {
              final ring = coordinates[0] as List<dynamic>? ?? [];
              if (ring.isNotEmpty) {
                double sumLat = 0, sumLng = 0;
                for (var point in ring) {
                  final p = point as List<dynamic>;
                  sumLng += (p[0] as num).toDouble();
                  sumLat += (p[1] as num).toDouble();
                }
                lng = sumLng / ring.length;
                lat = sumLat / ring.length;
              }
            }
          }
          
          if (lat == 0 && lng == 0) return null;
          
          // 名前を取得（タイ語優先、英語フォールバック）
          final nameTh = properties['name:th'] as String? 
              ?? properties['name'] as String? 
              ?? '';
          final nameEn = properties['name:en'] as String? 
              ?? properties['name'] as String?
              ?? '';
          final amenity = properties['amenity'] as String? ?? 'shelter';
          
          return RegionalShelter(
            nameTh: nameTh.isNotEmpty ? nameTh : nameEn,
            nameEn: nameEn.isNotEmpty ? nameEn : nameTh,
            lat: lat,
            lng: lng,
            amenityType: amenity,
          );
        } catch (e) {
          return null;
        }
      }).whereType<RegionalShelter>().toList();
      
      if (kDebugMode) {
        print('🇹🇭 Loaded ${_satunShelters.length} Satun shelters from GeoJSON');
      }
      
      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('❌ Error loading Satun shelters: $e');
      _satunShelters = [];
    }
  }

  List<RegionalShelter> _thaiWaterStations = [];

  /// タイの給水所データ（確約された水資源）を読み込み
  Future<void> loadThaiWaterStations() async {
    try {
      final jsonString = await rootBundle.loadString('assets/data/water_th.json');
      final List<dynamic> jsonList = json.decode(jsonString);
      
      _thaiWaterStations = jsonList.map((data) {
        return RegionalShelter(
          nameTh: data['name'],
          nameEn: data['name'],
          lat: (data['lat'] as num).toDouble(),
          lng: (data['lng'] as num).toDouble(),
          amenityType: 'water_station', // 特別タイプ
        );
      }).toList();
      
      if (kDebugMode) {
        print('🇹🇭 Loaded ${_thaiWaterStations.length} Thai water stations');
      }
    } catch (e) {
      if (kDebugMode) print('❌ Error loading Thai water stations: $e');
    }
  }

  /// タイランドデータを一括読み込み
  Future<void> loadThailandData() async {
    await loadSatunShelters();
    await loadThaiWaterStations();
  }

  /// 最寄りの安全な給水所を取得（タイ専用）
  /// 
  /// @param userLoc 現在位置
  /// @return 最寄りの安全な給水所（RegionalShelter）
  RegionalShelter? getNearestSafeWaterStation(LatLng userLoc) {
    RegionalShelter? nearest;
    double minDistance = double.infinity;

    for (final station in _thaiWaterStations) {
      // 1. 危険エリア判定 (浸水・感電リスク)
      if (isPointInHazardZone(station.position)) {
        continue; // 危険な場所はスキップ
      }

      // 2. 距離計算
      final distance = Geolocator.distanceBetween(
        userLoc.latitude,
        userLoc.longitude,
        station.lat,
        station.lng,
      );

      if (distance < minDistance) {
        minDistance = distance;
        nearest = station;
      }
    }
    
    return nearest;
  }

  /// 現在向いている方向の道路リスクを取得する
  /// 
  /// @param currentLocation 現在地
  /// @param heading 現在のヘディング（0-360）
  /// @return {riskFactor: double, message: String, isSafe: bool}
  Map<String, dynamic>? getRoadRiskInDirection(LatLng currentLocation, double heading) {
    if (_roadGraph == null) return null;

    // 1. 最寄りのノードを探す (50m以内)
    final nearestNodeId = BinaryGraphLoader.findNearestNode(_roadGraph!, currentLocation, maxDistance: 50.0);
    if (nearestNodeId == null) return null;

    final nearestNode = _roadGraph!.nodes[nearestNodeId];
    if (nearestNode == null) return null;

    // 2. そのノードに接続するエッジを取得
    final edges = _roadGraph!.getEdgesFromNode(nearestNodeId);
    
    // 3. ユーザーの向きと一致する道路（エッジ）を探す
    // 許容誤差: +/- 20度（少し緩めに設定）
    for (final edge in edges) {
      final otherNodeId = _roadGraph!.getOtherNodeId(edge.id, nearestNodeId);
      final otherNode = _roadGraph!.nodes[otherNodeId];
      if (otherNode == null) continue;

      // エッジの方位角を計算
      final bearing = Geolocator.bearingBetween(
        nearestNode.position.latitude,
        nearestNode.position.longitude,
        otherNode.position.latitude,
        otherNode.position.longitude,
      );

      // 角度の差を計算（最短距離）
      double diff = (bearing - heading).abs();
      if (diff > 180) diff = 360 - diff;

      // 30度以内なら「その道を見ている」と判定（緩和）
      if (diff <= 30) {
        // === Unified Risk Calculation using RoutingEngine logic ===
        double riskFactor = 1.0;
        String message = '';
        bool isSafe = true;

        if (_currentRegion.startsWith('th') && _routingEngine != null) {
           // --- Thailand Mode (Flood/Power) ---
           // Use RoutingEngine's sophisticated weight calculation
           try {
             final weight = _routingEngine!.calculateEdgeWeight(edge);
             final baseWeight = edge.distance;
             
             // Cost Ratio (How much more expensive is this road compared to its length?)
             double ratio = weight / baseWeight;
             if (baseWeight == 0) ratio = 1.0; // Safety check

             if (weight == double.infinity || ratio >= 5.0) {
                // High Risk (Flood > 1.5m OR Power Danger)
                message = 'DANGER: 深い浸水または感電リスク';
                isSafe = false;
                riskFactor = 5.0; // Max risk
             } else if (ratio >= 2.0) {
                message = 'WARNING: 浸水あり (注意して通行)';
                isSafe = false;
                riskFactor = ratio;
             } else {
                message = 'SAFE: 通行可能';
                isSafe = true;
                riskFactor = 1.0;
             }
           } catch (e) {
             // Fallback
             message = 'Unknown Risk';
           }
        } else {
           // --- Japan Mode (Road Width) ---
           // Existing logic using SurvivalRiskFactor
           riskFactor = SurvivalRiskFactor.getFactorForHighwayType(edge.highwayType);
           
           if (riskFactor >= 5.0) {
             message = '危険: 路地・細道 (回避推奨)';
             isSafe = false;
           } else if (riskFactor >= 1.2) {
             message = '注意: 生活道路 (閉塞リスクあり)';
             isSafe = false; // 警告対象
           } else {
             message = '安全: 大通り (推奨ルート)';
             isSafe = true;
           }
        }

        return {
          'riskFactor': riskFactor,
          'message': message,
          'isSafe': isSafe,
          'edgeId': edge.id,
        };
      }
    }
    
    return null; // 該当する道路なし
  }
}

/// 大崎市公式避難所データモデル
class OsakiShelter {
  final String name;
  final double lat;
  final double lng;
  final bool isFloodShelter; // 洪水対応フラグ
  final String address;
  final int capacity;

  OsakiShelter({
    required this.name,
    required this.lat,
    required this.lng,
    required this.isFloodShelter,
    this.address = '',
    this.capacity = 0,
  });
  
  LatLng get position => LatLng(lat, lng);
}

/// 食料補給ポイントデータモデル
class FoodSupplyPoint {
  final String name;
  final String nameEn;
  final double lat;
  final double lng;
  final String shopType; // convenience, supermarket, etc.

  FoodSupplyPoint({
    required this.name,
    required this.nameEn,
    required this.lat,
    required this.lng,
    this.shopType = 'convenience',
  });
  
  LatLng get position => LatLng(lat, lng);
}

/// 地域避難所データモデル（共通）
/// 日本・タイ両方で使用可能な汎用モデル
class RegionalShelter {
  final String nameTh;    // タイ語名/日本語名
  final String nameEn;    // 英語名
  final double lat;
  final double lng;
  final String amenityType; // hospital, school, shelter, etc.
  final bool isFloodShelter;
  final String address;
  final int capacity;

  RegionalShelter({
    required this.nameTh,
    required this.nameEn,
    required this.lat,
    required this.lng,
    this.amenityType = 'shelter',
    this.isFloodShelter = false,
    this.address = '',
    this.capacity = 0,
  });
  
  LatLng get position => LatLng(lat, lng);
  
  String getDisplayName(String lang) {
    if (lang == 'th' || lang == 'ja') {
      return nameTh.isNotEmpty ? nameTh : nameEn;
    }
    return nameEn.isNotEmpty ? nameEn : nameTh;
  }
}

/// キャッシュ用ルートデータ
class CachedRouteData {
  final List<String> route;
  final Shelter target;
  final double distance; // Route distance in meters
  
  CachedRouteData({
    required this.route, 
    required this.target,
    required this.distance,
  });
}
