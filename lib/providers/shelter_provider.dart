import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shelter.dart';
import '../data/poi_catalog.dart';
import '../data/map_repository.dart';
import '../data/road_parser.dart' hide RoadGraph;
import '../services/binary_graph_loader.dart';
import '../services/routing_engine.dart';
import '../services/safest_route_engine.dart';
import 'region_mode_provider.dart'; // Used for AppRegion enum
import '../services/risk_visualization_service.dart';
import '../models/road_graph.dart';

/// 避難所データを管理するProvider
class ShelterProvider with ChangeNotifier {
  // State
  // 初期値は jp_osaki (大崎市) -> AppRegion.japan
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

  // --- 外部ルート統合 (main.dartのIsolateから受信) ---
  // Isolate（main.dart）から受け取ったルートを一時保存する変数
  List<LatLng>? _externalRoute;

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
  
  RoadGraph? get roadGraph => _roadGraph;
  List<String>? get safestRoute => _safestRoute;
  List<FloodCircleData> get floodRiskCircles => _floodRiskCircles;
  List<PowerRiskCircleData> get powerRiskCircles => _powerRiskCircles;
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

  // ── エリア判定ヘルパー ───────────────────────────────────────────────────
  static bool isTokyoArea(double lat, double lng) =>
      lat >= 35.60 && lat <= 35.78 && lng >= 139.60 && lng <= 139.85;

  static bool isOsakiArea(double lat, double lng) =>
      lat >= 38.30 && lat <= 38.90 && lng >= 140.60 && lng <= 141.20;

  /// いずれのエリアにも属さない場合に最近傍エリアを返す
  static String _nearestRegion(double lat, double lng) {
    double distTokyo = (lat - 35.69).abs() + (lng - 139.69).abs();
    double distOsaki = (lat - 38.59).abs() + (lng - 140.90).abs();
    if (distTokyo <= distOsaki) return 'jp_tokyo';
    return 'jp_osaki';
  }

