import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../providers/shelter_provider.dart';
import '../models/shelter.dart';
import '../utils/localization.dart';
import '../providers/location_provider.dart';
import '../utils/styles.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  bool _compassMode = false;

  @override
  void initState() {
    super.initState();
    // 初期データを読み込む
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<ShelterProvider>();
      provider.loadShelters();
      provider.loadHazardPolygons();
      
      // 現在位置または拠点がある場合、そこを中心に表示
      final locationProvider = context.read<LocationProvider>();
      if (locationProvider.currentLocation != null) {
        _mapController.move(
          locationProvider.currentLocation!,
          13.0,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('🗺️ ${AppLocalizations.t('map_title')}', style: emergencyTextStyle(size: 20, isBold: true, color: Colors.white)),
        actions: [
          // コンパスモードボタン
          IconButton(
            onPressed: () {
              setState(() {
                _compassMode = !_compassMode;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    _compassMode ? AppLocalizations.t('compass_mode_on') : AppLocalizations.t('compass_mode_off'),
                  ),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            icon: Icon(
              Icons.explore,
              color: _compassMode ? Colors.yellow : Colors.white,
            ),
          ),
        ],
      ),
      body: Consumer<ShelterProvider>(
        builder: (context, provider, child) {
          // ローディング中
          if (provider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          // 地図の中心座標を取得（LocationProviderから優先）
          final locationProvider = context.watch<LocationProvider>();
          LatLng initialCenter;
          
          if (locationProvider.currentLocation != null) {
            initialCenter = locationProvider.currentLocation!;
            
            // 現在地が変わったらカメラを追従させる（自動センター）
            WidgetsBinding.instance.addPostFrameCallback((_) {
               // アニメーションなしで即座に移動（ユーザー要望：即座にanimateCamera... animateCameraはないのでmove使用）
               // flutter_mapのバージョンによってはanimateCamera系のメソッドがあるが、moveで十分
               _mapController.move(initialCenter, 15.0);
            });
          } else {
            final center = provider.getCenter();
            initialCenter = LatLng(center['lat']!, center['lng']!);
          }

          return Stack(
            children: [
              // FlutterMap
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: initialCenter,
                  initialZoom: 15.0, // 詳細ズーム
                  minZoom: 10.0,
                  maxZoom: 18.0,
                ),
                children: [
                  // 1. タイルレイヤー (OpenStreetMap)
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.safe_japan',
                    maxZoom: 19,
                  ),
                  // 2. ポリゴンレイヤー (ハザードマップ)
                  PolygonLayer(
                    polygons: provider.hazardPolygons.map((polygon) {
                      return Polygon(
                        points: polygon,
                        color: Colors.red.withValues(alpha: 0.3),
                        borderColor: Colors.red,
                        borderStrokeWidth: 2.0,
                        isFilled: true,
                      );
                    }).toList(),
                  ),
                  // 3. マーカーレイヤー (避難所)
                  MarkerLayer(
                    markers: provider.shelters.map((shelter) {
                      final Color markerColor = _getMarkerColor(shelter.type);
                      final IconData markerIcon = _getMarkerIcon(shelter.type);
                      
                      return Marker(
                        point: LatLng(shelter.lat, shelter.lng),
                        width: 60,
                        height: 70,
                        child: GestureDetector(
                          onTap: () => _showShelterDetails(context, shelter),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // マーカーラベル
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: markerColor,
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Colors.black26,
                                      blurRadius: 4,
                                      offset: Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Text(
                                  _getShelterLabel(shelter.type),
                                  style: emergencyTextStyle(
                                    color: Colors.white,
                                    size: 10,
                                    isBold: true,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              // ピンの先端
                              Icon(
                                markerIcon,
                                color: markerColor,
                                size: 30,
                                shadows: const [
                                  Shadow(
                                    color: Colors.black54,
                                    blurRadius: 4,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
              
              // 避難所数インジケーター
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.location_on,
                        color: Color(0xFFE53935),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        AppLocalizations.t('shelter_count').replaceAll('@count', '${provider.shelters.length}'),
                        style: emergencyTextStyle(
                          isBold: true,
                          size: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 避難所詳細をModalBottomSheetで表示
  void _showShelterDetails(BuildContext context, Shelter shelter) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ハンドル
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              
              // タイトル
              Row(
                children: [
                  Icon(
                    shelter.verified ? Icons.verified : Icons.warning,
                    color: shelter.verified ? Colors.green : Colors.orange,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      shelter.name,
                      style: emergencyTextStyle(
                        size: 20,
                        isBold: true,
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 20),
              
              // タイプ
              _buildInfoRow(
                Icons.category,
                AppLocalizations.t('label_type'),
                _getShelterLabel(shelter.type),
              ),
              
              const SizedBox(height: 12),
              
              // 座標
              _buildInfoRow(
                Icons.map,
                AppLocalizations.t('label_coordinates'),
                '${shelter.lat.toStringAsFixed(5)}, ${shelter.lng.toStringAsFixed(5)}',
              ),
              
              const SizedBox(height: 12),
              
              // 検証済みステータス
              _buildInfoRow(
                Icons.check_circle,
                AppLocalizations.t('label_status'),
                shelter.verified ? AppLocalizations.t('verified') : AppLocalizations.t('unverified'),
              ),
              
              const SizedBox(height: 24),
              
              // ナビゲーションボタン
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(AppLocalizations.t('navigation_developing')),
                      ),
                    );
                  },
                  icon: const Icon(Icons.navigation),
                  label: Text(AppLocalizations.t('navigate_here')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 情報行を構築
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Text(
          '$label: ',
          style: emergencyTextStyle(
            size: 14,
            isBold: true,
            color: Colors.grey[700]!,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: emergencyTextStyle(
              size: 14,
            ),
          ),
        ),
      ],
    );
  }

  /// マーカーの色を取得
  Color _getMarkerColor(String type) {
    switch (type) {
      case 'hospital':
        return Colors.red;
      case 'shelter':
        return const Color(0xFF43A047); // Green
      case 'water':
        return Colors.blue;
      case 'fuel':
        return Colors.deepPurple;
      case 'convenience':
        return Colors.orange;
      case 'school':
        return const Color(0xFF43A047); // School is also a shelter
      default:
        return Colors.grey;
    }
  }

  /// マーカーのアイコンを取得
  IconData _getMarkerIcon(String type) {
    switch (type) {
      case 'hospital':
        return Icons.local_hospital;
      case 'shelter':
        return Icons.night_shelter;
      case 'water':
        return Icons.water_drop;
      case 'fuel':
        return Icons.local_gas_station;
      case 'convenience':
        return Icons.store;
      case 'school':
        return Icons.school;
      default:
        return Icons.place;
    }
  }
  
  /// タイプラベルを取得
  String _getShelterLabel(String type) {
    return AppLocalizations.translateShelterType(type);
  }
}
