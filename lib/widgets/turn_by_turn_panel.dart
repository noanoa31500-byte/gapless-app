import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../utils/localization.dart';

// ============================================================================
// TurnByTurnPanel — ターンバイターン案内パネル
// ============================================================================
//
// 【配置】NavigationScreen の地図下部に Positioned(bottom:0) で固定表示。
//
// 【計算ロジック】
//   ① 現在地に最も近いウェイポイントのインデックス i を線形探索
//   ② route[i+1] への方位と距離を計算
//   ③ 相対方位 = nextBearing - headingDeg で曲がり方向を判定
//   ④ route[i:] の区間合計を残距離として表示
//   ⑤ i >= route.length-1 かつ 20m 以内 → 到着と判定
//
// ============================================================================

// ── 向き判定 ──────────────────────────────────────────────────────────────────

enum _TurnDir { straight, right, left, uTurn }

_TurnDir _calcTurnDir(double relativeDeg) {
  // Dart の % は常に非負なので [-180, 180] に正規化
  double rel = relativeDeg % 360;
  if (rel > 180) rel -= 360;

  if (rel >= -30 && rel <= 30) return _TurnDir.straight;
  if (rel > 30 && rel <= 150) return _TurnDir.right;
  if (rel >= -150 && rel < -30) return _TurnDir.left;
  return _TurnDir.uTurn;
}

IconData _iconFor(_TurnDir dir) {
  switch (dir) {
    case _TurnDir.straight:
      return Icons.arrow_upward;
    case _TurnDir.right:
      return Icons.turn_right;
    case _TurnDir.left:
      return Icons.turn_left;
    case _TurnDir.uTurn:
      return Icons.u_turn_left;
  }
}

String _labelFor(_TurnDir dir) {
  switch (dir) {
    case _TurnDir.straight:
      return GapLessL10n.t('nav_straight');
    case _TurnDir.right:
      return GapLessL10n.t('nav_turn_right');
    case _TurnDir.left:
      return GapLessL10n.t('nav_turn_left');
    case _TurnDir.uTurn:
      return GapLessL10n.t('nav_u_turn');
  }
}

// ── 距離フォーマット ──────────────────────────────────────────────────────────

String _fmt(double m) {
  if (m >= 1000) return '${(m / 1000).toStringAsFixed(1)} km';
  return '${m.round()}m';
}

// ── 幾何計算 ──────────────────────────────────────────────────────────────────

