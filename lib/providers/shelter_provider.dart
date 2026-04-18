import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/shelter.dart';
import '../data/poi_catalog.dart';
import '../data/map_repository.dart';
import '../data/road_parser.dart';
import 'region_mode_provider.dart'; // Used for AppRegion enum
import '../services/risk_visualization_service.dart';
import '../services/ble_road_report_service.dart';

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

  static final _distance = Distance();

  // Internal State
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

  /// 避難所データを読み込む
  Future<void> loadShelters() async {
    if (_isLoading) return;
    _isLoading = true;
    notifyListeners();

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
      // POIロード完了後にローディング解除・通知（途中で isLoading=false が見えないよう）
      if (_currentAppRegion == AppRegion.japan) {
        if (_currentRegion == 'jp_tokyo') {
          await _loadTokyoPoiGplb();
        } else {
          await _loadJapanPoiGplb();
        }
      }
      _isLoading = false;
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
      final shelters   = grouped[PoiCategory.shelter] ?? [];
      final hospitals  = grouped[PoiCategory.hospital] ?? [];
      final convStores = grouped[PoiCategory.convenience] ?? [];
      final supplies   = grouped[PoiCategory.supply] ?? [];
      final landmarks  = grouped[PoiCategory.landmark] ?? [];

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
      final shelters   = grouped[PoiCategory.shelter] ?? [];
      final hospitals  = grouped[PoiCategory.hospital] ?? [];
      final convStores = grouped[PoiCategory.convenience] ?? [];
      final supplies   = grouped[PoiCategory.supply] ?? [];
      final landmarks  = grouped[PoiCategory.landmark] ?? [];

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

  @override
  void dispose() {
    super.dispose();
  }

  /// バックグラウンドで避難経路を更新（移動・停止検知付き）
  Future<void> updateBackgroundRoutes(LatLng currentLoc) async {}



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
      if (kDebugMode) debugPrint('Japan hazard load error ($hazardFile): $e');
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

  /// 最大安全ルートを計算 (SafetyRouteEngineに委譲 — このメソッドは廃止)
  Future<void> calculateSafestRoute(LatLng start, LatLng goal, {Shelter? target}) async {}
  
  /// キャッシュされたルートでナビゲーションを開始
  /// 成功すればtrueを返す
  bool startCachedNavigation(String type) => false;

  /// キャッシュされたルートを取得（なければnull）
  List<String>? getCachedRoute(String type) {
      return _cachedRoutes[type]?.route;
  }
  
  /// キャッシュされたルートの距離を取得（なければnull）
  double? getCachedDistance(String type) {
      return _cachedRoutes[type]?.distance;
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

  /// 指定したタイプの最寄り施設を検索
  /// [includeTypes]: 特定のタイプのみ検索したい場合に指定
  /// [officialOnly]: includeTypesがnullの場合に有効。trueなら公認避難所のみ(コンビニ除外)
  Shelter? getNearestShelter(LatLng userLocation, {
    List<String>? includeTypes,
    bool officialOnly = true
  }) {
    if (kDebugMode) {
      debugPrint('🔍 getNearestShelter: ${_shelters.length} shelters, types=$includeTypes');
    }
    if (_shelters.isEmpty) return null;

    Shelter? nearest;
    double minDistance = double.infinity;
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

      final d = _distance.as(LengthUnit.Meter, userLocation, LatLng(shelter.lat, shelter.lng));
      if (d < minDistance) {
        minDistance = d;
        nearest = shelter;
      }
    }

    if (kDebugMode) {
      if (nearest != null) {
        debugPrint('   ✅ Found: ${nearest.name} (${nearest.type}) at ${minDistance.toStringAsFixed(0)}m');
      } else {
        debugPrint('   ❌ No match found (matched=$matchCount)');
      }
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
    if (_externalRoute != null && _externalRoute!.isNotEmpty) {
      return _externalRoute!;
    }
    return [];
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
    double minCost = double.infinity;

    for (final shelter in _shelters) {
      final d = Geolocator.distanceBetween(
        currentPos.latitude, currentPos.longitude,
        shelter.lat, shelter.lng,
      );
      // ハザードゾーン内の避難所は実質的に到達困難 → コストを3倍に
      final inHazard = _isInHazardZone(LatLng(shelter.lat, shelter.lng));
      final cost = inHazard ? d * 3.0 : d;
      if (cost < minCost) {
        minCost = cost;
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
    final dist = _distance.as(LengthUnit.Meter, currentPos, LatLng(target.lat, target.lng));
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
      // 到着避難所をBLEで周囲へ伝播（_navTargetが判明している場合のみ）
      if (_navTarget != null) {
        BleRoadReportService.instance.enqueueShelterStatus(_navTarget!);
      }
      _isNavigating = false;
      unawaited(_clearPersistedNavTarget());
    }
    notifyListeners();
  }

  Map<String, dynamic>? getRoadRiskInDirection(LatLng currentLocation, double heading) => null;
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
