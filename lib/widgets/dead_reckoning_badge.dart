import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';
import '../providers/location_provider.dart';
import '../utils/localization.dart';

/// GPS 消失中に画面上部に表示するバッジ。
/// ・通常時: オレンジ — ステップ数 + 推定誤差半径
/// ・精度低下時（5分超 or ±100m超）: 赤 — 上記 + 警告テキスト
class DeadReckoningBadge extends StatelessWidget {
  const DeadReckoningBadge({super.key});

  static const Color _normalColor = Color(0xFFE65100);   // オレンジ
  static const Color _warningColor = Color(0xFFB71C1C);  // 赤

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>();
    final loc = context.watch<LocationProvider>();
    if (!loc.isDeadReckoning) return const SizedBox.shrink();

    final steps = loc.deadReckoningStepCount;
    final errorM = loc.deadReckoningErrorMeters.round();
    final isLow = loc.isDeadReckoningAccuracyLow;
    final bgColor = isLow ? _warningColor : _normalColor;

    final badgeText =
        GapLessL10n.t('dr_badge').replaceAll('@steps', '$steps');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor.withOpacity(0.93),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1行目: GPS off + ステップ数 + 誤差半径 ──
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.gps_off, color: Colors.white, size: 14),
              const SizedBox(width: 6),
              Text(
                badgeText,
                style: GapLessL10n.safeStyle(const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                )),
              ),
              const SizedBox(width: 6),
              // 推定誤差半径（実装①②の補正後）
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '±${errorM}m',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              // 学習済み歩幅（デフォルトから更新されていれば表示）
              if (loc.hasLearnedStride) ...[
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${(loc.learnedStrideLengthM * 100).round()}cm/step',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ],
          ),
          // ── 2行目: 精度低下警告（5分超 or ±100m超のみ表示）──
          if (isLow) ...[
            const SizedBox(height: 3),
            Text(
              GapLessL10n.t('dr_accuracy_low'),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
