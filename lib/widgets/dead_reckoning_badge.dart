import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/language_provider.dart';
import '../providers/location_provider.dart';
import '../services/dead_reckoning_service.dart';
import '../utils/localization.dart';

/// GPS 消失中に画面上部に表示するバッジ。
/// ・徒歩: オレンジ — ステップ数 + 推定誤差半径
/// ・自転車/車両: オレンジ — 推定速度 + 推定誤差半径
/// ・精度低下時（5分超 or ±100m超）: 赤 — 上記 + 警告テキスト
class DeadReckoningBadge extends StatelessWidget {
  const DeadReckoningBadge({super.key});

  static const Color _normalColor = Color(0xFFE65100); // オレンジ
  static const Color _warningColor = Color(0xFFB71C1C); // 赤

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>();
    final loc = context.watch<LocationProvider>();
    if (!loc.isDeadReckoning) return const SizedBox.shrink();

    final errorM = loc.deadReckoningErrorMeters.round();
    final isLow = loc.isDeadReckoningAccuracyLow;
    final bgColor = isLow ? _warningColor : _normalColor;
    final mode = loc.deadReckoningMovementMode;

    final (IconData modeIcon, String mainText) = switch (mode) {
      MovementMode.bicycle => (
          Icons.directions_bike,
          '${(loc.deadReckoningCurrentSpeedMs * 3.6).round()} km/h',
        ),
      MovementMode.vehicle => (
          Icons.directions_car,
          '${(loc.deadReckoningCurrentSpeedMs * 3.6).round()} km/h',
        ),
      MovementMode.walk => (
          Icons.gps_off,
          GapLessL10n.t('dr_badge')
              .replaceAll('@steps', '${loc.deadReckoningStepCount}'),
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor.withValues(alpha: 0.93),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1行目: モードアイコン + メイン情報 + 誤差半径 ──
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(modeIcon, color: Colors.white, size: 14),
              const SizedBox(width: 6),
              Text(
                mainText,
                style: GapLessL10n.safeStyle(const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                )),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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
                    fontFamily: 'NotoSansJP',
                    fontFamilyFallback: [
                      'NotoSansSC',
                      'NotoSansTC',
                      'NotoSansKR',
                      'NotoSansThai',
                      'NotoSansMyanmar',
                      'NotoSansSinhala',
                      'NotoSansDevanagari',
                      'NotoSansBengali',
                      'NotoSansArabic',
                      'NotoSans',
                      'sans-serif'
                    ],
                  ),
                ),
              ),
              // 徒歩モードかつ学習済み歩幅があれば表示
              if (mode == MovementMode.walk && loc.hasLearnedStride) ...[
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
                      fontFamily: 'NotoSansJP',
                      fontFamilyFallback: [
                        'NotoSansSC',
                        'NotoSansTC',
                        'NotoSansKR',
                        'NotoSansThai',
                        'NotoSansMyanmar',
                        'NotoSansSinhala',
                        'NotoSansDevanagari',
                        'NotoSansBengali',
                        'NotoSansArabic',
                        'NotoSans',
                        'sans-serif'
                      ],
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
              style: GapLessL10n.safeStyle(const TextStyle(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w400,
              )),
            ),
          ],
        ],
      ),
    );
  }
}