  /// 座標から地域を自動設定 (GPS連動)
  Future<void> setRegionFromCoordinates(double lat, double lng) async {
    String newRegion;
    if (isTokyoArea(lat, lng)) {
      newRegion = 'jp_tokyo';
    } else if (isOsakiArea(lat, lng)) {
      newRegion = 'jp_osaki';
    } else {
      newRegion = _nearestRegion(lat, lng);
    }

    if (_currentRegion != newRegion) {
      debugPrint('🌏 GPS Detected Region Change: $_currentRegion -> $newRegion (Lat: $lat, Lng: $lng)');
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
        debugPrint('🔍 ShelterProvider: Loading shelters for region: $_currentAppRegion (${_currentAppRegion == AppRegion.japan ? "Japan" : "Thailand"})');
      }
      
      // POI data is loaded in the finally block via GPLB files
      
      newShelters = newShelters.where((shelter) {
        final region = shelter.region ?? '';
        return region.startsWith('jp_') || region.isEmpty;
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

      debugPrint('✅ Loaded ${_shelters.length} shelters/locations (filtered)');
    } catch (e) {
      debugPrint('Error loading shelters: $e');
      _shelters = [];
    } finally {
      if (isFirstLoad) {
        _isLoading = false;
      }
      
      if (_currentAppRegion == AppRegion.japan) {
        if (_currentRegion == 'jp_tokyo') {
          await _loadTokyoPoiGplb();
        } else {
          await _loadJapanPoiGplb();
        }
      }

      
      notifyListeners();

      // シェルターロード完了後に保存済みnavTargetを復元
      await restoreNavTarget();
    }
  }

  /// osaki_poi.gplb から日本（大崎市）のPOIデータを読み込み _shelters に統合
  Future<void> _loadJapanPoiGplb() async {
    try {
      final bytes = await MapRepository.instance.readBytes('osaki_poi.gplb');
      final grouped    = GplbPoiParser.parseAndGroup(bytes);
      final shelters   = grouped[PoiCategory.shelter]!;
      final hospitals  = grouped[PoiCategory.hospital]!;
      final convStores = grouped[PoiCategory.convenience]!;
      final supplies   = grouped[PoiCategory.supply]!;
      final landmarks  = grouped[PoiCategory.landmark]!;

      int added = 0;
      for (final feature in [...shelters, ...hospitals, ...convStores, ...supplies, ...landmarks]) {
        final String type;
        if (feature.isShelter) {
          type = 'shelter';
        } else if (feature.isHospital) {
          type = 'hospital';
        } else if (feature.isConvenience) {
          type = 'convenience';
        } else if (feature.isSupply) {
          type = 'water';
        } else {
          type = 'landmark';
        }

        _shelters.add(Shelter(
          id: 'gplb_${feature.type.id}_${feature.lat.toStringAsFixed(5)}_${feature.lng.toStringAsFixed(5)}',
          name: feature.name,
          lat: feature.lat,
          lng: feature.lng,
          type: type,
          verified: true,
          region: 'jp_osaki',
          isFloodShelter: feature.handlesFlood,
        ));
        added++;
      }

      debugPrint('📦 _loadJapanPoiGplb: $added POIs loaded (shelter=${shelters.length} hospital=${hospitals.length} conv=${convStores.length} supply=${supplies.length})');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ _loadJapanPoiGplb error: $e');
    }
  }

  /// tokyo_center_poi.gplb から東京のPOIデータを読み込み _shelters に統合
  Future<void> _loadTokyoPoiGplb() async {
    try {
      final bytes = await MapRepository.instance.readBytes('tokyo_center_poi.gplb');
      final grouped    = GplbPoiParser.parseAndGroup(bytes);
      final shelters   = grouped[PoiCategory.shelter]!;
      final hospitals  = grouped[PoiCategory.hospital]!;
      final convStores = grouped[PoiCategory.convenience]!;
      final supplies   = grouped[PoiCategory.supply]!;
      final landmarks  = grouped[PoiCategory.landmark]!;

      int added = 0;
      for (final feature in [...shelters, ...hospitals, ...convStores, ...supplies, ...landmarks]) {
        final String type;
        if (feature.isShelter) {
          type = 'shelter';
        } else if (feature.isHospital) {
          type = 'hospital';
        } else if (feature.isConvenience) {
          type = 'convenience';
        } else if (feature.isSupply) {
          type = 'water';
        } else {
          type = 'landmark';
        }

        _shelters.add(Shelter(
          id: 'gplb_tokyo_${feature.type.id}_${feature.lat.toStringAsFixed(5)}_${feature.lng.toStringAsFixed(5)}',
          name: feature.name,
          lat: feature.lat,
          lng: feature.lng,
          type: type,
          verified: true,
          region: 'jp_tokyo',
          isFloodShelter: feature.handlesFlood,
        ));
        added++;
      }

      debugPrint('📦 _loadTokyoPoiGplb: $added POIs loaded');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ _loadTokyoPoiGplb error: $e');
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

  @override
  void dispose() {
    _recalcTimer?.cancel();
    super.dispose();
  }

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
    if (_currentAppRegion == AppRegion.japan) {
      if (_currentRegion == 'jp_tokyo') {
        try {
          if (kDebugMode) debugPrint('🛣️ Loading Tokyo road data from tokyo_center_roads.gplb');
          final bytes = await MapRepository.instance.readBytes('tokyo_center_roads.gplb');
          final features = RoadParser.parse(bytes);
          _roadPolylines = features.map((f) => f.geometry).toList();
          notifyListeners();
          if (kDebugMode) debugPrint('✅ Loaded ${_roadPolylines.length} road segments from tokyo_center_roads.gplb');
        } catch (e) {
          debugPrint('Error loading Tokyo road data: $e');
          _roadPolylines = [];
        }
      } else {
        // jp_osaki: osaki_roads.gplb を読み込む
        try {
          if (kDebugMode) debugPrint('🛣️ Loading Osaki road data from osaki_roads.gplb');
          final bytes = await MapRepository.instance.readBytes('osaki_roads.gplb');
          final features = RoadParser.parse(bytes);
          _roadPolylines = features.map((f) => f.geometry).toList();
          notifyListeners();
          if (kDebugMode) debugPrint('✅ Loaded ${_roadPolylines.length} road segments from osaki_roads.gplb');
        } catch (e) {
          debugPrint('Error loading Osaki road data: $e');
          _roadPolylines = [];
        }
      }
      return;
    }
    try {
      if (kDebugMode) {
        debugPrint('🛣️ Loading Thailand road data from thailand_roads.gplb');
      }
      final bytes = await MapRepository.instance.readBytes('thailand_roads.gplb');
      final features = RoadParser.parse(bytes);
      _roadPolylines = features.map((f) => f.geometry).toList();
      notifyListeners();
      if (kDebugMode) {
        debugPrint('✅ Loaded ${_roadPolylines.length} road segments from thailand_roads.gplb');
      }
    } catch (e) {
      debugPrint('Error loading Thailand road data: $e');
      _roadPolylines = [];
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

  /// 地域を切り替える (Demo用: jp_osaki / jp_tokyo toggle)
  void toggleRegion() {
    if (_currentRegion == 'jp_tokyo') {
      _currentRegion = 'jp_osaki';
    } else {
      _currentRegion = 'jp_tokyo';
    }
    notifyListeners();

    // データ再読み込み
    loadShelters();
    loadHazardPolygons();
    _loadRoadData();
  }

  /// 特定の地域を設定する
  Future<void> setRegion(String region) async {
    // 文字列を正規化（大文字入力も対応）
    final normalizedRegion = region.toLowerCase();

    // 安全のため、地域設定時は常にナビゲーション状態をリセット
    _navTarget = null;
    _isNavigating = false;
    unawaited(_clearPersistedNavTarget());

    // AppRegionを判定し、内部用の地域コードを設定
    if (normalizedRegion == 'jp_tokyo') {
      _currentAppRegion = AppRegion.japan;
      _currentRegion = 'jp_tokyo';
    } else {
      _currentAppRegion = AppRegion.japan;
      _currentRegion = 'jp_osaki'; // デフォルトは大崎市
    }
    
    debugPrint('🌏 Region set to: $_currentRegion (AppRegion: $_currentAppRegion)');

    notifyListeners();
    // 全データリロード
    await loadShelters();
    // loadShelters内部で _loadHazardPolygons と _loadRoadData が呼ばれるのでここでは不要
  }

  /// 現在の地域の中心座標を取得
  Map<String, double> getCenter() {
    if (_currentRegion == 'jp_tokyo') {
      return {'lat': 35.6895, 'lng': 139.6917}; // 東京都庁
    } else {
      // Japan (Osaki)
      return {'lat': 38.5772, 'lng': 140.9559};
    }
  }

  /// ハザードデータを読み込む
  Future<void> loadHazardPolygons() async {
    _hazardPolygons = [];
    _hazardPoints = [];

    // Japan: 地域に応じたハザードファイルを読み込む
    final hazardFile = _currentRegion == 'jp_tokyo'
        ? 'tokyo_center_hazard.gplh'
        : 'osaki_hazard.gplh';
    try {
      final jsonString = await MapRepository.instance.readString(hazardFile);
      final jsonData = json.decode(jsonString) as Map<String, dynamic>;
      final List<dynamic> polygonsData =
          (jsonData['polygons'] as List<dynamic>?) ?? [];
      _hazardPolygons = polygonsData.map((polygon) {
        final List<dynamic> coords = polygon is Map<String, dynamic> &&
                polygon.containsKey('coordinates')
            ? polygon['coordinates'] as List<dynamic>
            : polygon as List<dynamic>;
        return coords.map((coord) {
          final List<dynamic> pt = coord as List<dynamic>;
          return LatLng(
              (pt[1] as num).toDouble(), (pt[0] as num).toDouble());
        }).toList();
      }).toList();
      if (kDebugMode) {
        debugPrint(
            'Loaded ${_hazardPolygons.length} Japan hazard polygons from $hazardFile');
      }
    } catch (e) {
      if (kDebugMode) print('Japan hazard load error ($hazardFile): $e');
      _hazardPolygons = [];
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
    // このメソッドは非推奨
    if (kDebugMode) {
      debugPrint('⚠️ loadRiskData() is deprecated');
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
          debugPrint('✅ 浸水データ: ${_floodRiskCircles.length}地点');
          debugPrint('✅ 電力設備データ: ${_powerRiskCircles.length}箇所');
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
  /// Japan road graph is handled via gplb; this is a no-op stub.
  Future<void> buildRoadGraph() async {}

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
          debugPrint('✅ 安全ルート発見: ${_safestRoute!.length}ノード');
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
      candidates.sort((a, b) => a.value.compareTo(b.value));
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
    debugPrint('🔍 getNearestShelter called:');
    debugPrint('   Total shelters: ${_shelters.length}');
    debugPrint('   includeTypes: $includeTypes');
    debugPrint('   userLocation: ${userLocation.latitude}, ${userLocation.longitude}');
    
    if (_shelters.isEmpty) {
      debugPrint('   ⚠️ _shelters is EMPTY!');
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
    debugPrint('   Matched: $matchCount items');
    if (nearest != null) {
      debugPrint('   ✅ Found: ${nearest.name} (${nearest.type}) at ${minDistance.toStringAsFixed(0)}m');
    } else {
      debugPrint('   ❌ No match found');
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

  /// 指定した地点が洪水リスク円の範囲内にあるかチェック (半径 radiusM メートル)
  bool isNearFloodRisk(LatLng point, {double radiusM = 50.0}) {
    for (final circle in _floodRiskCircles) {
      final dist = Geolocator.distanceBetween(
        point.latitude, point.longitude,
        circle.position.latitude, circle.position.longitude,
      );
      if (dist <= radiusM) return true;
    }
    // point_hazard 形式の場合も確認
    for (final p in _hazardPoints) {
      final t = (p['type'] as String? ?? '').toLowerCase();
      if (!t.contains('flood')) continue;
      final lat = (p['lat'] as num?)?.toDouble() ?? 0;
      final lng = (p['lng'] as num?)?.toDouble() ?? 0;
      if (lat == 0 && lng == 0) continue;
      final dist = Geolocator.distanceBetween(
        point.latitude, point.longitude, lat, lng,
      );
      if (dist <= radiusM) return true;
    }
    return false;
  }

  /// 指定した地点が感電リスク円の範囲内にあるかチェック (半径 radiusM メートル)
  bool isNearPowerRisk(LatLng point, {double radiusM = 30.0}) {
    for (final circle in _powerRiskCircles) {
      final dist = Geolocator.distanceBetween(
        point.latitude, point.longitude,
        circle.position.latitude, circle.position.longitude,
      );
      if (dist <= radiusM) return true;
    }
    for (final p in _hazardPoints) {
      final t = (p['type'] as String? ?? '').toLowerCase();
      if (!t.contains('power') && !t.contains('electric') && !t.contains('tower')) continue;
      final lat = (p['lat'] as num?)?.toDouble() ?? 0;
      final lng = (p['lng'] as num?)?.toDouble() ?? 0;
      if (lat == 0 && lng == 0) continue;
      final dist = Geolocator.distanceBetween(
        point.latitude, point.longitude, lat, lng,
      );
      if (dist <= radiusM) return true;
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
  // ---------------------------------------------------------------------------
  // NavTarget Persistence (SharedPreferences)
  // ---------------------------------------------------------------------------

  static const _kNavTargetKey = 'nav_target_json';

  /// 目的地をSharedPreferencesに保存する
  Future<void> _persistNavTarget(Shelter shelter) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kNavTargetKey, jsonEncode(shelter.toJson()));
  }

  /// 保存済み目的地をSharedPreferencesから復元する
  /// [shelters]がロード済みのときに呼ぶ（IDで照合して整合性を保証）
  Future<void> restoreNavTarget() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kNavTargetKey);
    if (raw == null) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final restored = Shelter.fromJson(json);
      // 現在ロード済みのshelterリストに同IDがあれば最新データを優先
      final match = _shelters.where((s) => s.id == restored.id).firstOrNull;
      _navTarget = match ?? restored;
      _isNavigating = true;
      notifyListeners();
      if (kDebugMode) debugPrint('🔄 navTarget復元: ${_navTarget!.name}');
    } catch (e) {
      if (kDebugMode) debugPrint('navTarget復元失敗: $e');
      await prefs.remove(_kNavTargetKey);
    }
  }

  /// 保存済み目的地を削除する
  Future<void> _clearPersistedNavTarget() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kNavTargetKey);
  }

  // ---------------------------------------------------------------------------

  Future<void> startNavigation(Shelter shelter, {LatLng? currentLocation}) async {
    _navTarget = shelter;
    _isNavigating = true;
    notifyListeners();
    unawaited(_persistNavTarget(shelter));
    
    // 現在地がある場合は安全ルートを計算
    if (currentLocation != null && _roadGraph != null && _routingEngine != null) {
      final goalLatLng = LatLng(shelter.lat, shelter.lng);
      
      if (kDebugMode) {
        debugPrint('🛡️ ハザード回避ルート計算開始...');
        debugPrint('   出発: ${currentLocation.latitude}, ${currentLocation.longitude}');
        debugPrint('   目的: ${shelter.name}');
      }
      
      await calculateSafestRoute(currentLocation, goalLatLng);
      
      if (_safestRoute != null && _safestRoute!.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('✅ 安全ルート計算完了: ${_safestRoute!.length}ポイント');
        }
      }
    }
  }
  
  /// main.dart で計算されたルートを受け取り、地図更新を通知する
  void updateSafeRoute(List<List<double>> points) {
    if (points.isEmpty) return;
    
    // [lat, lng] のリストを LatLng オブジェクトに変換して保存
    _externalRoute = points.map((p) => LatLng(p[0], p[1])).toList();
    
    // 画面（地図）に「データが変わったぞ！」と知らせる
    notifyListeners();
  }

  /// 安全ルートをLatLngリストとして取得（コンパスナビゲーション用）
  List<LatLng> getSafestRouteAsLatLng() {
    // 1. main.dart からのルートがあればそれを最優先で返す
    if (_externalRoute != null && _externalRoute!.isNotEmpty) {
      return _externalRoute!;
    }

    // 2. なければ従来のグラフ計算ルートを返す
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
    unawaited(_clearPersistedNavTarget());
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
      unawaited(_clearPersistedNavTarget());
    }
    notifyListeners();
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
