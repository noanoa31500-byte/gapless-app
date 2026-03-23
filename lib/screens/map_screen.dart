import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/shelter_provider.dart';
import '../models/shelter.dart';
import '../models/hazard_spot.dart';
import '../utils/localization.dart';
import '../providers/location_provider.dart';
import '../utils/styles.dart';
import '../services/device_id_service.dart';
import '../services/ble_sync_service.dart';

// ============================================================================
// MapScreen - 地図画面（BLE同期・危険情報追加・即時反映統合版）
// ============================================================================
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const Color _navyPrimary  = Color(0xFF2E7D32);
  static const Color _orangeAccent = Color(0xFFFF6F00);
  static const Color _warningColor = Color(0xFFF9A825);

  final MapController _mapController = MapController();
  LatLng? _tappedPoint;
  bool _isSubmitting = false;

  // △ローカルキー（旧実装との互換性）
  static const String _legacyKey = 'gapless_hazard_spots';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeMap());
  }

  Future<void> _initializeMap() async {
    final provider = context.read<ShelterProvider>();
    provider.loadShelters();
    provider.loadHazardPolygons();

    final locationProvider = context.read<LocationProvider>();
    if (locationProvider.currentLocation != null) {
      _mapController.move(locationProvider.currentLocation!, 13.0);
    }

    // 第四の指示: 起動時にlocalStorageから未確認スポットを全件読み込む
    await HazardSpotRepository.instance.load();
    if (!mounted) return;

    // 旧フォーマット(gapless_hazard_spots)からのマイグレーション
    await _migrateLegacyData();
    if (!mounted) return;

    // BLE同期を開始（iOSのみ）
    await BleSyncService.instance.start();
    if (!mounted) return;

    // BleSyncServiceの更新でも再描画
    BleSyncService.instance.addListener(_onBleSyncUpdate);
    HazardSpotRepository.instance.addListener(_onRepositoryUpdate);
  }

  void _onBleSyncUpdate() => setState(() {});
  void _onRepositoryUpdate() => setState(() {});

  @override
  void dispose() {
    BleSyncService.instance.removeListener(_onBleSyncUpdate);
    HazardSpotRepository.instance.removeListener(_onRepositoryUpdate);
    BleSyncService.instance.stop();
    super.dispose();
  }

  /// 旧フォーマットデータをHazardSpotRepositoryに移行
  Future<void> _migrateLegacyData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final legacy = prefs.getStringList(_legacyKey) ?? [];
      if (legacy.isEmpty) return;

      final spots = legacy.map((s) {
        try {
          final json = jsonDecode(s) as Map<String, dynamic>;
          // 旧フォーマットはタイムスタンプがISO文字列
          return HazardSpot(
            id: json['id'] as String,
            lat: (json['lat'] as num).toDouble(),
            lng: (json['lng'] as num).toDouble(),
            deviceId: json['device_id'] as String? ?? 'migrated',
            timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now().toUtc(),
            status: json['status'] as String? ?? 'unconfirmed',
          );
        } catch (_) { return null; }
      }).whereType<HazardSpot>().toList();

      if (spots.isNotEmpty) {
        await HazardSpotRepository.instance.mergeReceived(spots);
        await prefs.remove(_legacyKey); // 移行完了後に旧データを削除
        debugPrint('🔄 旧データを移行しました: ${spots.length}件');
      }
    } catch (e) {
      debugPrint('⚠️ 旧データ移行エラー: $e');
    }
  }

  // ─── タップ処理 ────────────────────────────────────────────
  void _onMapTap(TapPosition tapPosition, LatLng latLng) {
    setState(() => _tappedPoint = latLng);
  }

  // ─── 送信処理 ──────────────────────────────────────────────
  Future<void> _submitHazardSpot() async {
    if (_tappedPoint == null || _isSubmitting) return;
    setState(() => _isSubmitting = true);

    try {
      final deviceId = DeviceIdService.instance.deviceId ?? 'unknown';
      final spot = HazardSpot(
        id: '${DateTime.now().millisecondsSinceEpoch}_${_tappedPoint!.latitude.toStringAsFixed(5)}',
        lat: _tappedPoint!.latitude,
        lng: _tappedPoint!.longitude,
        deviceId: deviceId,
        timestamp: DateTime.now().toUtc(),
        status: 'unconfirmed',
      );

      // 第二・第三の指示: localStorageに保存（notifyListeners → 即時反映）
      await HazardSpotRepository.instance.add(spot);

      if (!mounted) return;
      setState(() => _tappedPoint = null);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.white),
            const SizedBox(width: 8),
            Text(GapLessL10n.t('map_info_added'), style: GapLessL10n.safeStyle(const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          ]),
          backgroundColor: _warningColor,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
          duration: const Duration(seconds: 2),
        ));
      }
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  // ─── UI ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // HazardSpotRepositoryの変更で自動再描画（BLE受信後も即時更新）
    final hazardSpots = HazardSpotRepository.instance.unconfirmedSpots;
    final bleService = BleSyncService.instance;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: _navyPrimary,
        title: Text('🗺️ ${GapLessL10n.t('map_title')}',
          style: emergencyTextStyle(size: 20, isBold: true, color: Colors.white)),
        actions: [
          // BLE同期状態インジケーター
          _buildBleSyncIndicator(bleService),
          // 危険スポット数バッジ
          if (hazardSpots.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: _warningColor, borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
                const SizedBox(width: 4),
                Text('${hazardSpots.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              ]),
            ),
        ],
      ),
      body: Consumer<ShelterProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) return const Center(child: CircularProgressIndicator());

          final locationProvider = context.watch<LocationProvider>();
          final initialCenter = locationProvider.currentLocation ??
            () { final c = provider.getCenter(); return LatLng(c['lat']!, c['lng']!); }();

          return Stack(children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: initialCenter,
                initialZoom: 15.0,
                minZoom: 10.0,
                maxZoom: 18.0,
                onTap: _onMapTap,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.safe_japan',
                  maxZoom: 19,
                ),
                PolygonLayer(
                  polygons: provider.hazardPolygons.map((polygon) => Polygon(
                    points: polygon,
                    color: Colors.red.withValues(alpha: 0.3),
                    borderColor: Colors.red, borderStrokeWidth: 2.0, isFilled: true,
                  )).toList(),
                ),
                MarkerLayer(
                  markers: provider.shelters.map((shelter) => Marker(
                    point: LatLng(shelter.lat, shelter.lng),
                    width: 60, height: 70,
                    child: GestureDetector(
                      onTap: () => _showShelterDetails(context, shelter),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getMarkerColor(shelter.type),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))],
                          ),
                          child: Text(_getShelterLabel(shelter.type),
                            style: emergencyTextStyle(color: Colors.white, size: 10, isBold: true),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        Icon(_getMarkerIcon(shelter.type), color: _getMarkerColor(shelter.type), size: 30,
                          shadows: const [Shadow(color: Colors.black54, blurRadius: 4)]),
                      ]),
                    ),
                  )).toList(),
                ),

                // 第三・第四の指示: 危険スポット三角形マーカー（BLE受信後も即時反映）
                MarkerLayer(
                  markers: hazardSpots.map((spot) {
                    // reportCountが多いほど大きく・濃く表示（評価の重みを視覚化）
                    final size = (30.0 + spot.reportCount * 4.0).clamp(30.0, 60.0);
                    final opacity = (0.7 + spot.reportCount * 0.05).clamp(0.7, 1.0);
                    return Marker(
                      point: LatLng(spot.lat, spot.lng),
                      width: size + 4, height: size + 4,
                      child: GestureDetector(
                        onTap: () => _showHazardSpotDetail(spot),
                        child: Icon(
                          Icons.warning_amber_rounded,
                          color: _warningColor.withValues(alpha: opacity),
                          size: size,
                          shadows: const [Shadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 2))],
                        ),
                      ),
                    );
                  }).toList(),
                ),

                // タップ仮マーカー
                if (_tappedPoint != null)
                  MarkerLayer(markers: [Marker(
                    point: _tappedPoint!, width: 20, height: 20,
                    child: Container(
                      decoration: BoxDecoration(
                        color: _orangeAccent.withValues(alpha: 0.8),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [BoxShadow(color: _orangeAccent.withValues(alpha: 0.5), blurRadius: 8)],
                      ),
                    ),
                  )]),
              ],
            ),

            if (_tappedPoint != null) _buildAddSpotPopup(),

            Positioned(
              top: 16, right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 2))],
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.location_on, color: Color(0xFFE53935), size: 20),
                  const SizedBox(width: 8),
                  Text(GapLessL10n.t('shelter_count').replaceAll('@count', '${provider.shelters.length}'),
                    style: emergencyTextStyle(isBold: true, size: 14)),
                ]),
              ),
            ),

            // 操作ヒント
            Positioned(
              bottom: 24, left: 0, right: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _tappedPoint == null ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _navyPrimary.withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.touch_app, color: Colors.white, size: 18),
                      const SizedBox(width: 6),
                      Text(GapLessL10n.t('map_tap_hint'),
                        style: GapLessL10n.safeStyle(const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
                    ]),
                  ),
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }

  // ─── BLE同期インジケーター ─────────────────────────────────
  Widget _buildBleSyncIndicator(BleSyncService bleService) {
    final isActive = bleService.isRunning;
    final peerCount = bleService.connectedPeerCount;
    final lastSync = bleService.lastSyncTime;

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Tooltip(
        message: isActive
          ? GapLessL10n.t('map_ble_syncing').replaceAll('@count', '$peerCount') +
              (lastSync != null ? '\n${lastSync.toLocal().toString().substring(11, 16)}' : '')
          : GapLessL10n.t('map_ble_waiting'),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: peerCount > 0 ? Colors.green.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.bluetooth_connected,
              color: peerCount > 0 ? Colors.green : (isActive ? Colors.blue : Colors.grey),
              size: 16),
            if (peerCount > 0) ...[
              const SizedBox(width: 4),
              Text('$peerCount', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green)),
            ],
          ]),
        ),
      ),
    );
  }

  // ─── 情報追加ポップアップ ─────────────────────────────────
  Widget _buildAddSpotPopup() {
    return Positioned(
      bottom: 0, left: 0, right: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 20, offset: const Offset(0, -4))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: _warningColor.withValues(alpha: 0.12), shape: BoxShape.circle),
                      child: const Icon(Icons.warning_amber_rounded, color: _warningColor, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(GapLessL10n.t('map_hazard_title'),
                        style: GapLessL10n.safeStyle(const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)))),
                      const SizedBox(height: 2),
                      Text('📍 ${_tappedPoint!.latitude.toStringAsFixed(5)}, ${_tappedPoint!.longitude.toStringAsFixed(5)}',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                    ])),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: Colors.grey[400]),
                      onPressed: () => setState(() => _tappedPoint = null),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Divider(color: Colors.grey[200]),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _navyPrimary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      const Icon(Icons.bluetooth, size: 16, color: Color(0xFF2E7D32)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(GapLessL10n.t('map_hazard_hint'),
                        style: GapLessL10n.safeStyle(const TextStyle(fontSize: 12, color: Color(0xFF2E7D32))))),
                    ]),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity, height: 54,
                    child: ElevatedButton.icon(
                      onPressed: _isSubmitting ? null : _submitHazardSpot,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _warningColor, foregroundColor: Colors.white,
                        elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      icon: _isSubmitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.add_location_alt_rounded, size: 22),
                      label: Text(_isSubmitting ? GapLessL10n.t('map_submitting') : GapLessL10n.t('map_submit'),
                        style: GapLessL10n.safeStyle(const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5))),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _showHazardSpotDetail(HazardSpot spot) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4,
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),
          Row(children: [
            const Icon(Icons.warning_amber_rounded, color: _warningColor, size: 32),
            const SizedBox(width: 12),
            Expanded(child: Text(GapLessL10n.t('hazard_unconfirmed_title'),
              style: emergencyTextStyle(size: 20, isBold: true, color: const Color(0xFF2E7D32)))),
          ]),
          const SizedBox(height: 16),
          _buildInfoRow(Icons.map, GapLessL10n.t('label_coordinates'), '${spot.lat.toStringAsFixed(5)}, ${spot.lng.toStringAsFixed(5)}'),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.schedule, GapLessL10n.t('label_timestamp'), spot.timestamp.toLocal().toString().substring(0, 16)),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.people, GapLessL10n.t('label_report_count'), '${spot.reportCount}${GapLessL10n.t('unit_count')}'),
          const SizedBox(height: 8),
          _buildInfoRow(Icons.flag_outlined, GapLessL10n.t('label_status'), GapLessL10n.t('unverified')),
        ]),
      ),
    );
  }

  void _showShelterDetails(BuildContext context, Shelter shelter) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2)))),
          Row(children: [
            Icon(shelter.verified ? Icons.verified : Icons.warning,
              color: shelter.verified ? Colors.green : Colors.orange, size: 32),
            const SizedBox(width: 12),
            Expanded(child: Text(shelter.name, style: emergencyTextStyle(size: 20, isBold: true))),
          ]),
          const SizedBox(height: 20),
          _buildInfoRow(Icons.category, GapLessL10n.t('label_type'), _getShelterLabel(shelter.type)),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.map, GapLessL10n.t('label_coordinates'),
            '${shelter.lat.toStringAsFixed(5)}, ${shelter.lng.toStringAsFixed(5)}'),
          const SizedBox(height: 12),
          _buildInfoRow(Icons.check_circle, GapLessL10n.t('label_status'),
            shelter.verified ? GapLessL10n.t('verified') : GapLessL10n.t('unverified')),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(GapLessL10n.t('navigation_developing')))),
              icon: const Icon(Icons.navigation),
              label: Text(GapLessL10n.t('navigate_here')),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) => Row(children: [
    Icon(icon, size: 20, color: Colors.grey[600]),
    const SizedBox(width: 12),
    Text('$label: ', style: emergencyTextStyle(size: 14, isBold: true, color: Colors.grey[700]!)),
    Expanded(child: Text(value, style: emergencyTextStyle(size: 14))),
  ]);

  Color _getMarkerColor(String type) {
    switch (type) {
      case 'hospital': return Colors.red;
      case 'shelter': return const Color(0xFF43A047);
      case 'water': return Colors.blue;
      case 'fuel': return Colors.deepPurple;
      case 'convenience': return Colors.orange;
      case 'school': return const Color(0xFF43A047);
      default: return Colors.grey;
    }
  }

  IconData _getMarkerIcon(String type) {
    switch (type) {
      case 'hospital': return Icons.local_hospital;
      case 'shelter': return Icons.night_shelter;
      case 'water': return Icons.water_drop;
      case 'fuel': return Icons.local_gas_station;
      case 'convenience': return Icons.store;
      case 'school': return Icons.school;
      default: return Icons.place;
    }
  }

  String _getShelterLabel(String type) => GapLessL10n.translateShelterType(type);
}