/// 2点間の方位角 [0, 360)
double _bearing(LatLng from, LatLng to) {
  final lat1 = from.latitude * math.pi / 180;
  final lat2 = to.latitude * math.pi / 180;
  final dLng = (to.longitude - from.longitude) * math.pi / 180;
  final y = math.sin(dLng) * math.cos(lat2);
  final x = math.cos(lat1) * math.sin(lat2) -
      math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// 現在地に最も近いウェイポイントのインデックスを返す
int _nearestIndex(LatLng pos, List<LatLng> route) {
  const dist = Distance();
  int best = 0;
  double bestD = double.infinity;
  for (int i = 0; i < route.length; i++) {
    final d = dist(pos, route[i]);
    if (d < bestD) {
      bestD = d;
      best = i;
    }
  }
  return best;
}

/// route[fromIndex:] の残距離合計（メートル）
double _remaining(List<LatLng> route, int fromIndex) {
  const dist = Distance();
  double total = 0;
  for (int i = fromIndex; i < route.length - 1; i++) {
    total += dist(route[i], route[i + 1]);
  }
  return total;
}

// ── ウィジェット ──────────────────────────────────────────────────────────────

class TurnByTurnPanel extends StatefulWidget {
  /// 全ウェイポイント列（空のとき非表示）
  final List<LatLng> route;

  /// 現在地（毎フレーム更新）
  final LatLng currentPosition;

  /// 現在の進行方向（SensorFusion から）
  final double headingDeg;

  /// 目的地到着コールバック（null 可）
  final VoidCallback? onArrived;

  const TurnByTurnPanel({
    super.key,
    required this.route,
    required this.currentPosition,
    required this.headingDeg,
    required this.onArrived,
  });

  @override
  State<TurnByTurnPanel> createState() => _TurnByTurnPanelState();
}

class _TurnByTurnPanelState extends State<TurnByTurnPanel> {
  static const Color _navy = Color(0xFF2E7D32);
  static const Color _orange = Color(0xFFFF6F00);
  static const double _arrivalThresholdM = 20.0;

  bool _arrived = false;

  // ── 到着チェック ────────────────────────────────────────────────────────────
  // didUpdateWidget で実行することで build() 外から副作用を起こす

  @override
  void didUpdateWidget(TurnByTurnPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_arrived) _checkArrival();
  }

  void _checkArrival() {
    if (widget.route.isEmpty) return;
    final idx = _nearestIndex(widget.currentPosition, widget.route);
    if (idx >= widget.route.length - 1) {
      const dist = Distance();
      final d = dist(widget.currentPosition, widget.route.last);
      if (d <= _arrivalThresholdM) {
        setState(() => _arrived = true);
        widget.onArrived?.call();
      }
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.route.isEmpty) return const SizedBox.shrink();
    if (_arrived) return _buildArrivalPanel();

    const dist = Distance();
    final idx = _nearestIndex(widget.currentPosition, widget.route);

    // 最終ウェイポイント到達（まだ 20m 圏外）→ 目的地方向を案内
    if (idx >= widget.route.length - 1) {
      final d = dist(widget.currentPosition, widget.route.last);
      final bear = _bearing(widget.currentPosition, widget.route.last);
      final dir = _calcTurnDir(bear - widget.headingDeg);
      return _buildPanel(distToNext: d, dir: dir, remaining: d);
    }

    // 通常案内
    final nextPos = widget.route[idx + 1];
    final distToNext = dist(widget.currentPosition, nextPos);
    final bear = _bearing(widget.currentPosition, nextPos);
    final dir = _calcTurnDir(bear - widget.headingDeg);
    final rem = _remaining(widget.route, idx);

    return _buildPanel(distToNext: distToNext, dir: dir, remaining: rem);
  }

  // ── 案内パネル ──────────────────────────────────────────────────────────────

  Widget _buildPanel({
    required double distToNext,
    required _TurnDir dir,
    required double remaining,
  }) {
    return Container(
      height: 100,
      decoration: const BoxDecoration(
        color: _navy,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // 左: 方向アイコン
          Icon(_iconFor(dir), color: Colors.white, size: 48),

          const SizedBox(width: 16),

          // 中: 距離 + 方向ラベル
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  GapLessL10n.t('nav_dist_ahead').replaceAll('@dist', _fmt(distToNext)),
                  style: GapLessL10n.safeStyle(const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  )),
                ),
                const SizedBox(height: 2),
                Text(
                  _labelFor(dir),
                  style: GapLessL10n.safeStyle(const TextStyle(
                    color: _orange,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  )),
                ),
              ],
            ),
          ),

          // 右: 残り距離
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _fmt(remaining),
                style: GapLessL10n.safeStyle(const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                )),
              ),
              const SizedBox(height: 2),
              Text(
                GapLessL10n.t('nav_to_dest'),
                style: GapLessL10n.safeStyle(const TextStyle(
                  color: Color(0xFF90A4AE),
                  fontSize: 12,
                )),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── 到着パネル ──────────────────────────────────────────────────────────────

  Widget _buildArrivalPanel() {
    return Container(
      height: 100,
      decoration: const BoxDecoration(
        color: _navy,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.flag_rounded, color: Color(0xFFFF6F00), size: 28),
          const SizedBox(width: 12),
          Text(
            GapLessL10n.t('nav_arrived_panel'),
            style: GapLessL10n.safeStyle(const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            )),
          ),
        ],
      ),
    );
  }
}
