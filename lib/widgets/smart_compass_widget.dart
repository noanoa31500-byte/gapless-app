import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../controllers/smart_compass_controller.dart';
import '../providers/location_provider.dart';
import '../providers/shelter_provider.dart';

/// ルート追従型スマートコンパスウィジェット
/// 
/// 防災エンジニアとしての視点:
/// パニック状態でも一目で分かるシンプルなデザイン。
/// 色とアイコンで直感的に状態を理解できることが重要です。
class SmartCompassWidget extends StatefulWidget {
  final double size;
  
  const SmartCompassWidget({
    super.key,
    this.size = 200.0,
  });

  @override
  State<SmartCompassWidget> createState() => _SmartCompassWidgetState();
}

class _SmartCompassWidgetState extends State<SmartCompassWidget>
    with SingleTickerProviderStateMixin {
  late SmartCompassController _compassController;
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    
    _compassController = SmartCompassController();
    
    // 回転アニメーション用
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    
    // ルート変更を監視
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final shelterProvider = context.read<ShelterProvider>();
     if (shelterProvider.safestRoute != null && shelterProvider.roadGraph != null) {
        _updateRoute(shelterProvider);
      }
    });
  }

  @override
  void dispose() {
    _compassController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  /// ルートを更新
  void _updateRoute(ShelterProvider shelterProvider) {
    final routeNodeIds = shelterProvider.safestRoute;
    final graph = shelterProvider.roadGraph;
    
    if (routeNodeIds == null || graph == null) return;
    
    // ノードIDから座標リストを作成
    final routePoints = routeNodeIds
        .map((id) => graph.nodes[id]?.position)
        .whereType<LatLng>()
        .toList();
    
    if (routePoints.isNotEmpty) {
      _compassController.setRoute(routePoints);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationProvider = context.watch<LocationProvider>();
   final shelterProvider = context.watch<ShelterProvider>();

    // ルート更新チェック
    if (shelterProvider.safestRoute != null && shelterProvider.roadGraph != null) {
      _updateRoute(shelterProvider);
    }

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: Colors.grey[850]?.withValues(alpha: 0.95) ?? Colors.grey.withValues(alpha: 0.95),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: StreamBuilder<CompassEvent?>(
        stream: FlutterCompass.events,
        builder: (context, compassSnapshot) {
          if (!compassSnapshot.hasData || compassSnapshot.data == null) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final deviceHeading = compassSnapshot.data!.heading ?? 0.0;
          _compassController.updateHeading(deviceHeading);

          // 現在地を更新
          final currentLoc = locationProvider.currentLocation;
          if (currentLoc != null) {
            _compassController.updateLocation(currentLoc);
          }

          return StreamBuilder<CompassState>(
            stream: _compassController.stateStream,
            builder: (context, stateSnapshot) {
              if (!stateSnapshot.hasData) {
                return const Center(child: Text('待機中...'));
              }

              final state = stateSnapshot.data!;

              return Stack(
                alignment: Alignment.center,
                children: [
                  // 背景円
                  _buildBackground(state),
                  
                  // 方位マーク（N, E, S, W）
                  _buildCardinalMarks(),
                  
                  // コンパスの針
                  if (state.compassRotation != null)
                    _buildCompassNeedle(state),
                  
                  // 中央の情報表示
                  _buildCenterInfo(state),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// 背景を構築
  Widget _buildBackground(CompassState state) {
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: state.isOffCourse
              ? [
                  Colors.red.withValues(alpha: 0.3),
                  Colors.red.withValues(alpha: 0.1),
                ]
              : [
                  Colors.green.withValues(alpha: 0.2),
                  Colors.transparent,
                ],
        ),
      ),
    );
  }

  /// 方位マークを構築
  Widget _buildCardinalMarks() {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        children: [
          // N
          Positioned(
            top: 10,
            left: widget.size / 2 - 10,
            child: const Text(
              'N',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red,
              ),
            ),
          ),
          // E
          Positioned(
            right: 10,
            top: widget.size / 2 - 10,
            child: Text(
              'E',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ),
          // S
          Positioned(
            bottom: 10,
            left: widget.size / 2 - 10,
            child: Text(
              'S',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ),
          // W
          Positioned(
            left: 10,
            top: widget.size / 2 - 10,
            child: Text(
              'W',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// コンパスの針を構築
  Widget _buildCompassNeedle(CompassState state) {
    return Transform.rotate(
      angle: state.compassRotation! * (math.pi / 180),
      child: Icon(
        Icons.navigation,
        size: widget.size * 0.4,
        color: state.isOffCourse ? Colors.red : Colors.green,
      ),
    );
  }

  /// 中央の情報表示を構築
  Widget _buildCenterInfo(CompassState state) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),
        
        // 次のウェイポイントまでの距離
        if (state.distanceToNext != null)
          Text(
            '${state.distanceToNext!.toStringAsFixed(0)}m',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        
        const SizedBox(height: 5),
        
        // 状態メッセージ
        Text(
          state.isOffCourse ? '⚠️ ルート外' : '✓ ルート上',
          style: TextStyle(
            fontSize: 12,
            color: state.isOffCourse ? Colors.red : Colors.green,
            fontWeight: FontWeight.bold,
          ),
        ),
        
        const SizedBox(height: 10),
        
        // 目的地までの総距離
        if (state.distanceToGoal != null)
          Text(
            '目的地まで ${(state.distanceToGoal! / 1000).toStringAsFixed(1)}km',
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
            ),
          ),
      ],
    );
  }
}
